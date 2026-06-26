# Roadmap

Current trusted version: `DesktopVisual 1.1.0` Public Release Permission Alignment, Agent Efficiency, and Release Tree Sync.

Current active development layer: `DesktopVisual 1.1.0 Public Release Permission Alignment, Agent Efficiency, and Release Tree Sync`.

Current phase: developer_1_1_0_public_permission_agent_efficiency.

Next phase: post_v1_1_0_github_sync_when_user_requests.

## DesktopVisual 1.1.0 Public Release Permission Alignment, Agent Efficiency, and Release Tree Sync

DesktopVisual 1.1.0 aligns `PUBLIC_DEFAULT` with ordinary visible desktop capabilities, keeps developer permissions unchanged, adds compact progress/full evidence reporting policy, and prepares source release/public-dist trees for later GitHub sync on explicit user request.

Accepted scope is limited to public permission profile alignment, developer/public profile separation checks, report-level policy, Skill/adapter/doc synchronization, release tree sync scripts/selftests, public-dist leak checks, evidence, and cleanup. It does not perform GitHub sync and does not generate a release zip/package unless explicitly requested.

Post-1.1.0 developer state:

- current_trusted_version: 1.1.0
- last_completed_version: 1.1.0
- last_completed_status: pass
- developer_rc_ready: true
- public_release_ready: true
- next_planned_version: post_v1_1_0_github_sync_when_user_requests
- current_stage: developer_1_1_0_public_permission_agent_efficiency
- developer_full_access_default: true
- public_permission_aligned: true
- compact_output_default: true
- release_permission_hardening_deferred: false
- public_release_hardening_started: true

## DesktopVisual 1.0.5 Full-screen Capture/OCR Performance Pipeline

DesktopVisual 1.0.5 is a developer-tree performance and evidence pipeline release. It preserves full-screen screenshots and PNG evidence while decoupling OCR runtime processing from PNG persistence.

Accepted scope is limited to full-screen frame registry, memory-frame OCR, foreground/window crop-from-frame OCR with same-frame fallback, async PNG evidence writer and flush barrier, OCR cache/tile hash cache, VLM frame-bound provider transport, documentation, Skill synchronization, and regression evidence. It does not add new VS/PyCharm complex workflows, alter developer permissions, modify release/public-dist trees, or package a release. DesktopVisual 1.1.0 later aligns `PUBLIC_DEFAULT`.

Post-1.0.5 developer state:

- current_trusted_version: 1.0.5
- last_completed_version: 1.0.5
- last_completed_status: pass
- developer_rc_ready: true
- public_release_ready: false
- next_planned_version: v1_1_0_public_permission_policy_hardening
- current_stage: developer_1_0_5_capture_ocr_performance_pipeline
- developer_full_access_default: true
- release_permission_hardening_deferred: true
- public_release_hardening_started: false

## DesktopVisual 1.0.4 Visual Studio C++ Complex IDE Human-Like Workflow

DesktopVisual 1.0.4 is a developer-tree visible workflow release. It validates a Visual Studio C++ Empty Project workflow through real desktop operations, step checkpoints, visible build/run, visible output evidence, and top-right X close discipline.

Accepted scope is limited to Visual Studio C++ `SingleTestProject`, source/header file-add workflow, three-stage IDE build/run acceptance, Skill/documentation/evidence synchronization, and regressions. It does not add PyCharm complex workflow, v1.0.5 Capture/OCR performance work, release/public-dist changes, or release packaging. Public profile alignment is completed later in v1.1.0.

Post-1.0.4 developer state:

- current_trusted_version: 1.0.4
- last_completed_version: 1.0.4
- last_completed_status: pass
- developer_rc_ready: true
- public_release_ready: false
- next_planned_version: v1_0_5_capture_ocr_performance_pipeline
- current_stage: developer_1_0_4_vs_cpp_complex_ide_workflow
- developer_full_access_default: true
- release_permission_hardening_deferred: true
- public_release_hardening_started: false

## DesktopVisual 1.0.3.1 Legacy Mock VLM Quarantine and VLM Path Hardening

