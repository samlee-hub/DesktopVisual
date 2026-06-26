# Changelog

Current trusted version: `DesktopVisual 1.1.0 Public Release Permission Alignment, Agent Efficiency, and Release Tree Sync`.

## DesktopVisual 1.1.0 Public Release Permission Alignment, Agent Efficiency, and Release Tree Sync

- Aligns `PUBLIC_DEFAULT` ordinary visible desktop capability with developer ordinary app/web/IDE/Explorer/localhost workflows: third-party app, browser, https, localhost, Explorer, local file open, cross-window, global desktop, communication, and content-decision capabilities are enabled without requiring a legacy FULL_ACCESS session.
- Preserves STOP behavior for real active protection and security interception: real exam/proctoring/lockdown browser, CAPTCHA/human verification, bot or automation challenge, protected desktop/UAC, credential/security handoff, and anti-cheat mechanisms remain stop boundaries.
- Keeps developer permissions unchanged: `DEVELOPER_CAPABILITY_DISCOVERY` remains the developer default, `DEVELOPER_FULL_RUNTIME` remains broad, ordinary content keywords are not developer STOP conditions, and `allow_absolute_screen_click=true` remains enabled.
- Adds compact agent output policy with `report_level=compact`, `progress_output=compact`, and `step_chat_detail=compact` while retaining `evidence_level=full` and `artifact_evidence=full`.
- Adds public permission alignment, profile separation, compact output, Skill policy, source release sync, public-dist sync, and release readiness selftests plus v1.1.0 evidence under `artifacts\dev1.1.0_public_permission_agent_efficiency\`.
- Syncs the source release tree and public-dist tree for v1.1.0 without GitHub upload and without generating a release zip/package.

## DesktopVisual 1.0.5 Full-screen Capture/OCR Performance Pipeline

- Adds `capture-fullscreen-frame` and a frame registry so a full-screen frame is the source-of-truth for OCR, foreground/window crops, VLM transport, and PNG evidence.
- Moves OCR to a memory-frame-first path with `ocr-fullscreen-frame`, `ocr-foreground-from-frame`, and `ocr-window-from-frame`; OCR results bind `frame_id` and `screenshot_id` and report `png_read_for_ocr=false`.
- Keeps PNG evidence retained while saving it asynchronously by default; `evidence-flush` / `frame-evidence-flush` provide the flush barrier required before failure/BLOCKED/final reports.
- Crops foreground/window OCR from the full-screen frame and falls back to full-screen OCR using the same frame when crop OCR fails.
- Adds frame-level OCR cache plus crop/tile hash cache commands `ocr-cache-status` and `ocr-cache-clear`.
- Hardens VLM image transport with `vlm-frame-transport-check`; Codex CLI currently declares `provider_transport=file_path`, `provider_requires_file_input=true`, and `supports_memory_bytes=false`, with provider input PNG generated from the existing frame rather than recapturing.
- Keeps v1.0.4 Visual Studio workflow semantics, developer permissions, release/public-dist directories, and release packaging untouched.

## DesktopVisual 1.0.4 Visual Studio C++ Complex IDE Human-Like Workflow

- Adds step-by-step Visual Studio C++ complex IDE workflow evidence for the existing `SingleTestProject` developer fixture.
- Requires Visual Studio launch by visible desktop icon double-click and close by visible top-right X at stage boundaries.
- Covers `SingleTestProject` Empty Project creation, visible IDE file-add workflow for `main.cpp`, `math.cpp`, and `math_utils.h`, and three IDE build/run stages: single file, multi-source, and multi-source plus header.
- Keeps project creation, file creation, code input, build, and run on visible VS UI or visible IDE shortcuts. Backend project/file/build/run substitution remains invalid PASS evidence.
- Keeps the v1.0.3+ real VLM path locate-only and forbids legacy mock VLM in normal workflow paths.
- Keeps developer permissions unchanged; public profile alignment is completed later in v1.1.0.

## DesktopVisual 1.0.3.1 Legacy Mock VLM Quarantine and VLM Path Hardening

- Quarantines legacy mock VLM commands as explicit opt-in, deprecated, test-only fixtures. Normal Agent/Runtime VLM use must not call them.
- Keeps the v1.0.3+ normal VLM path on `vlm-capability-probe`, `vlm-assist-locate`, `vlm-candidate-validate`, `RealVlmRuntimeBridge`, and `tools\codex_vlm_provider.ps1`.
- Hardens VLM command JSON envelopes with top-level `ok`, `command`, `timestamp`, `duration_ms`, error details, and `data` / `evidence` mirrors while preserving v1.0.3 command-specific fields.
- Makes VLM action boundaries explicit: `vlm-assist-locate` is locate-only, accepted candidates are not action success, and Runtime must perform coordinate mapping, target window lock, visible action execution, and post-action verification before any future v1.0.4 IDE action.
- Updates Skill, adapter, shared rules, and documentation so agents do not treat legacy mock commands as available workflows and continue Runtime-only when VLM is unavailable.

## DesktopVisual 1.0.3 Automatic Real VLM Runtime Bridge

- Adds provider-gated real VLM assist through `vlm-capability-probe`, `vlm-assist-locate`, and `vlm-candidate-validate`.
- Implements the Codex CLI VLM provider wrapper for `codex exec <prompt> --image <file>` with strict JSON output, timeout/unavailable/invalid-response handling, raw output artifacts, and parsed JSON artifacts.
- Adds session-level file cache for VLM capability so each provider/session probes once and later Runtime calls use cached `VLM_AVAILABLE`, `VLM_UNAVAILABLE`, or `VLM_UNKNOWN` status.
- Validates VLM candidates through Runtime-owned checks for JSON schema, confidence, bbox/point bounds, `image_pixels` coordinates, target semantics, target type, active-protection safety flags, evidence files, screenshot/frame binding, and coordinate/window mapping.
- Wires VLM assist evidence into visible fallback discipline. VLM may assist only after eligible visible perception/location ambiguity, may verify unclear keyboard fallback state, and never runs after backend fallback starts.
- Keeps VLM assistive only: it does not click, type, move the mouse, execute commands, decide backend fallback, bypass safety policy, or run every step.
- Updates source Skill, Codex adapter Skill, and shared adapter rules so agents probe once per large task/session, reuse capability cache, downgrade to Runtime-only when VLM is unavailable, and stop on active protection instead of asking VLM to bypass it.
- Keeps developer permissions unchanged: `DEVELOPER_CAPABILITY_DISCOVERY` remains the developer default, developer capabilities remain enabled, and `allow_absolute_screen_click=true` remains enabled.
- Does not add complex IDE workflow automation, does not implement the full-screen Capture/OCR performance pipeline, does not modify release/public-dist paths, and does not generate a release package. Public profile alignment is completed later in v1.1.0.

## DesktopVisual 1.0.2 Skill Contract Hardening

- Hardens the source-of-truth Skill contract so agents must treat DesktopVisual as a Windows visible-first desktop runtime, not a background script executor.
- Documents `visible-app-launch` as the required desktop-first launch entry for apps, URLs, local shortcuts, `.lnk`, `.url`, and webpage shortcuts; Start Menu visible search is fallback only, and backend launch/ShellExecute/direct file open/background browser navigation are not default paths.
- Documents the three-layer fallback order: visible UI path, visible keyboard fallback, then backend fallback only after visible and keyboard fallback failures. One locator/click failure is not enough to change layers, and `target_not_found`, `uia_not_found`, `ocr_not_found`, and `click_failed` alone are not surface-impossible evidence.
- Adds `skill_template\win-desktop-agent\references\VISIBLE_FIRST_CONTRACT.md` and updates source references for usage, real workflow, safety, safety model, known limitations, and command protocol.
- Hardens the Codex adapter Skill and shared adapter rules to match the source contract, and updates adapter scripts to accept `-Root`.
- Adds `skill_contract_hardening_selftest.ps1` and `skill_adapter_contract_selftest.ps1` for structured Skill/adapter contract checks, reference consistency, banned old-rule checks, and adapter script execution checks.
- Keeps developer permissions unchanged: `DEVELOPER_CAPABILITY_DISCOVERY` remains the developer default, developer capabilities remain enabled, and `allow_absolute_screen_click=true` remains enabled.
- Does not modify Runtime behavior, connect real VLM providers, add complex IDE workflow automation, redefine PUBLIC_DEFAULT, modify release/public-dist paths, or generate a release package.

## DesktopVisual 1.0.1 Runtime Visible-First Launch and Fallback Discipline

- Adds the generic `visible-app-launch` Runtime command with desktop-first visible launch behavior: show/observe desktop, locate visible desktop shortcuts/icons through UIA with OCR supplement evidence, double-click with real mouse input, verify the target window by title/process, and only then use visible Start/Search or visible browser navigation fallback.
- Strengthens `VisibleOperationPolicy` fallback gates. Shortcut fallback now requires two bounded visible attempts with checkpoint/recovery/re-observe evidence, or strict `surfaceImpossible` evidence. Backend fallback additionally requires failed shortcut evidence and a non-convenience backend reason.
- Wires the stricter fallback evidence through `visible-operation-policy-check`, `visible-ui-verify`, `visible-text-input`, `visible-action-batch`, `StepContractValidator`, and the visible runtime primitives so a path violation invalidates final PASS evidence.
- Adds real visible UI selftests `visible_app_launch_desktop_first_selftest.ps1` and `visible_fallback_discipline_selftest.ps1`.
- Keeps developer permission posture unchanged: `DEVELOPER_CAPABILITY_DISCOVERY` remains the default developer mode, developer capabilities remain enabled, and `allow_absolute_screen_click=true` remains enabled. Public profile alignment is completed later in v1.1.0.
- This change is limited to `D:\desktopvisual`; it does not modify release/public-dist paths, generate release packages, or upload/publicize artifacts.

## DesktopVisual 1.0.0 Developer Closure Baseline

- Freezes the developer tree as DesktopVisual 1.0.0. The internal v6.12.1 development line maps to this 1.0.0 developer baseline.
- Accepted 1.0.0 scope: visible-first Windows desktop automation runtime, real mouse and keyboard execution, global DPI-aware screenshots, target window lock, coordinate mapper, foreground preempt/cache, operation timeline profiling, visible UI latency optimization, structured text input, and Python simple PyCharm current-main acceptance.
- The accepted visible path keeps clipboard and backend file writes out of PASS evidence.
- Explicitly does not promise arbitrary complex IDE automated development, Visual Studio C++ multi-file project creation, Android Studio / Java / Kotlin complex project development, arbitrary web or complex app automation, or a generalized natural-language-to-mouse/keyboard planner.
- Future work moves to v1.1+ Visual Studio C++ multi-file workflow, v1.x complex IDE visible workflow expansion, and v2.x natural-language-to-workflow planner hardening.
- This closure is limited to `D:\desktopvisual`; it does not modify release/public-dist paths, sync release trees, package a public release, or upload GitHub.

## v6.12.1 - Visible UI Operation Latency Optimization

- Adds cached visible-first performance paths for foreground preempt, target window lock, and global DPI-aware frame reuse while preserving target lock, coordinate mapping, and final global screenshot evidence.
- Adds `fast-real-keyboard` structured text input options with zero char/line delay and batched real keyboard events; clipboard and backend file writes remain disallowed.
- Extends deterministic action batch performance evidence and adds orchestration latency summaries for operation gaps, fixed sleeps, and cached validation paths.
- Adds 165Hz motion pacer selftest support and wires fast/165Hz pacing into visible launch primitives (`visible-show-desktop`, `desktop-icon-double-click`, and taskbar clicks).
- Validates real PyCharm current `main.py` visible UI performance under `artifacts/dev6.12.1_performance_optimization/` with visible desktop icon launch, real keyboard input, Shift+F10 run, global final screenshot, and output verification.
- This change is limited to `D:\desktopvisual`; it does not modify release/public-dist paths, generate public packages, upload GitHub, prepare WeChat tests, or expand App coverage.

## v6.12.1 - Continuous Operation Timeline Profiling

- Adds `OperationTimelineProfiler` schema support and `operation-timeline-profiler-selftest` for profiling record field coverage and overhead classification.
- Adds `v6_12_1_continuous_operation_timeline_runner.ps1` to wrap each `winagent.exe` call with wall-clock timing, stdout/stderr capture, Runtime `duration_ms` extraction, overhead calculation, wait/fixed-sleep classification, and bottleneck summaries.
- Generates profiling-only evidence under `artifacts/dev6.12.1_performance_timeline/`, including JSONL/CSV timelines, runtime-vs-wallclock analysis, overhead suspects, fixed sleep report, bottleneck summary, and final status.
- This change does not optimize Runtime parameters, alter visible-first policy, package public release artifacts, upload GitHub, or modify release/public-dist paths.

## v6.12.1 - Visible UI Execution Foundation Hardening

- Adds bottom-layer visible UI foundation modules: `GlobalDpiAwareFrame`, `TargetWindowLock`, `ScreenshotCoordinateMapper`, `ForegroundPreempt`, `VisibleTextInputPolicy`, `VLMRuntimeBridge`, `DeterministicActionBatch`, `VisibleUIVerificationPolicy`, and `PyCharmVisibleWorkflow`.
- Adds bottom-layer `VisibleOperationPolicy` enforcement for universal visible-first priority: visible mouse/keyboard first, keyboard shortcut fallback second, backend fallback third, then fail/stop. The policy is wired into visible text input, final UI verification, deterministic action batches, StepContract validation, backend launch, backend browser navigation, backend focus/window switching, and PyCharm visible workflow evidence.
- Adds Runtime visible-first command surfaces `visible-operation-policy-check`, `taskbar-icon-locate`, `taskbar-icon-click`, `desktop-icon-locate`, `desktop-icon-double-click`, `start-menu-visible-launch`, `visible-show-desktop`, `visible-window-switch`, and `visible-page-navigation`.
- Enforces default visible habits for show desktop and window switching: show desktop clicks the bottom-right Show Desktop hot area before Win+D/backend fallback, and window switching uses Alt+Tab before taskbar/window click or backend focus fallback.
- Adds CLI commands `global-screenshot`, `target-lock-acquire`, `target-lock-release`, `coordinate-map`, `foreground-preempt`, `visible-text-input`, `visible-action-batch`, `visible-ui-verify`, `vlm-runtime-candidate`, and `pycharm-visible-demo`.
- Changes `screenshot --out <file>` with no target selector to default to global DPI-aware desktop capture; target-selected screenshots remain `window_only` diagnostics and cannot be final PASS evidence.
- Enforces target lock and coordinate mapping evidence for app-internal desktop click paths, and target lock support for desktop keyboard/type paths.
- Generalizes visible text input policy to real keyboard events by default and rejects unapproved clipboard operations plus backend file write evidence.
- Adds `line_by_line_keyboard` and `code_editor_keyboard` visible text input modes. CRLF, LF, CR, and Tab are lowered to Enter/Tab key events before first input, with first-pass multiline, collapsed-to-single-line, and `selfself` artifact evidence.
- Adds 165Hz HumanMode motion pacing for `fast-visible-ui` and explicit `--motion-profile 165hz` / `--motion-frame-rate 165` arguments, with QPC frame timestamps, average/p95 frame interval, actual frame-rate evidence, target miss, and cursor overshoot fields.
- Separates current-model visual inspection from Runtime-validated VLM assistance; only the complete Runtime candidate validation chain may report `vlm_assisted=true`.
- Adds deterministic action batch and visible UI final verification policy checks.
- Adds targeted selftests for each foundation module. PyCharm workflow support is implemented as a policy/dry-run harness in this scope; real PyCharm execution remains blocked unless it can run entirely through visible UI without backend project writes.
- This developer-tree change is limited to `D:\desktopvisual`. It does not inspect release/public-dist dirty state, generate public packages, upload GitHub, or modify public release artifacts.

## Post-v6 Developer Runtime UX Optimization

- Adds foreground preparation for visible UI tasks, including agent host detection, CLI/Codex/terminal minimize-or-move-away fallback, target activation, and foreground verification.
- Adds window foreground commands: `focus-window`, `activate-window`, `bring-window-front`, `minimize-window`, `restore-window`, and `prepare-foreground`.
- Adds command compatibility aliases and help guidance for `mouse_position`, `read_window_text`, screen-coordinate `right-click`/`double-click`, active-window screenshot/observe defaults, `uia-tree --process`, invalid-argument suggestions, and unknown-command closest matches.
- Adds `pycharm-dev-demo` for the dedicated safe project `D:\testrepo\pycharm_sanity` with explicit backend fallback reporting when the visible PyCharm surface is unusable.
- Adds latency profiles `conservative`, `normal`, and `fast-visible-ui`; fast mode lowers visible UI dwell/settle/mouse movement defaults without converting actions to backend operations.
- Adds targeted selftests for foreground preparation, activation commands, aliases, latency profile, PyCharm fast path, and local skill frontmatter.
- Developer FULL_ACCESS default is unchanged. Public-release hardening, keyword denylist policy, public release packaging, and GitHub upload are not part of this change.

## Post-v6 Developer Build Preparation - F12 Current Task Force Exit

- Adds reusable `UserAbortController` support for F12 current-task cancellation.
- Adds structured stop code `STOP_USER_FORCE_EXIT_F12` with evidence fields `user_force_exit=true`, `force_exit_key=F12`, `force_exit_scope=current_task_only`, and `process_exit=false`.
- Wires the abort check into runtime dispatch, session step execution, input movement, typing, clicking, scrolling, case runner waits, and recorder loops so F12 stops the active task without terminating the winagent process.
- Adds `f12_force_exit_selftest.ps1` and `f12_force_exit_runtime_integration_selftest.ps1`.
- This developer-tree change is limited to F12 runtime control. It does not implement public-release permission hardening, keyword denylist behavior, or release-specific exam integrity policy.

## v6.12.0 - Developer RC Gate and Handoff (ACCEPTED)

- Adds Developer RC metadata modules: `DeveloperRCGate`, `VersionIntegrityChecker`, `EvidenceChainVerifier`, `CapabilityMatrixBuilder`, `WorkflowBoundaryAuditor`, `DeveloperFullAccessPolicyVerifier`, `ReleaseHardeningDeferredLedger`, and `HandoffPackageBuilder`.
- Adds CLI commands `developer-rc-gate`, `version-integrity-check`, `evidence-chain-verify`, `capability-matrix-build`, `workflow-boundary-audit`, `developer-full-access-policy-check`, `release-hardening-deferred-ledger`, `handoff-package-build`, and `v6-12-rc-handoff-check`.
- Verifies v6.2-v6.11 evidence chain, v6.11 tag, version/runtime/docs consistency, workflow boundary preservation, developer full-access policy, release-hardening deferral, and handoff package safety.
- Generates developer capability matrix, deferred public-release hardening ledger, and developer handoff package under `artifacts/dev6.12.0_rc_gate_and_handoff/`.
- Does not add Explorer/Browser/Communication/VLM/Template/Memory behavior, does not change RuntimeSession or StepContract semantics, does not rerun old UI workflows, does not implement public-release hardening, does not add task keyword denylist, and does not generate a public release package.

## v6.11.0 - Workflow Template Learning and Batch Acceleration (ACCEPTED)

- Adds evidence-derived `WorkflowTemplateRecord`, local `WorkflowTemplateRegistry`, candidate extraction, template validation/safety, and validated-template instantiation.
- Adds `BatchWorkflowPlan`, planner, validator, and coordinator for compile-only, validate-only, and serial mock-safe batch orchestration.
- Adds CLI commands `workflow-template-extract`, `workflow-template-validate`, `workflow-template-register`, `workflow-template-instantiate`, `workflow-template-report`, `batch-workflow-plan`, `batch-workflow-validate`, `batch-workflow-run`, `batch-workflow-report`, and `v6-11-template-batch-check`.
- Template Learning is candidate extraction and validation from accepted evidence or read-only memory only. It is not model training, an optimizer, an execution planner, an auto-repair system, or a Runtime trigger.
- Validated templates instantiate StepContract JSON only through `StepContractValidator`; candidate, rejected, and deprecated templates are not executable.
- Batch acceleration compiles, validates, and serially coordinates mock-safe batches only. It does not run parallel real UI, share concurrent RuntimeSession state, skip verifier/evidence, rerun old UI workflows, or change RuntimeSession/StepContract/Executor/Verifier semantics.
- Runner output remains `RAW_COMPLETED_UNVERIFIED`; verifier and acceptance gate own PASS authority. Allows v6.12.0 RC gate and handoff planning to start without implementing v6.12 RC in this release.
- Final closure evidence is recorded under `artifacts/dev6.11.0_final_closure/` before merge/tag and v6.12 branch creation.

## v6.10.0 - Experience Memory and Failure Attribution Integration (ACCEPTED)

- Adds append-only local structured Experience Memory records, store, index, query, report, and safety boundary modules.
- Adds unified failure attribution normalization across Explorer, Browser/Form, Communication, VLM, and compiled plan execution statuses.
- Adds CLI commands `experience-memory-record`, `experience-memory-query`, `experience-memory-report`, `failure-attribution-normalize`, `memory-safety-check`, and `v6-10-experience-memory-check`.
- Memory remains read-only for planning and execution: it does not mutate StepContract, AgentPlanDraft, RuntimeSession, locator selection, retry behavior, workflow optimization, or Runtime execution paths.
- Communication memory redacts recipient/subject content to hashes and never stores full message bodies.
- Runner output remains `RAW_COMPLETED_UNVERIFIED`; verifier and acceptance gate own PASS authority.
- Allows v6.11.0 to start as Workflow Template Learning and Batch Acceleration. Does not implement v6.11 templates or v6.12 RC gates.

## v6.9.0 System Stabilization and Evidence Boundary Hardening

- Adds reusable `RuntimeEvidenceConsolidator`, `SessionLifecycleManager`, and `WorkflowSystemBoundary` modules.
- Adds CLI commands `evidence-consolidate`, `session-lifecycle-audit`, `workflow-boundary-check`, and `system-stabilization-check`.
- Classifies artifacts and runtime sessions without deleting evidence; final reports, evidence indexes, acceptance gates, runtime sessions, and unknown artifacts are not marked safe to delete.
- Checks Explorer, Browser/Form, Communication, VLM Observation, VLM Candidate, and compiled plan execution boundaries without rerunning old UI workflows.
- Keeps `current_trusted_version` at v6.9.0 and allows v6.10.0 Experience Memory work to start after the stabilization gate.

## v6.9.0 - Mail / Message / Draft Communication Workflows (ACCEPTED)

- Adds bottom-layer Communication workflow schema, adapter, executor, verifier, selftests, runner, verifier, acceptance gate, and full regression evidence under `artifacts/dev6.9.0_communication_workflow/`.
- Communication workflows compile through StepContract and StepContractValidator, execute through CompiledPlanExecutor and RuntimeSession, create local draft/message artifacts, emit execution evidence packs, and never send real messages.
- Rejects fake send, external mail/messaging APIs, missing validator, runner-only execution, and missing evidence.
- Allows v6.9.0 system stabilization before v6.10.0. Does not implement Experience Memory.

## v6.8.0 - Browser and Web Form Agent Workflows (ACCEPTED)

- Adds bottom-layer `BrowserWorkflow`, `BrowserWorkflowAdapter`, `BrowserWorkflowExecutor`, `BrowserWorkflowVerifier`, and `WebFormFieldLocator`.
- Adds CLI commands `compile-browser-workflow`, `run-browser-workflow`, and `verify-browser-workflow`.
- Browser/Form workflows compile to StepContract, validate through StepContractValidator, call CompiledPlanExecutor, use RuntimeSession and RuntimeContextGuard, use BrowserSurfaceNormalizer, execute visible browser UI paths, and emit evidence packs.
- Covers local file page, localhost page, basic form fill/submit, long-scroll form fill/submit, wrong-page recovery with final submit, ordinary external read-only diagnostic, missing field rejection, ambiguous submit rejection, active-protection STOP, and credential-required STOP.
- Rejects DOM/JS/WebDriver/CDP/Playwright/Selenium backend automation, direct coordinate actions, runner-only workflow logic, fake form execution, RAW_COMPLETED_UNVERIFIED-as-PASS, unverified submit, and unsafe regression skip.
- Allows v6.9.0 to start as Mail / Message / Draft Workflows. Does not open v6.8.1.

## v6.8.0-preflight - Validation Consistency Hardening

- Adds reusable evidence fingerprinting through `validation-fingerprint`.
- Adds `validation-consistency-check` for accepted-evidence hash/status/evidence-index consistency checks without replaying old UI workflows.
- Adds `regression-skip-evaluate` so accepted old features can skip UI replay only when fingerprints, consistency checks, trusted version, and source-change policy are safe.
- Adds v6.8 preflight selftests, runner, verifier, acceptance gate, evidence hash lock, and reports under `artifacts/dev6.8.0_preflight_validation_consistency_hardening/`.
- Keeps `current_trusted_version` and `VERSION` at 6.7.0. This is not v6.7.1 and not v6.8.0 Browser/Form completion.
- Does not execute Explorer move/scroll UI workflows, does not change Runtime behavior, and does not implement Browser/Form workflows.

## v6.7.0 - Explorer Agent Workflows (ACCEPTED)

- Accepted v6.7.0 through the `v6.7.0-rerun` blocker repair.
- Repairs `case_04_move_file` with staged Explorer UI move evidence: mouse selection, selection verification, cut attempt/send/effect, destination open/focus, paste attempt/send/observe, retry verification, source absence, destination existence, and explicit no PowerShell/direct file API workflow flags.
- Repairs `case_06_scroll_and_locate` with staged list-area focus, Home reset, per-iteration visible item evidence, observable scroll progress, target visibility/location evidence, stale-rect rejection, and RuntimeContextGuard checks on each iteration.
- Requires v6.7 runner, verifier, acceptance gate, and full regression to run from the beginning before acceptance.
- Full regression completed from the beginning and PASS in `artifacts/dev6.7.0_explorer_agent_workflows_rerun/full_regression_rerun_result.json`.
- `rc_check.ps1` was run and recorded as real FAIL for `script_lint`, `benchmark_selftest`, and `public_repo_check`; it is not promoted as PASS evidence.
- Allows v6.8.0 to start as Browser and Web Form Agent Workflows. Does not enter v6.7.1.

## v6.7.0 - Explorer Agent Workflows (BLOCKED)

- Adds Explorer workflow schema, compiler adapter, executor, verifier, context-menu handler, safe recovery, targeted selftests, runner, verifier, acceptance gate, and full regression runner.
- Adds CLI commands `compile-explorer-workflow`, `run-explorer-workflow`, and `verify-explorer-workflow`.
- Blocks acceptance on `case_04_move_file` (`VERIFY_MOVE_FAILED`) and `case_06_scroll_and_locate` (`FAIL_TARGET_NOT_FOUND`).
- Trusted version remains v6.6.0. Next planned work is `6.7.0-rerun`.

## v6.6.0 - VLM-Assisted Unknown UI Candidate Handling

- Adds bottom-layer `VLMCandidateBridge` for Runtime locate-failed events. The bridge builds `VLMObservationRequest`, calls the mock/disabled provider layer, validates with `VLMObservationValidator`, and forwards observation-only `possible_targets` to Runtime validation without executing actions.
- Adds `RuntimeCandidateValidator` to validate VLM semantic candidates against current observe state, screenshot/window bounds, UIA/OCR/visible text/context evidence, viewport, freshness, uniqueness, and active-protection/credential risk policy.
- Adds `LocatorCandidate` conversion for Runtime-validated VLM candidates with `candidate_source=vlm_assisted_runtime_validated`, `coordinate_source_type=vlm_assisted_runtime_validated`, final guard, mouse-first evidence, and post-action verification requirements.
- Adds CLI commands `vlm-assisted-locate`, `vlm-assisted-locate-dry-run`, and `vlm-assisted-locate-and-click-local-safe`.
- Adds mock unknown UI, ambiguous, offscreen, active-protection, credential, stale, low-confidence, direct-action, direct-coordinate, and ROI candidate evidence paths through runner/verifier/gate separation.
- Preserves Runtime-only execution. VLM cannot click, type, scroll, emit executable Runtime commands, or convert approximate regions directly into click points.
- Allows v6.7.0 to start as Explorer Agent Workflows.

## v6.5.0 - VLM-Assisted Observation Contract

- Adds bottom-layer `VLMObservationRequest` and `VLMObservationResult` schemas for packaging Runtime observe/screenshot/OCR/UIA/window context/task hint evidence into assistive-only VLM observation requests.
- Adds `IVLMProvider`, disabled external provider placeholder, and `MockVLMProvider` scenarios for valid, malicious, malformed, provider-role mismatch, prompt-injection-like, bypass, credential, runtime-command, and coordinate-action outputs.
- Adds `VLMObservationValidator` with schema checks, request-id matching, provider_role enforcement, observation-only candidate requirements, Runtime validation requirements, direct action rejection, coordinate action rejection, Runtime command rejection, bypass/credential/anti-cheat rejection, prompt-injection classification, and blocked-context handling.
- Adds `VLMObservationBoundary` and `vlm-observation-dry-run` so VLM output can be displayed and validated without executing Runtime actions. `safe_for_direct_execution` is always false in v6.5.
- Adds CLI commands `vlm-observation-build-request`, `vlm-observation-run-mock`, `vlm-observation-validate`, `vlm-observation-dry-run`, and `vlm-observation-selftest`.
- Adds v6.5 targeted selftests, raw runner, independent verifier, acceptance gate, positive observation cases, negative/malformed/boundary cases, and dry-run evidence.
- Preserves Runtime-only executor behavior from v6.4. VLM results do not enter `StepContract`, `CompiledPlanExecutor`, `RuntimeSession`, click, type, or scroll paths.
- Does not add real API key UI, provider login UI, mandatory real VLM calls, VLM-assisted click/type/scroll, VLM candidate handling, Experience Memory, Workflow Templates, or expanded real App/Web tests.
- Allows v6.6.0 to start as VLM-Assisted Unknown UI Candidate Handling.

## v6.4.0 - Runtime Task Execution from Compiled Agent Plan

- Adds bottom-layer `CompiledPlanExecutor` support for executing validated v6.3 `StepContract` JSON in dry-run or local-safe execution modes.
- Adds `StepContractRuntimeAdapter` to convert compiled contracts into RuntimeSession-compatible structured dispatch plans without bypassing the v6.2 session boundary.
- Adds a TaskSession execution bridge and CLI commands `run-agent-task`, `execute-step-contract`, and `execute-compiled-plan`.
- Adds `StepExecutionVerifier` for step-level verification and `ExecutionEvidencePack` for execution result JSON, step result JSONL, evidence index, and execution report output.
- Enforces risk and confirmation gates for REAL_COMMIT, DESTRUCTIVE, ACTIVE_PROTECTION_BLOCKED, and CREDENTIAL_REQUIRED_BLOCKED contracts before Runtime execution.
- Adds v6.4 targeted selftests, runner, verifier, risk confirmation cases, full regression runner, and acceptance gate. Runner output remains `RAW_COMPLETED_UNVERIFIED`; verifier/gate evidence owns PASS authority.
- Positive execution coverage includes Explorer path open, browser page open, browser form fill, local mock mail draft fill, safe recovery during execution, and dry-run no Runtime execution.
- Negative coverage includes invalid contracts, missing expected context, missing verification, blocked protection/credential risks, unconfirmed high-risk actions, unsafe direct coordinates, wrong context stop, verification failure stop, stale target rejection, and runner-only execution detection.
- Does not develop VLM, Experience Memory, Workflow Templates, public-release permission narrowing, v6.2 latency optimization, or natural-language direct Runtime execution.
- Allows v6.5.0 to start as VLM-Assisted Observation Contract.

## v6.3.0 - PlanDraft to StepContract Compiler

- Adds bottom-layer `PlanCompiler` support for compiling reviewed `AgentPlanDraft` JSON into v6.3 `StepContract` JSON.
- Adds v6.3 `StepContract` schema fields for expected context, action preconditions, verification hints, risk, confirmation, recovery, stop, session, and evidence policies.
- Adds independent `StepContractValidator` support with `validation_ok`, validation errors/warnings, executable status, v6.2 session compatibility, developer full-access safety, and public-release safety fields.
- Adds compile diagnostics with structured error codes for missing expected context, missing verification hints, unsupported actions, unsafe direct coordinates, risk/confirmation policy gaps, invalid recovery, missing stop policy, ambiguous targets, invalid session policy, and malformed schema.
- Adds dry-run conversion to v6.2 session-compatible structured step JSON with `runtime_executed=false`; no Runtime session dispatch or real desktop action is executed by v6.3.
- Adds CLI commands `plan-compile`, `step-contract-validate --input`, `step-contract-dry-run`, and `plan-compile-selftest` while preserving legacy `step-contract-validate --file` behavior.
- Extends `AgentPlanDraft` output with v6.3 fields while preserving v6.1 planner compatibility fields.
- Adds v6.3 selftests, runner, verifier, and acceptance gate. Runner output remains `RAW_COMPLETED_UNVERIFIED`; verifier/gate evidence owns PASS authority.
- Positive compile coverage includes Explorer path open, browser page open with surface normalization, browser form fill, code editor run, message/mail draft, and developer real-commit policy.
- Negative coverage includes missing expected context, missing verification hint, unsupported action, unsafe direct coordinate, missing high-risk confirmation, invalid recovery bypass, missing stop policy, ambiguous target, invalid JSON, non-continuous step indexes, duplicate step ids, active-protection executable action, and credential-required executable action.
- Does not execute compiled plans, call Runtime actions from dry-run, add real UI automation cases, develop VLM, Experience Memory, Workflow Templates, public-release permission narrowing, or v6.2 latency optimization.
- Allows v6.4.0 to start as Runtime Task Execution from Compiled Agent Plan.

## v6.2.0 - Persistent Runtime Session and Latency Gate

- Adds bottom-layer Persistent Runtime Session support with `RuntimeSession`, `SessionManager`, session lifecycle commands, structured JSON envelopes, timeout/closed-session rejection, and persisted session state under `artifacts/runtime_sessions`.
- Adds session-scoped window binding for hwnd/process/title/bounds reuse while preserving RuntimeContextGuard and SafetyPolicy checks before actions.
- Adds session observe cache and locator cache with action/window/foreground/scroll invalidation, stale-target rejection, and force-reobserve/force-relocate paths.
- Adds `SessionCommandDispatcher` for single-step and structured multi-step session dispatch. Dispatch accepts structured JSON only and stops subsequent steps after the first failure.
- Adds Runtime-level act-and-verify primitives, including click/type/scroll combinations and session-scoped `uia_contains:` verification for local browser/mock UI value and result checks.
- Adds `LatencyTracker` and latency benchmark evidence comparing one-shot baseline to persistent session on the same controlled 10-step workflow.
- Preserves one-shot CLI behavior when `--session-id` is absent; compatible legacy commands can route through the session path only when `--session-id` is present.
- Adds v6.2.0 selftests, runner, verifier, and acceptance gate scripts. Runner output remains `RAW_COMPLETED_UNVERIFIED`; verifier/gate evidence owns PASS authority.
- Required v6.2.0 verifier cases cover session lifecycle, one-shot compatibility, 10-step workflow, local Edge mail mock browser form workflow, scroll-and-locate workflow, wrong-context stop, cache invalidation, and latency comparison.
- Accepted latency comparison: one-shot average 65 ms / p95 139 ms / 14 process restarts; persistent average 45 ms / p95 78 ms / 1 process restart; average step improvement 30.77%.
- Does not implement PlanCompiler, AgentPlanDraft to StepContract Compiler, natural-language task execution, VLM, Experience Memory, Workflow Template Learning, public-release permission narrowing, or new real App/Web capability expansion.
- Allows v6.3.0 to start as PlanDraft to StepContract Compiler work.

## v6.1.6 - Scope Reset and Case2 PyCharm Closure

- Accepts v6.1.6 and closes the v6.1 series.
- Keeps Case1 QQ Mail fresh machine evidence PASS/frozen.
- Keeps bottom-layer StepCompletionGate PASS from content1 and uses it for Case2 step trace closure.
- Completes Case2 PyCharm with visible UI evidence: PyCharm was opened/activated through visible UI, code was input through Runtime keyboard path, and run was triggered with SHIFT+F10.
- Records Case2 output closure with PowerShell full-screen CopyFromScreen visible PyCharm evidence plus paired console transcript for the same run id `DV616_CASE2_LLM_20260614_011000`.
- Confirms Case2 `run_triggered=true`, `execution_started=true`, `execution_completed=true`, `execution_success=true`, `exit_code=0`, seven `DV616_SEQ` lines, `DV616_RUN_END`, and `old_output_reuse_detected=false`.
- Establishes PowerShell CopyFromScreen as the default visible UI screenshot method; PrintWindow and OCR screenshots remain auxiliary.
- Defers Case3/Case4, WeChat, TikTok, and the old integrated sequence; they are not v6.1.6 gate blockers.
- Defers deep self-drawn App UI testing to the VLM/visual candidate stage.
- Allows v6.2.0 to start Persistent Runtime Session and Latency Gate work.

## v6.1.6 Scope Reset Content1 - StepCompletionGate PASS_READY_FOR_CASE2

- Keeps `current_trusted_version` at v6.1.5a; full v6.1.6 is not accepted until Case2 PyCharm passes.
- Preserves Case1 QQ Mail fresh machine evidence PASS/frozen using the current machine validation report and registry state.
- Adds bottom-layer `StepCompletionGate` support with `winagent.exe step-completion-evaluate --input-json <path> --result-json <path>`.
- Enforces `next_step_allowed=false` when preconditions fail, an action is not executed, required post-observe is missing, or postconditions fail.
- Adds `step_completion_gate_selftest.ps1` covering generic failures, a successful step, and PyCharm editor/code/run gate semantics without running Case2.
- Adds v6.1.6 scope-reset runner, verifier, and acceptance gate scripts for content1 only.
- Supersedes the old v6.1.6 four-case and integrated sequence scripts for the current PASS path; WeChat/TikTok and old integrated sequence are not run.
- Does not enter v6.2 and does not develop Persistent Runtime, PlanCompiler, VLM, or Experience Memory.
- Next allowed work is v6.1.6 content2 Case2 PyCharm only.

## v6.1.6 Scope Reset Attempt - BLOCKED

- Stops the v6.1.6 scope-reset closure at the mandatory Case1 evidence trust gate.
- Keeps `current_trusted_version` at v6.1.5a because the current fresh Case1 QQ Mail PASS marker lacks required send-target and post-send verification fields.
- Records `BLOCKED_CASE1_EVIDENCE_NOT_TRUSTWORTHY` under `artifacts/dev6.1.6_scope_reset_step_completion_closure/`.
- Does not continue Case2 PyCharm, does not run WeChat or TikTok, and does not run the old four-case integrated sequence.
- Does not implement StepCompletionGate, Persistent Runtime, PlanCompiler, VLM, or Experience Memory in this blocked attempt.
- Sets the next work item to v6.1.6-rerun: repair or regenerate trustworthy fresh Case1 evidence before Case2 and bottom-layer StepCompletionGate closure.

## v6.1.5a - Visible Mouse-First Interaction Supplement

- Adds v6.1.5a mouse-first runner, verifier, and acceptance gate scripts. Runner output remains `RAW_COMPLETED_UNVERIFIED`; only verifier/gate evidence can promote the version.
- Adds controlled local form and code editor mock pages under `D:\testrepo\testwindow` for visible mouse click, focus verification, typing, submit/run, and mid-editor insertion evidence.
- Proves visible locate -> mouse move -> click -> focus/context verification for Chrome desktop open, Chrome address bar URL entry, Google search box/button, search result/link click-through, local form fill, local code editor Run, and mid-editor reposition.
- Adds mouse evidence fields for interaction mode, mouse move/click counts, target rect/center, locator source, coordinate source type, focus/context verification, fallback use, wrong-field input, and wrong-context continuation.
- Records keyboard use only as allowed text entry or explicit auxiliary selection after mouse focus. Keyboard-only navigation, Ctrl+L, Tab focus chains, Win+R launch, and Enter-only search are not counted as mouse-first PASS.
- Required matrix passed for build, selftest, runtime guard, browser normalization, v6.1.2 gate, v6.1.3 gate, v6.1.4 gate, v6.1.5 gate, and v6.1.5a mouse-first runner/verifier/gate. Optional `rc_check.ps1` timed out and is not promoted as PASS evidence.
- Promotes `current_trusted_version` to v6.1.5a. v6.1.6 remains the next Dynamic App/Web Developer FULL_ACCESS Automation RC; v6.2 remains disallowed.
- v6.1.6 PASS means the 6.1 series should stop further optimization and proceed to later versions.

## v6.1.5 - Safe Context Recovery and Developer Dynamic Diagnostics

- Adds Runtime-level `safe-context-recovery` with bounded recovery policy/result evidence, active-protection STOP, credential-required STOP, allowed recovery target validation, reobserve, and marker verification.
- Adds `task-checkpoint-evaluate` for checkpoint/resume decisions and replay-required evidence after recovery.
- Adds `failure-attribution-classify` with unified failure attribution for runtime and diagnostic cases.
- Adds v6.1.5 safe recovery runner/verifier/gate scripts with raw-only runner output and independent verifier/gate PASS authority.
- Covers local file mock, localhost mock, Explorer test directory, browser wrong-page recovery, active-protection hard STOP, credential-required hard STOP, and keyword non-block regression.
- Adds dynamic diagnostics runner/verifier/report for PyCharm, QQ Mail, ordinary web, LeetCode/OJ, and social search. Dynamic diagnostics are real attempts with failure attribution, not v6.1 final automation.
- Keeps Developer FULL_ACCESS / DEVELOPER_CAPABILITY_DISCOVERY behavior: ordinary words such as test, exam, contest, interview, challenge, OJ, submit, code, and race are not STOP conditions by themselves.
- Required test matrix passed for build, selftest, runtime guard, browser normalization, v6.1.2 gate, v6.1.3 gate, v6.1.4 gate, v6.1.5 safe recovery, and v6.1.5 dynamic diagnostics.
- Promotes `current_trusted_version` to v6.1.5 only after verifier/gate evidence passed.
- Leaves full Dynamic App/Web Developer FULL_ACCESS Automation RC to v6.1.6. v6.1.5 does not enter v6.2, Persistent Runtime, PlanCompiler, VLM, or Experience Memory.

## v6.1.4-rerun-runtime-guard-and-browser-normalization

- Adds Runtime-level context guard and conservative browser surface normalization.
- Adds optional guard parameters to low-level desktop/window/adaptive/scroll commands while preserving legacy behavior when no guard is requested.
- Adds `browser-surface-normalize` and `browser-open-url-human` for HumanMode browser navigation without JS/DOM/WebDriver/CDP/Playwright/Selenium.
- Adds runtime guard and browser normalization selftests plus v6.1.4 runtime rerun/verifier/acceptance gate scripts.
- Stabilizes `browser-open-url-human` URL input with bounded retries, address-bar clipboard fallback, input failure STOP semantics, and wrong-page STOP semantics.
- Narrows BrowserSurfaceNormalizer active-protection detection to the current browser document/page scope so inactive tab titles cannot poison the active page context.
- Restores v6.1.2 baseline acceptance, v6.1.3 scroll acceptance, and v6.1.4 runtime guard acceptance.
- Promotes `current_trusted_version` to v6.1.4 only after the current acceptance gates passed.
- Leaves PyCharm, WeChat, QQ Mail, and real Internet App/Web diagnostics deferred to v6.1.5; no real message, email, or external form was sent.

## v6.1.4 - Dynamic App/Web Click Accuracy and Offset Diagnostics

- State Guard remediation remains BLOCKED but improved: wrong-context negative guard now stops before click/type/send on Chrome New Tab with `STOP_WRONG_CONTEXT`.
- Adds Action Precondition / Expected Context checks around dynamic runner actions and records `context_trace.jsonl` evidence for wrong page, wrong foreground, stale target, and target validity stops.
- Updates v6.1.2 baseline runner to use real UI Run dialog URL navigation for `file:///D:/testrepo/testwindow/desktopvisual_mail_mock.html`, to enforce local mock page context before field actions, and to avoid unbounded `winagent.exe` waits.
- Reclassifies v6.1.3 scroll gate failure as `BASELINE_REPLAY_WRONG_CONTEXT`; the wheel/scroll primitive cases themselves verify, but the nested baseline replay is still blocking.
- Does not execute WeChat or QQ Mail sends in the state-guard-only remediation run because baseline replay and scroll gate preconditions are not yet clean.
- Rerun status: BLOCKED. The previous v6.1.4 interrupted attempt is archived as a false-positive emergency-stop attempt and must not be used as PASS evidence.
- Fixes the runner-side emergency stop false positive where PowerShell's case-insensitive substring matching treated `emergency_stop_checked` as `EMERGENCY_STOP`; F12 now requires debounce or an explicit stop flag before `USER_INTERRUPTION` is recorded.
- Fixes future rerun command exit-code capture by replacing redirected `Start-Process` execution with `ProcessStartInfo` plus async stdout/stderr reads.
- Keeps `current_trusted_version` at v6.1.3 and blocks v6.2 entry until the dynamic UI cases and baseline replay pass.
- Treats v6.1.3 as the current trusted baseline entering this stage.
- Adds a v6.1.x dynamic App/Web click accuracy and offset diagnostics repair stage. This version does not enter v6.2.
- Does not develop Persistent Runtime Session, PlanDraft to StepContract Compiler, Runtime natural-language execution, VLM Provider, real VLM calls, Experience Memory, Workflow Template behavior, public release permission narrowing, or developer permission direction changes.
- Requires real dynamic UI tests for PyCharm, WeChat, and QQ Mail. QQ Mail must use `https://mail.qq.com`, not `v.qq.com`.
- WeChat strict communication is limited to `文件传输助手` with message `这是一条测试信息`. QQ Mail strict communication is limited to `1581782307@qq.com`, subject `测试邮件`, and body `这是一个测试邮件`.
- Adds `v6_1_4_dynamic_ui_runner.ps1`, `v6_1_4_dynamic_ui_verifier.ps1`, and `v6_1_4_dynamic_ui_acceptance_gate.ps1`. Runner output is raw only; verifier independently decides case PASS/FAIL; acceptance gate blocks PASS without real dynamic UI evidence.
- Records `first_attempt_success`, `misclick`, `wrong_target_click`, cursor offset, keyboard focus offset, stale target rect, `retry_count`, and `reobserve_count` through case traces and verified `task_result.json` fields.
- Requires one v6.1.2/v6.1.3 baseline regression replay before acceptance, including HumanMode pacing run1/run2.
- Adds runner heartbeat and timeout evidence: 60 second command-step timeout, 15 second heartbeat JSONL, 15 minute PyCharm/QQ Mail case limits, 10 minute WeChat case limit, 45 minute global limit, and no-progress blocking.
- Blocks synthetic evidence, placeholder screenshots, hardcoded hwnd/rect, invalidated evidence reuse, old artifacts reused as v6.1.4 PASS, JS/DOM/WebDriver/CDP/Playwright/Selenium actions, UIA InvokePattern/ValuePattern strict actions, backend sends, direct file writes, and diagnostic-only PASS.
- Does not add an extra send-confirmation popup in the real communication cases, because target/content/window/page verification is part of the runner/verifier contract and extra UI can make dynamic pages stale.

