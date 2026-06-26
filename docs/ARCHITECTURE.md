# Architecture

Current trusted version: `DesktopVisual 1.1.0`.

Current active development layer: `DesktopVisual 1.1.0 Public Release Permission Alignment, Agent Efficiency, and Release Tree Sync`.

## DesktopVisual 1.1.0 Public Permission Alignment And Agent Efficiency

DesktopVisual 1.1.0 separates developer capability from public STOP policy without making public releases a disabled desktop mode. `DEVELOPER_CAPABILITY_DISCOVERY` remains the developer default and keeps ordinary desktop/app/web/IDE/Explorer/localhost capabilities enabled. `PUBLIC_DEFAULT` now aligns with those ordinary visible capabilities for normal user-authorized workflows and does not require a legacy FULL_ACCESS session for ordinary visible desktop operations.

The public profile differs at the STOP boundary, not by disabling normal desktop operation. Public releases stop on real active protection or security interception: real exam/proctoring/lockdown browser, CAPTCHA/human verification, bot or automation challenge, protected desktop/UAC, credential/security handoff, and anti-cheat mechanisms.

The agent efficiency layer is a reporting policy, not an evidence reduction. `report_level=compact`, `progress_output=compact`, and `step_chat_detail=compact` reduce chat verbosity, while `evidence_level=full` and `artifact_evidence=full` keep audit artifacts complete. `safety-report` exposes both the public/developer profile difference and the active report policy.

## DesktopVisual 1.0.5 Full-screen Capture/OCR Performance Pipeline

DesktopVisual 1.0.5 keeps full-screen capture as the source-of-truth while separating Runtime processing from evidence persistence:

```text
full-screen capture
  -> in-memory/full-screen frame registry with frame_id + screenshot_id
  -> OCR from memory frame
  -> foreground/window crop OCR from the same full-screen frame
  -> same-frame full-screen OCR fallback when crop OCR fails
  -> async PNG evidence writer
  -> flush barrier before failure/BLOCKED/final reports
```

The old slow path was full-screen screenshot -> PNG write -> PNG read -> OCR. The v1.0.5 path is full-screen screenshot -> memory frame -> OCR, with PNG evidence saved asynchronously. PNG evidence remains mandatory for audit, but OCR no longer depends on the PNG write/read cycle.

The frame registry records `frame_id`, `screenshot_id`, capture time, screen dimensions, DPI/coordinate scale, pixel format, byte size, content hash, foreground window metadata, evidence PNG path, write status, originating command, and raw frame bytes for cross-process CLI materialization. OCR results are always bound to `frame_id` and `screenshot_id`.

Foreground and window OCR never create a partial screenshot as the source-of-truth. They crop the current full-screen frame in memory. If crop OCR fails or is insufficient, fallback OCR uses the same full-screen frame and records `same_frame_for_fallback=true`.

The OCR cache is scoped by frame/content hash, crop rect, OCR engine/config, and tile hash. Repeating full-screen OCR on the same frame or repeating the same crop can hit cache, while new frame IDs do not reuse old OCR unless the content/tile hash strategy validates equality.

VLM image transport uses the same frame binding. Current Codex CLI requires `--image <png_path>`, so the provider input PNG is generated from frame bytes as a transport artifact and reports `provider_transport=file_path`. OCR must not read the VLM input PNG. Future providers can declare `provider_transport=memory_bytes` or `base64` when supported.

## DesktopVisual 1.0.4 Complex IDE Visible Workflow

DesktopVisual 1.0.4 adds a path-sensitive Visual Studio C++ workflow layer above the existing visible Runtime primitives. The layer proves that a real IDE task can be executed as visible desktop operations: desktop icon launch, VS Start Window project open, Solution Explorer file navigation, IDE file-add workflow, visible editor input, visible IDE build/run, visible output verification, and visible top-right X close.

The accepted fixture is `SingleTestProject`, created once through Visual Studio as an Empty Project and then reused for three staged build/run checks. Stage 1 verifies single-source `main.cpp`; Stage 2 verifies `main.cpp` plus `math.cpp`; Stage 3 verifies a header include path with `math_utils.h` and a source implementation.

This layer does not add a planner that bypasses the IDE. Backend cleanup is allowed only for wrong-project cleanup after an unrecoverable visible failure. Backend project creation, backend file creation or writes, `.vcxproj` edits, backend build, and backend exe run are not valid PASS paths.

VLM remains locate-only assistance through the v1.0.3+ real path. Legacy mock VLM is not used in normal workflow paths, and accepted VLM candidates still require coordinate mapping, target-window lock, Runtime visible action, and post-action verification before influencing a UI action.

## DesktopVisual 1.0.3.1 Legacy Mock VLM Quarantine

DesktopVisual 1.0.3.1 keeps the v1.0.3 real VLM bridge as the normal VLM path and quarantines legacy mock VLM commands as deprecated test-only fixtures. Normal Agent/Runtime use must go through `RealVlmRuntimeBridge`, `vlm-capability-probe`, `vlm-assist-locate`, `vlm-candidate-validate`, and `tools\codex_vlm_provider.ps1`.

The historical `MockVLMProvider`, `VLMRuntimeBridge`, and `VLMCandidateBridge` sources can remain buildable for legacy selftests, but default user/agent calls to mock commands fail unless an explicit legacy mock opt-in is present. Opt-in output is marked `legacy_mock_vlm=true`, `real_vlm=false`, and `not_for_agent_workflow=true`.

## DesktopVisual 1.0.3 Provider-Gated VLM Runtime Bridge

DesktopVisual 1.0.3 adds a real but provider-gated VLM assist layer below the Skill contract and inside Runtime evidence discipline. The bridge is intentionally assistive: it can interpret screenshot pixels, return candidate target bbox/point data, and explain visual uncertainty, but it cannot perform actions or choose fallback paths.

