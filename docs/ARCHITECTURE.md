# Architecture

DesktopVisual 1.0.0 Public RC2 is a local Windows desktop automation runtime for visible UI workflows. The public package is a closed-source binary release candidate.

## Public Package Layout

```text
bin/
  winagent.exe
config/
  safety.conf
  safety_manifest.json
docs/
  ARCHITECTURE.md
  KNOWN_LIMITATIONS.md
  PUBLIC_RELEASE_GUIDE.md
  ROADMAP.md
  USER_QUICKSTART.md
README.md
RELEASE_NOTES.md
PUBLIC_RELEASE_SAFETY_POLICY.md
COMMAND_PROTOCOL.md
*.ps1 selftests
```

Source code and developer evidence are not part of the public package.

## Runtime Boundary

The runtime operates locally on visible Windows UI surfaces. It is designed for user-authorized desktop workflows such as local desktop automation, browser form tasks, file operations, communication drafts, local workflow testing, and developer validation.

The runtime does not provide a protected-desktop bypass, credential bypass, CAPTCHA bypass, anti-cheat bypass, proctoring bypass, or account security bypass.

## Command Layer

The public command layer exposes a small set of user-facing commands and selftests:

- `winagent.exe version`
- `winagent.exe serve`
- `winagent.exe serve --help`
- `winagent.exe serve /?`
- Public package selftests and acceptance gate scripts.

`serve --help` and `serve /?` are help-only paths. They print service help and exit with code `0`.

## F12 Force Exit

F12 is handled as current-task cancellation. It stops the current automation task, releases input state, records structured evidence, and keeps the `winagent.exe` process available for future commands.

F12 stop code:

```text
STOP_USER_FORCE_EXIT_F12
```

## Public Release Safety Policy

The public release safety policy stops automation in explicit exam-integrity restricted contexts. It is not a simple keyword denylist. Ordinary learning, practice, documentation, local test pages, and forms are allowed when they do not include explicit restrictions against external assistance, AI assistance, cheating, scripts, or automation.

Safety stop code:

```text
STOP_PUBLIC_RELEASE_EXAM_INTEGRITY_POLICY
```

## Package Verification

The RC2 package is verified with:

- Package selftest.
- Serve help selftest.
- F12 force-exit selftest.
- Public release safety policy tests.
- Allowed-context tests.
- Package privacy scan.
- Package structure verifier.
- Package acceptance gate.

The package excludes source code, repository metadata, runtime session artifacts, developer evidence, debug screenshots, browser cache, build intermediates, credentials, tokens, and private local paths.

## Distribution Model

The GitHub repository contains public documentation. The runnable artifact is distributed only through GitHub Releases as a zip package plus a SHA256 checksum file.
