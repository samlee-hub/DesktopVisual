# Roadmap

DesktopVisual 1.0.0 Public RC2 is focused on a small, publishable Windows binary package for local visible UI automation workflows.

## Current RC2 Scope

- Public documentation repository.
- Closed-source public binary package.
- Windows local runtime binary.
- SHA256 checksum file.
- F12 force-exit support for the current task.
- Public release safety policy for explicit exam-integrity restricted contexts.
- Package selftests and acceptance gate.
- Clear install guidance that points users to GitHub Releases instead of `git clone` or GitHub `Code > Download ZIP`.
- Windows first-run notice for the unsigned RC binary.
- `serve --help` and `serve /?` help output that exits immediately.

## Near-Term Priorities

- Continue validating public package installation and first-run behavior.
- Evaluate code signing options for future release candidates.
- Improve user-facing diagnostics for package selftests.
- Keep public package contents limited to redistributable binary, documentation, checksums, and public-safe scripts.
- Continue verifying that public packages exclude source code, runtime sessions, debug screenshots, developer evidence, browser cache, credentials, tokens, and private paths.

## Safety Direction

DesktopVisual will keep the public safety boundary explicit:

- Do not bypass CAPTCHA, human verification, account verification, proctoring, lockdown browsers, anti-cheat, anti-automation, protected desktop, payment confirmation, or credential flows.
- Do not assist with violating explicit exam, assessment, interview, contest, or platform rules.
- Do not use a simple keyword denylist for ordinary learning, practice, documentation, or local testing contexts.

## Deferred

- `default/full_access user mode selector = deferred`
- Source publication is deferred.
- Code signing is deferred for post-RC2 evaluation.
- Enterprise deployment certification is deferred.
- Broader platform support beyond local Windows desktop automation is deferred.

## Non-Goals For RC2

- Publishing source code.
- Adding new runtime permissions.
- Changing the public release safety policy behavior.
- Changing F12 behavior.
- Adding a default/full_access selector.
- Shipping developer artifacts or runtime sessions.
- Shipping legacy UI workflow evidence.