The bridge path is:

```text
visible Runtime locate/action ambiguity
  -> VLM capability/session cache
  -> Codex CLI provider wrapper
  -> strict JSON response artifact
  -> RuntimeCandidateValidator
  -> coordinate/evidence binding
  -> Runtime-owned visible retry or fallback policy
```

Capability is cached on disk per session/provider so repeated CLI invocations do not probe every action. `VLM_UNAVAILABLE` and `VLM_UNKNOWN` are not blockers for Runtime; they downgrade to Runtime-only visible fallback discipline with evidence.

`vlm-assist-locate` and `vlm-candidate-validate` never execute mouse, keyboard, command, file, or backend actions. Candidate acceptance requires strict JSON, `coordinate_space=image_pixels`, in-bounds bbox/point, confidence threshold, semantic match, acceptable target type, existing screenshot/evidence files, screenshot/frame binding, target/window mapping, and no active-protection safety flags.

For v1.0.3.1, accepted VLM candidates are locate-only. Candidate accepted is not action executed, click success, input success, or task success. Future v1.0.4 complex IDE workflows require coordinate mapping, target window lock, and post-action verification before using any VLM candidate for visible action. The concrete preconditions are: image pixel coordinates are mapped to screen coordinates, the target window rect / hwnd / title / process is locked, the candidate point is proven inside the locked target window, Runtime executes the visible action, and post-action observe verifies the expected state. This repository already has `ScreenshotCoordinateMapper` and `TargetWindowLock` foundation components, but v1.0.3.1 does not pretend the full real VLM action path is complete.

The visible fallback integration allows VLM only after eligible UIA/OCR/template/perception failures in the first visible layer, or for keyboard fallback state verification. Once backend fallback starts, VLM is no longer invoked. Active protection/security interception remains STOP, not VLM recovery.

This layer does not implement complex IDE workflows, full-screen Capture/OCR performance optimization, public permission hardening, release packaging, or release/public-dist changes.

## DesktopVisual 1.0.2 Skill Contract Layer

DesktopVisual 1.0.2 adds no new Runtime behavior. It hardens the source-of-truth Skill, Codex adapter, shared adapter rules, and usage references so agents must enter DesktopVisual through the v1.0.1 visible-first Runtime discipline.

The Skill contract sits above the Runtime command layer. It tells agents that DesktopVisual is a Windows visible-first desktop runtime, not a background script executor. Agent success is path-sensitive: `observe / locate / act / verify` or equivalent task/visible command evidence is required, and a backend shortcut can invalidate a task even when the final UI state appears correct.

The launch contract maps app, URL, local shortcut, `.lnk`, `.url`, and webpage shortcut launches to `visible-app-launch` desktop-first. Start Menu visible search is a visible fallback only after bounded desktop evidence, and backend launch/ShellExecute/direct file open/background browser navigation are not default launch paths.

The fallback contract documents the three layers: visible UI path, visible keyboard fallback, then backend fallback. Shortcut fallback requires at least two bounded visible attempts or strict surface-impossible evidence. Backend fallback additionally requires visible path failure plus keyboard fallback failure and a non-convenience reason. Active protection/security interception remains STOP, not fallback.

The developer permission architecture is unchanged. `DEVELOPER_CAPABILITY_DISCOVERY` / `DEVELOPER_FULL_RUNTIME` remain broad developer modes; ordinary category or keyword matching is not a developer STOP condition without active protection. DesktopVisual 1.1.0 later aligns `PUBLIC_DEFAULT` ordinary visible capabilities while preserving active-protection STOP boundaries.

## DesktopVisual 1.0.1 Runtime Visible-First Launch Layer

DesktopVisual 1.0.1 adds a generic Runtime-level desktop-first launch path through `visible-app-launch`. The launch path is desktop surface observation -> visible desktop icon/shortcut locate through UIA with OCR supplement evidence -> real mouse double-click -> target window verification by title/process. Start Menu/taskbar Search and visible browser address-bar navigation are visible fallbacks only after bounded desktop failure evidence.

`VisibleOperationPolicy` now owns stricter fallback gates across direct policy checks, visible final verification, visible text input, deterministic action batches, StepContract validation, and visible primitives. Attempt 2 requires at least two bounded visible attempts with pre-action checkpoint, recovery, re-observe/re-locate, and same-surface evidence, unless strict `surfaceImpossible` evidence is present. Attempt 3 backend fallback additionally requires failed shortcut evidence and a non-convenience backend reason.

The developer tree keeps maximum developer permissions. DesktopVisual 1.1.0 later aligns `PUBLIC_DEFAULT` ordinary visible capabilities for release trees without narrowing this developer mode.

## v6.12.1 Visible UI Execution Foundation Layer

The v6.12.1 layer adds visible UI execution primitives under `src/winagent`: `GlobalDpiAwareFrame`, `TargetWindowLock`, `ScreenshotCoordinateMapper`, `ForegroundPreempt`, `VisibleTextInputPolicy`, `VLMRuntimeBridge`, `DeterministicActionBatch`, `VisibleUIVerificationPolicy`, and `PyCharmVisibleWorkflow`.

The foundation path is global DPI-aware frame capture -> foreground preempt -> target window lock -> coordinate mapper -> visible real-keyboard input or locked click/hotkey -> deterministic wait condition -> global-frame verification. `screenshot --out` without a target selector now follows the global frame path, while window-only screenshots are diagnostic evidence only.

Visible text input is planned before it is sent. The plan maps CRLF, LF, CR, and Tab to Enter/Tab key events and records first-pass multiline evidence so code editor input cannot be accepted after first collapsing into one line. `code_editor_keyboard` rejects detected `selfself` autocomplete artifacts instead of counting a later repair as PASS.

