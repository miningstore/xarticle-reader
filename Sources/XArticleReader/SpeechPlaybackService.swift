import AVFoundation
import Foundation
import Observation

@MainActor
protocol SpeechBackendAdapterDelegate: AnyObject {
    func speechAdapterDidFinishPlayback(_ adapter: SpeechBackendAdapter, successfully: Bool)
    func speechAdapter(_ adapter: SpeechBackendAdapter, willSpeak range: NSRange, utterance: String)
    func speechAdapter(_ adapter: SpeechBackendAdapter, didUpdatePlaybackTime currentTime: TimeInterval, duration: TimeInterval)
}

@MainActor
protocol SpeechBackendAdapter: AnyObject {
    var backendID: SpeechBackendID { get }
    var voices: [VoiceOption] { get }
    var isSpeaking: Bool { get }
    var isPaused: Bool { get }
    var currentItemDuration: TimeInterval? { get }
    var delegate: SpeechBackendAdapterDelegate? { get set }

    func start(text: String, voiceID: String, speed: Double) async throws
    func pause()
    func resume()
    func stop()
    func seek(toProgress progress: Double)
}

private struct PlaybackChunk: Identifiable {
    let id: Int
    let range: NSRange
    let paragraphRange: ClosedRange<Int>
}

private struct TimelineChunk {
    let range: NSRange
    let estimatedDuration: TimeInterval
    var actualDuration: TimeInterval?

    var resolvedDuration: TimeInterval {
        max(actualDuration ?? estimatedDuration, 0.01)
    }
}

private struct PlaybackTimeline {
    var chunks: [TimelineChunk]

    var totalDuration: TimeInterval {
        chunks.reduce(0) { $0 + $1.resolvedDuration }
    }

    mutating func setActualDuration(_ duration: TimeInterval, forChunkAt index: Int) {
        guard chunks.indices.contains(index) else { return }
        chunks[index].actualDuration = max(duration, 0.01)
    }

    func time(forTextOffset offset: Int) -> TimeInterval {
        guard !chunks.isEmpty else { return 0 }
        let clampedOffset = max(0, offset)
        var elapsed: TimeInterval = 0

        for chunk in chunks {
            let upperBound = NSMaxRange(chunk.range)
            if clampedOffset >= upperBound {
                elapsed += chunk.resolvedDuration
                continue
            }

            let localOffset = max(0, min(clampedOffset - chunk.range.location, chunk.range.length))
            let progress = chunk.range.length > 0 ? Double(localOffset) / Double(chunk.range.length) : 0
            return elapsed + (chunk.resolvedDuration * progress)
        }

        return totalDuration
    }

    func absoluteTime(forChunkAt index: Int, chunkTime: TimeInterval) -> TimeInterval {
        guard chunks.indices.contains(index) else { return 0 }
        let prior = chunks[..<index].reduce(0) { $0 + $1.resolvedDuration }
        return min(prior + max(chunkTime, 0), totalDuration)
    }

    func progress(forTextOffset offset: Int) -> Double {
        let total = totalDuration
        guard total > 0 else { return 0 }
        return min(max(time(forTextOffset: offset) / total, 0), 1)
    }

    func textOffset(forProgress progress: Double) -> Int {
        textOffset(forTime: totalDuration * min(max(progress, 0), 1))
    }

    func textOffset(forTime time: TimeInterval) -> Int {
        guard !chunks.isEmpty else { return 0 }
        let clampedTime = min(max(time, 0), totalDuration)
        var remaining = clampedTime

        for chunk in chunks {
            if remaining > chunk.resolvedDuration {
                remaining -= chunk.resolvedDuration
                continue
            }

            let progress = chunk.resolvedDuration > 0 ? remaining / chunk.resolvedDuration : 0
            return chunk.range.location + Int((Double(chunk.range.length) * progress).rounded())
        }

        return NSMaxRange(chunks.last!.range)
    }
}

@Observable
@MainActor
final class SpeechPlaybackService {
    static let defaultSpeed = 1.0
    var availableBackends: [SpeechBackendOption] = [
        SpeechBackendOption(id: .kokoro, title: SpeechBackendID.kokoro.displayName, subtitle: SpeechBackendID.kokoro.detailLabel),
        SpeechBackendOption(id: .qwen3, title: SpeechBackendID.qwen3.displayName, subtitle: SpeechBackendID.qwen3.detailLabel),
    ]
    var selectedBackendID: SpeechBackendID = .kokoro
    var availableVoices: [VoiceOption] = []
    var selectedVoiceID: String = ""
    var speed: Double = defaultSpeed
    var isPlaying: Bool = false
    var isBackendPreparing: Bool = false
    var backendStatusMessage: String = ""
    var backendStatuses: [SpeechBackendID: SpeechEngineStatus] = [:]
    var currentArticleID: UUID?
    var currentParagraphIndex: Int?
    var currentParagraphRange: NSRange?
    var currentWordRange: NSRange?
    var currentProgress: Double = 0
    var currentPlaybackOffset: TimeInterval = 0
    var isStartingPlayback: Bool = false
    var followPlaybackRequestID: Int = 0

    var shouldPresentProcessingOverlay: Bool {
        guard selectedBackendID != .system else { return false }
        if isStartingPlayback || isBackendPreparing {
            return true
        }
        guard let status = backendStatuses[selectedBackendID] else { return false }
        return status.isPreparing
    }

    var processingOverlayTitle: String {
        let message = processingOverlayMessage
        if message.localizedCaseInsensitiveContains("cache") || message.localizedCaseInsensitiveContains("saved audio") {
            return "Loading Saved Audio"
        }
        if message.localizedCaseInsensitiveContains("generating audio locally") {
            return "Generating Audio Locally"
        }
        if message.localizedCaseInsensitiveContains("downloading") || message.localizedCaseInsensitiveContains("installing") {
            return "Preparing \(selectedBackendID.displayName)"
        }
        return "Preparing \(selectedBackendID.displayName)"
    }