## v6.1.3 - Mouse Wheel Scroll Primitive Defaulting and Scroll-and-Locate

- Treats v6.1.2 as the current trusted baseline entering this stage.
- Adds a v6.1.x baseline repair for real mouse wheel input and scroll-and-locate. This version does not enter v6.2.
- Does not develop Persistent Runtime Session, PlanDraft to StepContract Compiler, Runtime natural-language execution, VLM Provider, real VLM calls, Experience Memory, Workflow Template behavior, public release permission narrowing, or developer permission direction changes.
- Makes real mouse wheel input through `SendInput` plus `MOUSEEVENTF_WHEEL` the strict default scroll strategy for the new `adaptive-scroll` and `scroll-and-locate` commands.
- Forbids scrollbar track click, right-rail click, scrollbar thumb drag, PageDown/ArrowDown, JS/DOM scroll, WebDriver/CDP/Playwright/Selenium scroll, and UIA ScrollPattern as strict mouse wheel PASS evidence.
- Allows scrollbar fallback only after `wheel_attempted_first=true`, real wheel input has no content change after reobserve, and `fallback_reason` is recorded; diagnostic fallback cannot become this version's core strict PASS.
- Adds content-change verification with before/after screenshots and content signatures. If wheel input does not change content, the Runtime returns `WHEEL_NO_CONTENT_CHANGE` instead of claiming scroll success.
- Adds `adaptive-scroll` for targeted real wheel evidence and `scroll-and-locate` for observe -> locate -> wheel -> reobserve -> content-change verification -> locate closure without auto-clicking the target.
- Adds `v6_1_3_wheel_scroll_runner.ps1`, `v6_1_3_wheel_scroll_verifier.ps1`, and `v6_1_3_scroll_acceptance_gate.ps1`. Runner output is raw only; verifier and gate decide PASS/FAIL.
- Requires real UI wheel cases A-F, including Mouse Wheel Primitive, Browser Long Page Scroll-and-Locate, Mock Friend List Scroll-and-Locate, Explorer List Scroll-and-Locate, Wheel No-Progress Detection, and fresh v6.1.2 baseline replay.
- Requires HumanMode pacing run1/run2, v6.1 Planner, v6.1.1 acceptance gate regression, v6.1.2 baseline acceptance gate regression, v6.0 boundary, permission selftest, adaptive loop regression, JSON/JSONL parse, Markdown fence validation, encoding scan, COMMAND_PROTOCOL consistency, and evidence pointer checks before acceptance.
- Acceptance gate blocks synthetic evidence, placeholder screenshots, hardcoded hwnd/rect, invalidated evidence reuse, old v6.1.2 artifacts reused as v6.1.3 PASS, scrollbar-first strict PASS, missing content-change evidence, and missing target invisible-to-visible evidence.