HumanMode mouse movement uses high-resolution frame timestamps. `fast-visible-ui` defaults to a 165Hz best-effort target and records target frame interval, actual frame rate, average/p95 frame interval, target miss, and cursor overshoot evidence without weakening target lock or foreground verification.

`VisibleOperationPolicy` owns the default operation-priority rules. Show desktop defaults to a bottom-right taskbar Show Desktop click, with Win+D and backend show desktop only as later fallbacks. Window switching defaults to Alt+Tab keyboard switching, with visible taskbar/window click and backend focus only as later fallbacks.

Runtime VLM assistance is defined as a candidate chain validated by RuntimeCandidateValidator, ScreenshotCoordinateMapper, TargetWindowLock, action, and verification. Current-model visual inspection of a screenshot is explicitly classified separately and cannot set `vlm_assisted=true`.

This layer is developer-tree only and does not inspect, modify, package, or publish release/public-dist trees.

## v6.12.0 Developer RC Gate and Handoff Layer

The v6.12.0 layer adds metadata and handoff modules under `src/winagent`: `DeveloperRCGate`, `VersionIntegrityChecker`, `EvidenceChainVerifier`, `CapabilityMatrixBuilder`, `WorkflowBoundaryAuditor`, `DeveloperFullAccessPolicyVerifier`, `ReleaseHardeningDeferredLedger`, and `HandoffPackageBuilder`.

This layer verifies the v6.2-v6.11 evidence chain, version/runtime/docs consistency, command protocol consistency, workflow boundary preservation, memory and template safety boundaries, developer full-access policy, release-hardening deferral, and handoff package safety. It generates reports and a developer handoff package only.

v6.12.0 does not add workflow behavior, does not change `RuntimeSession`, `StepContract`, `CompiledPlanExecutor`, verifier, or safety-intercept semantics, does not rerun old UI workflows, and does not implement public-release permission hardening.

## v6.11.0 Workflow Template and Batch Layer

The v6.11.0 layer adds reusable workflow structures under `src/winagent`: `WorkflowTemplateRecord`, `WorkflowTemplateRegistry`, `WorkflowTemplateCandidateExtractor`, `WorkflowTemplateValidator`, `WorkflowTemplateInstantiator`, `WorkflowTemplateSafetyBoundary`, `BatchWorkflowPlan`, `BatchWorkflowPlanner`, `BatchWorkflowValidator`, and `BatchWorkflowCoordinator`.

Template Learning is evidence-derived candidate extraction plus validation. It is not model training, an optimizer, automatic planning, automatic repair, or Runtime execution influence. Candidate templates are non-executable; only validated templates can instantiate StepContract JSON, and instantiation calls the existing `StepContractValidator`.

The registry is local structured JSON under `artifacts\workflow_templates` by default and appends audit records for updates. It stores template metadata, source evidence refs, schemas, safety constraints, validation status, and deterministic template hashes. It does not use external databases, vector databases, or network services.

Batch acceleration creates deterministic batch plans for compile-only, validate-only, and serial mock-safe coordination. It does not run parallel real UI, share concurrent RuntimeSession state, skip step-level verification, skip EvidencePack requirements, or change RuntimeSession, StepContract, Executor, or Verifier semantics.

## v6.10.0 Experience Memory Layer

The v6.10.0 layer adds append-only evidence-derived memory and unified failure attribution under `src/winagent`: `ExperienceMemoryRecord`, `ExperienceMemoryStore`, `ExperienceMemoryIndex`, `FailureAttributionNormalizer`, `FailureAttributionIntegrator`, and `MemorySafetyBoundary`.

Experience Memory is a structured local record layer. It stores JSONL records and a read-only index under `artifacts\experience_memory` by default. Records include workflow type, execution result, failure type/code, normalized failure category, evidence reference, evidence hash, source version, trusted version, schema version, redaction status, and execution-influence guard fields.

The memory layer is not a planner, optimizer, executor, recovery engine, or locator selector. Query/report commands are read-only and do not emit StepContracts, workflow actions, automatic retries, fixes, or optimization suggestions. Runtime execution remains owned by the existing StepContract -> validator -> CompiledPlanExecutor -> RuntimeSession path.

`FailureAttributionNormalizer` maps workflow-specific status and stop codes into the v6.10 category set: `LOCATOR_FAILURE`, `CONTEXT_MISMATCH`, `RUNTIME_GUARD_STOP`, `CREDENTIAL_REQUIRED`, `ACTIVE_PROTECTION`, `STEP_VALIDATION_FAILED`, `EXECUTION_VERIFICATION_FAILED`, `EVIDENCE_MISSING`, `ENVIRONMENT_BLOCKED`, `UNKNOWN_FAILURE`, and `SUCCESS_NO_FAILURE`. Unknown failures are never success, and `RAW_COMPLETED_UNVERIFIED` maps to `EVIDENCE_MISSING`.

`MemorySafetyBoundary` blocks missing or invalid evidence references, missing source/trusted version fields, sensitive plaintext communication content, untrusted sources, runner-only memory logic, query side effects, Runtime execution influence, StepContract mutation, and `RAW_COMPLETED_UNVERIFIED` recorded as success.

## v6.9.0 System Stabilization Layer

The v6.9.0 stabilization layer adds reusable evidence and boundary modules under `src/winagent`: `RuntimeEvidenceConsolidator`, `SessionLifecycleManager`, and `WorkflowSystemBoundary`.

`RuntimeEvidenceConsolidator` scans artifacts, classifies evidence, computes hashes, detects unreferenced runtime sessions, duplicate session evidence, missing evidence indexes, missing final status reports, and raw artifact growth. It generates JSON and Markdown reports only; it does not delete files.

