# XArticleReader

XArticleReader is a local-first macOS reader for long-form pasted articles. You can save articles, listen with local Apple Silicon TTS models, jump around the text, review highlights and notes, and keep your reading history entirely on your Mac.

## What it does

- Paste and save long-form articles locally
- Browse saved article history in a sidebar
- Read in a focused desktop reader with timestamp markers
- Listen with local `Kokoro` or local `Qwen3` voices on Apple Silicon
- Keep playback speed, voice, article position, highlights, and notes locally
- Click in the text or on the scrubber to jump playback
- Auto-follow the currently spoken text while listening
- Cache generated audio locally so replay does not regenerate the same chunk again
- Cache per-word timing sidecars from the generated audio so word highlighting is driven by real aligned timings instead of guessed word weights

## Requirements

- macOS 14 or later
- Apple Silicon Mac
- Xcode Command Line Tools
- Internet access the first time a local model and the tiny alignment model are downloaded

Why Apple Silicon only:

- The local TTS backends here use MLX-based Hugging Face models (`Kokoro` and `Qwen3`), which are meant for Apple Silicon Macs.

## Build

```bash
git clone https://github.com/YOUR-USERNAME/xarticle-reader.git
cd xarticle-reader
swift build
```

## Run

```bash
swift run XArticleReader
```

You can also launch the built binary directly:

```bash
./.build/arm64-apple-macosx/debug/XArticleReader
```

## First-run behavior

On the first local playback run, the app may:

1. create an isolated Python runtime under `~/Library/Application Support/XArticleReader/LocalTTS`
2. install local runtime dependencies
3. download the selected local TTS model
4. download the tiny local alignment model used to produce word-level timing sidecars
5. generate and cache audio for the article chunk

After that:

- repeated playback of the same chunk/voice/speed combination reuses cached audio
- word highlighting reuses cached timing sidecars generated from that audio

## Local storage

The app stores its data locally on your Mac with SwiftData. Generated model runtime files and cached audio live under:

```text
~/Library/Application Support/XArticleReader/
```

## Validation

The main validation flow used during development was:

```bash
swift build
```

and a direct local runtime probe that:

- synthesized Kokoro audio
- generated a cached word-timing sidecar from the real WAV with Faster-Whisper
- verified cached playback reused the saved audio instead of regenerating it

## Current scope

- Paste-first article intake
- No direct X URL fetching yet
- Local-only storage
- Local model playback with cached audio and aligned word highlighting

## Notes

- The alignment path is built on top of the generated local audio itself, so the word highlight timing is based on a real timing sidecar rather than a text-length estimate.
- If you change the article text, voice, or speed, the app generates a new cached audio variant for that combination.
