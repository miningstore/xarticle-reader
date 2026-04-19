# Phase 2 Validation

Use this checklist to validate the multi-backend local voice architecture.

## Backend Selection

- Confirm the app exposes `System`, `Kokoro`, and `Qwen3`.
- Switch backends for an article and confirm the backend label updates in the reader and player UI.
- Save an article, reopen it, and confirm the previously used backend is restored.

## First-Run Local Model Setup

- Select `Kokoro` on a machine with no prepared local runtime and confirm the app starts preparing the local runtime.
- Confirm `Kokoro` downloads and plays locally after setup completes.
- Select `Qwen3` on a machine with no prepared model weights and confirm setup and playback eventually succeed.
- Confirm status text explains what is happening during first-run setup.

## Fallback Behavior

- Simulate local model failure by interrupting dependency installation or breaking the runtime and confirm the app falls back to `System`.
- Confirm fallback does not corrupt the article's text position.
- Confirm the user still has at least one playable voice after a backend failure.

## Persistence

- Choose `Kokoro` and a Kokoro voice, reopen the article, and confirm both persist.
- Choose `Qwen3` and a Qwen3 voice, reopen the article, and confirm both persist.
- Confirm `lastSpeed` persists across all three backends.

## Playback Semantics

- Confirm `System` still supports word-level highlight updates.
- Confirm `Kokoro` playback works with paragraph-level progress and no crashes.
- Confirm `Qwen3` playback works with paragraph-level progress and no crashes.
- Confirm pause, resume, and 30-second jumps still work after backend switching.

## Capability-Aware UX

- Confirm the UI communicates which backend is active.
- Confirm preview works for all available backends.
- Confirm the app remains usable while local-model setup is happening.

## Relaunch Safety

- Relaunch the app after using `Kokoro` and confirm it can play again without reinstalling dependencies.
- Relaunch the app after using `Qwen3` and confirm it can play again without reinstalling dependencies.
- Confirm missing or stale local assets degrade gracefully instead of crashing the app at launch.