`SessionLifecycleManager` scans `artifacts/runtime_sessions`, links sessions back to evidence indexes when possible, marks referenced, duplicate, stale, and unreferenced sessions, and generates an archive plan. Referenced sessions are retained, unknown-source sessions are retained, and no runtime session is deleted by default.

`WorkflowSystemBoundary` checks the structure of Explorer, Browser/Form, Communication, VLM Observation, VLM Candidate, and compiled plan execution paths. It verifies the expected StepContract, validator, RuntimeSession, RuntimeContextGuard, step-level verification, evidence pack, evidence index, final report, and gate boundaries where applicable. VLM observation remains assistive-only and non-executable.

The stabilization commands are metadata and source-structure checks only. They do not replay old UI workflows and do not change RuntimeSession, StepContract, CompiledPlanExecutor, or VLM candidate execution semantics.

## v6.8.0 Browser/Form Workflow Layer

The v6.8.0 branch adds accepted Browser/Form workflow components under `src/winagent`: `BrowserWorkflow`, `BrowserWorkflowAdapter`, `BrowserWorkflowExecutor`, `BrowserWorkflowVerifier`, and `WebFormFieldLocator`. The path is workflow JSON -> StepContract -> StepContractValidator -> CompiledPlanExecutor -> RuntimeSession/RuntimeContextGuard -> Browser UI action -> Browser/Form verification -> recovery or STOP -> evidence pack.

BrowserWorkflow supports open/read/scroll/locate, local-safe form fill/submit, wrong-page recovery, active-protection STOP, and credential-required STOP. Web form field location uses UIA/visible text/nearby label association and rejects missing, ambiguous, direct-coordinate, DOM/JS/WebDriver/CDP/Playwright/Selenium, and fake evidence paths. Ordinary external webpages are limited to read-only diagnostic evidence in v6.8.0.

## v6.7.0 Explorer Workflow Layer

The v6.7.0 branch adds accepted Explorer workflow components under `src/winagent`: `ExplorerWorkflow`, `ExplorerWorkflowAdapter`, `ExplorerWorkflowExecutor`, `ExplorerWorkflowVerifier`, and `ExplorerContextMenuHandler`. The path is workflow JSON -> StepContract -> StepContractValidator -> RuntimeSession/RuntimeContextGuard -> Explorer UI action -> step-level verification/evidence pack.

The accepted rerun repairs the Explorer move and scroll-and-locate blockers. Move workflows must prove mouse source selection, cut/paste action sending, destination focus, result verification, and no PowerShell/direct file API workflow action. Scroll-and-locate workflows must prove list focus, visible item movement, target visibility/location, no stale rect use, and RuntimeContextGuard on each iteration.

v6.6.0 accepts VLM-Assisted Unknown UI Candidate Handling. Runtime can ask for assistive-only VLM semantic candidates after locator failure, but only Runtime-validated candidates can become LocatorCandidates and enter the normal Runtime guard plus mouse action path.

DesktopVisual v3.7.0 is organized as a Windows-only, agent-agnostic, auditable, safety-bounded Computer Use Runtime:

```text
Agent adapter / Skill / Script
  -> Agent Boundary validation (runtime or vlm_assisted)
  -> VLMObservationRequest / VLMObservationResult contract
  -> VLMProvider / MockVLMProvider observation-only provider layer
  -> VLMObservationValidator
  -> VLMObservationBoundary dry-run diagnostics
  -> VLMCandidateBridge after Runtime locate failure
  -> RuntimeCandidateValidator
  -> LocatorCandidate(candidate_source=vlm_assisted_runtime_validated)
  -> AgentTaskRequest / AgentPlan validation
  -> TaskIntent / AgentPlanDraft planning boundary
  -> PlanCompiler
  -> StepContract validator
  -> dry-run session-compatible structured step output
  -> CompiledPlanExecutor
  -> StepContractRuntimeAdapter
  -> RuntimeSession dispatch
  -> step-level verification
  -> recovery or stop
  -> execution evidence pack
  -> CLI or explicit local Service Protocol v1.0
  -> PermissionManager DEFAULT/FULL_ACCESS gate
  -> global desktop/app launch gate when requested
  -> external web/browser navigation gate when requested
  -> form/control semantics when requested
  -> content_decision gate + decision engine when requested
  -> communication gate + communication action runtime when requested
  -> content_decision gate + coding workflow when requested
  -> full access benchmark/evidence harness when requested
  -> developer-tool dogfood evidence harness when requested
  -> session checkpoint + loop guard
  -> task template expansion
  -> WindowSession resolve/reconfirm
  -> observe
  -> observe2 provider registry and perception graph when requested
  -> App Profile adapter metadata when requested
  -> selector locate
  -> controlled act
  -> observe after action
  -> expect verification
  -> recovery strategy engine where allowed
  -> report, audit log, failure classification
```

## Agent Boundary Layer

v6.0.0 exposes `agent-boundary-validate` for read-only validation of the desktop Agent boundary.

Runtime Mode is the local execution path. It uses Runtime capabilities such as observe, UIA, OCR, screenshot, selector/adaptive locate, StepContract, TaskRuntime, SafetyPolicy, PermissionManager, and HumanMode.

VLM-Assisted Mode may interpret screenshots, propose semantic targets, classify a scene, explain failures, or help construct a plan. It must not execute desktop actions directly.

Runtime is the only action executor. A valid AgentPlan uses `executor="runtime"` and `compile_required=true`; plan steps also require `executor="runtime"` and `compile_required=true`. `executor="vlm"` and `executor="agent_direct"` fail validation. JS, DOM, WebDriver, CDP, UIA InvokePattern, and UIA ValuePattern are not HumanMode Runtime actions.

