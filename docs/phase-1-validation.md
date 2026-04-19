# Phase 1 Validation

Use this checklist to validate the stabilized single-backend and fallback experience.

## Reader Readability

- Open a saved article in light appearance and confirm the body text is clearly legible.
- Open a saved article in dark appearance and confirm the body text is clearly legible.
- Confirm there is no white-on-white or low-contrast text in the reader, metadata row, or player bar.
- Select text and verify the selection chip remains readable.
- Add a highlight and confirm the highlight remains visible without obscuring the text.

## Playback Defaults

- Create a brand-new article and confirm playback defaults to `1.5x`.
- Reopen that article and confirm it still shows the same speed.
- Change the speed, reopen the article, and confirm the user-selected speed persists.
- Reopen an older article created before the default change and confirm the app follows the persistence policy.

## System Voice Experience

- Confirm the built-in system voice list is curated and readable.
- Use the preview button and confirm preview playback works without corrupting article progress.
- Switch between multiple system voices and confirm playback restarts cleanly.

## Core Playback

- Start playback on a saved article.
- Pause and resume playback.
- Jump backward 30 seconds.
- Jump forward 30 seconds.
- Close and reopen the app, then confirm the article resumes near the saved position.

## Highlighting

- While using the system backend, confirm the active paragraph highlight updates as playback moves.
- Confirm active word highlighting updates while the system backend is speaking.
- Save multiple manual highlights and confirm they remain attached to the correct text after reopening.

## Failure Handling

- Switch voices during playback and confirm the app recovers cleanly.
- Stop playback and start again from the current article without needing to reload the app.