    var processingOverlayMessage: String {
        let primary = backendStatusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !primary.isEmpty {
            return primary
        }
        return backendStatuses[selectedBackendID]?.message ?? "Preparing \(selectedBackendID.displayName)…"
    }

    var processingOverlayProgress: Double? {
        guard let status = backendStatuses[selectedBackendID], status.isPreparing else { return nil }
        return max(status.progress, 0.05)
    }

    var processingOverlayETA: String? {
        guard
            let status = backendStatuses[selectedBackendID],
            status.isPreparing,
            let startedAt = backendProcessingStartedAt[selectedBackendID]
        else {
            return nil
        }

        let progress = max(status.progress, 0)
        let elapsed = Date().timeIntervalSince(startedAt)
        guard progress >= 0.08, elapsed >= 1.5 else { return nil }

        let estimatedTotal = elapsed / progress
        let remaining = max(estimatedTotal - elapsed, 0)
        guard remaining >= 1 else { return "Almost done" }
        return "Estimated time left: \(formatETA(remaining))"
    }

    private var paragraphSegments: [ParagraphSegment] = []
    private var playbackChunks: [PlaybackChunk] = []
    private var currentArticle: Article?
    private var shouldAutoadvance = false
    private var pendingChunkProgress = 0.0
    private var currentChunkIndex: Int?
    private var playbackTimelines: [String: PlaybackTimeline] = [:]
    private var backendProcessingStartedAt: [SpeechBackendID: Date] = [:]
    private let adapters: [SpeechBackendID: SpeechBackendAdapter]
    private var playbackTask: Task<Void, Never>?

    init() {
        let system = SystemSpeechAdapter()
        let kokoro = LocalModelSpeechAdapter(backendID: .kokoro)
        let qwen3 = LocalModelSpeechAdapter(backendID: .qwen3)
        adapters = [.system: system, .kokoro: kokoro, .qwen3: qwen3]
        for adapter in adapters.values {
            adapter.delegate = self
        }
        backendStatuses = [
            .kokoro: SpeechEngineStatus(message: LocalModelTTSRuntime.shared.statusMessage(for: .kokoro)),
            .qwen3: SpeechEngineStatus(message: LocalModelTTSRuntime.shared.statusMessage(for: .qwen3)),
        ]
        applyBackendSelection(.kokoro)
        Task { await refreshBackendStatuses() }
    }

    func configure(for article: Article) {
        currentArticle = article
        currentArticleID = article.id
        if article.lastSpeed <= 0 || (article.lastPlayedAt == nil && article.lastSpeed == 1.5) {
            article.lastSpeed = Self.defaultSpeed
        }
        speed = article.lastSpeed
        paragraphSegments = ArticleTextProcessor.paragraphSegments(for: article.bodyText, speed: speed)
        playbackChunks = buildPlaybackChunks(from: paragraphSegments, in: article.bodyText)
        let storedBackend = SpeechBackendID(rawValue: article.lastBackendIdentifier ?? SpeechBackendID.kokoro.rawValue) ?? .kokoro
        let requestedBackend = availableBackends.contains(where: { $0.id == storedBackend }) ? storedBackend : .kokoro
        applyBackendSelection(requestedBackend)

        let requestedVoice = article.lastVoiceIdentifier.isEmpty ? selectedVoiceID : article.lastVoiceIdentifier
        if availableVoices.contains(where: { $0.id == requestedVoice }) {
            selectedVoiceID = requestedVoice
        } else if let fallback = availableVoices.first {
            selectedVoiceID = fallback.id
            article.lastVoiceIdentifier = fallback.id
        }

        let paragraphIndex = paragraphSegments.isEmpty ? nil : ArticleTextProcessor.paragraphIndex(
            for: article.lastReadPosition,
            in: article.bodyText,
            speed: speed
        )
        currentParagraphIndex = paragraphIndex
        currentParagraphRange = paragraphIndex.flatMap { paragraphSegments[safe: $0]?.range }
        currentWordRange = nil
        currentChunkIndex = paragraphIndex.flatMap(chunkIndex(containingParagraph:))
        currentProgress = progress(for: article.lastReadPosition, in: article)
        currentPlaybackOffset = playbackTime(for: article.lastReadPosition, in: article)
        article.lastPlaybackOffset = currentPlaybackOffset
        updatePendingChunkProgress(for: article.lastReadPosition)
    }

    func refreshBackendStatuses() async {
        for backend in availableBackends.map(\.id) {
            setBackendStatus(await LocalModelTTSRuntime.shared.currentStatus(for: backend), for: backend)
        }
        backendStatusMessage = backendStatuses[selectedBackendID]?.message ?? backendReadyMessage(for: selectedBackendID)
    }

    func togglePlayback(for article: Article) {
        if currentArticleID != article.id {
            stopSpeaking()
            configure(for: article)
        }

        if isStartingPlayback {
            stopSpeaking()
            return
        }

        let adapter = currentAdapter
        if adapter.isSpeaking {
            pause()
        } else if adapter.isPaused {
            requestPlaybackFollow()
            adapter.resume()
            isPlaying = true
        } else {
            startPlayback(for: article)
        }
    }

    func startPlayback(for article: Article) {
        if currentArticleID != article.id || currentArticle == nil {
            configure(for: article)
        }

        guard !paragraphSegments.isEmpty else { return }
        if article.isFinished || article.lastReadPosition >= max(article.bodyText.utf16.count - 1, 0) {
            article.lastReadPosition = 0
            article.lastPlaybackOffset = 0
            article.isFinished = false
            currentParagraphIndex = 0
            currentParagraphRange = paragraphSegments.first?.range
            currentWordRange = nil
            currentChunkIndex = 0
            currentProgress = 0
            currentPlaybackOffset = 0
            article.lastPlaybackOffset = 0
            pendingChunkProgress = 0
        }
        stopSpeaking()
        let index = currentChunkIndex ?? chunkIndex(containingParagraph: currentParagraphIndex ?? 0) ?? 0
        isStartingPlayback = true
        backendStatusMessage = "Starting \(selectedBackendID.displayName) playback…"
        playbackTask = Task { [weak self] in
            guard let self else { return }
            await speakChunk(at: index, for: article)
        }
    }

