import CryptoKit
import Foundation

struct LocalModelSynthesisRequest {
    let backendID: SpeechBackendID
    let voiceID: String
    let text: String
    let speed: Double
    let outputURL: URL
}

enum LocalModelRuntimeError: LocalizedError {
    case unsupportedBackend
    case commandFailed(String)
    case missingPython

    var errorDescription: String? {
        switch self {
        case .unsupportedBackend:
            return "That local speech backend is not supported."
        case .commandFailed(let message):
            return message
        case .missingPython:
            return "Python 3 is required to install and run the local speech models."
        }
    }
}

actor LocalModelTTSRuntime {
    static let shared = LocalModelTTSRuntime()
    private static let alignmentModelIdentifier = "tiny.en"

    private let fileManager = FileManager.default
    private let appSupportURL: URL
    private let runtimeURL: URL
    private let audioCacheURL: URL
    private let venvURL: URL
    private let scriptURL: URL
    private var preparedBackends = Set<SpeechBackendID>()
    private var activeProcesses: [SpeechBackendID: Process] = [:]

    init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        appSupportURL = base.appendingPathComponent("XArticleReader", isDirectory: true)
        runtimeURL = appSupportURL.appendingPathComponent("LocalTTS", isDirectory: true)
        audioCacheURL = runtimeURL.appendingPathComponent("AudioCache", isDirectory: true)
        venvURL = runtimeURL.appendingPathComponent("venv", isDirectory: true)
        scriptURL = runtimeURL.appendingPathComponent("mlx_tts_runner.py")
        Self.terminateOrphanedRunnerProcesses()
    }

    nonisolated func statusMessage(for backendID: SpeechBackendID) -> String {
        switch backendID {
        case .system:
            return "Ready instantly with built-in macOS voices."
        case .kokoro:
            return "Smaller local model. Quickest to download and start on Apple Silicon."
        case .qwen3:
            return "Higher-quality local model. Larger first download and slower setup."
        }
    }

    func currentStatus(for backendID: SpeechBackendID) async -> SpeechEngineStatus {
        guard backendID != .system else {
            return SpeechEngineStatus(isPreparing: false, isReady: true, progress: 1, message: statusMessage(for: backendID))
        }

        let ready = modelReadyMarkerURL(for: backendID)
        if fileManager.fileExists(atPath: ready.path) {
            return SpeechEngineStatus(isPreparing: false, isReady: true, progress: 1, message: readyMessage(for: backendID))
        }

        return SpeechEngineStatus(isPreparing: false, isReady: false, progress: 0, message: statusMessage(for: backendID))
    }

    func prepare(
        backendID: SpeechBackendID,
        statusHandler: (@Sendable (SpeechEngineStatus) -> Void)? = nil
    ) async throws {
        guard backendID != .system else { return }
        try fileManager.createDirectory(at: runtimeURL, withIntermediateDirectories: true, attributes: nil)
        try writeRunnerScript()
        if preparedBackends.contains(backendID) {
            statusHandler?(SpeechEngineStatus(isPreparing: false, isReady: true, progress: 1, message: readyMessage(for: backendID)))
            preparedBackends.insert(backendID)
            return
        }

        if fileManager.fileExists(atPath: modelReadyMarkerURL(for: backendID).path), (try? dependenciesLookHealthy()) == true {
            statusHandler?(SpeechEngineStatus(isPreparing: false, isReady: true, progress: 1, message: readyMessage(for: backendID)))
            preparedBackends.insert(backendID)
            return
        }

        statusHandler?(SpeechEngineStatus(isPreparing: true, isReady: false, progress: 0.08, message: "Preparing the local \(backendID.displayName) runtime folder…"))
        statusHandler?(SpeechEngineStatus(isPreparing: true, isReady: false, progress: 0.2, message: "Creating the isolated Python runtime for \(backendID.displayName)…"))
        try ensureVenv()
        statusHandler?(SpeechEngineStatus(isPreparing: true, isReady: false, progress: 0.48, message: "Installing the local audio dependencies for \(backendID.displayName)…"))
        try installDependencies()
        statusHandler?(SpeechEngineStatus(isPreparing: true, isReady: false, progress: 0.78, message: "Downloading \(backendID.displayName) model weights. This first run can take a bit…"))
        try await warmupModel(backendID: backendID)
        preparedBackends.insert(backendID)
        statusHandler?(SpeechEngineStatus(isPreparing: false, isReady: true, progress: 1, message: readyMessage(for: backendID)))
    }

    func synthesize(
        _ request: LocalModelSynthesisRequest,
        statusHandler: (@Sendable (SpeechEngineStatus) -> Void)? = nil
    ) async throws {
        guard let profile = LocalModelCatalog.profile(for: request.backendID) else {
            throw LocalModelRuntimeError.unsupportedBackend
        }
        try await prepare(backendID: request.backendID, statusHandler: statusHandler)
        try fileManager.createDirectory(at: audioCacheURL, withIntermediateDirectories: true, attributes: nil)

        let cachedOutputURL = cacheURL(for: request)
        if fileManager.fileExists(atPath: cachedOutputURL.path) {
            _ = try await ensureWordTimings(for: request, audioURL: cachedOutputURL, statusHandler: statusHandler)
            if fileManager.fileExists(atPath: request.outputURL.path) {
                try? fileManager.removeItem(at: request.outputURL)
            }
            try fileManager.copyItem(at: cachedOutputURL, to: request.outputURL)
            statusHandler?(SpeechEngineStatus(isPreparing: false, isReady: true, progress: 1, message: "Using saved \(request.backendID.displayName) audio from your local cache."))
            return
        }

        let voiceName = request.voiceID.components(separatedBy: ":").last ?? request.voiceID
        let python = venvURL.appendingPathComponent("bin/python").path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [
            scriptURL.path,
            "--model", profile.modelIdentifier,
            "--voice", voiceName,
            "--text", request.text,
            "--output", cachedOutputURL.path,
            "--speed", String(request.speed),
            "--backend", request.backendID.rawValue,
            "--lang", profile.languageCode,
        ]
        statusHandler?(SpeechEngineStatus(isPreparing: true, isReady: false, progress: 0.92, message: "Generating audio locally with \(request.backendID.displayName)…"))
        try await run(process, backendID: request.backendID)
        _ = try await ensureWordTimings(for: request, audioURL: cachedOutputURL, statusHandler: statusHandler)
        if fileManager.fileExists(atPath: request.outputURL.path) {
            try? fileManager.removeItem(at: request.outputURL)
        }
        try fileManager.copyItem(at: cachedOutputURL, to: request.outputURL)
        statusHandler?(SpeechEngineStatus(isPreparing: false, isReady: true, progress: 1, message: readyMessage(for: request.backendID)))
    }

    func cancelRunningWork(for backendID: SpeechBackendID) {
        Self.safelyStop(activeProcesses[backendID])
        activeProcesses[backendID] = nil
    }

    func cachedOutputURL(for request: LocalModelSynthesisRequest) -> URL? {
        let url = cacheURL(for: request)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func cachedWordTimings(for request: LocalModelSynthesisRequest) -> [AlignedWordTiming]? {
        let url = alignmentCacheURL(for: request)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([AlignedWordTiming].self, from: data)
    }

    private func ensureWordTimings(
        for request: LocalModelSynthesisRequest,
        audioURL: URL,
        statusHandler: (@Sendable (SpeechEngineStatus) -> Void)? = nil
    ) async throws -> [AlignedWordTiming] {
        if let cached = cachedWordTimings(for: request), !cached.isEmpty {
            return cached
        }

        let alignmentURL = alignmentCacheURL(for: request)
        let python = venvURL.appendingPathComponent("bin/python").path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [
            scriptURL.path,
            "--align-audio", audioURL.path,
            "--alignment-text", request.text,
            "--align-output", alignmentURL.path,
            "--align-model", Self.alignmentModelIdentifier,
        ]
        statusHandler?(SpeechEngineStatus(isPreparing: true, isReady: false, progress: 0.97, message: "Aligning spoken words to the article text locally…"))
        try await run(process, backendID: request.backendID)

        guard let aligned = cachedWordTimings(for: request), !aligned.isEmpty else {
            throw LocalModelRuntimeError.commandFailed("The local speech runtime finished, but word alignment could not be prepared.")
        }

        return aligned
    }

    private func ensureVenv() throws {
        let pythonPath = venvURL.appendingPathComponent("bin/python").path
        if fileManager.isExecutableFile(atPath: pythonPath) {
            return
        }

        guard fileManager.isExecutableFile(atPath: "/usr/bin/python3") else {
            throw LocalModelRuntimeError.missingPython
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-m", "venv", venvURL.path]
        try run(process)
    }

    private func installDependencies() throws {
        let markerURL = runtimeURL.appendingPathComponent("deps-installed.txt")
        if fileManager.fileExists(atPath: markerURL.path), try dependenciesLookHealthy() {
            return
        }

        let pip = venvURL.appendingPathComponent("bin/pip").path

        let upgrade = Process()
        upgrade.executableURL = URL(fileURLWithPath: pip)
        upgrade.arguments = ["install", "--upgrade", "pip", "setuptools", "wheel"]
        try run(upgrade)

        let install = Process()
        install.executableURL = URL(fileURLWithPath: pip)
        install.arguments = ["install", "mlx-audio", "soundfile", "misaki", "num2words", "kokoro", "faster-whisper"]
        try run(install)

        try "ok".write(to: markerURL, atomically: true, encoding: .utf8)
    }

    private func dependenciesLookHealthy() throws -> Bool {
        let python = venvURL.appendingPathComponent("bin/python").path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = ["-c", "import mlx_audio, soundfile, misaki, num2words, kokoro, faster_whisper"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private func warmupModel(backendID: SpeechBackendID) async throws {
        guard let profile = LocalModelCatalog.profile(for: backendID) else {
            throw LocalModelRuntimeError.unsupportedBackend
        }
        let markerURL = modelReadyMarkerURL(for: backendID)
        if fileManager.fileExists(atPath: markerURL.path) {
            return
        }

        let python = venvURL.appendingPathComponent("bin/python").path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [
            scriptURL.path,
            "--model", profile.modelIdentifier,
            "--backend", backendID.rawValue,
            "--lang", profile.languageCode,
            "--warmup",
        ]
        try await run(process, backendID: backendID)
        try "ready".write(to: markerURL, atomically: true, encoding: .utf8)
    }

    private func writeRunnerScript() throws {
        let source = """
        import argparse
        import json
        import difflib
        import numpy as np
        import re
        import soundfile as sf
        from faster_whisper import WhisperModel
        from mlx_audio.tts.utils import load_model

        parser = argparse.ArgumentParser()
        parser.add_argument("--model")
        parser.add_argument("--voice")
        parser.add_argument("--text")
        parser.add_argument("--output")
        parser.add_argument("--speed", type=float, default=1.0)
        parser.add_argument("--backend")
        parser.add_argument("--lang")
        parser.add_argument("--warmup", action="store_true")
        parser.add_argument("--align-audio")
        parser.add_argument("--alignment-text")
        parser.add_argument("--align-output")
        parser.add_argument("--align-model", default="tiny.en")
        args = parser.parse_args()

        WORD_PATTERN = re.compile(r"\\b[\\w'’-]+\\b", re.UNICODE)

        def normalize_word(word):
            lowered = word.lower()
            cleaned = "".join(ch for ch in lowered if ch.isalnum())
            return cleaned

        def source_words(text):
            words = []
            for match in WORD_PATTERN.finditer(text):
                normalized = normalize_word(match.group(0))
                if not normalized:
                    continue
                words.append(
                    {
                        "word": match.group(0),
                        "normalized": normalized,
                        "start_offset": match.start(),
                        "end_offset": match.end(),
                        "start": None,
                        "end": None,
                    }
                )
            return words

        def spoken_words(audio_path, model_name):
            model = WhisperModel(model_name, device="cpu", compute_type="int8")
            segments, _ = model.transcribe(
                audio_path,
                language="en",
                beam_size=1,
                best_of=1,
                temperature=0.0,
                condition_on_previous_text=False,
                word_timestamps=True,
                vad_filter=False,
            )

            words = []
            for segment in segments:
                for word in getattr(segment, "words", []) or []:
                    token = (word.word or "").strip()
                    normalized = normalize_word(token)
                    if not normalized:
                        continue
                    words.append(
                        {
                            "word": token,
                            "normalized": normalized,
                            "start": float(word.start or 0.0),
                            "end": float(word.end or word.start or 0.0),
                        }
                    )
            return words

        def assign_direct_matches(source, spoken):
            source_norms = [item["normalized"] for item in source]
            spoken_norms = [item["normalized"] for item in spoken]
            matcher = difflib.SequenceMatcher(a=source_norms, b=spoken_norms, autojunk=False)

            for tag, i1, i2, j1, j2 in matcher.get_opcodes():
                if tag != "equal":
                    continue
                for source_index, spoken_index in zip(range(i1, i2), range(j1, j2)):
                    source[source_index]["start"] = spoken[spoken_index]["start"]
                    source[source_index]["end"] = spoken[spoken_index]["end"]

        def fill_unmatched_timings(source, duration):
            matched = [index for index, item in enumerate(source) if item["start"] is not None and item["end"] is not None]
            if not source:
                return

            if not matched:
                slot = duration / max(len(source), 1)
                for index, item in enumerate(source):
                    item["start"] = max(0.0, slot * index)
                    item["end"] = max(item["start"] + 0.01, min(duration, slot * (index + 1)))
                return

            first = matched[0]
            if first > 0:
                span = max(source[first]["start"], 0.01)
                slot = span / first
                for index in range(first):
                    start = slot * index
                    end = slot * (index + 1)
                    source[index]["start"] = start
                    source[index]["end"] = max(start + 0.01, min(end, source[first]["start"]))

            for left, right in zip(matched, matched[1:]):
                gap_indices = list(range(left + 1, right))
                if not gap_indices:
                    continue
                start_time = source[left]["end"]
                end_time = source[right]["start"]
                span = max(end_time - start_time, 0.01)
                slot = span / (len(gap_indices) + 1)
                cursor = start_time
                for index in gap_indices:
                    next_cursor = min(end_time, cursor + slot)
                    source[index]["start"] = cursor
                    source[index]["end"] = max(cursor + 0.01, next_cursor)
                    cursor = next_cursor

            last = matched[-1]
            if last < len(source) - 1:
                remainder = max(duration - source[last]["end"], 0.01)
                slot = remainder / max(len(source) - last - 1, 1)
                cursor = source[last]["end"]
                for index in range(last + 1, len(source)):
                    next_cursor = min(duration, cursor + slot)
                    source[index]["start"] = cursor
                    source[index]["end"] = max(cursor + 0.01, next_cursor)
                    cursor = next_cursor

        def align_audio_to_text(audio_path, text, output_path, model_name):
            source = source_words(text)
            spoken = spoken_words(audio_path, model_name)
            duration = float(sf.info(audio_path).duration)
            assign_direct_matches(source, spoken)
            fill_unmatched_timings(source, duration)

            payload = [
                {
                    "word": item["word"],
                    "startTime": round(float(item["start"]), 6),
                    "endTime": round(float(max(item["end"], item["start"] + 0.01)), 6),
                    "startOffset": int(item["start_offset"]),
                    "endOffset": int(item["end_offset"]),
                }
                for item in source
            ]
            with open(output_path, "w", encoding="utf-8") as handle:
                json.dump(payload, handle)

        if args.align_audio:
            if not args.alignment_text or not args.align_output:
                raise RuntimeError("Alignment text and output path are required for word timing alignment.")
            align_audio_to_text(args.align_audio, args.alignment_text, args.align_output, args.align_model)
            print("ALIGNMENT_READY")
            raise SystemExit(0)

        if not args.model or not args.backend or not args.lang:
            raise RuntimeError("Model, backend, and language are required.")

        model = load_model(args.model)
        if args.warmup:
            print("MODEL_READY")
            raise SystemExit(0)

        if not args.voice or not args.text or not args.output:
            raise RuntimeError("Voice, text, and output are required for synthesis.")

        kwargs = {"text": args.text, "voice": args.voice, "speed": args.speed}
        if args.backend == "kokoro":
            kwargs["lang_code"] = args.lang
        else:
            kwargs["language"] = args.lang

        segments = list(model.generate(**kwargs))
        if not segments:
            raise RuntimeError("No audio was generated.")

        combined = None
        for result in segments:
            audio = np.array(result.audio)
            combined = audio if combined is None else np.concatenate((combined, audio))

        if combined is None:
            raise RuntimeError("Audio combination failed.")

        sf.write(args.output, combined, 24000)
        """
        try source.write(to: scriptURL, atomically: true, encoding: .utf8)
    }

    private func modelReadyMarkerURL(for backendID: SpeechBackendID) -> URL {
        runtimeURL.appendingPathComponent("\(backendID.rawValue)-ready.txt")
    }

    private func cacheURL(for request: LocalModelSynthesisRequest) -> URL {
        let payload = "\(request.backendID.rawValue)|\(request.voiceID)|\(String(format: "%.2f", request.speed))|\(request.text)"
        let digest = SHA256.hash(data: Data(payload.utf8)).compactMap { String(format: "%02x", $0) }.joined()
        return audioCacheURL.appendingPathComponent("\(digest).wav")
    }

    private func alignmentCacheURL(for request: LocalModelSynthesisRequest) -> URL {
        let payload = "\(request.backendID.rawValue)|\(request.voiceID)|\(String(format: "%.2f", request.speed))|\(request.text)"
        let digest = SHA256.hash(data: Data(payload.utf8)).compactMap { String(format: "%02x", $0) }.joined()
        return audioCacheURL.appendingPathComponent("\(digest).words.json")
    }

    private func readyMessage(for backendID: SpeechBackendID) -> String {
        "\(backendID.displayName) is downloaded and ready on this Mac."
    }

    private static func terminateOrphanedRunnerProcesses() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process.arguments = ["-f", "mlx_tts_runner.py"]
        try? process.run()
        process.waitUntilExit()
    }

    nonisolated private static func safelyStop(_ process: Process?) {
        guard let process, process.isRunning else { return }
        process.interrupt()
        if process.isRunning {
            process.terminate()
        }
    }

    private func run(_ process: Process) throws {
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let outputText = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let merged = [errorText, outputText].filter { !$0.isEmpty }.joined(separator: "\n")
            throw LocalModelRuntimeError.commandFailed(merged.isEmpty ? "The local speech runtime failed." : merged)
        }
    }

    private func run(_ process: Process, backendID: SpeechBackendID) async throws {
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        defer {
            activeProcesses[backendID] = nil
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in
                    continuation.resume(returning: ())
                }
                activeProcesses[backendID] = process
                do {
                    try process.run()
                } catch {
                    activeProcesses[backendID] = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            Self.safelyStop(process)
        }

        if Task.isCancelled {
            throw CancellationError()
        }

        guard process.terminationStatus == 0 else {
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let outputText = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let merged = [errorText, outputText].filter { !$0.isEmpty }.joined(separator: "\n")
            throw LocalModelRuntimeError.commandFailed(merged.isEmpty ? "The local speech runtime failed." : merged)
        }
    }
}