DesktopVisual 1.0.3.1 is a developer-tree hardening release between v1.0.3 and v1.0.4. It quarantines legacy mock VLM user paths, keeps the real v1.0.3+ VLM commands as the only normal VLM path, hardens VLM command envelopes, and makes locate-only action boundaries explicit before complex IDE work starts.

Accepted scope is limited to legacy mock quarantine, VLM schema/report hardening, VLM action-boundary documentation, Skill/adapter synchronization, and regression evidence. It does not add complex IDE workflow automation, full-screen Capture/OCR performance optimization, release/public-dist changes, or release packaging. Public profile alignment is completed later in v1.1.0.

Post-1.0.3.1 developer state:

- current_trusted_version: 1.0.3.1
- last_completed_version: 1.0.3.1
- last_completed_status: pass
- developer_rc_ready: true
- public_release_ready: false
- next_planned_version: v1_0_4_complex_ide_visible_workflow
- current_stage: developer_1_0_3_1_legacy_mock_vlm_quarantine
- developer_full_access_default: true
- release_permission_hardening_deferred: true
- public_release_hardening_started: false

## DesktopVisual 1.0.3 Automatic Real VLM Runtime Bridge

DesktopVisual 1.0.3 is a developer-tree Runtime bridge release. It adds provider-gated real Codex CLI VLM assist, session capability caching, strict JSON locate output, Runtime candidate validation, coordinate/evidence binding, and visible fallback evidence integration.

Accepted scope is limited to VLM capability/session gate, real Codex CLI provider JSON output, RuntimeCandidateValidator/CoordinateMapper/evidence binding, visible fallback discipline integration, and Skill contract synchronization. It does not add complex IDE workflow automation, full-screen Capture/OCR performance optimization, release/public-dist changes, or release packaging. Public profile alignment is completed later in v1.1.0.

Post-1.0.3 developer state:

- current_trusted_version: 1.0.3
- last_completed_version: 1.0.3
- last_completed_status: pass
- developer_rc_ready: true
- public_release_ready: false
- next_planned_version: v1_0_4_complex_ide_visible_workflow
- current_stage: developer_1_0_3_automatic_real_vlm_runtime_bridge
- developer_full_access_default: true
- release_permission_hardening_deferred: true
- public_release_hardening_started: false

## DesktopVisual 1.0.2 Skill Contract Hardening

DesktopVisual 1.0.2 is a developer-tree Skill/adapter contract release. It hardens the source-of-truth Skill, Codex adapter Skill, shared adapter rules, and usage references so agents must use v1.0.1 Runtime visible-first launch and fallback discipline.

Accepted scope is limited to contracts and tests. It does not change Runtime behavior, connect real VLM providers, add complex IDE workflow automation, redefine PUBLIC_DEFAULT, modify release/public-dist trees, or package a release.

Post-1.0.2 developer state:

- current_trusted_version: 1.0.2
- last_completed_version: 1.0.2
- last_completed_status: pass
- developer_rc_ready: true
- public_release_ready: false
- next_planned_version: v1_0_3_real_vlm_provider_gating
- current_stage: developer_1_0_2_skill_contract_hardening
- developer_full_access_default: true
- release_permission_hardening_deferred: true
- public_release_hardening_started: false

## DesktopVisual 1.0.1 Runtime Visible-First Launch and Fallback Discipline

DesktopVisual 1.0.1 is a developer-tree Runtime behavior correction release. It adds `visible-app-launch` as a generic desktop-first visible launch command and strengthens fallback gates across shared Runtime policy surfaces.

The accepted scope is limited to Runtime launch/fallback behavior. It does not harden Skill contracts, connect real VLM providers, add complex IDE workflow automation, redefine PUBLIC_DEFAULT permissions, modify release/public-dist trees, or package a release.

Post-1.0.1 developer state:

- current_trusted_version: 1.0.1
- last_completed_version: 1.0.1
- last_completed_status: pass
- developer_rc_ready: true
- public_release_ready: false
- next_planned_version: v1_0_2_skill_contract_hardening
- current_stage: developer_1_0_1_runtime_visible_first_launch_and_fallback_discipline
- developer_full_access_default: true
- release_permission_hardening_deferred: true
- public_release_hardening_started: false

## DesktopVisual 1.0.0 Developer Baseline