    func pause() {
        if isStartingPlayback {
            stopSpeaking()
            return
        }
        currentAdapter.pause()
        isPlaying = false
    }

    func stopSpeaking() {
        shouldAutoadvance = false
        playbackTask?.cancel()
        playbackTask = nil
        for adapter in adapters.values {
            adapter.stop()
        }
        isPlaying = false
        isStartingPlayback = false
        currentWordRange = nil
    }

    func seek(by delta: TimeInterval, in article: Article) {
        configure(for: article)

        let maxLength = article.bodyText.utf16.count
        let baselineTime: TimeInterval
        if currentArticleID == article.id, (isPlaying || isStartingPlayback || currentAdapter.isPaused) {
            baselineTime = currentPlaybackOffset
        } else {
            baselineTime = playbackTime(for: article.lastReadPosition, in: article)
        }
        let newOffset = textOffset(forPlaybackTime: baselineTime + delta, in: article)
        let clampedOffset = max(0, min(newOffset, maxLength))
        seek(toTextOffset: clampedOffset, in: article)
    }

    func seek(toTextOffset offset: Int, in article: Article) {
        configure(for: article)

        let maxLength = article.bodyText.utf16.count
        let newOffset = max(0, min(offset, maxLength))
        article.lastReadPosition = newOffset
        article.isFinished = newOffset >= maxLength

        currentParagraphIndex = paragraphSegments.isEmpty ? nil : ArticleTextProcessor.paragraphIndex(
            for: newOffset,
            in: article.bodyText,
            speed: speed
        )
        currentParagraphRange = currentParagraphIndex.flatMap { paragraphSegments[safe: $0]?.range }
        currentWordRange = nil
        currentChunkIndex = currentParagraphIndex.flatMap(chunkIndex(containingParagraph:))
        currentProgress = progress(for: newOffset, in: article)
        currentPlaybackOffset = playbackTime(for: newOffset, in: article)
        article.lastPlaybackOffset = currentPlaybackOffset
        updatePendingChunkProgress(for: newOffset)

        if isStartingPlayback || currentAdapter.isSpeaking || currentAdapter.isPaused {
            let targetChunkIndex = currentChunkIndex ?? 0
            stopSpeaking()
            isStartingPlayback = true
            requestPlaybackFollow()
            playbackTask = Task { [weak self] in
                guard let self else { return }
                await speakChunk(at: targetChunkIndex, for: article)
            }
        }
    }

    func seek(toProgress progress: Double, in article: Article) {
        let offset = textOffset(forProgress: progress, in: article)
        seek(toTextOffset: offset, in: article)
    }

    func updateBackend(_ backendID: SpeechBackendID, for article: Article) {
        stopSpeaking()
        article.lastBackendIdentifier = backendID.rawValue
        applyBackendSelection(backendID)
        if !availableVoices.contains(where: { $0.id == selectedVoiceID }), let fallback = availableVoices.first {
            selectedVoiceID = fallback.id
            article.lastVoiceIdentifier = fallback.id
        }
        Task {
            try? await prepareBackend(backendID)
        }
    }

    func updateVoice(_ voiceID: String, for article: Article) {
        selectedVoiceID = voiceID
        article.lastVoiceIdentifier = voiceID
        article.lastBackendIdentifier = selectedBackendID.rawValue
        article.lastPlayedAt = .now
        if currentAdapter.isSpeaking || currentAdapter.isPaused {
            stopSpeaking()
            startPlayback(for: article)
        }
    }

    func updateSpeed(_ newValue: Double, for article: Article) {
        speed = newValue
        article.lastSpeed = newValue
        paragraphSegments = ArticleTextProcessor.paragraphSegments(for: article.bodyText, speed: newValue)
        playbackChunks = buildPlaybackChunks(from: paragraphSegments, in: article.bodyText)
        playbackTimelines.removeValue(forKey: timelineKey(for: article, backendID: selectedBackendID, voiceID: selectedVoiceID, speed: newValue))

        if let currentParagraphIndex {
            currentParagraphRange = paragraphSegments[safe: currentParagraphIndex]?.range
            currentChunkIndex = chunkIndex(containingParagraph: currentParagraphIndex)
            updatePendingChunkProgress(for: article.lastReadPosition)
        } else {
            currentChunkIndex = nil
            pendingChunkProgress = 0
        }
        currentProgress = progress(for: article.lastReadPosition, in: article)
        currentPlaybackOffset = playbackTime(for: article.lastReadPosition, in: article)
        article.lastPlaybackOffset = currentPlaybackOffset

        if currentAdapter.isSpeaking || currentAdapter.isPaused {
            stopSpeaking()
            startPlayback(for: article)
        }
    }

    private func applyBackendSelection(_ backendID: SpeechBackendID) {
        selectedBackendID = backendID
        availableVoices = adapters[backendID]?.voices ?? []
        if availableVoices.contains(where: { $0.id == selectedVoiceID }) {
            backendStatusMessage = backendStatuses[backendID]?.message ?? backendReadyMessage(for: backendID)
            return
        }
        selectedVoiceID = availableVoices.first?.id ?? ""
        backendStatusMessage = backendStatuses[backendID]?.message ?? backendReadyMessage(for: backendID)
    }

