# Recovery Draft

Current version: `v1.0.0`.

This document is a strategy note only. There is no `RecoveryEngine`, automatic retry loop, or hidden recovery behavior in v1.0.0.

## WINDOW_NOT_FOUND

Stop and ask the user to open the target window.

## WINDOW_NOT_UNIQUE

Stop and ask the user to close duplicate windows or use a more precise title.

## ASSERTION_FAILED

Stop and preserve screenshots, the Markdown report, state files, and logs for review.

## INVALID_ARGUMENT

Stop and report that the case file or command arguments are invalid.

## SEND_INPUT_FAILED

Stop and report likely causes: permissions, focus restrictions, or system input limitations.

## SCREENSHOT_FAILED

Stop and report likely causes: minimized window, blocked capture API, or unsupported window rendering.
