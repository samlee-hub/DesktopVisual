# Public Release Guide

DesktopVisual public releases are distributed as closed-source Windows binary packages through GitHub Releases.

The GitHub repository is for public documentation, agent instruction files, and checksums. It is not the installable package and it does not contain source code.

## Correct Install Path

Use this path:

1. Open the GitHub Release page.
2. Download `DesktopVisual-1.0.0-public-rc3.zip`.
3. Download `DesktopVisual-1.0.0-public-rc3.sha256.txt`.
4. Verify the SHA256.
5. Extract the zip.
6. Run commands from the extracted package root.

Do not use these paths:

- `git clone https://github.com/samlee-hub/DesktopVisual`
- GitHub `Code` > `Download ZIP`

Those paths download documentation only and are not expected to run.

## SHA256 Verification

```powershell
Get-FileHash .\DesktopVisual-1.0.0-public-rc3.zip -Algorithm SHA256
Get-Content .\DesktopVisual-1.0.0-public-rc3.sha256.txt
```

Do not run the package if the values differ.

## Agent Instructions

The release package includes `AGENTS.md` and `skills/desktopvisual-visible-ui-first/SKILL.md`.

`skills/desktopvisual-visible-ui-first/SKILL.md` is included in the release package so agent tools can follow DesktopVisuals intended operation priority.

Agents should read both files before using DesktopVisual for desktop automation tasks.

DesktopVisual operation priority:

1. Visible UI operation first.
2. Keyboard shortcut fallback only when visible UI operation cannot continue reliably.
3. Backend/non-UI operation only when the visible window is unusable or the user explicitly asks for backend work.

## Windows First Run

The public RC binary is not code signed. Windows, SmartScreen, Microsoft Defender, or third-party security software may show a first-run confirmation.

This release is not claimed to be Microsoft Defender certified, SmartScreen allowlisted, or enterprise distribution certified.

Only run the package if you downloaded it from the official GitHub Release and verified SHA256. If you do not trust the source, do not run it.

Code signing is planned for future evaluation and is not an RC3 blocker.

## Service Help

To view service help without starting the service loop:

```powershell
.\bin\winagent.exe serve --help
.\bin\winagent.exe serve /?
```

Both commands print help and exit with code 0.

## Intended Use

Use DesktopVisual for authorized Windows desktop automation, browser form workflows, file operations, communication drafts, local workflows, developer tests, and personal tasks where automation is permitted.

## Not Intended For

Do not use DesktopVisual to violate explicit rules for exams, assessments, interviews, contests, or platform evaluations. Do not use it to bypass CAPTCHA, human verification, credential or account checks, proctoring, lockdown browser, anti-cheat, anti-automation, or third-party security controls.

## Safety Behavior

The release policy is context based. It does not stop only because a page contains `test`, `quiz`, or `exam`.

It stops when the environment contains clear assessment integrity rules or active protection and the requested automation would answer, submit, fill answers, complete the assessment, or bypass restrictions.

## F12

Press F12 to force-exit the current task. The `winagent.exe` process remains alive and the runtime reports `STOP_USER_FORCE_EXIT_F12` with `process_exit=false`.

## Deferred Items

- default/full_access user mode selector = deferred
- limited access mode = deferred
- per-task permission mode = deferred
