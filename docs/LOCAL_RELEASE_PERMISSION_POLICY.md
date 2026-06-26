# Local And Release Permission Policy

Current version: `v3.7.0`.

DesktopVisual maintains two separate project postures:

## Local Development Tree

Path:

```text
D:\desktopvisual
```

`D:\desktopvisual` is the local development and future evaluation tree. It may keep the broadest project permission surface for controlled local development, simulated-exam correctness measurement, operation-accuracy measurement, and future runtime optimization.

This local posture still does not permit credential handling, captcha solving, payment automation, UAC or protected desktop control, anti-cheat bypass, anti-automation bypass, paid-limit bypass, high-frequency batch submit, or problem-set scraping.

## Public Release Tree

Path:

```text
D:\desktopvisual-release
```

Public release must not be made by submitting `D:\desktopvisual` directly. Before publication, create a separate `D:\desktopvisual-release` tree and apply the restricted release permission policy there.

In `D:\desktopvisual-release`, exam, interview assessment, hiring test, certification, rated-contest, proctored, and similar workflows must be disabled or gated by a dedicated permission model before distribution.

The release tree must not include local artifacts, raw motion data, browser profiles, sensitive logs, local FULL_ACCESS session state, or the local development tree's broad test posture.

## Required Release Review

- Confirm `VERSION`, `README.md`, `CHANGELOG.md`, `COMMAND_PROTOCOL.md`, `docs\SAFETY_MODEL.md`, and `docs\KNOWN_LIMITATIONS.md` describe the restricted release posture.
- Confirm release packaging excludes `artifacts`, `bin`, `obj`, `dist`, browser profiles, raw motion data, sensitive logs, and local permission session state.
- Confirm assessment/exam-like workflows have release-specific restrictions before publication.