    func prepareBackend(_ backendID: SpeechBackendID) async throws {
        guard backendID != .system else { return }
        isBackendPreparing = true
        setBackendStatus(SpeechEngineStatus(
            isPreparing: true,
            isReady: false,
            progress: backendStatuses[backendID]?.progress ?? 0,
            message: backendStatuses[backendID]?.message ?? LocalModelTTSRuntime.shared.statusMessage(for: backendID)
        ), for: backendID)
        if backendID == selectedBackendID {
            backendStatusMessage = backendStatuses[backendID]?.message ?? ""
        }
        defer { isBackendPreparing = false }
        try await LocalModelTTSRuntime.shared.prepare(backendID: backendID) { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.setBackendStatus(status, for: backendID)
                if backendID == self.selectedBackendID {
                    self.backendStatusMessage = status.message
                }
            }
        }
        let readyStatus = await LocalModelTTSRuntime.shared.currentStatus(for: backendID)
        setBackendStatus(readyStatus, for: backendID)
        if backendID == selectedBackendID {
            backendStatusMessage = readyStatus.message
        }
    }

    private func backendReadyMessage(for backendID: SpeechBackendID) -> String {
        switch backendID {
        case .system:
            return "Using built-in macOS voices."
        case .kokoro:
            return "Using Kokoro locally on this Mac."
        case .qwen3:
            return "Using Qwen3 locally on this Mac."
        }
    }

    private var currentAdapter: SpeechBackendAdapter {
        adapters[selectedBackendID] ?? adapters[.system]!
    }

    fileprivate func didFinishSpeaking(successfully: Bool) {
        guard successfully, shouldAutoadvance, let article = currentArticle, let currentChunkIndex else {
            isPlaying = false
            shouldAutoadvance = false
            return
        }

        if let chunk = playbackChunks[safe: currentChunkIndex] {
            article.lastReadPosition = NSMaxRange(chunk.range)
            currentPlaybackOffset = totalDuration(for: article)
            article.lastPlaybackOffset = currentPlaybackOffset
            currentProgress = progress(for: article.lastReadPosition, in: article)
        }

        let nextIndex = currentChunkIndex + 1
        if nextIndex >= playbackChunks.count {
            article.lastReadPosition = article.bodyText.utf16.count
            article.lastPlaybackOffset = totalDuration(for: article)
            article.lastPlayedAt = .now
            article.isFinished = true
            currentProgress = 1
            currentPlaybackOffset = article.lastPlaybackOffset
            currentWordRange = nil
            isPlaying = false
            shouldAutoadvance = false
            return
        }

        currentWordRange = nil
        Task {
            await speakChunk(at: nextIndex, for: article)
        }
    }

    fileprivate func willSpeakWord(range: NSRange, in utterance: String) {
        guard
            let article = currentArticle,
            let chunkIndex = currentChunkIndex,
            let chunk = playbackChunks[safe: chunkIndex],
            let chunkText = excerpt(in: article.bodyText, range: chunk.range),
            utterance == chunkText
        else {
            return
        }

        let absoluteLocation = chunk.range.location + range.location
        let absoluteRange = NSRange(location: absoluteLocation, length: range.length)
        let paragraphIndex = ArticleTextProcessor.paragraphIndex(
            for: absoluteLocation,
            in: article.bodyText,
            speed: speed
        )
        currentParagraphIndex = paragraphIndex
        currentParagraphRange = paragraphSegments[safe: paragraphIndex]?.range
        currentWordRange = absoluteRange
        updatePendingChunkProgress(for: absoluteLocation)

        article.lastReadPosition = absoluteLocation
        article.lastPlaybackOffset = playbackTime(for: absoluteLocation, in: article)
        article.lastPlayedAt = .now
        article.isFinished = false
        currentProgress = progress(for: absoluteLocation, in: article)
        currentPlaybackOffset = article.lastPlaybackOffset
    }

    private func speakChunk(at index: Int, for article: Article) async {
        guard let chunk = playbackChunks[safe: index] else {
            isPlaying = false
            return
        }

        do {
            backendStatusMessage = "Preparing \(selectedBackendID.displayName)…"
            try await ensureArticleAudioReady(for: article)
            if Task.isCancelled {
                isStartingPlayback = false
                isPlaying = false
                playbackTask = nil
                return
            }
            shouldAutoadvance = true
            currentArticle = article
            currentArticleID = article.id
            currentChunkIndex = index
            currentParagraphIndex = chunk.paragraphRange.lowerBound
            currentParagraphRange = paragraphSegments[safe: chunk.paragraphRange.lowerBound]?.range
            currentWordRange = nil
            currentProgress = progress(for: article.lastReadPosition, in: article)
            currentPlaybackOffset = playbackTime(for: article.lastReadPosition, in: article)
            requestPlaybackFollow()

            let chunkStart = max(chunk.range.location, article.lastReadPosition)
            article.lastReadPosition = chunkStart
            article.lastPlaybackOffset = playbackTime(for: chunkStart, in: article)
            article.lastPlayedAt = .now
            article.lastBackendIdentifier = selectedBackendID.rawValue
            article.lastVoiceIdentifier = selectedVoiceID
            article.lastSpeed = speed
            article.isFinished = false

            guard let chunkText = excerpt(in: article.bodyText, range: chunk.range) else {
                throw NSError(domain: "XArticleReader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to prepare the next reading section."])
            }
            try await currentAdapter.start(text: chunkText, voiceID: selectedVoiceID, speed: speed)
            if let realizedDuration = currentAdapter.currentItemDuration {
                updateTimelineDuration(realizedDuration, forChunkAt: index, in: article)
            }
            if Task.isCancelled {
                isStartingPlayback = false
                isPlaying = false
                return
            }
            currentAdapter.seek(toProgress: min(max(pendingChunkProgress, 0), 0.985))
            isStartingPlayback = false
            isPlaying = true
            backendStatusMessage = backendReadyMessage(for: selectedBackendID)
            playbackTask = nil
        } catch {
            if error is CancellationError {
                shouldAutoadvance = false
                isPlaying = false
                isStartingPlayback = false
                playbackTask = nil
                return
            }
            backendStatusMessage = error.localizedDescription
            setBackendStatus(SpeechEngineStatus(
                isPreparing: false,
                isReady: false,
                progress: backendStatuses[selectedBackendID]?.progress ?? 0,
                message: error.localizedDescription
            ), for: selectedBackendID)
            shouldAutoadvance = false
            isPlaying = false
            isStartingPlayback = false
            playbackTask = nil
        }
    }

    private func buildPlaybackChunks(from segments: [ParagraphSegment], in bodyText: String) -> [PlaybackChunk] {
        guard !segments.isEmpty else { return [] }
        let nsText = bodyText as NSString
        let targetCharacters = 1200
        let maxCharacters = 1800
        var chunks: [PlaybackChunk] = []
        var startIndex = 0

        while startIndex < segments.count {
            var endIndex = startIndex
            var accumulatedLength = 0

            while endIndex < segments.count {
                let segment = segments[endIndex]
                let separatorLength = endIndex == startIndex ? 0 : 2
                let proposedLength = accumulatedLength + segment.range.length + separatorLength
                if endIndex > startIndex, proposedLength > maxCharacters {
                    break
                }
                accumulatedLength = proposedLength
                endIndex += 1
                if accumulatedLength >= targetCharacters, segment.role != .heading {
                    break
                }
            }

            let lowerSegment = segments[startIndex]
            let upperSegment = segments[max(startIndex, endIndex - 1)]
            let upperBound = min(nsText.length, NSMaxRange(upperSegment.range))
            let range = NSRange(location: lowerSegment.range.location, length: max(0, upperBound - lowerSegment.range.location))
            chunks.append(
                PlaybackChunk(
                    id: chunks.count,
                    range: range,
                    paragraphRange: startIndex...max(startIndex, endIndex - 1)
                )
            )
            startIndex = endIndex
        }

        return chunks
    }

    private func chunkIndex(containingParagraph paragraphIndex: Int) -> Int? {
        playbackChunks.firstIndex { $0.paragraphRange.contains(paragraphIndex) }
    }

    private func updatePendingChunkProgress(for textOffset: Int) {
        guard let currentChunkIndex, let chunk = playbackChunks[safe: currentChunkIndex] else {
            pendingChunkProgress = 0
            return
        }

        let localOffset = max(0, min(textOffset - chunk.range.location, chunk.range.length))
        pendingChunkProgress = chunk.range.length > 0 ? Double(localOffset) / Double(chunk.range.length) : 0
    }

    private func excerpt(in text: String, range: NSRange) -> String? {
        let nsText = text as NSString
        guard range.location != NSNotFound, NSMaxRange(range) <= nsText.length else {
            return nil
        }
        return nsText.substring(with: range)
    }

    func playbackTime(for textOffset: Int, in article: Article) -> TimeInterval {
        timeline(for: article).time(forTextOffset: textOffset)
    }

    func progress(for textOffset: Int, in article: Article) -> Double {
        timeline(for: article).progress(forTextOffset: textOffset)
    }

    func textOffset(forProgress progress: Double, in article: Article) -> Int {
        timeline(for: article).textOffset(forProgress: progress)
    }

    func textOffset(forPlaybackTime time: TimeInterval, in article: Article) -> Int {
        timeline(for: article).textOffset(forTime: time)
    }

    func totalDuration(for article: Article) -> TimeInterval {
        timeline(for: article).totalDuration
    }

    func timestampLabel(forTextOffset offset: Int, in article: Article) -> String {
        ArticleTextProcessor.timestampLabel(for: playbackTime(for: offset, in: article))
    }

    func timestampMarkers(for article: Article, interval: TimeInterval = ArticleTextProcessor.sectionInterval) -> [TimestampMarker] {
        guard interval > 0 else { return [] }
        let timeline = timeline(for: article)
        let segments = article.id == currentArticleID && !paragraphSegments.isEmpty
            ? paragraphSegments
            : ArticleTextProcessor.paragraphSegments(for: article.bodyText, speed: speed)
        guard let lastSegment = segments.last else { return [] }

        let sectionCount = max(Int(ceil(timeline.totalDuration / interval)), 1)
        var stacks: [Int: Int] = [:]
        var markers: [TimestampMarker] = []

        for section in 0..<sectionCount {
            let boundary = TimeInterval(section) * interval
            let offset = timeline.textOffset(forTime: boundary)
            let segmentIndex = ArticleTextProcessor.paragraphIndex(for: offset, in: article.bodyText, speed: speed)
            let segment = segments[safe: segmentIndex] ?? lastSegment
            let stackKey = max(0, min(offset, max(article.bodyText.utf16.count - 1, 0)))
            let stackIndex = stacks[stackKey, default: 0]
            stacks[stackKey] = stackIndex + 1
            markers.append(
                TimestampMarker(
                    id: section,
                    label: ArticleTextProcessor.timestampLabel(for: boundary),
                    textOffset: offset,
                    paragraphRange: segment.range,
                    paragraphIndex: segment.index,
                    stackIndex: stackIndex
                )
            )
        }

        return markers
    }

    private func updateTimelineDuration(_ duration: TimeInterval, forChunkAt index: Int, in article: Article) {
        let key = timelineKey(for: article, backendID: selectedBackendID, voiceID: selectedVoiceID, speed: speed)
        var existing = timeline(for: article)
        existing.setActualDuration(duration, forChunkAt: index)
        playbackTimelines[key] = existing
    }

    private func ensureArticleAudioReady(for article: Article) async throws {
        guard selectedBackendID != .system else {
            try await prepareBackend(selectedBackendID)
            return
        }

        try await prepareBackend(selectedBackendID)
        let totalChunks = max(playbackChunks.count, 1)

        for index in playbackChunks.indices {
            try Task.checkCancellation()

            if let existing = playbackTimelines[timelineKey(for: article, backendID: selectedBackendID, voiceID: selectedVoiceID, speed: speed)],
               existing.chunks.indices.contains(index),
               existing.chunks[index].actualDuration != nil {
                continue
            }

            guard let chunkText = excerpt(in: article.bodyText, range: playbackChunks[index].range) else { continue }
            let tempOutputURL = FileManager.default.temporaryDirectory.appendingPathComponent("xar-prebuild-\(article.id.uuidString)-\(index).wav")
            let request = LocalModelSynthesisRequest(
                backendID: selectedBackendID,
                voiceID: selectedVoiceID,
                text: chunkText,
                speed: speed,
                outputURL: tempOutputURL
            )

            if let cachedURL = await LocalModelTTSRuntime.shared.cachedOutputURL(for: request),
               let cachedDuration = audioDuration(at: cachedURL) {
                let progress = (Double(index) + 1) / Double(totalChunks)
                let status = SpeechEngineStatus(
                    isPreparing: true,
                    isReady: false,
                    progress: progress,
                    message: "Using saved \(selectedBackendID.displayName) audio for section \(index + 1) of \(totalChunks)…"
                )
                setBackendStatus(status, for: selectedBackendID)
                backendStatusMessage = status.message
                updateTimelineDuration(cachedDuration, forChunkAt: index, in: article)
                continue
            }

            try Task.checkCancellation()
            try await LocalModelTTSRuntime.shared.synthesize(request) { [weak self] status in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let overallProgress = (Double(index) + status.progress) / Double(totalChunks)
                    let overallStatus = SpeechEngineStatus(
                        isPreparing: true,
                        isReady: false,
                        progress: overallProgress,
                        message: "\(status.message) Section \(index + 1) of \(totalChunks)."
                    )
                    self.setBackendStatus(overallStatus, for: self.selectedBackendID)
                    self.backendStatusMessage = overallStatus.message
                }
            }

            try Task.checkCancellation()
            if let duration = audioDuration(at: tempOutputURL) {
                updateTimelineDuration(duration, forChunkAt: index, in: article)
            }
            try? FileManager.default.removeItem(at: tempOutputURL)
        }

        let readyStatus = SpeechEngineStatus(
            isPreparing: false,
            isReady: true,
            progress: 1,
            message: "\(selectedBackendID.displayName) audio is prepared locally and saved on this Mac."
        )
        setBackendStatus(readyStatus, for: selectedBackendID)
        backendStatusMessage = readyStatus.message
    }

    private func timeline(for article: Article) -> PlaybackTimeline {
        let key = timelineKey(for: article, backendID: selectedBackendID, voiceID: selectedVoiceID, speed: speed)
        let activeChunks = chunks(for: article)
        if let existing = playbackTimelines[key], existing.chunks.count == activeChunks.count {
            return existing
        }

        let timeline = PlaybackTimeline(
            chunks: activeChunks.map {
                TimelineChunk(
                    range: $0.range,
                    estimatedDuration: ArticleTextProcessor.estimatedDuration(forUTF16Length: $0.range.length, speed: speed),
                    actualDuration: nil
                )
            }
        )
        playbackTimelines[key] = timeline
        return timeline
    }

    private func chunks(for article: Article) -> [PlaybackChunk] {
        if article.id == currentArticleID, !playbackChunks.isEmpty {
            return playbackChunks
        }

        let segments = ArticleTextProcessor.paragraphSegments(for: article.bodyText, speed: speed)
        return buildPlaybackChunks(from: segments, in: article.bodyText)
    }

    private func timelineKey(for article: Article, backendID: SpeechBackendID, voiceID: String, speed: Double) -> String {
        "\(article.id.uuidString)::\(backendID.rawValue)::\(voiceID)::\(String(format: "%.2f", speed))"
    }

    private func audioDuration(at url: URL) -> TimeInterval? {
        guard let audioFile = try? AVAudioFile(forReading: url) else { return nil }
        let sampleRate = audioFile.processingFormat.sampleRate
        guard sampleRate > 0 else { return nil }
        return TimeInterval(audioFile.length) / sampleRate
    }

    private func setBackendStatus(_ status: SpeechEngineStatus, for backendID: SpeechBackendID) {
        if status.isPreparing {
            if backendProcessingStartedAt[backendID] == nil {
                backendProcessingStartedAt[backendID] = .now
            }
        } else {
            backendProcessingStartedAt[backendID] = nil
        }
        backendStatuses[backendID] = status
    }

    private func formatETA(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded()), 1)
        let minutes = total / 60
        let remainder = total % 60
        if minutes > 0 {
            return "\(minutes)m \(String(format: "%02ds", remainder))"
        }
        return "\(remainder)s"
    }

    private func requestPlaybackFollow() {
        followPlaybackRequestID &+= 1
    }
}