DesktopVisual 1.0.0 is the frozen developer baseline for the internal v6.12.1 line. It includes visible-first Windows desktop automation runtime support, real mouse and keyboard execution, global DPI-aware screenshot evidence, target window lock, coordinate mapping, foreground preempt/cache, operation timeline profiling, visible UI latency optimization, structured text input, and Python simple PyCharm current-main acceptance.

The 1.0.0 accepted visible path does not use clipboard or backend file writes as PASS evidence.

1.0.0 intentionally does not promise arbitrary complex IDE automated development, Visual Studio C++ multi-file project creation, Android Studio / Java / Kotlin complex project development, arbitrary web or complex app automation, or a fully generalized natural-language-to-mouse/keyboard planner.

Future roadmap:

- v1.1+: Visual Studio C++ multi-file workflow.
- v1.x: complex IDE visible workflow expansion.
- v1.0.4: complex IDE visible workflow development.
- v1.0.5: Full-screen Capture/OCR Performance Pipeline with memory-frame OCR, async PNG, tile hash cache, and OCR cache.
- v2.x: natural-language-to-workflow planner hardening.

Post-v6 developer build preparation state:

- current_trusted_version: 1.0.0
- last_completed_version: 1.0.0
- last_completed_status: pass
- developer_rc_ready: true
- public_release_ready: false
- next_planned_version: v1.1_plus_visual_studio_cpp_multi_file_workflow
- current_stage: developer_1_0_0_closure_baseline
- developer_full_access_default: true
- release_permission_hardening_deferred: true
- public_release_hardening_started: false

## v6.12.1 Visible UI Execution Foundation Hardening

v6.12.1 adds the developer-tree visible UI foundation needed before future visible workflows can claim completion: global DPI-aware screenshot evidence, target window locks, screenshot-to-screen coordinate mapping, foreground preempt, generalized real-keyboard visible text input with first-pass multiline/code-editor keyboard modes, Runtime-validated VLM candidate bridging, deterministic action batches, visible UI final verification policy, bottom-right visible Show Desktop default, Alt+Tab default window switching, and 165Hz best-effort HumanMode motion pacing evidence.

This phase is scoped to `D:\desktopvisual` only. Release/public-dist trees are out of scope, public package generation is forbidden, and GitHub upload is forbidden.

## v6.12.0 RC Gate and Handoff

v6.12.0 is complete as the Developer RC Gate and Handoff branch. It adds `DeveloperRCGate`, `VersionIntegrityChecker`, `EvidenceChainVerifier`, `CapabilityMatrixBuilder`, `WorkflowBoundaryAuditor`, `DeveloperFullAccessPolicyVerifier`, `ReleaseHardeningDeferredLedger`, and `HandoffPackageBuilder`.

The accepted scope is metadata, evidence-chain, boundary, policy, and handoff verification only. Developer full access remains default, public release permission hardening remains deferred, no exam/test/interview/contest keyword denylist is added, no public release package is generated, and no old UI workflow is rerun.

Next planned work is developer_build_preparation.

## v6.11.0 Workflow Template Learning and Batch Acceleration

v6.11.0 is complete. It adds evidence-derived WorkflowTemplate records, local registry, candidate extraction, template validation/safety, validated-template StepContract instantiation, batch plans, batch planner/validator/coordinator, targeted selftests, runner/verifier/gate separation, and evidence under `artifacts/dev6.11.0_workflow_template_learning_batch_acceleration/`. Final closure evidence is recorded under `artifacts/dev6.11.0_final_closure/`.

This phase intentionally does not train models, introduce vector/external databases, use network services, let ExperienceMemory influence execution, bypass StepContractValidator/RuntimeSession/verifier/evidence, parallelize real UI, rerun old UI workflows, implement v6.12 RC gates, or start public-release hardening.

## v6.10.0 Experience Memory and Failure Attribution Integration

v6.10.0 is complete. It adds append-only Experience Memory records, store, index, read-only query/report commands, failure attribution normalization, integrator, memory safety boundary, targeted selftests, runner/verifier/gate separation, and evidence under `artifacts/dev6.10.0_experience_memory_failure_attribution/`.

