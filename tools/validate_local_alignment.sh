#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROBE_SWIFT="$(mktemp /tmp/xar-alignment-probe.XXXXXX.swift)"
PROBE_BIN="$(mktemp /tmp/xar-alignment-probe.XXXXXX)"
PROBE_WAV="/tmp/xar_alignment_probe.wav"

cleanup() {
  rm -f "$PROBE_SWIFT" "$PROBE_BIN" "$PROBE_WAV"
}
trap cleanup EXIT

echo "[xarticle-reader] building package"
(cd "$ROOT" && swift build)

cat >"$PROBE_SWIFT" <<'SWIFT'
import Foundation

@main
struct Probe {
    static func main() async throws {
        let outputURL = URL(fileURLWithPath: "/tmp/xar_alignment_probe.wav")
        let request = LocalModelSynthesisRequest(
            backendID: .kokoro,
            voiceID: "kokoro:af_heart",
            text: "Hello world. This is a test of alignment driven highlighting.",
            speed: 1.0,
            outputURL: outputURL
        )

        try await LocalModelTTSRuntime.shared.synthesize(request) { status in
            print("STATUS|\(String(format: "%.3f", status.progress))|\(status.message)")
        }

        let timings = await LocalModelTTSRuntime.shared.cachedWordTimings(for: request) ?? []
        print("TIMING_COUNT|\(timings.count)")
        for timing in timings {
            print("WORD|\(timing.word)|\(timing.startTime)|\(timing.endTime)|\(timing.startOffset)|\(timing.endOffset)")
        }
        print("OUTPUT_EXISTS|\(FileManager.default.fileExists(atPath: outputURL.path))")
    }
}
SWIFT

echo "[xarticle-reader] compiling runtime probe"
swiftc \
  -o "$PROBE_BIN" \
  "$ROOT/Sources/XArticleReader/SpeechSupport.swift" \
  "$ROOT/Sources/XArticleReader/LocalModelTTSRuntime.swift" \
  "$PROBE_SWIFT"

echo "[xarticle-reader] running runtime probe"
"$PROBE_BIN"