@MainActor
final class SystemSpeechAdapter: NSObject, SpeechBackendAdapter {
    let backendID: SpeechBackendID = .system
    weak var delegate: SpeechBackendAdapterDelegate?

    var voices: [VoiceOption] {
        Self.curatedVoices()
    }

    var isSpeaking: Bool {
        synthesizer.isSpeaking
    }

    var isPaused: Bool {
        synthesizer.isPaused
    }

    var currentItemDuration: TimeInterval? { nil }

    private let synthesizer = AVSpeechSynthesizer()
    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func start(text: String, voiceID: String, speed: Double) async throws {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(identifier: voiceID)
        utterance.rate = mapRate(for: speed)
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0.08
        synthesizer.speak(utterance)
    }

    func pause() {
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
        }
    }

    func resume() {
        synthesizer.continueSpeaking()
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    func seek(toProgress progress: Double) {
        // AVSpeechSynthesizer does not support sample-accurate seeks.
    }

    private func mapRate(for value: Double) -> Float {
        let minimum = Double(AVSpeechUtteranceMinimumSpeechRate)
        let maximum = Double(AVSpeechUtteranceMaximumSpeechRate)
        let normalized = (value - 0.75) / 1.25
        return Float(minimum + normalized * (maximum - minimum) * 0.55)
    }

    private static func curatedVoices() -> [VoiceOption] {
        let preferredNames = ["Samantha", "Allison", "Daniel", "Tessa", "Ava", "Karen", "Moira", "Alex"]
        let rawVoices = AVSpeechSynthesisVoice.speechVoices().map {
            VoiceOption(id: $0.identifier, backendID: .system, name: $0.name, localeIdentifier: $0.language)
        }
        let englishVoices = rawVoices.filter { $0.localeIdentifier.hasPrefix("en") }
        var curated: [VoiceOption] = []

        for preferredName in preferredNames {
            if let match = englishVoices.first(where: { $0.name == preferredName }) {
                curated.append(match)
            }
        }

        for voice in englishVoices where curated.count < 6 {
            if !curated.contains(voice) {
                curated.append(voice)
            }
        }

        return curated.isEmpty ? Array(rawVoices.prefix(6)) : curated
    }
}

