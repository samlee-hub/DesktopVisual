# Known Limitations

DesktopVisual 1.0.0 Public RC2 is a local Windows desktop automation runtime for visible UI workflows. It is a public binary release candidate, not a source release.

This remains a local Windows desktop automation project.

## Package And Installation

- The GitHub repository is a public documentation repository.
- Source code is not included in the public release.
- GitHub `Code > Download ZIP` is not the installation method.
- `git clone` does not provide a runnable package.
- Users should download the release zip from GitHub Releases, verify the SHA256 file, extract the zip, and run commands from the extracted package root.

## Platform Scope

- Windows is required.
- Behavior depends on the active desktop, focused windows, display scaling, accessibility exposure, and application layout.
- DesktopVisual controls visible UI workflows. It is not designed for hidden background windows or protected desktop surfaces.
- Some applications may expose limited UI Automation metadata, which can reduce reliability.

## Unsigned Binary Notice

- The public RC binary is not code-signed.
- Windows or security software may show a first-run confirmation.
- Users should run the binary only if it was downloaded from the official GitHub Release and the SHA256 hash matches the published checksum.
- If the source or checksum cannot be trusted, users should not run the binary.
- Code signing will be evaluated after RC2 and is not a blocker for this release candidate.

## Safety Boundaries

DesktopVisual does not bypass or automate:

- CAPTCHA or human verification.
- Account security verification.
- Credential entry or credential extraction.
- Proctoring, lockdown browser, or exam monitoring.
- Anti-cheat or anti-automation controls.
- Payment confirmation.
- Protected desktop or administrator prompts.
- Tasks that violate explicit exam, assessment, interview, contest, or platform rules.

## Public Release Safety Policy

The public release safety policy is intentionally narrow. It does not stop merely because a page contains words such as `test`, `quiz`, or `exam`.

The runtime stops when the current context forms a clear exam-integrity risk, such as a formal assessment environment that explicitly prohibits external assistance, AI assistance, scripts, automation, cheating, or similar restricted conduct.

## F12 Force Exit

F12 stops the current task only. It does not terminate the `winagent.exe` process. After F12, the runtime records a structured force-exit stop and remains available for later commands.

## Reliability

- UI automation can be affected by focus changes, window movement, DPI scaling, pop-ups, and application updates.
- Selftests confirm the public package behavior on the current machine; they are not a guarantee that every third-party app or website will work.
- The public package does not include legacy development evidence, runtime sessions, debug screenshots, or source code.

## Deferred Items

- `default/full_access user mode selector = deferred`
- Code signing is deferred for evaluation after RC2.
- Enterprise deployment certification is not included in RC2.
- Source publication is not part of this public release candidate.