## v6.1.2 - Real UI Baseline Sanity and Pre-v6.2 Test Gate

- Treats v6.1.1 as the current trusted baseline before this stage runs.
- Adds a pre-v6.2 real UI baseline revalidation version; this version does not enter v6.2.
- Does not develop the v6.2 PlanDraft to StepContract Compiler, new Agent Planner functionality, Runtime natural-language execution, VLM Provider, real VLM calls, Experience Memory, or Workflow Template behavior.
- Requires real Explorer UI sanity for `D:\testrepo\testwindow\desktopvisual_mail_mock.html`.
- Requires real Browser Mail Mock UI sanity for `file://D:/testrepo/testwindow/desktopvisual_mail_mock.html`.
- Requires a Browser Mail Mock repeat run so one successful form-send run is not enough.
- Requires HumanMode pacing regression at least twice.
- Keeps Runner / Verifier / Gate separated: `v6_1_2_real_ui_baseline_runner.ps1` collects raw evidence only, `v6_1_2_real_ui_baseline_verifier.ps1` independently decides real UI PASS/FAIL/SKIP, and `v6_1_2_pre_v6_2_acceptance_gate.ps1` decides whether v6.1.2 may advance the trusted baseline.
- Runner must not self-certify PASS. Real UI PASS must come from raw command output, cursor/target rect evidence, screenshots/overlays, verifier output, and the final acceptance gate.
- Synthetic evidence, placeholder screenshots, hardcoded hwnd/rect, invalidated evidence, diagnostic-only output, backend opens, direct file opens, JS/DOM/WebDriver/CDP/Playwright/Selenium actions, and UIA InvokePattern/ValuePattern actions cannot count as PASS.
- If required real UI tests fail or cannot run, v6.1.2 is BLOCKED and the project cannot enter v6.2.