extension SystemSpeechAdapter: @preconcurrency AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        delegate?.speechAdapterDidFinishPlayback(self, successfully: true)
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        guard synthesizer === self.synthesizer else { return }
        delegate?.speechAdapter(self, willSpeak: characterRange, utterance: utterance.speechString)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        delegate?.speechAdapterDidFinishPlayback(self, successfully: false)
    }
}

@MainActor
final class LocalModelSpeechAdapter: NSObject, SpeechBackendAdapter {
    private struct DisplayWordCue {
        let range: NSRange
        let startBoundary: TimeInterval
        let endBoundary: TimeInterval
    }

    let backendID: SpeechBackendID
    weak var delegate: SpeechBackendAdapterDelegate?

    var voices: [VoiceOption] {
        LocalModelCatalog.profile(for: backendID)?.voices ?? []
    }

    var isSpeaking: Bool {
        player?.isPlaying == true
    }

    var isPaused: Bool {
        isPausedInternally
    }

    var currentItemDuration: TimeInterval? {
        player?.duration
    }

    private var player: AVAudioPlayer?
    private var isPausedInternally = false
    private var currentOutputURL: URL?
    private let runtime = LocalModelTTSRuntime.shared
    private var alignedWordTimings: [AlignedWordTiming] = []
    private var displayWordCues: [DisplayWordCue] = []
    private var cueTimer: Timer?
    private var currentText: String = ""
    private var lastEmittedWordIndex: Int?