## VLM Observation Contract Layer

v6.5.0 exposes assistive-only observation commands:

- `vlm-observation-build-request`
- `vlm-observation-run-mock`
- `vlm-observation-validate`
- `vlm-observation-dry-run`
- `vlm-observation-selftest`

`VLMObservationRequest` packages screenshot path/ROI, UIA summary, OCR summary, visible text hash, element summary, window context, task hint, expected context, observation purpose, provider role, allowed outputs, forbidden outputs, and blocked-context markers. The provider role is always `assistive_only`.

`VLMObservationResult` can contain scene summary, visible text, approximate layout regions, semantic elements, possible targets, uncertainty, rejection reason, and safety notes. Possible targets are observation-only and must require Runtime validation. Approximate regions are not direct click points.

`VLMObservationValidator` rejects malformed JSON, provider role mismatch, direct click/type/scroll, coordinate-only action, Runtime command output, executable action output, active-protection bypass, CAPTCHA solving, credential handling, anti-cheat/script-detection bypass, and possible targets that lack Runtime validation requirements. Prompt-injection-like visible text is classified as untrusted text and cannot become an instruction.

`VLMObservationBoundary` records dry-run evidence with `runtime_executed=false`, `mouse_click_sent=false`, `keyboard_type_sent=false`, `vlm_result_entered_runtime_action_path=false`, and `safe_for_direct_execution=false`. VLM results do not enter `StepContract`, `CompiledPlanExecutor`, or `RuntimeSession` execution paths directly.

## VLM-Assisted Candidate Layer

v6.6.0 exposes Runtime-owned candidate commands:

- `vlm-assisted-locate`
- `vlm-assisted-locate-dry-run`
- `vlm-assisted-locate-and-click-local-safe`

`VLMCandidateBridge` runs only after a Runtime locate failure. It builds a VLM observation request, calls the mock or disabled provider placeholder, validates provider output with `VLMObservationValidator`, and forwards observation-only `possible_targets` to `RuntimeCandidateValidator`. The bridge does not click, type, scroll, or return executable actions.

`RuntimeCandidateValidator` checks schema, `observation_only`, `requires_runtime_validation`, direct-coordinate attempts, role support, confidence floor, target freshness, active-protection and credential risk, window/viewport/ROI bounds, expected target/context, UIA/OCR/element-summary corroboration, and uniqueness. A candidate cannot pass on VLM confidence alone.

Only a Runtime-validated candidate can convert into `LocatorCandidate`. Converted candidates use `candidate_source=vlm_assisted_runtime_validated` and `coordinate_source_type=vlm_assisted_runtime_validated`, recompute the center from the validated rect, and require final RuntimeContextGuard, mouse-first evidence, and post-action verification before any local-safe action.

## PlanCompiler Layer

v6.3.0 exposes compile-only commands for reviewed `AgentPlanDraft` input:

- `plan-compile`
- `step-contract-validate --input`
- `step-contract-dry-run`
- `plan-compile-selftest`

`AgentPlanDraft` is not executable. It must compile to `StepContract` before any future Runtime execution layer can consume it. The v6.3 compiler requires expected context and verification hints, emits action preconditions, risk policy, confirmation policy, recovery policy, stop policy, session policy, and evidence policy for every step, and rejects unsafe direct coordinates, unsupported actions, ambiguous targets, missing high-risk confirmation, and recovery attempts that bypass active protection or credentials.

`StepContractValidator` independently checks schema completeness, unique step ids, continuous step indexes, supported runtime actions, expected context, action preconditions, verification hints, risk levels, high-risk confirmation policy, blocked risk non-executability, direct coordinate rejection, stop policy, recovery policy, v6.2 session compatibility, and verifier/gate evidence policy.

`step-contract-dry-run` emits structured JSON compatible with the v6.2 session step shape and records `runtime_executed=false`. It does not start sessions, call `runtime-session-dispatch`, click, type, scroll, launch apps, or open pages.

## Runtime Task Execution Layer

v6.4.0 exposes execution commands for compiled contracts:

- `run-agent-task`
- `execute-step-contract`
- `execute-compiled-plan`
- `step-execution-verify`

`CompiledPlanExecutor` loads a StepContract, invokes the v6.3 validator, rejects non-executable or unsafe contracts, creates or reuses a v6.2 RuntimeSession, applies context/precondition checks before each step, verifies every step after action, attempts recovery only when the recovery policy allows a safe local recovery, stops on verification/guard/risk failure, and writes an execution evidence pack.

`StepContractRuntimeAdapter` maps contract fields into RuntimeSession-compatible structured steps. Expected context feeds RuntimeContextGuard; action preconditions feed target/focus/viewport/stale/unique checks; verification hints feed step verification; recovery, stop, session, and evidence policies feed execution behavior.

Dry-run mode validates and adapts the plan but records `runtime_executed=false`. Execute-local-safe mode is limited to local/localhost/Explorer/mock-safe tasks in v6.4 and remains blocked for unconfirmed REAL_COMMIT/DESTRUCTIVE, active-protection, credential-required, or direct-coordinate-unsafe contracts.

## Agent Calling Layer

Agents call `winagent.exe` directly, use adapter helper scripts, use the legacy Skill helper scripts, or connect to an already-started local service. Service mode is explicit (`winagent serve`) and wraps existing command handlers; it does not bypass PermissionManager or SafetyPolicy.

Adapters live under `adapters\codex`, `adapters\claude-code`, `adapters\generic-cli`, and `adapters\shared`. They define host-specific instructions while sharing the same CLI safety boundary.

## WinAgent Execution Layer