## v6.1.1 - HumanMode Regression Triage and Evidence Gate Repair

- Treats v6.1.0 as a BLOCKED attempt, not a trusted baseline.
- Keeps the current trusted baseline at v6.0.0 unless this version's required tests, regressions, evidence checks, and acceptance gate all pass.
- Repairs the v6.1 acceptance path through HumanMode regression triage, evidence integrity repair, acceptance gate repair, and v6.1 Planner acceptance review.
- Does not enter v6.2.
- Does not develop a PlanDraft-to-StepContract compiler, execute real Agent tasks, call a VLM, develop Experience Memory, or change the developer permission direction.
- Requires missing required evidence, missing pointers, missing raw output, or missing verifier output to block acceptance.
- Keeps runner and implementation output below PASS authority; only independent verifier or acceptance gate output may decide acceptance.
- Adds `v6_1_1_humanmode_regression_triage.ps1` and `v6_1_1_evidence_acceptance_gate.ps1`.

## v6.1.0 - Natural Language Task Intent and Plan Draft

- Adds `agent-intent-parse` for minimal natural-language task parsing into `TaskIntent`.
- Adds `agent-plan-draft` for generating non-executable `AgentPlanDraft` records from a parsed intent.
- Adds `agent-planner-validate` for validating `TaskIntent` and `AgentPlanDraft` JSON files, including malformed JSON, missing fields, Runtime/VLM mode boundaries, executor boundaries, provider-role boundaries, and direct executable draft rejection.
- `TaskIntent` covers `explorer_open_path`, `explorer_open_file`, `explorer_delete_file`, `browser_open_page`, `browser_fill_form`, `local_mock_mail_fill`, and `unknown`, with `low`, `medium`, `high`, and `blocked` risk levels.
- Active-protection bypass semantics classify as `blocked`; destructive delete intent requires confirmation and at least medium risk.
- `AgentPlanDraft` is not a `StepContract`, is not directly executable, keeps `is_executable=false`, `compile_required=true`, and `executor=runtime`.
- Runtime remains the only executor. VLM-assisted mode remains assistive only through `provider_role=assistive_only` and does not call a real VLM provider.
- Adds `v6_1_0_task_intent_planner_selftest.ps1` for TaskIntent, AgentPlanDraft, Runtime/VLM boundaries, executor boundaries, active-protection classification, malformed JSON, missing fields, no-fake-PASS, and invalidated-evidence-use coverage.
- Does not execute tasks, compile StepContract, add real VLM provider calls, Provider API key UI/account system, Experience Memory, Failure Attribution, batch acceleration, HumanMode changes, or active-protection STOP changes.
- Leaves Plan-to-StepContract compilation for v6.2.0.

## v6.0.0 - Agent Boundary and Runtime/VLM Mode Architecture

- Starts the v6 Agent Boundary track from the accepted v5.10.2 real TaskRuntime handoff baseline.
- Adds `agent-boundary-validate` for Runtime/VLM mode validation, Runtime-only executor validation, HumanMode action boundary checks, AgentTaskRequest validation, and AgentPlan validation.
- Valid modes are `runtime` and `vlm_assisted`; unknown, empty, or missing mode values fail.
- Runtime remains the only action executor. `executor=runtime` is valid; `vlm` and `agent_direct` are rejected as executors.
- VLM-assisted mode is planning/interpretation only. It does not call a real VLM provider and does not execute desktop actions.
- Adds minimal AgentTaskRequest / AgentPlan / AgentPlanStep validation with required `task_id`, `mode`, `user_goal`, `plan_id`, `steps`, `risk`, `executor`, and `compile_required` coverage where applicable.
- Rejects malformed JSON, missing required fields, empty plan steps, non-runtime executors, and JS/DOM/WebDriver/CDP/UIA Invoke/Value as HumanMode actions.
- Adds `v6_0_0_agent_boundary_selftest.ps1` for positive/negative mode, executor, request, plan, malformed JSON, fake-PASS, and invalidated-evidence-use coverage.
- Does not implement a full Planner, real VLM provider calls, Provider API key UI/account system, Experience Memory, batch task acceleration, HumanMode changes, or active-protection STOP changes.

## v5.10.2 - REBUILT: Real TaskRuntime Integration and Final Pre-v6 Gate

- Old v5.10.2 is INVALIDATED and must not be used as evidence. This rebuilt v5.10.2 reruns real TaskRuntime integration and the final Pre-v6 Gate from the trusted v5.10.1 rebuilt evidence baseline.
- This version remains v5. It does not enter v6, introduce VLM, develop an Agent Planner, or perform public release permission narrowing.
- Adds real `TaskSession -> StepContract -> TaskRunner -> Adaptive HumanMode Loop -> winagent HumanMode action -> runtime verification` execution for `tasks\localhost_form_fill_submit_humanmode.task.json`.
- Hardcoded hwnd, hardcoded rect, simulated TaskRuntime PASS, synthetic action/locator/adaptive traces, JS/DOM/WebDriver/CDP actions, backend POST, UIA InvokePattern/ValuePattern actions, and runner self-PASS are forbidden as evidence.
- Adds `v5_10_2_taskruntime_evidence_verifier.ps1` as the independent TaskRuntime PASS/FAIL verifier.
- Adds `v5_10_2_final_pre_v6_gate.ps1` as the independent final validation gate for v5.10.1 evidence, TaskRuntime evidence, CLI/service, active-protection STOP, v5 regression status, docs, and artifacts.

## v5.10.1 - REBUILT: Real UI Adaptive Cases Rerun

- Old v5.10.1 remains INVALIDATED and must not be used as evidence. This rebuilt v5.10.1 reruns real UI adaptive Case D/E/F evidence from the trusted v5.10.0 Adaptive HumanMode Control Loop Core baseline.
- This version remains v5. It does not enter v6, introduce VLM, develop an Agent Planner, perform public release permission narrowing, or change the developer permission direction.
- Adds `v5_10_1_real_ui_adaptive_cases_runner.ps1` as a raw-evidence runner. The runner may collect command lines, stdout JSON, stderr, exit code, result-json, foreground windows, cursor positions, screenshots, and preliminary observations, but it must not self-write PASS.
- Adds `v5_10_1_real_ui_evidence_verifier.ps1` as the independent PASS/FAIL/SKIP verifier. The verifier reads raw winagent evidence and generates verified `task_result.json`, traces, reports, and failure reasons.
- Adds `v5_10_1_synthetic_evidence_guard.ps1` to fail synthetic evidence, placeholder screenshots, hardcoded hwnd/rect, backend/direct-launch actions, JS/DOM/WebDriver/CDP, UIA InvokePattern/ValuePattern action evidence, and runner self-PASS.
- Synthetic evidence, placeholder screenshots, hardcoded hwnd, hardcoded rect, simulated TaskRuntime PASS, runner self-PASS, and invalidated v5.10.1/v5.10.2 PASS artifacts are forbidden as evidence.

## v5.10.2 - INVALIDATED

Reason:
TaskRuntime handoff evidence used hardcoded/simulated browser form flow and cannot be used as ready_for_v6 evidence.