This phase intentionally does not let memory influence StepContract, AgentPlanDraft, RuntimeSession, locator selection, retries, workflow optimization, or Runtime execution. It does not implement Workflow Templates, v6.12 RC gates, public-release permission narrowing, new real App/Web tests, or old UI workflow replays.

## v6.9.0 System Stabilization and Evidence Boundary Hardening

v6.9.0 system stabilization is complete. It adds runtime evidence consolidation, runtime session lifecycle audit, workflow system boundary checking, artifact classification/archive policy, system stabilization selftests, verifier, acceptance gate, and evidence under `artifacts/dev6.9.0_system_stabilization/`.

This phase intentionally does not implement Experience Memory, Workflow Templates, v6.12 RC Gate, public-release permission narrowing, new real App/Web tests, or old UI workflow replays. It does not change RuntimeSession, StepContract, CompiledPlanExecutor, or VLM candidate execution semantics.

## v6.8.0 Browser and Web Form Agent Workflows

v6.8.0 is accepted. It adds BrowserWorkflow and BrowserFormWorkflow schema, compile-browser-workflow, run-browser-workflow, verify-browser-workflow, browser form field locator, browser workflow executor, page/form verifier, wrong-page recovery, active-protection STOP, credential-required STOP, local file and localhost fixtures, ordinary external read-only diagnostic, runner/verifier/gate separation, and full regression evidence.

v6.8.0 intentionally does not add Mail/Message/Draft workflows, Experience Memory, Workflow Templates, new VLM capabilities, real VLM API integration, social platform automation, real external form commit gates, or public-release permission narrowing.

## v6.9.0 Mail / Message / Draft Workflows

v6.9.0 is accepted for mail, message, and draft Communication workflows. It builds on the accepted Browser/Form workflow boundary without expanding into real mailbox sends or social platform automation.

## v6.7.0 Explorer Agent Workflows

v6.7.0 is accepted. It adds Explorer workflow orchestration on top of existing Runtime guard, locator, candidate, and evidence paths. The accepted rerun evidence repairs Explorer move and scroll-and-locate blockers with staged UI evidence and full regression from the beginning.

Out of scope until v6.7.0 explicitly starts: Experience Memory, Workflow Template Learning, public-release permission narrowing, real VLM API key UI, and VLM direct action execution.

## v6.6.0 VLM-Assisted Unknown UI Candidate Handling

v6.6.0 is accepted. It adds Runtime-owned handling for VLM-proposed unknown UI candidates, where approximate semantic candidates are revalidated by Runtime before any action path can use them.

v6.6.0 intentionally does not add direct VLM execution, VLM-generated click/type/scroll commands, bypassing Runtime validation, real provider API key UI, Experience Memory, Workflow Template Learning, public-release permission narrowing, or large-scale real App/Web testing.

## v6.5.0 VLM-Assisted Observation Contract

v6.5.0 is accepted. It adds an assistive observation contract for VLM-proposed interpretation, target hints, and failure explanations while preserving Runtime-only action execution.

v6.5.0 intentionally does not add real VLM execution, VLM direct desktop action, VLM candidate handling, Experience Memory, Workflow Template Learning, public-release permission narrowing, or bypassing StepContract validation.

## v6.4.0 Runtime Task Execution from Compiled Agent Plan

v6.4.0 is accepted. It connects compiled, validated StepContracts to controlled local Runtime task execution while preserving v6.2 session guards and v6.3 contract safety structure.

v6.4.0 intentionally does not develop VLM, Experience Memory, Workflow Template Learning, public-release permission narrowing, new real external App/Web scope, v6.2 latency optimization, or natural-language direct Runtime execution.

## v6.3.0 PlanDraft to StepContract Compiler

v6.3.0 is accepted. It compiles reviewed AgentPlanDraft structures into Runtime-consumable StepContract records, validates those contracts, emits structured compile diagnostics, and dry-runs v6.2 session-compatible step JSON without executing Runtime actions.

v6.3.0 intentionally does not execute compiled plans, run real App/Web tasks, call Runtime action execution from dry-run, develop VLM, Experience Memory, Workflow Templates, public-release permission narrowing, or v6.2 latency optimization.

## v6.2.0 Persistent Runtime Session and Latency Gate

