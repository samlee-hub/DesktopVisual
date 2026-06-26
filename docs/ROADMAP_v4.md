# Roadmap v4

Current version: `v4.7.0`.

## v4.7.0 - Hybrid Perception Release Candidate

Status: implemented in the local development tree.

- `v4_rc_check.ps1` runs focused v4 RC checks and writes `artifacts\dev4.7.0\v4_release_candidate_report.md`.
- v4.7.0 aggregates v4.1 provider evidence, v4.2 observe-loop evidence, v4.3 latency evidence, v4.4 dynamic recovery evidence, v4.5 App Profile evidence, and v4.6 visual dogfood evidence.
- v4.7.0 is a stabilization, documentation, evidence, safety, and release hygiene pass. It does not add a v5 task state machine or real VLM/OmniParser/YOLO integration.
- v4.x is positioned as Hybrid Screen Perception Runtime, not full autonomous desktop intelligence.

## v4.6.0 - Visual Dogfood on Developer Workflow

Status: implemented in the local development tree.

- `v4_visual_dogfood.ps1` runs bounded local v4 perception dogfood and writes `artifacts\dev4.6.0\dogfood_report.md`.
- Required cases cover local HTML forms, local mock problem run/result, local mock mail compose/attach/sent-state verification, Explorer temp-file selection, Notepad clean temp edit when available, and local PowerShell output reading.
- Each case records `observe2`, `ElementGraph`, `LocatorCandidate`, `SceneState`, `ChangeEvent`, `observe-loop` delta/ROI metadata, and App Profile evidence where applicable.
- The suite is evidence for local developer workflows only; it is not fixed-coordinate replay, real email sending, real account automation, real assessment automation, or arbitrary software control.

## v4.5.0 - App Profile System

Status: implemented in the local development tree.

- App Profile schema and built-in safe local profiles live under `profiles`.
- `profile-report` reports loaded/invalid profiles and effective capabilities without crashing on invalid JSON content.
- Profile common locators can feed the existing selector locator through `locate --profile <name> --profile-locator <name>`.
- Profile metadata includes window matching, common locators, ROI definitions, visual/OCR strategy, recovery strategy, task templates, and confirmation nodes.
- Profiles do not bypass Permission Profiles, Safety Manifest, semantic/risk routing, visual-only unresolved blocking, or foreground action gates.

## v4.4.0 - Dynamic UI Recovery

Status: implemented in the local development tree.

- `SceneState` now reports `normal`, `loading`, `dialog_open`, `error`, `success`, `blocked`, and `unknown`.
- `ChangeEvent` covers loading, dialog, error, success, moved/enabled/disabled elements, and target readiness.
- `dynamic-ui-recovery` evaluates local fixture states and router decisions without executing actions.
- Runtime recovery is finite: wait/re-observe loading, re-locate moved/stale candidates, rebuild affected perception, stop or escalate errors, and immediate STOP for blocked.
- Blocked state is not routed to VLM bypass. Unknown state does not authorize clicks.

## v4.3.0 - Latency Benchmark Pack

Status: implemented in the local development tree.

- `latency_benchmark.ps1` writes the v4 latency evidence pack under `artifacts\dev4.3.0\latency`.
- Required metrics include screenshot, UIA, full OCR, ROI OCR, screen delta, ElementGraph-producing observe2, hybrid locate, visual provider, observe-loop event latency, action-to-verify, cache hit ratio, and `llm_or_vlm_call_count`.
- Benchmark scenarios cover TestWindow basics, local HTML text/button fixtures, ROI vs full OCR, cache hit vs miss, image-template provider available/unavailable, and observe-loop detection.
- Warning thresholds are local-machine budget checks only.
- No real VLM, external account, OmniParser/YOLO weight, GPU, or public website benchmark is introduced.

## v4.2.0 - Realtime Observe Loop

Status: implemented in the local development tree.

- `observe-loop` and `observe2 --loop` provide bounded read-only event streams.
- Events are written to JSONL artifacts with cache/delta, loop guard, and changed-region metadata.
- The loop prioritizes screenshot hash, changed-region evidence, ROI OCR, cached ElementGraph state, and affected-region refreshes.
- No VLM/OmniParser/YOLO continuous monitoring is introduced.
- No action execution is allowed inside the observe loop.

v4.x is reserved for Hybrid Screen Perception Engine work. v3.7.0 does not implement complex visual reasoning or generalized custom-rendered UI understanding.

## v4 Direction

- Combine UIA, OCR, template/image evidence, region summaries, and task context into a structured perception layer.
- Preserve v3 safety boundaries: explicit target windows, foreground confirmation, PermissionManager, SafetyPolicy, Safety Manifest, audit logs, checkpoints, loop guards, and finite recovery.
- Keep perception outputs inspectable and tied to confidence, source, bounding boxes, and failure reasons.
- Prefer deterministic local fixtures and reproducible benchmarks before using real public sites or third-party software.

## Out Of Scope For v3.7

- General vision-language planning.
- Hidden/background browser or app control.
- Credential, payment, captcha, anti-cheat, or protected desktop automation.
- Automatic bypass of accessibility gaps through coordinate guessing.
- Public-release assessment, hiring, certification, or rated-contest assistance without a dedicated permission model.
- Publishing `D:\desktopvisual` directly; public release must be prepared separately under `D:\desktopvisual-release` with restricted assessment/exam permissions.

## Candidate v4 Milestones

- v4.0 Hybrid Screen Perception Engine baseline.
- v4.1 Visual Source Integration: provider registry, image-template source candidates, unavailable/degraded placeholders for OmniParser/YOLO/UGround/VLM/agent providers, and unresolved visual-only action blocking.
- v4.2 Realtime Observe Loop.
- v4.3 Latency Benchmark Pack.
- v4.4 Dynamic UI Recovery.
- v4.5 App Profile System.
- v4.6 Visual Dogfood on Developer Workflow.
- v4.7 Hybrid Perception Release Candidate.