    init(backendID: SpeechBackendID) {
        self.backendID = backendID
    }

    func start(text: String, voiceID: String, speed: Double) async throws {
        stop()
        let request = LocalModelSynthesisRequest(
            backendID: backendID,
            voiceID: voiceID,
            text: text,
            speed: speed,
            outputURL: FileManager.default.temporaryDirectory.appendingPathComponent(
                "xar-\(backendID.rawValue)-\(UUID().uuidString).wav"
            )
        )
        currentOutputURL = request.outputURL
        try await runtime.synthesize(request)

        let player = try AVAudioPlayer(contentsOf: request.outputURL)
        player.delegate = self
        player.prepareToPlay()
        self.player = player
        currentText = text
        let rawTimings = await runtime.cachedWordTimings(for: request) ?? approximateWordTimings(for: text, duration: player.duration)
        alignedWordTimings = remapWordRangesForRenderedText(rawTimings, text: text)
        displayWordCues = buildDisplayWordCues(from: alignedWordTimings, totalDuration: player.duration)
        lastEmittedWordIndex = nil
        player.play()
        startCueTimer()
        isPausedInternally = false
        emitCueIfNeeded(at: player.currentTime)
        publishPlaybackProgress()
    }

    func pause() {
        player?.pause()
        isPausedInternally = true
        publishPlaybackProgress()
    }

    func resume() {
        player?.play()
        isPausedInternally = false
        if let player {
            lastEmittedWordIndex = nil
            emitCueIfNeeded(at: player.currentTime)
        }
        publishPlaybackProgress()
    }

    func stop() {
        player?.stop()
        player = nil
        isPausedInternally = false
        cueTimer?.invalidate()
        cueTimer = nil
        alignedWordTimings = []
        displayWordCues = []
        currentText = ""
        lastEmittedWordIndex = nil
        if let currentOutputURL {
            try? FileManager.default.removeItem(at: currentOutputURL)
        }
        currentOutputURL = nil
    }

    func seek(toProgress progress: Double) {
        guard let player else { return }
        let clamped = min(max(progress, 0), 1)
        player.currentTime = player.duration * clamped
        publishPlaybackProgress()
        lastEmittedWordIndex = nil
        emitCueIfNeeded(at: player.currentTime)
    }

    // Real aligned timings are preferred. This only keeps playback usable if alignment is unavailable.
    private func approximateWordTimings(for text: String, duration: TimeInterval) -> [AlignedWordTiming] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let regex = try? NSRegularExpression(pattern: #"\b[\p{L}\p{N}'’-]+\b"#)
        let matches = regex?.matches(in: text, range: fullRange) ?? []
        guard !matches.isEmpty else {
            return []
        }

        let slot = max(duration, 0.1) / Double(max(matches.count, 1))
        return matches.enumerated().map { index, match in
            let word = nsText.substring(with: match.range)
            let start = slot * Double(index)
            let end = slot * Double(index + 1)
            return AlignedWordTiming(
                word: word,
                startTime: start,
                endTime: max(start + 0.01, end),
                startOffset: match.range.location,
                endOffset: NSMaxRange(match.range)
            )
        }
    }

    private func remapWordRangesForRenderedText(_ timings: [AlignedWordTiming], text: String) -> [AlignedWordTiming] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let regex = try? NSRegularExpression(pattern: #"\b[\p{L}\p{N}'’-]+\b"#)
        let matches = regex?.matches(in: text, range: fullRange) ?? []
        guard !matches.isEmpty, !timings.isEmpty else { return timings }

        func normalized(_ value: String) -> String {
            value
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .unicodeScalars
                .filter { CharacterSet.alphanumerics.contains($0) }
                .map(String.init)
                .joined()
        }

        let normalizedMatches: [(range: NSRange, token: String)] = matches.compactMap { match in
            let token = nsText.substring(with: match.range)
            let normalizedToken = normalized(token)
            guard !normalizedToken.isEmpty else { return nil }
            return (match.range, normalizedToken)
        }

        guard !normalizedMatches.isEmpty else { return timings }

        var remapped: [AlignedWordTiming] = []
        var cursor = 0

        for timing in timings {
            let normalizedTiming = normalized(timing.word)
            guard !normalizedTiming.isEmpty else { continue }

            var chosenIndex = cursor
            while chosenIndex < normalizedMatches.count, normalizedMatches[chosenIndex].token != normalizedTiming {
                chosenIndex += 1
            }

            if chosenIndex >= normalizedMatches.count {
                chosenIndex = min(cursor, normalizedMatches.count - 1)
            }

            let range = normalizedMatches[chosenIndex].range
            let renderedWord = nsText.substring(with: range)
            remapped.append(
                AlignedWordTiming(
                    word: renderedWord,
                    startTime: timing.startTime,
                    endTime: timing.endTime,
                    startOffset: range.location,
                    endOffset: NSMaxRange(range)
                )
            )
            cursor = min(chosenIndex + 1, normalizedMatches.count)
        }

        return remapped.isEmpty ? timings : remapped
    }