v6.2.0 is accepted. It adds bottom-layer Runtime sessions, SessionManager, session-scoped window binding, observe and locator caches, structured session dispatch, act-and-verify primitives, latency tracking, and one-shot CLI backward compatibility.

The accepted evidence lives under `artifacts/dev6.2.0_persistent_runtime_session_latency_gate/` and includes runner/verifier/gate separation. Runner output is raw only. Verifier and acceptance gate own PASS authority.

Latency comparison is accepted for the controlled 10-step workflow: one-shot average 65 ms, p95 139 ms, process restarts 14; persistent average 45 ms, p95 78 ms, process restarts 1.

v6.2.0 intentionally does not implement PlanCompiler, AgentPlanDraft to StepContract Compiler, Runtime natural-language task execution, VLM, Experience Memory, Workflow Template Learning, public-release permission narrowing, or new real App/Web scope.

## v6.1.4 Dynamic App/Web Click Accuracy and Offset Diagnostics

v6.1.4 keeps v6.1.3 as the trusted baseline unless real dynamic UI required tests, fresh baseline replay, regressions, JSON/JSONL checks, documentation checks, evidence pointer checks, and the dynamic UI acceptance gate pass.

Scope is limited to v6.1.x diagnostics and repairs: dynamic click offset, keyboard focus diagnostics, stale target rect prevention, adaptive reobserve/retry evidence, and first-attempt quality metrics for PyCharm, WeChat, and QQ Mail at `https://mail.qq.com`.

Out of scope: v6.2, Persistent Runtime Session, PlanDraft to StepContract Compiler, Runtime natural-language execution, VLM Provider/calls, Experience Memory, Workflow Templates, public release permission narrowing, and developer permission direction changes.

## v6.1.3 Mouse Wheel Scroll Primitive Defaulting and Scroll-and-Locate

v6.1.3 keeps v6.1.2 as the trusted baseline unless real wheel required tests, fresh baseline replay, regressions, JSON/JSONL checks, documentation checks, evidence pointer checks, and the scroll acceptance gate pass.

This phase makes real `SendInput` plus `MOUSEEVENTF_WHEEL` the strict scroll primitive for new wheel evidence. It adds `adaptive-scroll`, `scroll-and-locate`, `v6_1_3_wheel_scroll_runner.ps1`, `v6_1_3_wheel_scroll_verifier.ps1`, and `v6_1_3_scroll_acceptance_gate.ps1`.

This phase intentionally does not enter v6.2, develop Persistent Runtime Session, compile PlanDraft to StepContract, execute Runtime natural-language tasks, call or develop a real VLM Provider, add Experience Memory, add Workflow Templates, narrow public release permissions, or change the developer permission direction. Runner evidence is raw only; verifier and gate own PASS authority. Scrollbar/track/drag fallback is not a default strict strategy and requires wheel no-progress evidence plus `fallback_reason`.

## v6.1.2 Real UI Baseline Sanity and Pre-v6.2 Test Gate

v6.1.2 keeps v6.1.1 as the current trusted baseline unless real UI required tests, regressions, JSON/JSONL checks, documentation checks, evidence pointer checks, and the pre-v6.2 acceptance gate pass.

This phase proves that Runtime, HumanMode, Explorer, and Browser Mock Mail baselines are still trustworthy before v6.2. It requires `v6_1_2_real_ui_baseline_runner.ps1`, `v6_1_2_real_ui_baseline_verifier.ps1`, and `v6_1_2_pre_v6_2_acceptance_gate.ps1`.

This phase intentionally does not enter v6.2, compile PlanDraft to StepContract, execute Runtime natural-language tasks, call a real VLM provider, add Experience Memory, add Workflow Templates, narrow public release permissions, or change the developer permission direction. Runner evidence is raw only; verifier and gate own PASS authority.

## v6.1.1 HumanMode Regression Triage and Evidence Gate Repair

v6.1.1 keeps v6.1.0 as a BLOCKED attempt and keeps v6.0.0 as the trusted baseline unless all required v6.1.1 tests, HumanMode regression runs, evidence integrity checks, and the independent acceptance gate pass.

