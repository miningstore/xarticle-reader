# TTS Strategy

## Goal

Give users a better listening experience than the default macOS voices while keeping the app local-first on Apple Silicon Macs.

## What We Evaluated

### Whisper

Whisper is not a text-to-speech engine. It is speech-to-text, so it does not solve the voice-quality problem for this app.

### NVIDIA Magpie TTS Zeroshot

We investigated the NVIDIA Magpie path first because it offers high-quality expressive voices. It is not a practical local solution for this project's current target machine.

Why:

- NVIDIA's downloadable TTS NIM requires Linux plus an NVIDIA GPU with compute capability 8.0 or higher.
- The target app is a native macOS app running on Apple Silicon.
- Magpie Zeroshot can be used through hosted NVIDIA endpoints, but that would change the product from local-first playback to network-backed playback.

Official sources reviewed:

- NVIDIA TTS support matrix: https://docs.nvidia.com/nim/speech/latest/reference/support-matrix/tts.html
- NVIDIA TTS deploy guide: https://docs.nvidia.com/nim/speech/latest/tts/deploy-tts-model.html

Conclusion:

- Do not use NVIDIA Magpie as the primary local backend for this app.
- If we ever want a cloud/hosted premium voice tier later, Magpie can be revisited as an optional remote backend.

### Piper vs Coqui

We performed practical install tests on this Mac:

- `piper-tts` installed quickly and cleanly.
- `TTS` (Coqui) installed, but it brought a much heavier dependency stack.

Conclusion:

- Piper remains a strong lightweight fallback candidate.
- Coqui is not the right first integration for this macOS reader because it adds too much runtime and packaging weight for the value delivered.

### Hugging Face on Apple Silicon

The best Apple Silicon direction is to use MLX-native or MLX-compatible Hugging Face models through a common local runtime.

Two model families stood out:

- `Kokoro-82M`
- `Qwen3-TTS`

Key sources:

- Kokoro model card: https://huggingface.co/hexgrad/Kokoro-82M
- Kokoro ONNX port: https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX
- MLX-Audio: https://github.com/Blaizzy/mlx-audio
- Argmax OSS Swift / TTSKit: https://github.com/argmaxinc/argmax-oss-swift

## Final Product Decision

The app now supports three speech paths:

1. `System`
   - Built-in macOS voices
   - Instant availability
   - Best fallback and lowest-risk default

2. `Kokoro`
   - Fast local Hugging Face voice option
   - Lower setup/download cost than larger models
   - Best first upgrade over system voices

3. `Qwen3`
   - Higher-quality local Hugging Face voice option
   - Heavier model download and slower first-run setup
   - Better "premium local" choice for users who want better voice quality

## Why This Architecture

We chose one common Apple Silicon runtime path instead of separate one-off integrations:

- `mlx-audio` can run both Kokoro and Qwen3-TTS locally on Apple Silicon.
- A shared runtime keeps installation, invocation, and fallback behavior simpler.
- The app can offer both a lightweight model and a higher-quality model without maintaining unrelated backend stacks.

## UX Rules

- The app always keeps `System` available as the baseline fallback.
- `Kokoro` and `Qwen3` are opt-in local upgrades.
- First use of either local model may trigger dependency install and model download.
- If a local model fails, the app falls back to `System` instead of leaving playback broken.

## Tradeoffs Accepted

- Word-perfect highlighting is preserved only for the system backend.
- Local model backends currently operate at paragraph/chunk granularity.
- First-run setup for local models is slower because dependencies and weights are installed on demand.

## Future Notes

- If we later want lower-latency streaming local playback, we can revisit tighter integration paths such as native Core ML wrappers or TTSKit-style streaming.
- If a hosted premium tier ever becomes desirable, NVIDIA Magpie remains a candidate for a remote backend, not a local one.