The `ready_for_v6` true conclusion is revoked. Artifacts under `artifacts\dev5.10.2_final_pre_v6_gate\` must not be used as PASS evidence or v6 handoff evidence.

## v5.10.1 - INVALIDATED

Reason:
Synthetic adaptive case evidence was generated and cannot be used as real HumanMode PASS evidence.

The runner produced placeholder screenshots, synthetic locator/action traces, and synthetic PASS results for Explorer and browser form cases. Artifacts under `artifacts\dev5.10.1_adaptive_cases\` must not be used as Case D/E/F PASS evidence or v6 handoff evidence.

Current trusted baseline:
v5.10.0 - Adaptive HumanMode Control Loop Core

## v5.10.0 - Adaptive HumanMode Control Loop Core

- Implements the Adaptive HumanMode Control Loop core: `observe -> locate -> validate candidate -> move -> verify cursor -> click/type -> verify state -> re-observe/retry/stop`.
- Remains v5 and does not enter v6.
- Does not introduce VLM, develop an Agent Planner, perform public release permission narrowing, or change the developer capability discovery direction.
- Replaces preset-coordinate-script style HumanMode quality with current-observe target rectangles, cursor-inside-target-rect verification before click, post-action verification, and bounded retry.
- Adds reusable `AdaptiveTargetSpec`, `AdaptiveTargetCandidate`, `AdaptiveLocateResult`, `AdaptiveActionSpec`, `AdaptiveActionResult`, and `AdaptiveInteractionLoop` structures.
- Adds coordinate mapping helpers for screenshot-to-screen and window-relative-to-screen rectangles. Mapping failure returns `COORDINATE_MAPPING_FAILED`.
- Adds JSON CLI diagnostics: `adaptive-locate`, `adaptive-click`, `adaptive-double-click`, `adaptive-type`, and `adaptive-run-step`.
- Adds `v5_10_0_adaptive_humanmode_loop_test.ps1` and artifacts under `artifacts\dev5.10.0_adaptive_humanmode_loop\`.
- Keeps active-protection STOP behavior unchanged and keeps ordinary developer exploration allowed under `DEVELOPER_CAPABILITY_DISCOVERY`.

## v5.9.3 - Explorer Mouse Target Strictness Fix

- Remains v5 and only fixes Explorer mouse target landing strictness for Case D.
- Does not enter v6.
- Does not introduce VLM.
- Does not develop an Agent Planner.
- Does not perform public release permission narrowing.
- Does not change the developer permission model direction.
- Does not handle Case E, Case F, or TaskRuntime integration.
- Does not auto git commit.
- Upgrades Case D qualification to `STRICT_MOUSE_TARGET_HUMANMODE_PASS`: every path level must resolve a target item rect, move the cursor inside that rect, verify `cursor_inside_target_rect_before_click=true`, perform a real double-click inside the rect, and verify the next location/open result.
- Reclassifies incremental search + Enter, keyboard-assisted selection opens, Explorer address-bar path input, direct file open, ShellExecute, Start-Process, Invoke-Item, UIA InvokePattern/ValuePattern, and backend opens out of strict Case D evidence.

## v5.9.2 - Active Protection STOP Policy Fix

- Fixes the active-protection STOP policy gap found by the v5.9.1 pre-v6 gate.
- Remains v5 and does not enter v6.
- Does not introduce VLM, add an Agent Planner, narrow public release permissions, refactor HumanMode, fix HumanMode locators, or auto-commit changes.
- Preserves developer capability discovery for ordinary Chrome / Explorer / app / browser / local HTML / localhost / ordinary webpage and form exploration.
- Keeps ordinary content words such as test, exam, assessment, quiz, problem, challenge, mail, submit, hiring, recruitment, and login from becoming hard STOP signals by themselves.
- Stops explicit active-protection signals in developer mode, including bot challenge, CAPTCHA / human verification, automation/script detection, anti-cheat services and processes, lockdown / secure exam browsers, active proctoring, and protection-bypass requests.

## v5.9.1 - Pre-v6 Runtime Handoff Gate

- This version is the Runtime handoff gate before v6.
- Does not enter v6, introduce VLM, develop an Agent Planner, or perform public release permission narrowing.
- Verifies whether v5 HumanMode, Task Runtime, CLI/Service, active-protection STOP behavior, documentation, and artifacts are sufficient to support v6.
- Records PASS / FAIL / SKIP / NOT_RUN evidence under `artifacts\dev5.9.1_pre_v6_handoff\`.

## v5.9.0-e - HumanMode Cursor Motion and Action Result Contract Fix

- Remains v5 and only fixes HumanMode cursor motion pacing plus the HumanActionResult return contract.
- Does not enter v6, change the permission model, add VLM, narrow public release permissions, or auto commit.
- Makes `desktop-move`, `desktop-click`, and `desktop-double-click` use visible paced HumanMode movement by default: move steps, target verification, dwell before click, click/double-click, and post-click settle.
- Adds machine-readable `human_action_result.v1` output for HumanMode mouse commands, including target, start/final cursor, planned path, before-click cursor, epsilon verification, pacing timings, backend/fallback flags, error code, and exit code.
- Updates HumanMode case runners so mouse actions request paced HumanMode and task results record pacing/contract validation fields.
- Adds `v5_9_0_e_humanmode_motion_pacing_test.ps1` and artifacts under `artifacts\dev5.9.0-e_humanmode_motion_pacing\`.

## v5.9.0-b - HumanMode Visible UI Case Runner

- Implements the v5 HumanMode Visible UI Case Runner without entering v6, without introducing VLM, without adding an Agent Planner, and without public release permission narrowing.
- Adds developer-mode visible desktop primitives: `desktop-move`, `desktop-click`, `desktop-double-click`, `desktop-press`, `desktop-hotkey`, and `desktop-type`.
- Fixes the developer-mode boundary so base UI primitives are not blocked by FULL_ACCESS session requirements, TestWindow-only title/process allowlists, Program Manager/Desktop/Explorer titles, or ordinary content words such as test, exam, assessment, quiz, problem, challenge, submit, mail, hiring, or recruitment.
- Preserves STOP behavior for active protection: CAPTCHA, human verification, automation/script/bot detection, anti-cheat, active proctoring/lockdown browsers, protected desktop/UAC, and bypass requests.
- Adds `v5_9_0_b_humanmode_case_runner.ps1` and artifacts under `artifacts\dev5.9.0-b_humanmode_case_runner\` for Chrome/Edge open, browser address-bar navigation, third-party app launch, Explorer local HTML open, and local mock mail fill/send.
## v5.9.0-c - Strict HumanMode Case B/D/C Completion

- Completes Case B / Case D strict HumanMode paths for address-bar navigation and Explorer local HTML path opening when locators and the local GUI environment allow it.
- Adds Case C third-party App target resolution across explicit parameters, environment variables, common safe GUI apps, registry uninstall entries, and Start Menu shortcuts, avoiding early SKIP when PyCharm / VS Code are absent.
- Remains v5; this version does not enter v6.
- Does not introduce VLM.
- Does not perform permission narrowing.
- Does not auto git commit.

## v5.9.0-a - Developer Runtime Permission Model Reset

- Keeps this stage in v5. `-a` marks the developer permission reset and is not a public release version. This stage does not enter v6 and does not introduce a VLM main path.
- Resets the internal development tree default permission mode to `DEVELOPER_CAPABILITY_DISCOVERY` while retaining `PUBLIC_DEFAULT`, `CI_MOCK`, and legacy `FULL_ACCESS` compatibility.
- Developer mode now allows audited low-level desktop UI primitives, browser/Chrome/Edge navigation, Explorer, third-party app launch, local HTML, localhost, ordinary external web navigation, ordinary form filling, and mock workflows without requiring a FULL_ACCESS session.
- Removes over-broad content-keyword hard stops in developer mode. Words such as test, exam, assessment, quiz, homework, problem, challenge, submit, mail, hiring, recruitment, and coding are not active protection signals by themselves.
- Preserves hard STOP behavior for active protection: captcha, human verification, automation/script detection, active anti-cheat, active proctoring/lockdown clients, protected desktop/UAC, and protection-bypass requests return `STOP_ACTIVE_PROTECTION` / `BLOCKED_BY_ACTIVE_PROTECTION` style outcomes.
- Updates `config\safety_manifest.json`, `config\safety.conf`, PermissionManager, SafetyManifest/SafetyPolicy, command defaults, TaskSession profile validation, and documentation for the developer/public split.
- Adds `v5_9_permission_reset_selftest.ps1` covering developer aliases, low-level UI primitives, ordinary content keywords, active protection stops, and TaskSession developer profile acceptance.
- Adds v5.9.0-a artifacts and reports under `artifacts\dev5.9.0-a\`. This is not the future public permission narrowing pass.

## v5.8.8 - Runtime Boundary Dogfood and Real Desktop UI Stress Test

- Runtime Boundary Dogfood and Real Desktop UI Stress Test.
- Starts v5.8.8 real visible desktop UI boundary testing without starting v6, adding VLM as a main path, or adding an Agent Planner.
- Records Case A `desktop_mouse_open_chrome_visible_flow`: Runtime located a visible isolated Chrome desktop shortcut through UIA, then stopped at the existing SafetyPolicy boundary for `Program Manager` / `explorer.exe` real double-click input.
- Keeps the blocked desktop input result explicit as `BLOCKED`; no direct ShellExecute/browser launch is counted as strict UI evidence.

## v5.8.7 - Pre-v6 Runtime Hardening and Revalidation

- Starts the v5.8.7 documentation skeleton sync and revalidation track for the internal Task-Level Desktop Execution Runtime.
- Records that v6 has not started; v6 remains the future Initial Desktop Agent System boundary and provider architecture phase.
- Keeps v5 VLM-free: Runtime remains the only action executor, and SafetyPolicy, PermissionProfile, HumanConfirmation, blocked-action rules, StepContract, Verification, and AuditTrail boundaries must not be bypassed.
- Revalidates v5.0 TaskSession / state machine / artifact output and adds stable `runtime_version` and `protocol_version` fields to v5.0 validation and generated task artifacts.
- Revalidates v5.1 StepContract / PreconditionChecker / VerificationEngine / FailureReason behavior, reduces local-form hardcoding in precondition and verification checks, and keeps all checks local JSON / Runtime-bound without VLM or Agent execution.
- Revalidates v5.2 RecoveryPolicy / RecoveryAttempt / EscalationRequest / RetryBudget / SafeStop behavior, adds stable `max_total_recovery_ms` output, preserves structured candidates in EscalationRequest, and confirms blocked contexts route to STOP without provider bypass.
- Revalidates v5.4 TaskTemplateV2 / AppProfile binding, adds stable `runtime_version` and `protocol_version` fields to template validation output, rejects unsupported TaskParameter types, and confirms profiles cannot bypass Safety Manifest or degrade templates into fixed-coordinate scripts.
- Revalidates v5.5 File / Attachment / Cross-window workflows, makes FilePathResolver default-deny without explicit allowed roots, extends local mock coverage for file picker timeout and upload risk states, and keeps attachment workflows mock-only with metadata-only audit.
- Revalidates v5.6 task-level dogfood, adds explicit required case registry checks, measured latency summary validation, SKIP justification checks, and mock/local/real-external scope reporting for benchmark evidence.
- Revalidates v5.7 CLI task commands and service task API, adds explicit service capability protocol version checks, expands invalid-argument coverage, and writes `cancel_audit.json` for stopped cancellation/safe-stop artifacts.
- This entry does not add new runtime commands, VLM providers, Agent behavior, or public-release packaging.

## v5.8.6 - Task Execution Release Candidate Acceptance

- Added `v5_8_rc_acceptance.ps1` to run build, relevant v5 selftests, dogfood, service protocol, safety, latency, docs validation, and git status snapshot.
- v5 can now be described as a Task-Level Desktop Execution Runtime RC, with no VLM dependency and no real high-risk task execution.

## v5.8.5 - Docs and Versioning Note

- Updated README, CHANGELOG, ROADMAP, COMMAND_PROTOCOL, Task Runtime, Step Contract, Task Recovery, Human Confirmation, Task Templates v2, File Workflows, and Known Limitations with v5 RC scope and version normalization notes.
- Documented that v5.x is an internal engineering stage and a public Version Normalization Pass will map it to `0.x.x` prerelease versions before a formal `1.0.0`.

## v5.8.4 - Performance and Task Latency RC Check

- Added `v5_task_latency_rc_check.ps1` to record actual local TaskSession latency, verification latency, recovery latency, separate confirmation-wait handling, and LLM/VLM call count `0`.

## v5.8.3 - Safety and Permission RC Check

- Added `v5_safety_permission_rc_check.ps1` covering blocked actions, high-risk confirmation requirements, public profile restrictions, no VLM/Agent bypass, unresolved visual candidates, and real exam/hiring/game/payment/captcha stop paths.

## v5.8.2 - Evidence Consolidation

- Added `v5_evidence_consolidation.ps1` to consolidate v5.0 through v5.7 acceptance and dogfood evidence paths into a single RC index.

## v5.8.1 - Feature Freeze and Audit

- Added `docs/V5_TASK_EXECUTION_RC.md` and `v5_rc_audit.ps1` for feature matrix, missing features, known limitations, safety review, and performance review.

## v5.7.6 - Task Execution Stabilization Acceptance

- Added `v5_7_acceptance.ps1` for build, CLI task command tests, service protocol task tests, cancel/safe-stop tests, report schema tests, adapter smoke, docs validation, and git status snapshot.
- Acceptance confirms external Agents can call TaskSession execution through CLI or service without bypassing SafetyPolicy.

## v5.7.5 - Docs and Adapters

- Updated `COMMAND_PROTOCOL.md`, `docs/SERVICE_PROTOCOL.md`, adapter docs, README, VERSION, and CHANGELOG for v5.7 task execution.
- Added parseable service task request samples and docs validation.

## v5.7.4 - Task Report Compatibility

- Stabilized task artifact compatibility around `task_result.json`, `task_events.jsonl`, `task_report.md`, `evidence_index.md`, and machine-readable task status.
- Added `task_report_compat_selftest.ps1`.

## v5.7.3 - Cancellation and Safe Stop

- Added `task-cancel` handling for user cancel, timeout cancel, safety stop, provider unavailable stop, and confirmation timeout stop.
- Cancellation produces stopped artifacts and leaves terminal tasks as stable no-ops.

## v5.7.2 - Service Protocol Task API

- Added service task endpoints `/health`, `/capabilities`, `/run_task`, `/get_task_status`, `/get_task_events`, `/confirm_task_action`, `/cancel_task`, and `/read_task_report`.
- Task service endpoints use the existing service envelope and do not bypass safety.

## v5.7.1 - CLI Task Commands

- Stabilized TaskSession execution through `run-task --file <task-session.json>`.
- Added `task-status`, `task-events`, `task-report`, `task-confirm`, and `task-cancel`.

## v5.6.6 - Task-Level Dogfood Acceptance

- Added `v5_6_acceptance.ps1` for build, task dogfood suite, safety tests, report validation, and git status snapshot.
- Acceptance requires at least four controlled task-level PASS cases or justified SKIP and no failed dogfood cases.

## v5.6.5 - Dogfood Report and Latency Summary

- Added task-level dogfood Markdown and JSON reports with task states, step results, recovery attempts, confirmations, latency, artifacts, failure reasons, audit path, and per-case evidence files.
- Added `task_dogfood_report_selftest.ps1` for report parsing and artifact existence checks.

## v5.6.4 - Local Mail Mock Attachment Dogfood Case

- Added local mail mock attachment dogfood coverage using controlled local file picker, upload verification, cross-window return, pre-send confirmation evidence, mock sent state, and no real email send.

## v5.6.3 - Local Problem-Solving Mock Dogfood Case

- Added local problem-solving dogfood coverage over local mock HTML for read problem, compile error mock, run code, and result verification.
- Public exam, hiring assessment, real contest, and external submission automation remain out of scope.

## v5.6.2 - Local Form and Notepad Dogfood Cases

- Added local form TaskSession dogfood coverage.
- Added Notepad task-level registry entry with justified SKIP in the stable benchmark to avoid conflicting with user desktop windows; legacy desktop dogfood remains available separately.

## v5.6.1 - Dogfood Suite Skeleton

- Added `task_dogfood_benchmark.ps1` with case registry, empty-suite mode, dummy-case mode, PASS/FAIL/SKIPPED reporting, and artifact path setup.
## v5.5.5 - File Workflow Docs and Safety

- Added `docs/FILE_WORKFLOWS.md` and updated `docs/SAFETY_MANIFEST.md` with file, attachment, and cross-window safety boundaries.
- Updated the local mail mock TaskTemplateV2 with `file_picker_flow` and `upload_verification` metadata.
- Documented `file-path-resolve`, `file-picker-flow`, `attachment-verify`, `cross-window-check`, and `local-mail-attach-flow`.

## v5.5.4 - Cross-window Context

- Added `CrossWindowTaskContext` validation for parent task window, child dialog window, return to parent, foreground verification, `window_changed`, and focus restore.
- Wrong foreground state stops with `CROSS_WINDOW_WRONG_FOREGROUND`.

## v5.5.3 - Attachment Upload Verification

- Added `AttachmentState` and `UploadVerification` checks for visible file name, upload start, spinner/progress, spinner gone, completion, failure, file-too-large, retry, and timeout states.

## v5.5.2 - File Picker Flow

- Added local mock `FilePickerFlow` validation for picker detection, file path input, Open confirmation, picker close/target app change, timeout, and cancel.

## v5.5.1 - File Path Resolver

- Added `FilePathResolver` with absolute path support, allowed roots, existence, size, extension policy, traversal rejection, and metadata-only audit.
- Added `FileActionRisk` in resolver output and blocked sensitive/default externalization paths.
## v5.4.5 - Task Template v2 Docs and Samples

- Added `docs/TASK_TEMPLATES_V2.md` for TaskTemplateV2, ProfileBoundLocator, ProfileBoundVerification, TaskParameter, and TaskTemplateResolver.
- Added sample v5.4 task parameter files and sample profile pointers under `samples\tasks` and `samples\profiles`.
- Documented `task-template-v2-validate` and `task-template-v2-resolve` in README and command protocol.

## v5.4.4 - Built-in Local Task Templates v2

- Added built-in local TaskTemplateV2 files for local form submit, local problem page run/read, local mail mock compose/attach/no-real-send, Notepad edit/verify, and Explorer file select mock.
- Added built-in template parse coverage and resolver smoke coverage for two local templates.

## v5.4.3 - Task Template v2 Parameterization

- Added required parameter validation for `recipient`, `subject`, `body`, `file_path`, `expected_result`, `local_url`, and `output_region`.
- Added local path, local URL, missing parameter, and ROI parameter rejection paths.

## v5.4.2 - App Profile Binding Resolver

- Added TaskTemplateResolver binding over profile common locators, ROI definitions, visual strategy, recovery strategy, and confirmation nodes.
- Missing profile locators fail explicitly without falling back to fixed coordinates.
- Profile binding records that App Profiles cannot override Safety Manifest.

## v5.4.1 - Task Template v2 Schema

- Added TaskTemplateV2 schema validation through `task-template-v2-validate`.
- Required fields include `template_id`, `required_profile`, `parameters`, `states`, `steps`, `preconditions`, `verification`, `recovery`, `confirmation_nodes`, and `final_state_policy`.
- Templates cannot set `allow_unrestricted_desktop=true` or declare profile safety override.

## v5.3.5 - Human Confirmation Docs and Safety Alignment

- Added `docs/HUMAN_CONFIRMATION.md` for risk levels, ConfirmationRequest fields, confirmation gate behavior, local mock flow, and permission-mode boundaries.
- Added `docs/SAFETY_MANIFEST.md` with v5.3 confirmation alignment, high-risk actions, blocked actions, and development-vs-public release behavior.
- Documented `risk-action-classify`, `confirmation-request-create`, `confirmation-gate-check`, and `confirmation-flow-run` in README and the command protocol.
- Updated `VERSION`, runtime version output, README, command protocol, and changelog to the internal v5.3.5 stage.
- Added `confirmation_docs_selftest.ps1` for help output, docs presence, command contract, sample JSON parsing, and version checks.

## v5.3.4 - Local Mock Confirmation Flow

- Added `confirmation-flow-run` for the local `local_mail_mock_send_confirm` fixture.
- The flow creates a confirmation request, blocks without confirmation, accepts explicit `confirm`, writes confirmation audit, records `mock_sent`, and sends no real email.

## v5.3.3 - Confirmation Gate

- Added `confirmation-gate-check`.
- High-risk actions without confirmation are blocked; confirmed actions are allowed; rejected or timed-out actions stop; blocked actions cannot be confirmed through.

## v5.3.2 - ConfirmationRequest Schema

- Added `confirmation-request-create`.
- ConfirmationRequest includes action, risk level, summary, target window, screenshot, involved files, destination, timeout, allowed responses, audit id, request JSON, and Markdown report artifacts.

## v5.3.1 - Risk Action Classification

- Added `risk-action-classify`.
- Classified actions as `low`, `medium`, `high`, or `blocked`.
- High-risk actions require confirmation, while blocked public-profile and safety-sensitive actions remain disallowed after confirmation.

## v5.2.5 - Task Recovery Docs and Matrix

- Added `docs/TASK_RECOVERY.md` with RecoveryPolicy strategy coverage, recovery matrix, EscalationRequest fields, SafeStop matrix, artifacts, and limits.
- Documented `recovery-policy-validate`, `recovery-evaluate`, `escalation-request-create`, and `safe-stop-check` in README and the command protocol.
- Updated `VERSION`, runtime version output, README, command protocol, and changelog to the internal v5.2.5 stage.
- Added `recovery_docs_selftest.ps1` for help output, docs presence, command contract, sample JSON parsing, and version checks.

## v5.2.4 - SafeStop and Blocked Handling

- Added `safe-stop-check` for terminal high-risk conditions.
- High-risk reasons including captcha, anti-cheat, proctoring, payment, credential/security challenge, game automation, public-profile real exam/hiring submission, and `SAFETY_DENIED` stop without recovery.
- Tightened escalation routing so high-risk contexts cannot be routed to Agent/VLM as a bypass.

## v5.2.3 - EscalationRequest

- Added `escalation-request-create` for structured local escalation requests.
- EscalationRequest records reason, task, step, scene state, candidates, screenshot artifact, ElementGraph artifact, risk level, allowed routes, recommended action, and provider-unavailable fallback.
- Provider availability is local metadata only; v5.2.3 does not call VLM or Agent providers.

## v5.2.2 - Retry and Wait Recovery

- Added `recovery-evaluate` for low-risk recovery decisions.
- Mapped `TARGET_NOT_READY` to `wait_and_retry`, `TEXT_NOT_FOUND` to `re_observe`, `LOCATOR_NOT_FOUND` to `re_locate`, and `STALE_CANDIDATE` to `invalidate_cache`.
- Recovery attempts emit structured audit records without performing desktop actions.

## v5.2.1 - RecoveryPolicy Schema

- Added RecoveryPolicy data structures and `recovery-policy-validate`.
- Supported strategies: `re_observe`, `re_locate`, `wait_and_retry`, `invalidate_cache`, `use_profile_fallback`, `use_visual_provider`, `ask_user`, `escalate_to_agent`, and `stop`.
- Added focused valid/invalid policy selftest coverage.

## v5.1.5 - Step Contract Docs and Samples

- Added `docs/STEP_CONTRACT.md` for StepContract fields, preconditions, verification checks, failure reasons, and safety boundaries.
- Added sample task files under `samples\tasks` for the local form submit and local problem mock development fixtures.
- Documented `step-contract-validate`, `step-precondition-check`, `step-verify`, and `step-failure-classify` in README and the command protocol.
- Added `step_docs_selftest.ps1` for help output, docs presence, command contract, and sample JSON parsing.
- v5.1 remains Standard Runtime Mode by default and does not depend on VLM, Agent planners, external web, or real-account automation.

## v5.1.4 - Failure Reason Classification

- Added structured Step failure classification with `step-failure-classify`.
- Supported `PRECONDITION_FAILED`, `LOCATOR_NOT_FOUND`, `TARGET_NOT_READY`, `ACTION_FAILED`, `ACTION_NO_EFFECT`, `VERIFICATION_TIMEOUT`, `UNEXPECTED_SCENE`, `SAFETY_DENIED`, and `SEMANTIC_UNRESOLVED`.
- Added focused failure-reason selftest coverage.

## v5.1.3 - Verification Engine

- Added `step-verify` for post-action verification over local before/after perception JSON.
- Supported expected ChangeEvent, SceneState, element graph, text appeared/disappeared, element appeared/disappeared, region changed, and timeout checks.
- Added focused verification selftest coverage.

## v5.1.2 - Precondition Checker

- Added `step-precondition-check` for action-before-state checks over local perception JSON.
- Supported scene state, element existence, target readiness, focused window, active profile, safety allowed, and available capability checks.
- Added focused precondition pass/fail selftest coverage.

## v5.1.1 - StepContract Schema

- Added StepContract data structures and `step-contract-validate`.
- Defined required step fields: `step_id`, `name`, `preconditions`, `action`, `verification`, `timeout_ms`, `retry_policy`, `on_failure`, `safety_requirements`, `expected_scene_state`, `expected_change_events`, and `expected_elements`.
- Added focused schema and serialization selftest coverage.

## v5.0.5 - Task Runtime Docs and Command Contract

- Documented v5.0 TaskSession commands: `task-session-validate`, `task-session-transition`, and `task-session-run`.
- Added `docs/TASK_RUNTIME.md` with implemented schema, state machine, minimal runner, artifact, and safety boundaries.
- Updated `VERSION`, README, command protocol, and changelog to the internal v5.0.5 stage.
- Added `task_docs_selftest.ps1` for help output, docs presence, command contract, and JSON sample parsing.
- v5.0 remains Standard Runtime Mode by default and does not depend on VLM, Agent planners, external web, or real-account automation.

## v5.0.4 - Task Artifact and Audit

- Formalized task-level artifacts for the local mock TaskSession runner: `task_events.jsonl`, `task_result.json`, `task_report.md`, `current_state.json`, and `failure_dump.json`.
- Added `task_artifact_selftest.ps1`.

## v5.0.3 - Minimal Task Runner

- Added `task-session-run` for the local mock `local_form_fill_submit_mock` TaskSession.
- Added local mock HTML fixture and runner smoke coverage.

## v5.0.2 - State Machine Core

- Added dry-run TaskSession state transitions through `task-session-transition`.
- Implemented `start_task`, `enter_state`, `transition_to`, `fail_task`, `stop_task`, `complete_task`, timeout handling, and invalid transition rejection.

## v5.0.1 - Task Model Schema

- Added TaskSession data structures and `task-session-validate`.
- Defined TaskState enum, required session fields, artifact paths, and task result JSON.

## v4.7.0 - Hybrid Perception Release Candidate

- Closed v4.x as a Hybrid Screen Perception Runtime release candidate.
- Added `v4_rc_check.ps1` to run focused v4 RC checks and aggregate v4.1 through v4.6 evidence into `artifacts\dev4.7.0`.
- Added `hybrid_perception_release_candidate` capability marker and `hybrid_perception_rc_v4_7` experimental marker.
- Added v4 RC documentation for perception contracts, benchmark evidence, safety closure, release hygiene, and public-release boundaries.
- Reaffirmed that v4.x is not a complete autonomous Agent, does not fully understand arbitrary screens, and does not include real VLM/OmniParser/YOLO/UGround integrations or model weights.
- Public release preparation remains separate from the local development tree and must use `D:\desktopvisual-release` with restricted public permissions.

## v4.6.0 - Visual Dogfood on Developer Workflow

- Added `v4_visual_dogfood.ps1` as a bounded v4 visual dogfood suite for local developer workflow fixtures.
- Added required dogfood cases: `local_html_form_flow`, `local_problem_page_run_and_read_result`, `local_mail_mock_compose_attach_verify_no_real_send`, `explorer_temp_file_select_flow`, `notepad_text_edit_verify`, and `powershell_command_result_read`.
- Each v4.6 case records v4 perception evidence through `observe2`, `ElementGraph`, `LocatorCandidate`, `SceneState`, `ChangeEvent`, `observe-loop` delta/ROI metadata, and App Profile metadata where applicable.
- The local mail case proves mock attachment upload completion and mock sent-state verification without real email sending.
- The local problem page is explicitly labeled as a development benchmark fixture, not real exam, assessment, or hiring-test automation.
- Added `visual_developer_dogfood` capability marker and `visual_dogfood_v4_6` experimental marker.
- Added v4.6 dogfood evidence under `artifacts\dev4.6.0` and integrated the suite into `rc_check.ps1`.

## v4.5.0 - App Profile System

- Added `AppProfile` loading and validation for application-adapter metadata under `profiles\*.profile.json`.
- Added built-in safe local profiles for TestWindow, Notepad, Explorer, Calculator, local browser pages, a local problem fixture, and a local mail mock fixture.
- Added `profile-report` to report loaded/invalid profiles, common locator counts, effective capabilities, and the invariant `can_override_safety_manifest=false`.
- Integrated App Profile common locators with `locate --profile <name> --profile-locator <name>` while preserving the existing selector locator and safety gates.
- Added `profiles\schema\app_profile.schema.json` and `docs\APP_PROFILES.md`.
- Added `app_profile_selftest.ps1` and evidence under `artifacts\dev4.5.0`.
- v4.5.0 does not add real Gmail/Outlook automation, real-account profiles, public high-permission defaults, or fixed-coordinate scripts.

## v4.4.0 - Dynamic UI Recovery

- Enhanced v4 perception output with dynamic `SceneState` statuses: `normal`, `loading`, `dialog_open`, `error`, `success`, `blocked`, and `unknown`.
- Enhanced `ChangeEvent` coverage with loading, dialog, error, success, element movement, element enabled/disabled, and `target_ready` events.
- Added read-only `dynamic-ui-recovery` for deterministic local HTML dynamic UI fixtures and recovery-route evaluation.
- Added base PerceptionRouter, SemanticResolver, RiskRouter, and ActionExecutor gate decisions: `AUTO_EXECUTE`, `ESCALATE_TO_VLM`, `REQUIRE_HUMAN_CONFIRMATION`, and `STOP`.
- Added finite Dynamic UI recovery strategies for loading, target readiness, dialogs, stale/moved candidates, repaint/cache invalidation, errors, and blocked states.
- Preserved hard blocking for unresolved visual-only candidates with `ACTION_BLOCKED_SEMANTIC_UNRESOLVED`; blocked states stop immediately and are not routed to VLM bypass.
- Added `dynamic_ui_recovery_selftest.ps1` and evidence under `artifacts\dev4.4.0`.

## v4.3.0 - Latency Benchmark Pack

- Added `latency_benchmark.ps1` for reproducible current-machine latency evidence.
- Added `artifacts\dev4.3.0\latency\benchmark_config.json`, `latency_results.json`, `latency_summary.md`, `raw_logs\`, fixtures, screenshots, and observe-loop event evidence.
- Measured screenshot, UIA, full OCR, ROI OCR, screen delta, ElementGraph-producing observe2, hybrid locate, image-template provider, observe-loop event latency, action-to-verify, cache hit ratio, and `llm_or_vlm_call_count`.
- Added local TestWindow and local HTML fixture scenarios without real accounts, external websites, VLM calls, OmniParser/YOLO weights, or GPU requirements.
- Added warning thresholds as local-machine budget checks only; v4.3.0 does not claim cross-machine latency guarantees or superiority over other tools.

## v4.2.0 - Realtime Observe Loop

- Added read-only `observe-loop` and `observe2 --loop` for bounded continuous observation over an authorized target window.
- Added JSONL event stream output with target-ready, region-change, window/foreground-change, UIA, dialog, loading, error, success, and safety-blocked event types.
- Added Screen Delta and Perception Cache accounting so unchanged rounds avoid ROI OCR and UIA refresh work.
- Added debounce and loop guards for max duration, max events, max no-change rounds, stop-file shutdown, and safety-manifest stops.
- Added `observe_loop_selftest.ps1` and evidence under `artifacts\dev4.2.0`.
- v4.2.0 is an event stream layer, not a task planner or continuous VLM monitor.

## v4.1.0 - Visual Source Integration

- Added the provider-ready v4 perception foundation with `ScreenFrame`, `ElementGraph`, `LocatorCandidate`, `SceneState`, and `ChangeEvent` JSON output through the read-only `observe2` command.
- Added `VisualSourceProvider`-style runtime structures for provider status, provider results, and standardized visual element candidates.
- Added provider registry reporting for `uia`, `ocr`, `screen_delta`, `image_template`, `local_visual_provider`, `cloud_vlm`, and `agent_provider`.
- Added image template matching as the first concrete visual source, reusing existing BMP template matching without adding model weights or external dependencies.
- Added unavailable/degraded placeholder status for local visual, cloud VLM, and agent providers; v4.1.0 does not download OmniParser/YOLO/UGround weights or call VLMs.
- Added an ActionExecutor gate for unresolved visual-only selectors, returning `ACTION_BLOCKED_SEMANTIC_UNRESOLVED` before input.
- Added `observe2_provider_selftest.ps1` and evidence under `artifacts\dev4.1.0`.

## v3.7.0 - Public Release Candidate for v3.x

- Repositioned README around DesktopVisual as a Windows-only, agent-agnostic, auditable, safety-bounded Computer Use Runtime.
- Removed corrupted README text and tightened public release wording.
- Added v3.x release summary, v4 roadmap, and resume-safe positioning docs.
- Updated repository hygiene checks for browser-profile artifacts and sensitive browser state files.
- Synchronized public repo checks with the release-candidate positioning.
- Documented the local-vs-release permission split: `D:\desktopvisual` remains the broad local development/evaluation tree, while public releases must be prepared separately under `D:\desktopvisual-release` with restricted assessment/exam permissions.
- Kept service protocol at version `1.0`; v3.7.0 does not add new desktop-control commands or v4 perception features.

## v3.6.0 - Dogfood on Developer Tools

- Expanded the dogfood matrix into a bounded developer-tool evidence harness.
- Added required per-task metadata: `safety_boundary`, `expected_result`, and `skipped_condition`.
- Added local HTML dogfood for mixed form/control semantics through `form-control` without external web access.
- Added PowerShell dogfood for local non-admin read-only/test command output verified through `read-file`.
- Updated `dogfood_matrix.ps1` to write `artifacts\dogfood\dogfood_report.md`, `artifacts\dogfood\dogfood_summary.json`, and the legacy `artifacts\dogfood_matrix_report.md`.
- Added `dogfood_selftest.ps1` to validate task coverage, PASS/FAIL/SKIPPED counts, and report completeness.
- Added runtime capability marker `developer_tool_dogfood`.
- Updated runtime and report version strings to `3.6.0`.

## v3.5.0 - Service Protocol Stabilization

- Added service protocol version `1.0` to service envelopes and `version` data.
- Added service capability marker `service_protocol_v1`.
- Stabilized service endpoints for `/version`, `/observe`, `/locate`, `/act`, `/run-task`, `/read-report`, `/safety-report`, `/policy-check`, `/consent-check`, and `/health-check`.
- Standardized service responses with top-level `ok`, `error_code`, `message`, `data`, `artifacts`, `report_path`, `duration_ms`, and `service_protocol_version`.
- Kept legacy failure compatibility by retaining `error.code` and `error.message` on failed service responses.
- Added service audit entries for the protocol version and unified service requests, including unauthorized token failures.
- Added `service_protocol_selftest.ps1` for endpoint, envelope, audit, and report-path validation.
- Added `docs\SERVICE_PROTOCOL.md`.
- Updated runtime and report version strings to `3.5.0`.

## v3.4.0 - Recovery Strategy Engine

- Added `RecoveryStrategy` and `RecoveryAttemptRecord` for configured, auditable, bounded task recovery.
- Added strategy mapping for `LOCATOR_NOT_FOUND`, `WINDOW_NOT_FOUND`, `LOCATOR_NOT_UNIQUE`, `TEXT_NOT_FOUND`, and `SAFETY_POLICY_DENIED`.
- Integrated the Recovery Strategy Engine into `TaskRunner` and service-backed `run-task` reports.
- Recovery attempts now respect effective `max_recoveries` after Safety Manifest clamping and are written to the Markdown task report.
- `SAFETY_POLICY_DENIED` is recorded as `stop_immediately` and is never recovered.
- `LOCATOR_NOT_UNIQUE` and related non-unique control failures require explicit selectors or `nth`; the runtime does not auto-pick a candidate.
- Added `recovery_selftest.ps1` to verify locator recovery records, non-unique stop behavior, and safety-policy denial immutability.
- Added `docs\RECOVERY_STRATEGY_ENGINE.md`.
- Updated runtime and report version strings to `3.4.0`.

## v3.3.10 - Full Access Benchmark and Real Scenario Harness

- Added the Full Access benchmark harness under `benchmarks\full_access\` with task, expected, report, and artifact directories.
- Added `full_access_benchmark_matrix.ps1` to produce `artifacts\benchmark\full_access\full_access_benchmark_report.md` and `full_access_benchmark_summary.json`.
- Added `full_access_benchmark_selftest.ps1` to validate reproducible PASS/FAIL/SKIPPED semantics, required scenarios, required metrics, and evidence-pack contents.
- Added `export_full_access_evidence_pack.ps1` to create `artifacts\evidence\DesktopVisual-v3.3.10-full-access-evidence-pack.zip`.
- Covered benchmark scenarios for DEFAULT denial, interactive FULL_ACCESS unlock gating, safe app launch, local external-web simulation, mixed form semantics, decision-task forms, checkpoint loop guard, simulated communication, simulated coding workflow, and public-release assessment permission notice coverage.
- Added metrics for permission mode success, FULL_ACCESS unlock evidence, form classification accuracy, decision task success, loop guard triggers, user-takeover/stop conditions, communication simulation, coding workflow success, and report completeness.
- Evidence packs include selected reports and safety/runtime docs while excluding real account data, real communications, browser profiles, raw motion data, build outputs, and sensitive logs.
- Added runtime capability marker `full_access_benchmark_harness`.
- Updated runtime, reports, docs, and selftests to `3.3.10`.

## v3.3.9 - Coding and Problem-Solving Web Workflow

- Added the Coding Workflow engine (`src/winagent/CodingWorkflow.h/.cpp`): `CodingWorkflowContext`, `CodingWorkflowRecord`, and a deterministic read_context -> classify_task -> choose_action -> record pipeline for one authorized web coding-practice action at a time.
- Added `coding-eval` for dry-run coding-workflow checks over local HTML/DOM-like OJ fixtures (no input, focus, code execution, or live page access).
- Added `type: "coding"` task steps gated on the existing `content_decision` capability (DEFAULT denies with `SAFETY_POLICY_DENIED`; FULL_ACCESS requires a valid unlocked session id).
- Supported actions: `read_problem`, `select_language`, `input_code`, `run_code`, `read_result`, `revise_code`, `stop_before_submit`, and `submit_if_explicitly_allowed`.
- Recognized the code editor and Run Code control from page semantics (reusing `FormSemantics`); read the problem title/statement/examples/constraints regions; read the result state from a `data-result` marker or result region text.
- Result states: `COMPILE_ERROR`, `RUNTIME_ERROR`, `WRONG_ANSWER`, `TIME_LIMIT`, `SAMPLE_PASS`, `ACCEPTED`, `UNKNOWN_RESULT` (recorded in `result_state`, not as error codes).
- Default-stops after Run Code: submit is never recorded unless the task sets `allow_submit=true`; an unauthorized submit stops with `USER_TAKEOVER_REQUIRED`.
- Hard stops: login/password stops with `USER_TAKEOVER_REQUIRED`; captcha stops with `CAPTCHA_DETECTED`; anti-automation/AI-detection stops with `ANTI_AUTOMATION_DETECTED`; an unrecognized code editor stops with `LOCATOR_NOT_FOUND`.
- Corrected the development-runtime boundary for exam/assessment/hiring/certification/rated-contest keywords: these keywords no longer hard-stop by themselves because stage 9 explicitly allowed those categories under a user-authorized task. Public releases must add explicit permission restrictions before exposing these workflows outside controlled local development.
- Page/site content never overrides `user_goal`. Reports record a code summary/path only, never full code.
- Added `coding_workflow_selftest.ps1` (local simulated OJ fixtures) and `docs\CODING_WORKFLOW.md`.
- Reused existing stop codes and the `content_decision` manifest capability; no new error codes or manifest changes were required.
- Updated runtime and report version strings to `3.3.9`.

## v3.3.8 - Communication Action Runtime

- Added `communication_step` task runtime for local simulated communication actions under the existing `communication` permission capability.
- Added `CommunicationAction` records with channel, target, subject, content summary, content hash, user send authorization, send result, permission mode, and risk level.
- Enforced communication send boundaries: DEFAULT denies, FULL_ACCESS requires a valid session, send requires `user_requested_send=true`, target is required, multi-target sends stop, and login/captcha/credential/anti-automation surfaces stop.
- Added audit logging for communication actions without recording full message content.
- Added `communication_runtime_selftest.ps1` and `docs\COMMUNICATION_RUNTIME.md`.
- Updated runtime and report version strings to `3.3.8`.

## v3.3.7 - Session Checkpoint and Loop Guard

- Added `SessionCheckpoint` report records with checkpoint id, timestamp, permission mode, task id, step index, window/process, URL, observed summary, recent actions, form-state summary, and suggested recovery actions.
- Added manual `type: "checkpoint"` task steps and root `checkpoint` configuration with interval and temporary-file cleanup.
- Added TaskRunner loop guard configuration for repeated actions, repeated URLs, no progress, repeated window-open markers, scroll no-progress, max steps, and max duration.
- Added `SCROLL_NO_PROGRESS` and made TaskRunner emit `REPEATED_ACTION_LIMIT`, `URL_REDIRECT_LOOP`, `NO_PROGRESS_DETECTED`, `WINDOW_SPAWN_LOOP`, and `LOOP_GUARD_STOP` for long-task guard stops.
- Added `checkpoint_loopguard_selftest.ps1` and `docs\SESSION_CHECKPOINTS.md`.
- Updated runtime and report version strings to `3.3.7`.

## v3.3.6 - General Decision Task Runtime

- Added the Decision Engine for deterministic, auditable content decisions on one resolved control at a time.
- Added `DecisionTaskContext` (`user_goal`, `permission_mode`, `current_window`, `current_url`, `observed_content_summary`, `allowed_actions`, `denied_actions`, `risk_level`).
- Added `DecisionRecord` (`decision_type`, `source`, `reason`, `selected_action`, `target_field_id`, `target_label`, `control_type`, `chosen_value_present`, `confidence`, `user_goal_preserved`, `safety_check_result`, `timestamp`).
- Added `decision-eval` for dry-run decision checks over local HTML/DOM-like fixtures (no input, focus, or live UI inspection).
- Added `type: "decision"` task steps gated on the `content_decision` capability; DEFAULT denies with `SAFETY_POLICY_DENIED`, FULL_ACCESS requires a valid unlocked session id.
- Enforced decision rules: page/chat/web content never overrides `user_goal`; instruction-injection text is flagged and ignored; low-confidence fields stop with `FIELD_CONFIDENCE_LOW`; captcha stops with `CAPTCHA_DETECTED`; anti-automation/AI-detection content stops with `ANTI_AUTOMATION_DETECTED`; credential content stops with `CREDENTIAL_INPUT_DETECTED`; unauthorized submit stops with `USER_TAKEOVER_REQUIRED`.
- Recorded the decision context and record in task reports for each decision step.
- Added `decision_task_selftest.ps1` and `docs\DECISION_TASK_RUNTIME.md`.
- Reused existing stop codes and the `content_decision` manifest capability; no new error codes or manifest changes were required.
- Fixed post-acceptance RC gate issues: README now reports v3.3.6, `version` reports decision-task capabilities, selftest asserts them, and build scripts recover when child PowerShell processes do not inherit `ProgramFiles(x86)`.
- Updated runtime and report version strings to `3.3.6`.

## v3.3.5 - Form and Control Semantics Engine

- Added `FormControl` semantics with `field_id`, `label`, `control_type`, `required`, `options`, `rect`, `source`, `confidence`, and `recommended_action`.
- Added `form-control` for local DOM-like HTML form inspection and action mapping.
- Added control types: `textbox`, `textarea`, `radio`, `checkbox`, `dropdown`, `button`, `link`, `date_picker`, `file_upload`, `code_editor`, `captcha/challenge`, and `unknown`.
- Added action mapping: text fill, textarea fill, radio select, checkbox toggle, option select, button/link click, code input, and challenge stop.
- Added `form_action` task steps with field recognition and action mapping in task reports.
- Added `FIELD_NOT_UNIQUE` and `FIELD_CONFIDENCE_LOW`; captcha/challenge fields stop with `CAPTCHA_DETECTED`.
- Added `form_semantics_selftest.ps1` and `docs\FORM_SEMANTICS.md`.
- Updated runtime and report version strings to `3.3.5`.

## v3.3.4 - External Web and Browser Navigation Runtime

- Added `browser-nav` for FULL_ACCESS-gated browser navigation.
- Supported opening default/specified browser targets, URL entry via shell launch, local simulated page title extraction, basic scroll/click action recording, and optional visible browser window capture.
- Integrated external URL access with PermissionManager: DEFAULT denies external web, FULL_ACCESS requires a valid temporary session id.
- Added hard stops for login/credential URLs, captcha/challenge URLs, payment/checkout URLs, and anti-automation/bot-detection URLs.
- Added URL loop guard with `URL_REDIRECT_LOOP` plus no-progress/repeated-action stop codes.
- Added `external_web_selftest.ps1` with local simulated navigation, captcha/login stops, URL loop guard, and audit checks.
- Updated runtime and report version strings to `3.3.4`.

## v3.3.3 - Global Desktop and App Launcher Runtime

- Added `launch-app` for FULL_ACCESS-gated normal desktop/app launching.
- Supported launch kinds: `exe`, `desktop-shortcut`, `start-menu`, `explorer`, and `this-pc`.
- Integrated `launch-app` with PermissionManager: DEFAULT denies broad app/global desktop launch, FULL_ACCESS requires a valid temporary session id.
- Added target-window capture after launch: title, process, hwnd, pid, and rect.
- Added launch hard stops for credential, login/user-takeover, protected desktop/UAC, anti-cheat, and anti-automation targets.
- Added launch loop guard with `WINDOW_SPAWN_LOOP` for repeated app launches and abnormal visible-window growth.
- Added `WINDOW_NOT_VISIBLE`, `WINDOW_SPAWN_LOOP`, and `PROTECTED_DESKTOP_DETECTED`.
- Added `global_desktop_selftest.ps1`.
- Updated runtime and report version strings to `3.3.3`.

## v3.3.2 - Interactive Permission UX

- Changed `unlock-full-access` from direct session creation to a local interactive CLI permission selector.
- Added numeric permission selection: `[1] DEFAULT` and `[2] FULL_ACCESS`.
- Added FULL_ACCESS risk warning and exact confirmation phrase requirement: `ENABLE FULL_ACCESS`.
- Added non-interactive protection: piped input, task files, automated arguments, and service endpoints cannot unlock FULL_ACCESS.
- Added `FULL_ACCESS_REQUIRES_INTERACTIVE_CONFIRMATION` for blocked non-interactive unlock attempts.
- Added `permission_ux_selftest.ps1` and updated permission profile selftests for the stricter UX gate.
- Decoupled `rc_check.ps1` from release packaging: default RC checks skip `package_source.ps1`, `release.ps1`, and `verify_release.ps1`; use `-IncludeRelease` only when the user explicitly requests a release package.
- Updated runtime and report version strings to `3.3.2`.

## v3.3.1 - Permission Profiles and Full Access Gate

- Added DEFAULT/FULL_ACCESS permission profiles through `PermissionManager`.
- Added temporary FULL_ACCESS sessions with TTL, `task-only`/`session-only` scope, `permission-status`, `unlock-full-access`, and `lock-full-access`.
- Extended `config\safety_manifest.json` with `permission_modes`.
- Extended `policy-check` with `--permission-mode` and `--full-access-session-id`.
- Extended TaskRunner with `permission_mode` and `full_access_session_id`, plus Permission Decision reporting.
- Updated service `/policy-check` and `/run-task` to use already unlocked FULL_ACCESS sessions without exposing service-side unlock.
- Added immutable stop status codes for user takeover, credential input, captcha, anti-automation, anti-cheat, and loop guard.
- Added `permission_profile_selftest.ps1`.
- Updated runtime and report version strings to `3.3.1`.

## v3.3.0 - Task Template Library

- Added `tasks\templates\` with reusable task templates: `open_app`, `focus_window`, `fill_form`, `click_button`, `wait_until_text`, `wait_until_window`, `copy_text`, `save_file`, `open_local_html`, and `run_local_test_page`.
- Added TaskRunner support for `type: "template"` steps that load template JSON, substitute parameters, and expand into existing safe task steps.
- Added TaskRunner report diagnostics for template name, parameters, expanded steps, and PASS/FAIL result.
- Added a bounded `hotkey` task step for templates such as `copy_text` and `save_file`; it reuses existing target-window safety and focus paths.
- Added `template_selftest.ps1`.
- Updated runtime and report version strings to `3.3.0`.

## v3.2.0 - Window Session And Foreground Control

- Added `WindowSession.h/.cpp` to resolve authorized visible windows with title, optional process, hwnd, rect, foreground state, DPI, and monitor bounds.
- Extended `observe` with `data.window_session` and duplicate-window candidate diagnostics.
- Added `WINDOW_TITLE_CHANGED` for TaskRunner title-change detection during session reconfirmation.
- Updated `act` to confirm the target can be foregrounded before UIA or input actions, without bypassing SafetyPolicy or Safety Manifest checks.
- Integrated `run-task` startup and step-level WindowSession checks, including Markdown report diagnostics.
- Added `window_session_selftest.ps1`.

## v3.1.1 - Safety Manifest Strict JSON Patch

- Fixed `config\safety_manifest.json` so it parses as strict JSON with PowerShell `ConvertFrom-Json`.
- Replaced two corrupted denied title pattern strings with ASCII `login` and `captcha` deny patterns.
- Added a strict JSON parse check to `safety_manifest_selftest.ps1`.
- Updated runtime and report version strings to `3.1.1`.

## v3.1.0 - Advanced Selectors And Relative Locators

- Added UIA selector fields `automation_id`, `class_name`, `role`, and explicit `nth` disambiguation while preserving legacy `index`.
- Added `relative:` selectors for `right_of`, `left_of`, `below`, `above`, and `inside_window`.
- Added `near_text:` selectors using UIA text anchors plus target filters.
- Added `chain:` fallback selector chains with ordered attempt diagnostics, failure reasons, and final hit method.
- Extended selector result JSON with `ok`, `method`, `final_method`, `confidence`, `matched_text`, `matched_name`, `source`, `failure_reason`, and `artifacts.report_path`.
- Updated `run-task` reports to preserve full selector diagnostics on locate failures and fallback chains.
- Extended `selector_selftest.ps1` with automation id, class name, relative locator, near text, nth ambiguity, fallback chain, and run-task report coverage.

## v3.0.5 - Safety Manifest And Consent Layer

- Added `config\safety_manifest.json` as a machine-readable safety boundary for authorized local windows, denied sensitive categories, runtime limits, consent requirements, and audit settings.
- Added `SafetyManifest.h/.cpp` and merged manifest checks with existing `config\safety.conf` without loosening `safety.conf` hard limits.
- Added `winagent.exe safety-report`, `policy-check`, and `consent-check`.
- Added service endpoints `/safety-report`, `/policy-check`, and `/consent-check`, with service audit logging.
- Added manifest status to `version` output.
- Integrated run-task startup policy checks, unrestricted desktop denial, sensitive-category denial, and Safety Manifest summaries in task reports.
- Added `safety_manifest_selftest.ps1`.
- Added `docs\SAFETY_MODEL.md` and synchronized adapter safety guidance with the Safety Manifest boundary.

## v3.0.4 - Benchmark Evidence Pack

- Added `benchmarks\` with benchmark tasks, expected outcomes, and methodology docs.
- Added `benchmark_matrix.ps1` to produce `artifacts\benchmark\benchmark_report.md` and `benchmark_summary.json`.
- Added `benchmark_selftest.ps1` to verify benchmark output, required safe-stop behavior, and evidence export.
- Added `export_evidence_pack.ps1` to create `artifacts\evidence\DesktopVisual-v3.0.4-evidence-pack.zip`.
- Added benchmark metrics for PASS/FAIL/SKIPPED, pass rate excluding skipped, duration, step count, locator method counts, skipped reasons, failure categories, recovery counts, and report completeness.
- Documented that SKIPPED is not PASS and that benchmarks do not prove arbitrary Windows software control.

## v3.0.3 - Agent-Agnostic Adapters

- Added `adapters\codex`, `adapters\claude-code`, `adapters\generic-cli`, and `adapters\shared`.
- Synchronized the Codex adapter under `adapters\codex\win-desktop-agent` while keeping `skill_template\win-desktop-agent` as the legacy compatibility path.
- Added Claude Code instructions and wrapper scripts without assuming Codex Skill support.
- Added a generic CLI agent contract with normalized `ok`, `error_code`, `data`, `artifacts`, and `report_path` fields.
- Added shared adapter rules for task flow, safety, error handling, and report reading.
- Added `adapter_selftest.ps1` to verify adapter structure, shared safety markers, wrapper scripts, and legacy skill template compatibility.

## v3.0.2 - Portable Root And GitHub Hygiene

- Added portable root resolution through `-Root`, `DESKTOPVISUAL_ROOT`, script/exe marker discovery, and legacy `D:\desktopvisual` fallback.
- Added `project_root` to `winagent version`.
- Added `${PROJECT_ROOT}` support in `config\safety.conf` and case paths.
- Added `portable_root_selftest.ps1`.
- Added repository hygiene documentation and stronger `.gitignore` rules for generated artifacts, raw motion data, browser profiles, release archives, and local operator profiles.
- Enhanced `package_source.ps1` to generate `artifacts\release\DesktopVisual-v3.0.2-source.zip` with `SOURCE_PACKAGE_MANIFEST.md`.

## v3.0.1a - Operator Motion Human Calibration Fix

- Required `motion-calibrate --source human|synthetic|sample` so generated profiles cannot omit their origin.
- Isolated synthetic selftest raw data and profiles under `artifacts\motion_profile\synthetic\`; selftests no longer overwrite `config\operator_motion_profile.json`.
- Added `motion_calibration_session.ps1` for guided real operator collection and `motion_human_profile_check.ps1` for validating installed `source=human` profiles.
- Added explicit `--profile` and `--allow-synthetic-profile` test paths for `operator-human`; synthetic/sample profiles are rejected by default.
- Added `MOTION_PROFILE_NOT_HUMAN`, `MOTION_PROFILE_SOURCE_REQUIRED`, and `MOTION_PROFILE_TEST_ONLY` as explicit stop conditions.
- Clarified that synthetic profiles prove the pipeline only and must not be represented as user/operator behavior.

## v3.0.1 - Operator Motion Profile

- Added local operator motion profiling with raw mouse trajectory recording, calibration, profile info, validation, and clearing commands.
- Added `operator-human` move-mode for click, double-click, right-click, scroll, drag, image/text click, selector act, and task.json act steps.
- Added Motion Lab mode to the deterministic TestWindow for guided local recording.
- Added `motion_profile_selftest.ps1` with synthetic raw trajectory samples so CI does not depend on human drawing.
- Added `motion_profile_demo.ps1` for optional interactive collection and profile validation.
- Kept safety invariants: unique target window, SafetyPolicy allowlists, focus verification, exact final cursor target, F12 stop, audit logs, and explicit profile errors.
- Raw trajectories remain under `artifacts\motion_profile\raw`; generated profiles store aggregate statistics rather than full raw traces.

## v3.0.0-public-baseline - Public GitHub Baseline

- Added `.gitignore` for public source control boundaries.
- Added `package_source.ps1` to export a clean public source tree to `D:\desktopvisual_public_export`.
- Added `clean_artifacts.ps1` for dry-run-first generated artifact cleanup.
- Added `public_repo_check.ps1` for public repository readiness checks and size reporting.
- Updated README and docs to clarify Windows-only runtime positioning, safety boundaries, and public artifact exclusions.
- VERSION intentionally remains `3.0.0`; this is a packaging baseline, not a core behavior release.

## v3.0.0 - Windows Computer Use MVP

- Added TaskRunner module with task.json orchestration: observe -> locate -> act -> observe -> verify loop.
- New `run-task --file <task.json> --report <report.md>` CLI command.
- New `POST /run-task` service endpoint.
- FailureClassifier with 12 error categories, each with `can_recover` flag, `recommended_user_action`, and `safe_recovery_actions`.
- Limited recovery: focus retry, reobserve+relocate, UIA fallback for OCR, reobserve+reexpect.
- MVP comprehensive report: Summary, Environment, Step Timeline (with failure classification), Artifacts, Final Recommendation.
- 6 task.json examples: testwindow_basic, notepad_input, calculator_42, edge_local_form, explorer_temp_folder, vscode_edit_save.
- `mvp_selftest.ps1`: 9 checks covering TestWindow, real-app task smoke tests, locator recovery stop, safety denial stop, and window ambiguity stop.
- Windows Computer Use MVP positioning: not official Codex Computer Use, but a closed-loop agent skill/CLI/service platform.
- Known limitations documented: no admin windows, no protected desktop, no self-drawn UI guarantee, OCR environment-dependent.

## v2.3.0 - Local Service Mode (Named Pipe)

- Added `winagent serve` command with named pipe server (`\\.\pipe\DesktopVisualService`).
- Service API endpoints: `/version`, `/observe`, `/locate`, `/act`, `/run-case`, `/run-task`, `/report`, `/shutdown`.
- JSON-over-pipe protocol with UTF-8 transport.
- Optional token authentication (`--token`); without token, only localhost accepted.
- Session state tracking: session_id, request_count, action_count, error_count.
- Service audit log at `D:\desktopvisual\artifacts\service_audit.log`.
- All commands pass through existing SafetyPolicy (no bypass).
- Added `serve_start.ps1`, `serve_stop.ps1`, `serve_selftest.ps1`.
- Selftest: 9/9 endpoints verified with live TestWindow.
- No third-party dependencies, pure Win32 named pipe API.

## v2.2.0 - Codex Skill v2.2

- Rewrote `SKILL.md` with clear agent workflow: startup -> locator priority -> action -> verify -> stop conditions.
- Added 6 new skill helper scripts: `observe-target.ps1`, `locate-target.ps1`, `act-target.ps1`, `run-case-v2.ps1`, `summarize-report.ps1`, `run-dogfood-matrix.ps1`.
- Updated `selftest-skill-template.ps1` to verify all new scripts, references, SKILL.md content, and live agent operations (9 checks).
- Synced all 7 skill references to latest versions.
- Added `docs/AGENT_TASK_EXAMPLES.md` with 6 step-by-step agent task examples (TestWindow, Notepad, Calculator, dogfood matrix, OCR_UNAVAILABLE handling, WINDOW_NOT_UNIQUE handling).
- Updated locator priority to strict ordering: UIA > OCR text > image template > coordinate.
- Documented all 8 stop conditions with required agent actions.
- Updated README with Skill v2.2 section.

## v2.1.0 - Real App Dogfood Matrix

- Added `dogfood/` directory with 5 real Windows application test suites: Notepad, Calculator, Explorer, Edge, VS Code.
- Each app test includes: `README.md`, `*.case`, `run.ps1`, `expected.md`.
- Added unified `dogfood_matrix.ps1` runner with aggregated Markdown report and statistics.
- Notepad: type text, screenshot, save-to-file verification, close without saving.
- Calculator: keyboard input 12+30=42, OCR/UIA result verification.
- Explorer: temp directory file/folder operations with filesystem verification.
- Edge: local HTML page with input field + button + OCR/UIA result verification.
- VS Code: open text file, type, save, file content verification (SKIP if not installed).
- All dogfood operates exclusively in `D:\desktopvisual\artifacts\dogfood\`.
- Safety: no internet access, no real user file manipulation, no login.
- Updated locator strategy in Skill template: UIA > OCR > image > coord.
- Matrix report includes per-app status, reason, duration, locators used, and pass rate.

## v2.0.0 - Real Windows OCR

- Implemented real Windows OCR using WinRT `Windows.Media.Ocr.OcrEngine` via C++/WinRT headers from Windows SDK.
- Added `read-window-text` and `read-region-text` commands returning full text, lines, words with bounding boxes.
- Updated `find-text` with `--match exact|contains`, `--case-sensitive true|false`, and `--index` parameters.
- Updated `click-text` for real OCR-based text clicking with proper LOCATOR_NOT_UNIQUE/LOCATOR_NOT_FOUND.
- Added `wait-text --title --text --timeout-ms --interval-ms` for polling OCR text appearance.
- Added `assert-text-contains --title --text` for OCR-based text assertions.
- Updated Selector `text:` to support `exact`, `index` matching with real OCR.
- Added Case v2 commands: `read_text`, `wait_until text_contains`, `expect text_contains`.
- Dynamic OCR capability reporting in `version` output: `ocr_available`, `ocr_engine`, `ocr_languages`.
- Falls back to `OCR_UNAVAILABLE` when WinRT OCR is not available (compile-time or runtime).
- Added `ocr_selftest.ps1` with SKIPPED logic for OCR-unavailable environments.
- Updated locator priority: UIA first, OCR second, image third, coord last.

## v1.5.0 - Case v2 And Post-Action Verification

- Added Case v2 format with `case_version=2` declaration and key=value parameter syntax.
- Added quoted string support with `\"`, `\\`, and `\n` escape sequences.
- Added variable substitution with `set name="..." value="..."` and `${var}` references.
- Added `wait_until` command for polling conditions: selector, file_contains, and window_title_contains.
- Added `expect` command for assertions: selector_exists, file_contains, and active_window_title_contains.
- Added post-action expect verification on `act` via `expect_selector_exists` and `expect_file_contains_path/text` parameters.
- Added `case_v2` capability to version output.
- Enhanced case reports with case_version, variables summary, wait results, expect results, and observation before/after sections.
- Added 4 new v2 case samples: basic, expect success, expect failure, wait_until.
- Added `case_v2_selftest.ps1` with 10 test cases covering v1 compatibility, v2 basics, variables, wait_until, expect, error handling, and post-action verification.
- Updated Skill template to recommend Case v2 generation workflow.
- v1 .case files continue to work without modification.