    private func startCueTimer() {
        cueTimer?.invalidate()
        cueTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.emitCueIfNeeded()
            }
        }
        cueTimer?.tolerance = 1.0 / 240.0
        if let cueTimer {
            RunLoop.main.add(cueTimer, forMode: .common)
        }
    }

    private func emitCueIfNeeded(at timeOverride: TimeInterval? = nil) {
        guard let player else { return }
        let currentTime = timeOverride ?? player.currentTime
        guard player.isPlaying || timeOverride != nil else { return }
        publishPlaybackProgress()

        guard let wordIndex = wordIndex(for: currentTime), displayWordCues.indices.contains(wordIndex) else { return }
        guard wordIndex != lastEmittedWordIndex else { return }
        lastEmittedWordIndex = wordIndex
        let displayRange = displayWordCues[wordIndex].range
        if displayRange.location != NSNotFound, displayRange.length > 0 {
            delegate?.speechAdapter(self, willSpeak: displayRange, utterance: currentText)
        }
    }

    private func wordIndex(for time: TimeInterval) -> Int? {
        guard !displayWordCues.isEmpty else { return nil }

        if let lastEmittedWordIndex, displayWordCues.indices.contains(lastEmittedWordIndex) {
            let current = displayWordCues[lastEmittedWordIndex]
            if time >= current.startBoundary, time < current.endBoundary {
                return lastEmittedWordIndex
            }
        }

        var low = 0
        var high = displayWordCues.count - 1
        var best = 0
        while low <= high {
            let mid = (low + high) / 2
            if displayWordCues[mid].startBoundary <= time {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return best
    }

    private func buildDisplayWordCues(from timings: [AlignedWordTiming], totalDuration: TimeInterval) -> [DisplayWordCue] {
        guard !timings.isEmpty else { return [] }
        if timings.count == 1 {
            return [
                DisplayWordCue(
                    range: timings[0].range,
                    startBoundary: 0,
                    endBoundary: max(totalDuration, timings[0].endTime, 0.01)
                )
            ]
        }

        let startTimes = timings.map(\.startTime)
        let positiveGaps = zip(startTimes.dropLast(), startTimes.dropFirst())
            .map { max(0, $1 - $0) }
            .filter { $0 > 0.015 }
            .sorted()
        let medianGap = positiveGaps.isEmpty
            ? max(totalDuration / Double(max(timings.count, 1)), 0.12)
            : positiveGaps[positiveGaps.count / 2]
        let averageWindow = max(totalDuration / Double(max(timings.count, 1)), 0.04)
        let minimumWindow = min(max(averageWindow * 0.28, 0.045), 0.11)
        let lead = min(max(medianGap * 0.32, 0.07), 0.24)

        var boundaries = Array(repeating: 0.0, count: timings.count + 1)
        boundaries[0] = 0
        boundaries[timings.count] = max(totalDuration, timings.last?.endTime ?? totalDuration, 0.01)

        for index in 1..<timings.count {
            let midpoint = (timings[index - 1].startTime + timings[index].startTime) / 2
            let rawBoundary = max(0, midpoint - lead)
            let minAllowed = boundaries[index - 1] + minimumWindow
            let remainingWords = timings.count - index
            let maxAllowed = max(minAllowed, boundaries[timings.count] - (Double(remainingWords) * minimumWindow))
            boundaries[index] = min(max(rawBoundary, minAllowed), maxAllowed)
        }

        return timings.enumerated().map { index, timing in
            DisplayWordCue(
                range: timing.range,
                startBoundary: boundaries[index],
                endBoundary: max(boundaries[index + 1], boundaries[index] + 0.01)
            )
        }
    }

    private func publishPlaybackProgress() {
        guard let player else { return }
        delegate?.speechAdapter(self, didUpdatePlaybackTime: player.currentTime, duration: player.duration)
    }
}

extension LocalModelSpeechAdapter: @preconcurrency AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stop()
        delegate?.speechAdapterDidFinishPlayback(self, successfully: flag)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        stop()
        delegate?.speechAdapterDidFinishPlayback(self, successfully: false)
    }
}

extension SpeechPlaybackService: SpeechBackendAdapterDelegate {
    func speechAdapterDidFinishPlayback(_ adapter: SpeechBackendAdapter, successfully: Bool) {
        didFinishSpeaking(successfully: successfully)
    }

    func speechAdapter(_ adapter: SpeechBackendAdapter, willSpeak range: NSRange, utterance: String) {
        willSpeakWord(range: range, in: utterance)
    }

    func speechAdapter(_ adapter: SpeechBackendAdapter, didUpdatePlaybackTime currentTime: TimeInterval, duration: TimeInterval) {
        guard let article = currentArticle, let currentChunkIndex else { return }
        updateTimelineDuration(duration, forChunkAt: currentChunkIndex, in: article)
        let absoluteTime = timeline(for: article).absoluteTime(forChunkAt: currentChunkIndex, chunkTime: currentTime)
        currentPlaybackOffset = absoluteTime
        article.lastPlaybackOffset = absoluteTime
        let total = totalDuration(for: article)
        currentProgress = total > 0 ? min(max(absoluteTime / total, 0), 1) : article.readingProgress
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
