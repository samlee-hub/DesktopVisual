# Local-Use And Future Public Release Permission Policy

Current version: `v1.1.12`.
Current authority: `CURRENT_EXECUTION_CONTRACT.md`.
Release channel details: `docs\RELEASE_CHANNELS.md`.
Launch contract details: `docs\LAUNCH_CONTRACT.md`.

This policy describes the current v1.1.x developer tree and current local-use / demo / testing release tree. Older public-hardening notes are future policy only unless the user explicitly requests a restricted public release.

## A. Current Local-Use / Demo Release

Developer tree path:

```text
E:\desktopvisualproject\desktopvisual
```

Path:

```text
E:\desktopvisualproject\desktop_release
```

Current role: local-use/demo/testing release.

Current desktop_release is local-use/demo/testing release.

Current sync status: v1.1.12 protected local-use/demo sync is allowed only after developer validation passes.

Next sync point: no v1.2.0 entry in this version.

Permission relationship: aligned with the developer tree until the user requests public restricted release creation or public restricted release permission reduction.

Current desktop_release is not the final restricted public release.

Current `desktop_release` is not public-dist. It is for local machine use, demos, recording, experience testing, and simulated user feedback.

v1.1.12 protected sync does not reduce permissions and does not create a public restricted release.

v1.2.0 is not entered by v1.1.12. A future v1.2.0 does not create a public restricted release by default.

The current `desktop_release` tree temporarily keeps the same permission semantics as the developer tree. Ordinary apps, ordinary webpages, HTTPS pages, localhost pages, local HTML pages, IDEs, Explorer, browsers, email, communication pages, code platforms, programming-practice pages, and broad words such as `test`, `exam`, `challenge`, `assessment`, `interview`, `contest`, and `submit` do not trigger STOP or BLOCK by themselves.

Real active protection or security interception still requires STOP, including CAPTCHA, human verification, bot challenge, automation detection, credential/security handoff, UAC/protected desktop, proctoring, lockdown browser, Secure Exam Browser, anti-cheat, or equivalent active protection.

## B. Future Restricted Public Release

Not created yet.

Not created at v1.2.0 by default.

Requires explicit user request.

Future permission narrowing applies only to that future channel.

A restricted public release may be created only after the user explicitly says to start creating a public restricted release or to start public restricted release permission reduction.

Future restricted public release work may include permission reduction, packaging exclusions, and public hardening. That work is not active in v1.1.12.

Any older public hardening rule is future restricted-public policy only. It must not be applied to the current v1.1.x developer tree or the current `desktop_release` local-use / demo / testing tree.

Before any future restricted public release is created, a separate release plan must define the target tree, permission reduction, packaging exclusions, tests, and evidence for that explicitly requested release.