## v1.4.0 - Selector Locate And Act

- Added unified selector parsing for `coord`, `uia`, `image`, and `text` selectors.
- Added `locate --title <title> --selector <selector>` and `act --title <title> --selector <selector> --action <action>`.
- Added case commands `locate selector` and `act selector action [text]`.
- Added `selector_selftest.ps1` covering coord, UIA, image, OCR unavailable, not found, not unique, and case workflows.
- Updated agent guidance to prefer `observe`, then `locate/act`, and to stop on locator failures.

## v1.3.0 - Observe Command

- Added `observe --title <substring>` for pre/post-action window observation, including target window metadata, active window, focus state, mouse position, screenshot, UIA tree summary, safety policy summary, and warnings.
- Added case `observe [out_json_path]` and a report `## Observations` section.
- Added `observe_selftest.ps1`.
- Updated agent guidance to use the standard loop: observe, choose locator, act, observe, verify.

## v1.2.0 - Mouse Motion Profiles

- Added unified `instant`, `fast-human`, and `demo-human` mouse motion profiles, with legacy `human` mapped to `demo-human`.
- Added automatic movement duration calculation, bounded explicit durations, Bezier-style human motion, and F12 checks during stepped movement.
- Added motion telemetry fields to mouse action JSON: `move_profile`, `path_type`, `distance_px`, `duration_ms`, `step_count`, and `emergency_stop_checked`.
- Updated typing modes so `fast-human` and `demo-human` use bounded per-character delays and check F12 before each character.
- Added `motion_selftest.ps1`.