`winagent.exe` owns command parsing, target validation, action execution, file reading, case execution, task execution, safety reporting, permission reporting, and JSON envelope output. Input actions require a target title, must resolve to exactly one visible top-level window, must pass PermissionManager plus SafetyPolicy/Safety Manifest denied-category checks, and must verify foreground focus before input.

## PermissionManager Layer

`PermissionManager` defines `DEFAULT` and `FULL_ACCESS`. DEFAULT preserves the existing safety boundary. FULL_ACCESS requires a temporary session created only after local interactive `unlock-full-access` confirmation, validated by session id, TTL, and scope, and inspected through `permission-status`. It can relax configured title/process/action allowlists for normal user desktop tasks, but it cannot override immutable stops such as credentials, captcha, anti-automation, anti-cheat, protected desktop, user takeover, or loop guard.

`launch-app` is the v3.3.3 global desktop/app launch entry point. It runs only after PermissionManager allows `global_desktop` or `third_party_apps`, then records the unique visible target window. It does not provide hidden background launch/control.

`browser-nav` is the v3.3.4 external web/browser navigation entry point. It runs only after PermissionManager allows `external_web` for non-local URLs, audits the requested URL, and stops on login, credential, captcha, payment, anti-automation, and redirect-loop conditions. It does not provide hidden browser control or detection bypass.

`form-control` and `form_action` are the v3.3.5 form semantics entry points. They produce `FormControl` records and recommended action mappings, stop on captcha/challenge controls, and do not coerce unknown or low-confidence controls into textbox actions.

`decision-eval` and the `type: "decision"` task step are the v3.3.6 General Decision Task Runtime entry points. They run only after PermissionManager allows the `content_decision` capability, build a `DecisionTaskContext`, and produce a `DecisionRecord` for one resolved control. The Decision Engine never sends input, focuses windows, generates goals, lets page content override the user goal, or relaxes any boundary; it stops on captcha, anti-automation, credential, low-confidence, non-unique, and unauthorized-submit conditions using existing stop codes.

`SessionCheckpoint` and TaskRunner loop guard are the v3.3.7 long-task safety layer. Checkpoints record observable anchors and recovery suggestions; they are not rollback. Loop guard stops repeated actions, URL loops, no progress, repeated window-open markers, scroll no-progress, max-step overruns, and max-duration overruns before the task continues unsafe input.

`communication_step` is the v3.3.8 Communication Action Runtime entry point. It runs only after PermissionManager allows the `communication` capability, records `CommunicationAction` summaries, hashes message content instead of logging it, and stops when target or user send authorization is missing. It does not let page or chat content create new send instructions.

`coding-eval` and `type: "coding"` are the v3.3.9 Coding and Problem-Solving Web Workflow entry points. They run over local HTML/DOM-like OJ fixtures, record `CodingWorkflowContext` and `CodingWorkflowRecord`, and gate task execution on the existing `content_decision` capability. They stop on login/password, captcha, anti-automation/AI-detection, and missing reliable editor/run controls. Exam, assessment, hiring, certification, and rated-contest keywords require an explicit public-release permission policy before distribution, but are not hard-stopped solely by keyword in the development runtime.

The v3.3.10 Full Access benchmark harness is a script/report layer around the existing runtime. It runs safe local scenarios for permission gates, app launch, external-web simulation, forms, decision tasks, checkpoints, communication, coding workflows, and public-release assessment permission notice coverage. It does not add new desktop-control commands or weaken PermissionManager/SafetyPolicy.

The v3.4.0 Recovery Strategy Engine is the TaskRunner recovery layer. It maps known errors to finite strategies, records every recovery decision, and obeys the effective `max_recoveries` after Safety Manifest clamping. It does not recover `SAFETY_POLICY_DENIED`, auto-pick non-unique selectors, guess coordinates, or broaden target-window scope.

The v3.6.0 dogfood harness is a script/report layer for bounded developer-tool scenarios: Notepad, Calculator, Explorer under artifacts, local HTML form semantics, local PowerShell read-only/test output, and VS Code when available. Every task declares a safety boundary, expected result, and SKIPPED condition. It does not access external web, real accounts, browser profiles, payments, passwords, captcha, social apps, games, anti-cheat, UAC, or administrator windows.

The v4.6.0 visual dogfood harness extends that evidence approach with `v4_visual_dogfood.ps1`. It runs local developer workflow fixtures and records v4 perception evidence: `observe2`, `ElementGraph`, `LocatorCandidate`, `SceneState`, `ChangeEvent`, `observe-loop` delta/ROI metadata, and App Profile metadata. It is still a script/report layer, not a new desktop-control protocol or task planner.

The v4.7.0 release candidate layer adds `v4_rc_check.ps1` as a focused evidence aggregator. It reruns the v4 provider, observe-loop, latency, dynamic recovery, App Profile, visual dogfood, safety, profile JSON, Markdown, and public hygiene checks, then writes `artifacts\dev4.7.0\v4_release_candidate_report.md`. It is a stabilization and evidence layer, not a v5 task state machine.

## WindowSession Layer

`WindowSession` centralizes visible-window resolution and reconfirmation. It records requested title/process, actual title, hwnd, pid, process name, rect, visible/iconic state, foreground state, foreground controllability, per-window DPI, monitor device name, monitor bounds, and work-area bounds. Repeated matching windows return `WINDOW_NOT_UNIQUE`; a previously selected hwnd whose title no longer matches returns `WINDOW_TITLE_CHANGED` in TaskRunner reconfirmation.

## Safety Manifest Layer

`config\safety_manifest.json` is the machine-readable consent and safety boundary. It declares denied sensitive categories, runtime limits, permission modes, consent requirements, and audit settings. CLI exposes `safety-report`, `permission-status`, `unlock-full-access`, `lock-full-access`, `policy-check`, and `consent-check`.

