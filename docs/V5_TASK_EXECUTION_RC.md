# v5 Task Execution Release Candidate

Current RC: `v5.8.7`.

v5.x is a Task-Level Desktop Execution Runtime engineering track. It proves controlled TaskSession execution, step contracts, verification, bounded recovery, escalation records, human confirmation, TaskTemplateV2 plus App Profile binding, file workflows, task-level dogfood, and service protocol access. v5.8.7 is the pre-v6 hardening and revalidation pass; v6 has not started.

## Versioning Note

v5.x is an internal engineering stage number. Before any public release, DesktopVisual will run a Version Normalization Pass that maps internal stage numbers to `0.x.x` prerelease versions. The first formal public stable release remains `1.0.0`.

`D:\desktopvisual` is the internal development tree. It is not the public release tree and dirty git state is release-blocking until a later Release Normalization Pass.

## Feature Matrix

| Area | Status | Evidence |
|---|---|---|
| TaskSession schema/state machine | Implemented | `artifacts/dev5.0.6/v5.0_acceptance_report.md` |
| StepContract/precondition/verification/failure reason | Implemented | `artifacts/dev5.1.6/v5.1_acceptance_report.md` |
| Recovery/escalation/safe stop | Implemented | `artifacts/dev5.2.6/v5.2_acceptance_report.md` |
| Human confirmation gates | Implemented | `artifacts/dev5.3.6/v5.3_acceptance_report.md` |
| TaskTemplateV2 and App Profile binding | Implemented | `artifacts/dev5.4.6/v5.4_acceptance_report.md` |
| File picker/attachment/cross-window mock workflows | Implemented | `artifacts/dev5.5.6/v5.5_acceptance_report.md` |
| Task-level dogfood benchmark | Implemented | `artifacts/dev5.6.6/v5.6_acceptance_report.md` |
| CLI/service task API | Implemented | `artifacts/dev5.7.6/v5.7_acceptance_report.md` |
| v5 RC revalidation artifacts | Implemented | `artifacts/dev5.8.7_revalidation/` |

## Missing Features

- No VLM, OmniParser, YOLO, UGround, or model-provider integration is part of v5.
- No guarantee of semantic generalization to arbitrary unfamiliar screens.
- No real external account automation, real email send, real exam/hiring/certification/proctored submission, payment, captcha solving, or game automation.
- Recovery is bounded and policy-driven; it is not autonomous replanning.
- File workflows are controlled local/mock flows; default dangerous paths and sensitive exfiltration remain blocked.

## Known Limitations

- Minimal TaskSession execution remains intentionally narrow and local-mock oriented.
- App Profiles bind locators, ROI, visual strategy, recovery strategy, and confirmation nodes, but cannot override SafetyPolicy or Safety Manifest.
- Service mode is local named-pipe based and must be started explicitly.
- Confirmation records are audit artifacts; they do not turn blocked actions into allowed actions.
- RC latency numbers are current-machine evidence, not cross-machine performance guarantees.
- Internal RC PASS is not public release readiness. Public release readiness requires Phase 11 and release-tree normalization.

## Safety Review

- Blocked actions stop and are not routed through Agent/VLM bypass.
- High-risk actions require confirmation or stop.
- Public-release profile restrictions remain conservative.
- Visual-only unresolved candidates are not clicked.
- Real exam, hiring assessment, game automation, payment, captcha, anti-cheat, proctoring, and credential-security challenges are blocked or stopped.

## Performance Review

v5.8 records task latency from controlled local TaskSession/service/dogfood flows. Confirmation wait is excluded or separately recorded. LLM/VLM call count defaults to `0`; v5 RC does not call model providers.