## v1.1.0 - Input Primitives

- Added CLI commands: `double-click`, `right-click`, `scroll`, `drag`, `hotkey`, `clipboard-set`, `clipboard-paste`, `focus`, `active-window`, and `mouse-position`.
- Added matching case commands: `double_click`, `right_click`, `scroll`, `drag`, `hotkey`, `clipboard_set`, `clipboard_paste`, and `focus`.
- Preserved v1.0.1 command compatibility while routing all target-window input actions through safety policy and focus verification.
- Added `input_primitives_selftest.ps1`.

## v1.0.1 - Reliability and Safety Patch

- Tightened input focus verification: real input now fails with `WINDOW_FOCUS_FAILED` if the target window is not foreground after activation.
- Added `allowed_read_roots` and `allowed_write_roots` to the local safety policy.
- Enforced read path allowlists for `read-file`, case `read_file`, and case `assert_file_contains`, including `..` traversal rejection.
- Updated `version` capability reporting into `available`, `stub`, and `experimental`; OCR text commands remain stubs with `ocr_available=false`.
- Added focus and safety metadata to input action JSON and case reports.
- Added `focus_selftest.ps1` and `read_path_selftest.ps1`, and included them in `rc_check.ps1`.

## v1.0.0 - Windows Agent Desktop Runtime

