# Public Release Guide

DesktopVisual public releases are distributed as closed-source Windows binary packages through GitHub Releases.

The GitHub repository is for public documentation and checksums. It is not the installable package and it does not contain source code.

## Correct Install Path

Use this path:

1. Open the GitHub Release page.
2. Download `DesktopVisual-1.0.0-public-rc2.zip`.
3. Download `DesktopVisual-1.0.0-public-rc2.sha256.txt`.
4. Verify the SHA256.
5. Extract the zip.
6. Run commands from the extracted package root.

Do not use these paths:

- `git clone https://github.com/samlee-hub/DesktopVisual`
- GitHub `Code` > `Download ZIP`

Those paths download documentation only and are not expected to run.

## SHA256 Verification

```powershell
Get-FileHash .\DesktopVisual-1.0.0-public-rc2.zip -Algorithm SHA256
Get-Content .\DesktopVisual-1.0.0-public-rc2.sha256.txt
```

Expected RC2 SHA256:

```text
ff2e3e345e2a7484dbe8179ec768b77fc44594b907657c21dbeaf62a5f0b0736
```

Do not run the package if the values differ.

## Windows First Run

The public RC binary is not code signed. Windows, SmartScreen, Microsoft Defender, or third-party security software may show a first-run confirmation.

This release is not claimed to be Microsoft Defender certified, SmartScreen allowlisted, or enterprise distribution certified.

Only run the package if you downloaded it from the official GitHub Release and verified SHA256. If you do not trust the source, do not run it.

Code signing is planned for future evaluation and is not an RC2 blocker.

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
