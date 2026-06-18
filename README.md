# DesktopVisual 1.0.0 Public RC2

This repository is the public documentation repository for DesktopVisual. It is not the runnable application package.

Important:

- Source code is not included in the public release.
- Do not install DesktopVisual by using `git clone`.
- Do not install DesktopVisual by using GitHub `Code` > `Download ZIP`.
- The repository ZIP only contains public documentation and checksum text.
- Download the runnable Windows package from Releases:
  `DesktopVisual-1.0.0-public-rc2.zip`
- Download the checksum file from the same Release:
  `DesktopVisual-1.0.0-public-rc2.sha256.txt`
- Extract the release zip and run commands from the extracted package root.

Release page:

https://github.com/samlee-hub/DesktopVisual/releases/tag/v1.0.0-public-rc2

## Verify The Download

After downloading the RC2 zip and checksum file from GitHub Releases:

```powershell
Get-FileHash .\DesktopVisual-1.0.0-public-rc2.zip -Algorithm SHA256
Get-Content .\DesktopVisual-1.0.0-public-rc2.sha256.txt
```

Expected RC2 SHA256:

```text
ff2e3e345e2a7484dbe8179ec768b77fc44594b907657c21dbeaf62a5f0b0736
```

The two values must match. If they do not match, do not run the package.

## Windows First Run Notice

The DesktopVisual public RC binary is not code signed. Windows, Microsoft Defender SmartScreen, or third-party security software may show a first-run warning or confirmation prompt.

Only run the binary if all of the following are true:

- You downloaded it from the official GitHub Release.
- The SHA256 hash matches the published checksum.
- You trust the release source and intended local automation use.

If you do not trust the source, do not run it. Code signing is planned for future evaluation and is not a blocker for this RC2 package.

This release is not claimed to be Microsoft Defender certified, SmartScreen allowlisted, or enterprise distribution certified.

## What DesktopVisual Is For

DesktopVisual is a local Windows desktop automation runtime for visible UI workflows. This public release is intended for authorized local desktop automation, browser form workflows, local file workflows, communication drafts, developer tests, and personal tasks where automation is permitted.

## What DesktopVisual Is Not For

Do not use this package to violate explicit rules for exams, assessments, interviews, contests, or platform evaluations. Do not use it to bypass CAPTCHA, human verification, credential or account checks, proctoring, lockdown browser, anti-cheat, anti-automation, or third-party security controls.

The public release policy is context based. It is not a keyword-only blocker. Words such as `test`, `quiz`, `exam`, `OJ`, or `LeetCode` do not stop automation by themselves.

## Basic Package Commands

Run from the extracted release package root:

```powershell
.\bin\winagent.exe version
.\bin\winagent.exe serve --help
.\selftest.ps1
.\serve_help_selftest.ps1
.\public_release_acceptance_gate.ps1
```

`F12` stops the current task only and returns `STOP_USER_FORCE_EXIT_F12`. It does not close `winagent.exe`.

The default/full_access user mode selector is deferred in this release candidate:

- default/full_access user mode selector = deferred