- Released DesktopVisual as the first Windows Agent Desktop Runtime.
- Included basic authorized window discovery and window screenshot capture.
- Included real mouse and keyboard input scoped to a uniquely matched target window.
- Included observable `human` mode for cursor movement and text entry.
- Kept unified JSON envelopes, stable error codes, audit logs, and Markdown case reports.
- Included release packaging, release verification, and RC acceptance checks.
- Included Notepad dogfood workflow with explicit skip/failure reporting.
- Included a project-local Codex Skill template for reviewed manual installation.
- Included Windows UI Automation tree, find, click, and type support.
- Included OCR command interfaces and BMP image template location as early locator surfaces.
- Included project-local safety boundaries for title/process allowlists, case limits, and emergency stop.
- Kept the frozen protocol, case format, and safety policy unchanged for the v1.0 publication.

## v0.4.3-rc1 - 1.0 Release Candidate

- Added `rc_check.ps1` as the final pre-1.0 acceptance runner.
- Added `docs\V1_RELEASE_NOTES_DRAFT.md` for the v1.0 release notes draft.
- Updated version output to `0.4.3-rc1`.
- Kept the frozen command protocol unchanged; no commands, service endpoints, or new capabilities were added.
- Tightened safety wording in user-facing docs and Skill references to emphasize authorized testing and developer GUI verification.

## v0.4.2 - Release Freeze

- Froze the pre-1.0 candidate command surface without adding new commands, MCP, HTTP service, or new application scenarios.
- Updated release-facing documentation to version `0.4.2` and clarified the candidate capabilities and current limits.
- Added `verify_release.ps1` to validate the release package layout and packaged `winagent.exe version` output.
- Updated release packaging to include `build.ps1` and the release verification script.
- Kept the v0.1.6 command protocol compatibility boundary intact; no frozen command names, required fields, JSON envelopes, audit log shape, or case report formats changed.

## v0.4.1 - Safety Boundary

- Added `config\safety.conf` for project-local safety policy.
- Added `SafetyPolicy` module and wired title/process whitelist checks into input actions.
- Added `max_steps` and `max_duration_ms` enforcement for `run-case`.
- Added F12 emergency stop checks for human cursor movement and human typing.
- Added `safety_selftest.ps1`.
- Added safety error codes: `SAFETY_POLICY_DENIED`, `EMERGENCY_STOP`, and `CASE_DURATION_LIMIT_EXCEEDED`.
- Updated protocol, safety, case format, limitations, README, changelog, and Skill references.

## v0.4.0 - Real Dev Workflow

- Added `cases\real_dev_workflow.template.case`.
- Added `run_real_dev_workflow.ps1`.
- Added `docs\REAL_DEV_WORKFLOW.md`.
- Default real workflow behavior is SKIPPED until the user approves a target window and project path.
- The workflow does not modify real project code or read unapproved project paths.

## v0.3.3 - Image Template Location

- Added a built-in BMP template matcher without OpenCV or third-party image libraries.
- Added `find-image` and `click-image` commands.
- Added `run_image_demo.ps1`, which generates `assets\click_button.bmp` from a TestWindow screenshot and verifies click count changes.
- Added image template error codes.
- Documented limitations around DPI, scaling, themes, fonts, antialiasing, and dynamic scenes.
- Kept UI Automation as the preferred locator, OCR as second choice, and image templates as a supplemental locator.

## v0.3.2 Safety Freeze

- Added `docs\VISUAL_SAFETY_FREEZE.md` before v0.3.3 image/template work.
- Froze visual locator failure-stop rules for UIA, OCR, and future image/template matching.
- Updated Safety, Agent usage guidance, Skill instructions, and README with visual locator boundaries.
- Added Skill reference copy for the visual safety freeze.
- No new locator or input capability was added.

## v0.3.2 - OCR Text Location

- Added `find-text` and `click-text` command interfaces.
- Added OCR error codes: `OCR_INIT_FAILED`, `OCR_UNAVAILABLE`, `OCR_TEXT_NOT_FOUND`, `OCR_TEXT_NOT_UNIQUE`, and `OCR_FAILED`.
- Added `run_ocr_demo.ps1`, which records `SKIPPED` when OCR is unavailable.
- Documented that Windows native OCR is unavailable in the current build and no third-party OCR library is included.
- Reinforced that OCR must not be used for security-control bypass, credential extraction, or unauthorized workflow automation.

## v0.3.1 - UIA Action

- Added `winagent.exe uia-click --title <title> --name <name>`.
- Added `winagent.exe uia-type --title <title> --name <name> --text <text>`.
- `uia-click` uses `InvokePattern` first, then falls back to element-center real mouse click.
- `uia-type` uses `ValuePattern` first, then falls back to element-center click plus existing text input.
- Added `uia_click` and `uia_type` case commands.
- Added `cases\uia_action.case` and `run_uia_demo.ps1`.
- Updated TestWindow so the edit box can be located as `Input` through UIA value metadata.
- Did not add OCR, image/template matching, MCP, HTTP service, or complex automatic recovery.

## v0.3.0 - UI Automation Tree

- Added read-only Windows UI Automation module using native COM APIs.
- Added `winagent.exe uia-tree --title <title>` for control tree metadata.
- Added `winagent.exe uia-find --title <title> --name <name>` for exact or substring name lookup.
- Added UIA error codes: `UIA_INIT_FAILED`, `UIA_TREE_FAILED`, `UIA_ELEMENT_NOT_FOUND`, and `UIA_ELEMENT_NOT_UNIQUE`.
- Added `uia_selftest.ps1` to verify `Click Me` is visible through UIA and returns a rectangle.
- Updated protocol docs, Skill references, README, and release packaging for v0.3.0.
- Did not add OCR, image/template matching, MCP, HTTP service, automatic recovery, or UIA actions.

## v0.2.3 - Skill Stable Release

- Frozen the v0.2.x Skill template as a stable project-local release artifact.
- Added `docs\SKILL_INSTALLATION.md` with manual install, uninstall, path verification, and safety guidance.
- Updated README with stable Skill usage and selftest instructions.
- Tightened Skill template selftest and release preflight checks for the full template file set.
- Kept Skill installation manual; the project still does not write to global `.agents`, Codex, or user-home directories.

## v0.2.2 - Skill Failure Handling

- Added `run-failure-demo.ps1` to verify expected failure cases without unsafe retries.
- Added `explain-report.ps1` to read failed reports and explain frozen `error_code` values.
- Updated `SKILL.md` with stop-on-failure rules.
- Expanded `docs\AGENT_USAGE_GUIDE.md` with error code guidance, response template, and no-auto-recovery boundaries.
- Updated selftest to run the Skill failure demo and verify explanations for `WINDOW_NOT_FOUND`, `ASSERTION_FAILED`, and `INVALID_ARGUMENT`.

## v0.2.1 - Skill Execution Loop

- Added `cases\skill_basic.case` for Skill smoke testing.
- Added `docs\AGENT_USAGE_GUIDE.md`.
- Added Skill scripts for `run-skill-basic.ps1` and `selftest-skill-template.ps1`.
- Updated `SKILL.md` with the run-case, read-report, summarize, and stop-on-error execution loop.
- Updated selftest to verify Skill template files and optionally run the Skill basic loop.

## v0.2.0 - Skill Template

- Added project-local Codex Skill template under `skill_template\win-desktop-agent`.
- Added Skill scripts for basic demo, visible demo, running a case, and reading the latest report.
- Copied frozen protocol, error code, safety, and case format references into the Skill template.
- Documented manual Skill installation; the project does not write to global `.agents`, Codex, or user-home directories.
- Updated release packaging to include `skill_template`.

## v0.1.6 - Pre-Skill Freeze

- Froze the v0.1 CLI protocol, JSON schema, error codes, audit log format, case format, and report format for v0.2 Skill integration.
- Added `docs\CASE_FORMAT.md`.
- Added `docs\SKILL_INTEGRATION_PLAN.md`.
- Expanded `selftest.ps1` to verify version output, JSON schema, audit log format, case report format, expected case pass/fail behavior, and optional real-app dogfood.
- Made real-app dogfood opt-in for selftest and removed the Notepad `/new` launch argument to avoid `C:\new.txt` prompts on Notepad builds that treat `/new` as a file path.
- Updated release packaging to include scripts, docs, cases, and the full `bin` directory.

## v0.1.5 - Real App Dogfood

- Added `run_dogfood.ps1` for a real Windows Notepad dogfood test.
- Added a configurable dogfood case template and language-specific Notepad case examples.
- Added real-app dogfood artifacts: report plus before/after screenshots.
- Documented real-window limitations around localized titles, DPI, coordinate clicks, and missing OCR/UI Automation.

## v0.1.4 - Release Packaging

- Added `VERSION`.
- Added `winagent.exe version`.
- Added release packaging script.
- Added known limitations and recovery draft docs.
- Prepared `dist\DesktopVisual-v0.1.4` package layout.

## v0.1.3 - Action Trace Consistency

- Unified command JSON envelopes.
- Added stable error codes.
- Standardized audit log lines.
- Standardized case reports.
- Added expected-failure case tests.

## v0.1.2 - Visible Human Mode

- Added visible human cursor movement.
- Added move duration and move step tracing.
- Added human text typing with per-character delay.
- Added `visible_action.case`.

## v0.1.1 - Real Mouse Input Audit

- Confirmed click uses real cursor movement and `SendInput`.
- Added cursor before/after fields.
- Added click action audit details.

## v0.1.0 - Basic Window Control

- Added TestWindow target application.
- Added window find, screenshot, click, press, type, read-file, and run-case foundation.
- Added Markdown reports and basic demo flow.











## v5.9.0-d - Case D Explorer Content Locator Fix

- Fixes only Case D Explorer content-area location for `explorer_open_local_html_via_humanmode_flow`.
- Adds locked foreground Explorer hwnd evidence, content-rect scoped UIA/OCR locator attempts, per-level navigation verification, view normalization, scroll retry, and current-folder incremental search evidence.
- Remains v5; this version does not enter v6.
- Does not introduce VLM.
- Does not change the permission model.
- Does not perform public-release permission narrowing.
- Does not auto git commit.