## Observation Layer

`observe` combines target-window metadata, `window_session`, active-window metadata, mouse position, optional screenshot capture, UI Automation elements, safety summary, and warnings. It is read-only and is the standard first step for agent workflows.

## Hybrid Perception Layer

v4.1.0 adds `observe2` as a read-only provider-ready perception layer. It emits `ScreenFrame`, provider registry records, `ElementGraph`, `LocatorCandidate`, `SceneState`, and `ChangeEvent` JSON structures without executing input.

Visual source integration is intentionally local and pluggable. The registry reports `uia`, `ocr`, `screen_delta`, `image_template`, `local_visual_provider`, `cloud_vlm`, and `agent_provider`. UIA and image-template sources can produce candidates in v4.1.0. OCR is reported as a runtime capability but is not yet fused into `observe2` candidates. `screen_delta` reports degraded when no previous frame exists. OmniParser, YOLO, UGround, cloud VLM, and agent-provider integrations are placeholders that report unavailable or degraded unless future configuration and implementation are added.

Visual providers produce `VisualElementCandidate` records only. Each candidate carries source, source version, label, role, text, rect, confidence, attributes, artifact path, latency, semantic status, fusion status, and risk status. Image-template candidates are visual-only and `semantic_status="unresolved"` by default. `act` blocks unresolved visual-only selectors with `ACTION_BLOCKED_SEMANTIC_UNRESOLVED`.

v4.2.0 adds `observe-loop` and `observe2 --loop` as a read-only event stream over the same target-window boundary. The loop uses screenshot hashes as the first delta check, records cache hit/miss counts, runs ROI OCR and UIA refreshes only on changed rounds, emits debounced events, and stops through max-duration, max-events, max-no-change, stop-file, or safety-blocked guards.

The observe loop is not a task state machine. It does not click, type, plan cross-app tasks, call VLMs per frame, or let provider candidates execute actions. Its output is structured event evidence for future continuous execution layers.

v4.4.0 adds the Dynamic UI Recovery layer. `observe2` and `dynamic-ui-recovery` expose dynamic `SceneState`, `ChangeEvent`, recovery route, and router decisions. Runtime-owned recovery can wait/re-observe loading states, invalidate stale candidates, rebuild affected perception after repaint, and re-locate moved elements. Dialogs require a classified safe route or user confirmation. Errors stop or escalate by risk. Blocked states stop immediately and are not routed to VLM bypass.

The base routers are PerceptionRouter, SemanticResolver, RiskRouter, and ActionExecutor gate. They produce `AUTO_EXECUTE`, `ESCALATE_TO_VLM`, `REQUIRE_HUMAN_CONFIRMATION`, or `STOP`. `AUTO_EXECUTE` is allowed only when perception, semantic, and risk routes agree that the candidate is resolved and low risk.

## App Profile Layer

v4.5.0 adds App Profiles under `profiles\*.profile.json`. Profiles describe local app/window matching, common locators, OCR ROIs, visual strategy, recovery strategy, task templates, and confirmation nodes. The runtime can report profile load status with `profile-report` and can resolve a profile common locator through `locate --profile <name> --profile-locator <name>`.

Profiles are adapter metadata, not permissions. `effective_capabilities.can_override_safety_manifest` is always `false`, `safety_overrides` cannot loosen the Safety Manifest, and profile-derived candidates still carry `action_gate="requires_runtime_safety_policy"`. Built-in profiles are local and safe: TestWindow, Notepad, Explorer, Calculator, browser-local, local problem fixture, and local mail mock. They are not real-account or public-assessment profiles.

## Visual Dogfood Layer

v4.6.0 dogfood demonstrates the v4 perception layer on bounded local developer workflows: local HTML forms, a local mock problem page, a local mock mail page, an Explorer temp-file flow, Notepad when a clean safe target is available, and local PowerShell output reading. The report records commands, artifacts, observed events, locator methods, latency, PASS/FAIL/SKIPPED state, and failure reasons.

The local mail case is mock-only and does not send real email. The local problem page is a development benchmark fixture and not real exam, assessment, hiring-test, certification, proctored, or rated-contest automation.

## Hybrid Perception Release Candidate

v4.7.0 closes v4.x as a Hybrid Screen Perception Runtime. The stable v4 surface includes `ScreenFrame`, `ElementGraph`, `LocatorCandidate`, `SceneState`, `ChangeEvent`, `observe2`, provider registry reporting, Screen Delta, ROI OCR hooks, Perception Cache accounting, image-template visual candidates, `observe-loop`, Dynamic UI Recovery, App Profiles, latency evidence, and local visual dogfood evidence.

v4.x remains a runtime foundation. It does not include a complete autonomous Agent, full semantic understanding of arbitrary screens, real VLM integration, OmniParser/YOLO/UGround weights, GPU requirements, or real-account public benchmarks. v5 is reserved for task-level continuous execution. v6 is reserved for Runtime plus VLM/Agent semantic desktop intelligence.

## Selector Layer

Selectors unify coordinate, UIA, image, OCR text, relative, near-text, and fallback-chain location. UIA is preferred, OCR is second when available, image matching is third, and coordinates are last. v3.1.0 adds `automation_id`, `class_name`, explicit `nth`, relative positions, near-text anchors, and ordered fallback diagnostics. Locator failure stops the workflow; agents must not guess nearby positions.

## InputController

`InputController` activates the target window and sends mouse or keyboard input with `SendInput`. The default mouse movement mode is `human`, which resolves to `operator-human` and uses the validated local operator motion profile. If that profile is missing or invalid, mouse actions fail instead of falling back to legacy curved paths. Keyboard typing keeps legacy `human` compatibility by resolving to `demo-human`; `instant` is available only when explicitly requested by automation tests.

