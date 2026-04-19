# Playback Persistence Policy

## Intent

Playback state should feel predictable across new articles, reopened articles, and backend changes.

## Source of Truth

Per-article playback state lives on `Article`:

- `lastBackendIdentifier`
- `lastVoiceIdentifier`
- `lastSpeed`
- `lastReadPosition`
- `lastPlaybackOffset`
- `lastPlayedAt`
- `isFinished`

## Rules

### Speed

- New articles default to `1.5x`.
- If an untouched prototype-era article still has `1.0x` and has never been played, it is upgraded to `1.5x`.
- User-selected speeds are never overwritten after an article has been meaningfully used.

### Backend

- Each article remembers the last backend used.
- Valid values are currently:
  - `system`
  - `kokoro`
  - `qwen3`
- If the remembered backend is unavailable or fails at playback time, the app falls back to `system`.

### Voice

- Each article remembers the last selected voice within its backend.
- If the remembered voice is unavailable for the current backend, the app chooses the backend's first curated fallback voice.

### Resume Position

- `lastReadPosition` is the authoritative text offset for resume.
- `lastPlaybackOffset` is a derived estimate used for time display and 30-second jump behavior.
- System voices update the position at word granularity.
- Local model backends update position at paragraph/chunk boundaries.

### Finished State

- An article is marked finished when playback reaches the end of the normalized body text.
- Seeking near the end or replaying from the middle can clear the finished state again.

## Why This Policy Exists

- We want new content to start at the intended product default without stomping on user intent.
- We want backend upgrades to feel sticky per article.
- We want the app to degrade gracefully when local model setup is incomplete or a backend fails.