This phase audits v6.1.0 planner completeness, confirms Runtime-only and VLM-assisted assistive-only boundaries, triages `FAIL_CURSOR_NOT_AT_TARGET`, repairs missing evidence pointer handling, and adds `v6_1_1_evidence_acceptance_gate.ps1`.

This phase intentionally does not enter v6.2, compile PlanDraft to StepContract, execute natural-language tasks, call a real VLM provider, add Experience Memory, add Workflow Templates, narrow public release permissions, or change the developer permission direction.

## v6.1.0 Natural Language Task Intent and Plan Draft

v6.1.0 implements the minimal planner/intention layer. It parses natural language into `TaskIntent`, generates non-executable `AgentPlanDraft`, and validates both structures through `agent-intent-parse`, `agent-plan-draft`, and `agent-planner-validate`.

`AgentPlanDraft` is not a `StepContract`, is not directly executable, and must keep `is_executable=false`, `compile_required=true`, and `executor=runtime`. Runtime remains the only executor. VLM-assisted mode remains assistive only with `provider_role=assistive_only` and does not call a real VLM API.

This phase intentionally does not execute tasks, compile StepContract, call real VLM providers, add Provider API key UI/account system, add Experience Memory, add Failure Attribution, accelerate batch tasks, modify HumanMode, modify active-protection STOP, or perform public release normalization.

Plan-to-StepContract compilation is reserved for v6.3.0.

## v6.0.0 Agent Boundary and Runtime/VLM Mode Architecture

v6.0.0 starts v6 from the accepted v5.10.2 handoff evidence. It establishes two modes: Runtime Mode and VLM-Assisted Mode. Runtime Mode executes through local Runtime capabilities. VLM-Assisted Mode may interpret, plan, classify, and explain, but cannot execute desktop actions directly.

This phase adds `agent-boundary-validate`, minimal AgentTaskRequest / AgentPlan / AgentPlanStep validation, Runtime-only executor enforcement, malformed JSON and missing-field rejection, empty-step rejection, and HumanMode action boundary rejection for JS/DOM/WebDriver/CDP/UIA Invoke/Value actions.

This phase intentionally does not add a full Planner, real VLM provider calls, Provider API key UI/account system, Experience Memory, batch task acceleration, HumanMode changes, active-protection STOP changes, or public release normalization.

## v5.10.2 REBUILT Real TaskRuntime Integration and Final Pre-v6 Gate

v5.10.2 remains v5 and integrates the localhost HumanMode browser form flow through real TaskRuntime. It uses the rebuilt v5.10.1 verifier PASS evidence as prerequisite, then validates TaskRuntime evidence, CLI/service surface, active-protection STOP behavior, v5 core regression status, documentation, and artifacts through independent scripts.

The old invalidated v5.10.2 evidence remains excluded from evidence indexes. Rebuilt v5.10.2 does not introduce VLM, an Agent Planner, public release permission narrowing, or a public release tree.

## v5.10.1 REBUILT Real UI Adaptive Cases Rerun

v5.10.1 is rebuilt from the trusted v5.10.0 Adaptive HumanMode Control Loop Core baseline. It remains v5 and reruns real UI Case D/E/F evidence with a raw runner and independent verifier. It does not introduce VLM, an Agent Planner, public release permission narrowing, or developer permission direction changes.

The old invalidated v5.10.1/v5.10.2 artifacts remain excluded from evidence indexes and cannot support PASS or v6 readiness. Rebuilt v5.10.1 evidence is valid only if the verifier reads raw winagent command output, result-json, screenshots, foreground windows, cursor positions, and trace timestamps and rejects synthetic evidence, placeholder screenshots, hardcoded hwnd/rect, backend actions, direct launch, JS/DOM/WebDriver/CDP, UIA InvokePattern/ValuePattern action paths, and runner self-PASS.

## v5.10.1/v5.10.2 Invalidation Rollback

v5.10.1 and v5.10.2 are INVALIDATED. v5.10.1 synthetic adaptive case evidence and v5.10.2 hardcoded/simulated TaskRuntime browser form handoff evidence cannot be used as PASS evidence or v6 handoff evidence. `ready_for_v6` true is revoked.