## Motion Profile Layer

`MotionRecorder` records direct mouse trajectory samples for authorized Motion Lab windows. `MotionProfile` calibrates raw samples into aggregate statistics under `config\operator_motion_profile.json` without embedding full raw traces. `MotionSynthesizer` generates bounded, non-perfect-linear screen paths from those statistics while preserving exact final target coordinates and F12 interruption.

## CaseRunner

`CaseRunner` supports legacy Case v1 and Case v2. Case v2 adds quoted key/value arguments, variables, `wait_until`, `expect`, and post-action verification. It stops immediately on failure and writes a Markdown report.

## TaskRunner

`TaskRunner` runs v3 task.json files through a closed loop: permission gate, task template expansion, initial WindowSession resolution, checkpoint, loop guard check, observe before, locate, foreground confirmation, act/hotkey, observe after, verify expectations, classify failures, optionally apply the Recovery Strategy Engine, then write a Markdown MVP report. Recovery is limited to safe documented strategies and never broadens window scope, guesses coordinates, or chooses ambiguous targets. Reports include initial permission decision, recovery records, per-step window-session diagnostics, and session checkpoint summaries.

## Task Template Layer

Task templates live under `tasks\templates`. A `type: "template"` task step loads a named `.task-template.json`, validates required declarations, substitutes parameters into the template `steps` array, and executes the expanded steps through the existing TaskRunner paths. Templates must declare `required_permissions`, `allowed_window`, `expected_result`, and `failure_behavior`; they cannot set `allow_unrestricted_desktop=true`. The report records template name, parameters, expanded steps, and result.

## Service Mode

`winagent serve` uses a local named pipe while exposing DesktopVisual Service Protocol v1.0. Endpoints include `/version`, `/health-check`, `/safety-report`, `/profile-report`, `/policy-check`, `/consent-check`, `/observe`, `/locate`, `/act`, `/run-case`, `/run-task`, `/read-report`, `/report`, and `/shutdown`. Every response uses the top-level `ok`, `error_code`, `message`, `data`, `artifacts`, `report_path`, `duration_ms`, and `service_protocol_version` envelope. Service requests can use an already unlocked FULL_ACCESS session but cannot unlock one or provide interactive confirmation. Each request is written to `artifacts\service_audit.log` with `permission_mode` and `service_protocol_version`.

## Reports And Artifacts

Reports, screenshots, dogfood output, service audit logs, and task reports are written under `<project_root>\artifacts`. File reads and writes remain constrained by configured allowlists.

## Benchmark Evidence Layer

`benchmark_matrix.ps1` runs task-scoped benchmark evidence checks and writes `artifacts\benchmark\benchmark_report.md` plus `benchmark_summary.json`. `full_access_benchmark_matrix.ps1` writes `artifacts\benchmark\full_access\full_access_benchmark_report.md` plus `full_access_benchmark_summary.json`. `latency_benchmark.ps1` writes the v4.3 latency evidence pack under `artifacts\dev4.3.0\latency` with JSON metrics, Markdown summary, raw logs, screenshots, and local fixtures. `export_evidence_pack.ps1` and `export_full_access_evidence_pack.ps1` package selected benchmark reports and safety/methodology docs without including binaries, profiles, raw motion data, browser caches, real communications, account data, or historical artifacts.

The v4.3 latency layer measures before claiming: Runtime first, UIA/OCR/Delta/Profile/Cache first, visual providers on demand, and VLM/Agent only for future semantic escalation. The default benchmark records `llm_or_vlm_call_count = 0`.

## Public Baseline Export

The public GitHub baseline is produced by `package_source.ps1`. It copies source, docs, cases, tasks, config, dogfood scripts, adapters, benchmarks, Skill template, and necessary root scripts into a clean source export. It intentionally excludes generated runtime directories such as `artifacts`, `bin`, `obj`, `dist`, browser profiles, caches, screenshots, logs, and release archives. This keeps the public repository reproducible without publishing local run history.

## TestWindow And Dogfood

`TestWindow.exe` provides deterministic state for core tests. Dogfood scripts extend coverage to Notepad, Calculator, Explorer, local HTML form semantics, local PowerShell read-only/test output, and VS Code when installed, with SKIPPED status for missing or unsafe environments.

## Boundary

DesktopVisual is not unrestricted desktop automation and is not official Codex built-in Computer Use. It does not support protected desktops, administrator windows, arbitrary user files, autonomous decision-making, sensitive flows, or guaranteed control of every custom-drawn UI.

## Portable Root

PowerShell scripts resolve root through -Root, DESKTOPVISUAL_ROOT, upward marker discovery, then legacy fallback. The WinAgent executable resolves root through DESKTOPVISUAL_ROOT, executable-location discovery, current-directory runtime markers, then legacy fallback. `version` reports `project_root`.




## v5.9.0-a Permission Architecture Update

`PermissionManager` separates developer capability discovery from public release STOP policy. The internal development tree uses `DEVELOPER_CAPABILITY_DISCOVERY` by default, accepts `DEVELOPER_FULL_RUNTIME` as an alias, keeps `CI_MOCK` for schema/mock tests, aligns `PUBLIC_DEFAULT` ordinary visible capability for public release use, and keeps legacy `FULL_ACCESS` compatibility.

Developer mode returns audited allow decisions for ordinary low-level desktop UI primitives, browser, Explorer, third-party app, local HTML, localhost, ordinary external web navigation, ordinary forms, and mock workflows. It relaxes configured title/process allowlists for developer exploration but still honors active protection, protected desktop/UAC, and no-bypass rules.
