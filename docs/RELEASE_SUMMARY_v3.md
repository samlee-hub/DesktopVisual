# DesktopVisual v3.x Release Summary

Current version: `v3.7.0`.

DesktopVisual v3.x is a Windows-only, agent-agnostic, auditable, safety-bounded Computer Use Runtime. It is designed for authorized desktop workflows where every action can be traced through CLI/service envelopes, audit logs, task reports, benchmark evidence, and explicit safety stops.

## What v3.x Provides

- Authorized observe-locate-act-verify workflows for normal user-permission Windows applications.
- Agent-agnostic invocation through CLI, Codex adapter, Claude Code adapter, generic CLI adapter, and explicit local service protocol v1.0.
- DEFAULT/FULL_ACCESS permission profiles with local interactive FULL_ACCESS confirmation and audit records.
- WindowSession diagnostics, foreground confirmation, selector/locator diagnostics, and visible input only.
- Form/control semantics, deterministic decision tasks, communication action records, and coding workflow dry-runs under explicit permission gates.
- Session checkpoints, loop guards, and a finite Recovery Strategy Engine.
- Full Access benchmark evidence, developer-tool dogfood evidence, adapter checks, public repository checks, and release-candidate RC checks.

## Safety Boundary

DesktopVisual v3.x does not provide unrestricted desktop control. It does not support administrator windows, UAC, protected desktops, credential entry, payment flows, captcha solving, anti-cheat protected apps, hidden/background browser control, detection bypass, public-release assessment workflows without a dedicated permission policy, high-frequency batch submit, paid-limit bypass, or problem-set scraping.

## Local Versus Public Release Tree

`D:\desktopvisual` is the broad local development/evaluation tree. It is retained for future optimization, simulated-exam correctness evaluation, and operation-accuracy testing with the maximum project permission posture that still respects immutable safety stops.

Do not submit `D:\desktopvisual` as the public release project. Public release must be prepared in `D:\desktopvisual-release`. That release tree must contain a restricted permission policy for exam, interview assessment, hiring test, certification, rated-contest, proctored, and similar workflows before distribution.

## Evidence

The release-candidate evidence surface is:

- `benchmark_selftest.ps1`
- `full_access_benchmark_selftest.ps1`
- `dogfood_selftest.ps1`
- `safety_manifest_selftest.ps1`
- `adapter_selftest.ps1`
- `portable_root_selftest.ps1`
- `rc_check.ps1`

Generated runtime evidence belongs under `artifacts\` and is excluded from the public source package.

## Public Positioning

Use this phrasing:

DesktopVisual is a Windows-only, agent-agnostic, auditable, safety-bounded Computer Use Runtime for authorized desktop workflows.

Avoid phrasing that implies unrestricted control, hidden automation, account automation, anti-detection behavior, or bypassing platform/security controls.