The current trusted baseline is v5.10.0 Adaptive HumanMode Control Loop Core. It proves Adaptive Loop Core readiness only and does not prove real Case D/E/F, Explorer, browser form, localhost, or TaskRuntime browser-flow PASS.

Public release requires a later Version Normalization Pass and Release Normalization Pass. The Version Normalization Pass will map internal v5.x stage numbers to `0.x.x` prerelease versions before any formal `1.0.0` public stable release. `D:\desktopvisual` remains the internal development tree and must not be treated as the public release tree.

## v5.8.7 Pre-v6 Runtime Hardening

v5.8.7 revalidates and hardens the internal v5.x Task-Level Desktop Execution Runtime track. v5.x is an internal engineering stage number. v6 has not started in this tree. This phase synchronizes documentation skeletons, records artifact gaps, and prepares staged v5.0 through v5.8 revalidation. It does not start v6 and does not add VLM providers or desktop Agent behavior.

v5 can be described as Task-Level Desktop Execution Runtime: TaskSession, TaskState, StepContract, verification, bounded recovery, escalation, human confirmation, TaskTemplateV2, App Profile binding, controlled file workflows, task-level dogfood, service protocol, and task evidence. v5 remains VLM-free and does not depend on VLM. It does not claim unfamiliar-screen semantic generalization or real high-risk task execution. Runtime is the only action executor.

v6.0 is reserved for Agent Boundary and Provider Architecture. v6 is the future Initial Desktop Agent System track, not part of v5.8.7.

v3.7.0 closes the v3.x stability track as a public release candidate. The completed v3.x work includes DEFAULT/FULL_ACCESS permission profiles, local interactive FULL_ACCESS confirmation, FULL_ACCESS-gated normal desktop/app launch, FULL_ACCESS-gated external web/browser navigation, form/control semantics, the General Decision Task Runtime, session checkpoints, loop guard stops, the Communication Action Runtime, the Coding and Problem-Solving Web Workflow, a Full Access benchmark/evidence harness, a Recovery Strategy Engine, service protocol v1.0, and bounded developer-tool dogfood evidence.

v4.7.0 closes the v4.x Hybrid Screen Perception Runtime track as a release candidate. v4.x provides structured screen perception and evidence, but it is not a complete autonomous Agent. v5 is the task-level execution runtime. v6 is reserved for Initial Desktop Agent System boundary and provider architecture.

## Stage 1: Specified Window Test Loop

Build the first closed loop: find one authorized window, capture it, click relative coordinates, send keys/text, read state files, run cases, and write reports.

v0.1.2 adds Visible Action Mode inside this stage. `instant` mode keeps automated tests fast. `human` mode makes mouse movement and text entry observable for demos and audit review. Click actions support movement duration, and type actions support per-character delay. `visible_action.case` is the reference visible demo.

v0.1.3 adds Action Trace Consistency: unified JSON envelopes, stable error codes, stable audit lines, richer case reports, and failure case selftests.

## Stage 2: UI Automation Control Tree

Expose structured controls through Microsoft UI Automation where available, including names, roles, bounding boxes, and supported actions.

## Stage 3: OCR Text Location

Add optional OCR-based text discovery for windows that do not expose useful accessibility metadata.

## Stage 4: Image Template Location

Add template matching for visual targets such as buttons, icons, and game HUD elements in authorized test applications.

## Stage 5: Structured Runtime Data Monitoring

Support polling and change detection for logs, state files, sockets, or named pipes exposed by test applications.

## Stage 6: Skill Packaging And Optional Service Layer

Keep the project-local Skill template reviewable and manually installable. Any future MCP or service wrapper is outside v1.0.0 and must preserve the frozen CLI safety boundary.

Before 1.0, the project should keep the current Skill template, baseline UI Automation support, release verification, and failure-stop rules stable.

## Stage 7: Windows Agent Desktop Runtime

Evolve toward a Windows runtime that offers a controlled, auditable experience similar to macOS computer-use workflows while keeping authorization and safety boundaries explicit.

Current v1.0.0 is still only a controlled local Windows desktop test foundation. It includes limited UI Automation and BMP template matching, but OCR remains unavailable in this build. It does not provide MCP, HTTP services, complete computer use, complex automatic recovery, or autonomous decision-making.


## Current Focus

