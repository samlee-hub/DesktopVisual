# Release Notes

## DesktopVisual 1.0.0 Public RC3

RC3 adds public release package instructions for agent tools. Runtime behavior is unchanged from RC2.

Changes:

- Added public-safe DesktopVisual Visible-UI-First Skill.
- Added AGENTS.md release package instructions.
- Added package selftest coverage for the public skill and AGENTS instructions.
- No runtime behavior changes.
- No safety policy behavior changes.
- No F12 behavior changes.
- No source code included.

RC3 package:

- `DesktopVisual-1.0.0-public-rc3.zip`
- `DesktopVisual-1.0.0-public-rc3.sha256.txt`

Run from the directory containing the downloaded files:

```powershell
Get-FileHash .\DesktopVisual-1.0.0-public-rc3.zip -Algorithm SHA256
Get-Content .\DesktopVisual-1.0.0-public-rc3.sha256.txt
```

Only run the package when the SHA256 values match and the package was downloaded from the official GitHub Release.

## DesktopVisual 1.0.0 Public RC2

RC2 fixes public release experience issues found after RC1 external download validation.

Changes:

- README and user docs now clearly state that the GitHub repository is a public documentation repository, not the runnable package.
- Installation guidance now directs users to GitHub Releases for `DesktopVisual-1.0.0-public-rc2.zip`.
- Documentation now warns that `git clone` and GitHub `Code` > `Download ZIP` are not installation methods.
- Windows first-run guidance now states that the public RC binary is not code signed.
- SHA256 verification guidance is included before running the package.
- `winagent.exe serve --help` and `winagent.exe serve /?` now print help and exit with code 0 instead of entering the service loop.
- `serve_help_selftest.ps1` covers the help behavior and confirms it does not start a long-running service.

RC2 package:

- `DesktopVisual-1.0.0-public-rc2.zip`
- `DesktopVisual-1.0.0-public-rc2.sha256.txt`

## Safety Notes

The public release safety policy is unchanged from RC2. It is not a keyword-only denylist, and ordinary `test`, `quiz`, or `exam` words do not stop automation by themselves.

The policy stops automation in explicit exam-integrity restricted contexts and active protection contexts such as CAPTCHA, human verification, credential/account checks, proctoring, lockdown browser, anti-cheat, and anti-automation.

F12 behavior is unchanged. F12 stops the current task only and does not terminate the `winagent.exe` process.

The default/full_access user mode selector remains deferred.

## Signing Status

The RC3 binary is not code signed. Windows or security software may prompt on first run. The package is not claimed to be Microsoft Defender certified, SmartScreen allowlisted, or enterprise distribution certified. Code signing is planned for future evaluation and is not an RC3 blocker.