- Keep root resolution portable through -Root, DESKTOPVISUAL_ROOT, script/exe discovery, and legacy fallback.
- Keep GitHub exports clean through .gitignore, public_repo_check.ps1, and package_source.ps1.
- Keep adapters agent-agnostic and centered on shared Safety Manifest rules.
- Keep benchmark evidence reproducible with PASS/FAIL/SKIPPED semantics.
- Keep the Safety Manifest and consent layer machine-readable, reportable, and unable to loosen `safety.conf`.
- Keep PermissionManager DEFAULT/FULL_ACCESS decisions explicit, temporary, and auditable.
- Keep long tasks checkpointed, stoppable, and resumable only from observable state summaries.
- Keep communication sends tied to explicit user target/content intent, with summaries and hashes instead of full sensitive content logs.
- Keep coding workflow actions tied to explicit user goals, local auditable context, public-release permission restrictions for exams/assessments/hiring/certification/rated contests, and no submit without `allow_submit=true`.
- Keep `D:\desktopvisual` as the broad local development/evaluation tree, and prepare public release separately under `D:\desktopvisual-release` with restricted exam/assessment/hiring/certification/rated-contest permissions.
- Keep Full Access benchmark evidence reproducible, local-fixture based, and free of real accounts, real communications, browser profiles, raw motion data, build outputs, and sensitive logs.
- Keep recovery strategies finite, auditable, and bounded by the Safety Manifest; never recover safety-policy denial or ambiguous selectors.
- Keep service protocol responses stable, protocol-versioned, audited, and unable to unlock FULL_ACCESS or bypass safety checks.
- Keep dogfood evidence bounded to declared local developer-tool scenarios and do not treat PASS as proof of arbitrary software control.
- Keep v4 Hybrid Screen Perception Engine work separate from v3.7; do not implement complex perception in the v3.x release candidate.
- Keep v4.1 Visual Source Integration provider-ready and local-first: image templates are implemented, while OmniParser/YOLO/UGround/VLM providers remain unavailable or degraded placeholders until separately configured and reviewed.
- Keep v4.2 Realtime Observe Loop focused on read-only event streams: Screen Delta and Perception Cache first, ROI OCR on changed rounds, debounced JSONL events, bounded loop guards, and no autonomous action execution.
- Keep v4.3 Latency Benchmark Pack evidence-based: Runtime first, UIA/OCR/Delta/Profile/Cache first, OmniParser/YOLO on demand, VLM/Agent only for semantic escalation, and measure before claiming.
- Keep v4.4 Dynamic UI Recovery finite and safety-first: loading can wait and re-observe, moved/stale candidates can re-locate, dialogs require safe routing, unknown requires confirmation, and blocked stops immediately.
- Keep v4.5 App Profile System as adapter metadata: profiles can improve local locator/ROI/recovery hints, but cannot grant permissions, loosen Safety Manifest rules, or create real-account/public-assessment automation profiles.
- Keep v4.6 Visual Dogfood bounded and evidence-based: local developer workflow fixtures only, v4 perception evidence in every case, mock mail only, mock problem benchmarks only, and SKIPPED reported separately from PASS.
- Keep WindowSession resolution, foreground checks, DPI/monitor diagnostics, and duplicate-window failures explicit.
- Prefer audited task templates for common workflows instead of ad hoc coordinate-heavy task steps.
- Preserve command compatibility and explicit safety failures.




## v5.9.0-b Current Stage

Current internal version: `v5.9.0-b`.

Current phase: v5 HumanMode Visible UI Case Runner. This remains v5, does not start v6, does not introduce a VLM main path, does not add an Agent Planner, and does not do public release permission narrowing.

The internal development tree defaults to `DEVELOPER_CAPABILITY_DISCOVERY` for capability exploration. Public release permission narrowing remains a future Release Normalization Pass and must not be applied to current developer dogfood by default.


## v5.9.0-b Current Stage

Current internal version: `v5.9.0-b`.

Current phase: v5 HumanMode Visible UI Case Runner. This remains v5, does not start v6, does not introduce a VLM main path, does not add an Agent Planner, and does not perform public release permission narrowing. The next public-facing permission restriction work remains a future Release Normalization Pass.


