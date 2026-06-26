# DesktopVisual Project Control

DesktopVisual project control file.

## Project Identity

- Repository root: `E:\desktopvisualproject\desktopvisual`.
- DesktopVisual is a local Windows desktop Runtime and evidence project.
- AGENTS.md is the long-term control entrypoint only.
- AGENTS.md MUST store durable rules, current version state, trusted evidence pointers, invalidated evidence pointers, roadmap/protocol pointers, and run lifecycle rules.
- AGENTS.md MUST NOT store long version summaries, detailed test reports, full evidence content, long incident reviews, or complete future-version development instructions.
- Long status, reports, and evidence MUST live under `artifacts/dev<version>_<stage>/` or `docs/DEVELOPMENT_STATUS.md`.

## Current Development State

current_trusted_version: 1.1.0
runtime_version: 1.1.0
last_completed_version: 1.1.0
last_completed_status: pass
ready_for_next_version: true
next_planned_version: post_v1_1_0_github_sync_when_user_requests
current_stage: developer_1_1_0_public_permission_agent_efficiency
developer_runtime_ux_optimization: pass
developer_rc_ready: true
public_release_ready: true
developer_full_access_default: true
release_permission_hardening_deferred: false
public_release_hardening_started: true
f12_force_exit_current_task: pass
f12_force_exit_stop_code: STOP_USER_FORCE_EXIT_F12
preflight_validation_hardening: pass
system_stabilization: pass
v6_10_experience_memory: pass
v6_11_workflow_template_batch: pass
v6_12_developer_rc_gate_handoff: pass
v6_12_1_visible_ui_foundation_hardening: pass_input_and_motion
v6_12_1_visible_ui_performance_optimization: pass
desktopvisual_1_0_0_developer_baseline: pass
desktopvisual_1_0_1_runtime_visible_first_launch_and_fallback_discipline: pass
desktopvisual_1_0_2_skill_contract_hardening: pass
desktopvisual_1_0_3_automatic_real_vlm_runtime_bridge: pass
desktopvisual_1_0_3_1_legacy_mock_vlm_quarantine: pass
desktopvisual_1_0_4_vs_cpp_complex_ide_workflow: pass
desktopvisual_1_0_5_capture_ocr_performance_pipeline: pass
desktopvisual_1_1_0_public_permission_agent_efficiency: pass
report_level: compact
evidence_level: full
progress_output: compact
step_chat_detail: compact
artifact_evidence: full

next_version_scope:

- v6.1 series is closed at v6.1.6.
- v6.1.6 accepted based on Case1 QQ Mail fresh machine evidence, bottom-layer StepCompletionGate PASS, and Case2 PyCharm visible UI execution evidence.
- PowerShell full-screen CopyFromScreen is now the default visible UI proof method; PrintWindow and OCR screenshots are auxiliary only.
- Case3/Case4 are deferred and are not current gate blockers.
- Deep self-drawn App UI testing is deferred to the VLM/visual candidate stage.
- v6.2.0 accepted Persistent Runtime Session and Latency Gate work.
- v6.3.0 accepted PlanDraft to StepContract Compiler work.
- v6.4.0 accepted Runtime Task Execution from Compiled Agent Plan.
- v6.5.0 accepted VLM-Assisted Observation Contract.
- v6.6.0 accepted VLM-Assisted Unknown UI Candidate Handling.
- v6.7.0 accepted Explorer Agent Workflows after v6.7.0-rerun blocker repair.
- v6.8.0 preflight validation consistency hardening is PASS; old accepted capabilities use evidence/hash/state consistency checks unless affected source or fingerprint drift requires replay.
- v6.8.0 accepted Browser and Web Form Agent Workflows with local file, localhost, local-safe form fill/submit, long-scroll form, wrong-page recovery, protection/credential STOP, ordinary external read-only diagnostic, verifier-owned evidence, and full regression.
- v6.9.0 accepted Mail / Message / Draft Communication Workflows.
- v6.9.0 system stabilization is PASS and adds evidence consolidation, runtime session lifecycle audit, workflow boundary checking, and system stabilization gate evidence before v6.10.0.
- v6.10.0 accepted Experience Memory and Failure Attribution Integration.
- v6.11.0 accepted Workflow Template Learning and Batch Acceleration.
- v6.11.0 final closure completed and recorded before v6.12.0 branch creation.
- v6.12.0 accepted Developer RC Gate and Handoff. It verifies version integrity, v6.2-v6.11 evidence chain, developer capability matrix, workflow boundaries, developer full-access policy, release-hardening deferral, and handoff package generation.
- v6.12.0 does not implement public-release hardening, user permission-mode UI, task keyword denylist, new workflow behavior, or old UI workflow replay.
- Post-v6 developer preparation adds F12 force-exit for the current task only. It does not close winagent, does not implement public-release policy, and does not add keyword-based release restrictions.
- Post-v6 developer runtime UX optimization adds foreground preparation, activation commands, command aliases, PyCharm developer fast path, and `fast-visible-ui` latency profile in the developer tree only. It does not modify public-release safety policy or generate a public release package.
- v6.12.1 hardens the visible UI execution foundation in `D:\desktopvisual` with global DPI-aware screenshots, target window lock, coordinate mapping, foreground preempt, real-keyboard visible text input policy, `line_by_line_keyboard` and `code_editor_keyboard` first-pass multiline input, Runtime-validated VLM candidate bridge, deterministic action batches, global-frame final verification policy, bottom-right visible Show Desktop default, Alt+Tab default window switching, and 165Hz best-effort HumanMode motion pacing evidence. It does not inspect or modify release/public-dist paths.
- v6.12.1 visible UI performance optimization adds cached foreground preempt/target lock/global frame paths, fast-real-keyboard structured input, deterministic action batch performance evidence, 165Hz motion pacer validation, and real PyCharm current `main.py` visible UI performance acceptance under `artifacts/dev6.12.1_performance_optimization/`. It preserves visible-first behavior and does not inspect or modify release/public-dist paths.
- DesktopVisual 1.0.0 freezes the developer tree as the public developer baseline while preserving the internal v6.12.1 lineage.
- DesktopVisual 1.0.1 adds Runtime-only visible-app-launch desktop-first launch and stricter fallback discipline in `D:\desktopvisual`. It does not strengthen Skill contracts, connect real VLM providers, implement complex IDE workflows, redefine PUBLIC_DEFAULT, modify release/public-dist paths, or generate a release package.
- DesktopVisual 1.0.2 hardens the source-of-truth Skill contract, Codex adapter Skill contract, shared adapter rules, and contract selftests for the v1.0.1 Runtime visible-first launch/fallback discipline. It does not expand Runtime behavior beyond version metadata sync, connect real VLM providers, implement complex IDE workflows, redefine PUBLIC_DEFAULT, modify release/public-dist paths, or generate a release package.
- DesktopVisual 1.0.3 adds provider-gated real Codex CLI VLM assist with session capability cache, strict JSON output, Runtime candidate validation, coordinate/evidence binding, visible fallback evidence integration, and Skill contract synchronization. VLM remains assistive only and does not execute actions, decide backend fallback, run every step, or bypass active protection.
- DesktopVisual 1.0.3.1 quarantines legacy mock VLM commands as deprecated opt-in test fixtures, hardens real VLM command schema/reporting, and makes VLM locate-only action boundaries explicit. Normal VLM use goes through `RealVlmRuntimeBridge`, `vlm-capability-probe`, `vlm-assist-locate`, `vlm-candidate-validate`, and `tools\codex_vlm_provider.ps1`.
- DesktopVisual 1.0.4 accepted the Visual Studio C++ Complex IDE Human-Like Workflow and preserved visible-first Runtime action semantics.
- DesktopVisual 1.0.5 accepts the Full-screen Capture/OCR Performance Pipeline: full-screen frame registry, memory-frame OCR, foreground/window crop OCR from the same frame, async PNG evidence flush barrier, OCR cache/tile hash cache, and frame-bound VLM image transport. Public profile alignment is completed later in v1.1.0.
- DesktopVisual 1.1.0 aligns public release ordinary visible desktop capability with developer ordinary capability, preserves active-protection/security STOP boundaries, adds compact progress/full evidence policy, and syncs release/public-dist trees. GitHub sync is not performed by this version task.
- Next planned stage is GitHub sync only if the user explicitly requests it.

compact_output_policy:

- Default chat output is compact progress while artifacts keep full evidence.
- Failure output expands and must include error, evidence, and next repair.
- compact output must not hide failures.
- Use read-once context with `agent_context_digest.md`; do not repeatedly reread full documents as a default workflow.
- Search narrowly and do not scan artifacts, `.git`, `bin`, or `obj` unless a verifier explicitly requires it.

valid_evidence_index:

- artifacts/dev5.10.1_real_ui_adaptive_cases/evidence_index.md
- artifacts/dev5.10.2_real_taskruntime_final_gate/evidence_index.md
- artifacts/dev6.0.0_agent_boundary/evidence_index.md
- artifacts/dev6.1.1_humanmode_regression_triage_and_evidence_gate/evidence_index.md
- artifacts/dev6.1.2_real_ui_baseline_sanity_pre_v6_2_gate/evidence_index.md
- artifacts/dev6.1.3_mouse_wheel_scroll_and_scroll_locate/evidence_index.md
- artifacts/dev6.1.4_runtime_guard_browser_stabilization/evidence_index.md
- artifacts/dev6.1.5_safe_context_recovery_dynamic_diagnostics/evidence_index.md
- artifacts/dev6.1.5a_visible_mouse_first_interaction/evidence_index.md
- artifacts/dev6.1.6_scope_reset_step_completion_closure/evidence_index.md
- artifacts/dev6.2.0_persistent_runtime_session_latency_gate/evidence_index.md
- artifacts/dev6.3.0_plan_draft_to_step_contract_compiler/evidence_index.md
- artifacts/dev6.4.0_runtime_task_execution_from_compiled_agent_plan/evidence_index.md
- artifacts/dev6.5.0_vlm_assisted_observation_contract/evidence_index.md
- artifacts/dev6.6.0_vlm_assisted_unknown_ui_candidate_handling/evidence_index.md
- artifacts/dev6.7.0_explorer_agent_workflows_rerun/evidence_index.md
- artifacts/dev6.8.0_preflight_validation_consistency_hardening/evidence_index.md
- artifacts/dev6.8.0_browser_and_web_form_agent_workflows/evidence_index.md
- artifacts/dev6.9.0_communication_workflow/evidence_index.md
- artifacts/dev6.9.0_system_stabilization/evidence_index.md
- artifacts/dev6.10.0_experience_memory_failure_attribution/evidence_index.md
- artifacts/dev6.11.0_workflow_template_learning_batch_acceleration/evidence_index.md
- artifacts/dev6.11.0_final_closure/evidence_index.md
- artifacts/dev6.12.0_rc_gate_and_handoff/evidence_index.md
- artifacts/dev6.12.1_performance_optimization/evidence_index.md
- artifacts/dev6.12.1_visible_ui_foundation_hardening/evidence_index.md
- artifacts/dev1.0.1_runtime_visible_first_launch_and_fallback_discipline/evidence_index.md
- artifacts/dev1.0.2_skill_contract_hardening/evidence_index.md
- artifacts/dev1.0.3_automatic_real_vlm_runtime_bridge/evidence_index.md
- artifacts/dev1.0.3.1_legacy_mock_vlm_quarantine/evidence_index.md
- artifacts/dev1.0.4_vs_cpp_complex_ide_workflow/evidence_index.md
- artifacts/dev1.0.5_capture_ocr_performance_pipeline/evidence_index.md

handoff_report:

- artifacts/dev6.12.0_rc_gate_and_handoff/final_status_report.md

test_summary:

- artifacts/dev1.0.5_capture_ocr_performance_pipeline/test_summary.md

interrupted_attempt_report:

- artifacts/dev6.1.4_dynamic_app_web_click_accuracy/INTERRUPTED_FALSE_POSITIVE_DO_NOT_USE_AS_PASS.md

blocked_evidence_index:

- artifacts/dev6.1.4_dynamic_app_web_click_accuracy_state_guard/evidence_index.md
- artifacts/dev6.7.0_explorer_agent_workflows/evidence_index.md

blocking_report:

- artifacts/dev6.1.4_dynamic_app_web_click_accuracy_state_guard/blocking_report.md

invalidated_evidence_index:

- artifacts/invalidation_index.md

invalidated_evidence_root:

- artifacts/invalidated/

known_limits_doc:

- docs/KNOWN_LIMITATIONS.md

roadmap_doc:

- docs/ROADMAP.md

command_protocol_doc:

- COMMAND_PROTOCOL.md

development_status_doc:

- docs/DEVELOPMENT_STATUS.md

development_protocol_doc:

- docs/DEVELOPMENT_PROTOCOL.md

## Mandatory Run Initialization

Every development run MUST reload AGENTS.md from disk.

This applies even if:

- the same Codex window is still open;
- the same chat session continues;
- the previous version was completed moments ago;
- the model claims it remembers the rules.

Conversation memory is never sufficient.

Before any implementation, code edit, documentation edit, or test execution, the agent MUST:

1. Read AGENTS.md from disk.
2. Read VERSION.
3. Read CHANGELOG.md.
4. Read COMMAND_PROTOCOL.md.
5. Read docs/ROADMAP.md.
6. Read docs/KNOWN_LIMITATIONS.md.
7. Read every file pointer listed in Current Development State if it exists.
8. Scan the real project file tree.
9. Generate this run's `agent_context_digest.md` under the current version artifact directory.
10. Only after the digest exists begin the current version request.

Every run MUST generate:

`artifacts/dev<target_version>_<stage>/agent_context_digest.md`

The digest MUST include:

- AGENTS.md read: yes/no
- AGENTS.md path
- read timestamp
- VERSION read: yes/no
- current_trusted_version
- last_completed_version
- ready_for_next_version
- next_planned_version
- this_run_target_version
- current user request summary
- loaded non-negotiable rules
- loaded evidence integrity rules
- loaded file discovery rules
- loaded testing rules
- loaded Runtime/VLM boundary rules
- loaded HumanMode rules
- loaded Safety/Permission rules
- valid evidence pointers checked
- invalidated evidence pointers checked
- missing pointers, if any
- replacement files, if any
- conflicts between AGENTS.md and current prompt, if any

If `agent_context_digest.md` is not generated:

- MUST NOT begin development;
- MUST NOT modify source;
- MUST NOT modify documentation;
- MUST NOT run implementation;
- MUST NOT output a completion report.

If AGENTS.md conflicts with the current user instruction, the agent MUST STOP, report the conflict, and MUST NOT choose one side silently.

## Real File Discovery Rule

The agent MUST NOT assume file paths exist.

Before editing any file, the agent MUST confirm the file exists.

If a requested file does not exist:

1. Search the project tree for equivalent files.
2. Search by semantic role and filename keywords.
3. Report the missing file and candidate replacement.
4. Use a replacement only if it satisfies the same architectural purpose.
5. Create a new file only when no suitable file exists and the feature requires a new component.
6. Explain why the new file is necessary.

Every development report MUST include a file discovery section:

- requested files
- existing files
- missing files
- replacements used
- new files created
- reason for every replacement or new file

FORBIDDEN:

- editing an assumed path;
- referencing nonexistent files in AGENTS.md;
- silently using a replacement file;
- silently creating new files;
- treating file existence checks as optional.

## Evidence Integrity Rule

Runner MUST NOT self-certify PASS.

Final PASS must come from an independent verifier, selftest, or explicitly audited validation path.

Synthetic, mock, diagnostic, or placeholder evidence MUST NOT be counted as real PASS.

## Screen Evidence Capture Rule

For visible desktop screenshot evidence, PowerShell full-screen `System.Drawing.Graphics.CopyFromScreen` capture is the default first-choice method after the target application is restored to a visible foreground position. This captures the actually visible desktop state and avoids `PrintWindow` gaps with custom-rendered or partially clipped application surfaces.

`winagent.exe screenshot --title ...` / `PrintWindow` remains allowed as a secondary or diagnostic capture method, but it MUST NOT override a conflicting PowerShell full-screen screenshot when judging visible UI state. If PowerShell full-screen capture is unavailable, blocked, or captures the wrong foreground because another window, widget, notification, protected desktop, or overlay covers the target, the evidence must record that condition and re-establish the target foreground before recapture.

The following MUST NOT be treated as real PASS:

- synthetic trace
- placeholder screenshot
- hardcoded hwnd
- hardcoded rect
- generated action_trace without real command output
- generated locator_trace without real observe/locate evidence
- generated HumanActionResult without real input action
- mock provider result
- diagnostic-only result
- file-existence-only check
- documentation-only check
- NOT_RUN
- SKIP
- SKIP_ENVIRONMENT
- NOT_IMPLEMENTED
- PARTIAL

If a test is skipped, it is SKIP, not PASS.
If a feature is not implemented, it is NOT_IMPLEMENTED, not PASS.
If evidence is missing, result MUST be FAIL_EVIDENCE_MISSING.
If validation is inconclusive, result MUST be INCONCLUSIVE, not PASS.

Every version MUST include:

- evidence_index.md
- test_summary.md
- verifier_report.md or equivalent selftest report
- explicit fake-pass scan result if applicable

FORBIDDEN:

- final result decided by the same runner that generated the evidence;
- writing ready_for_next_version=true without tests/verifier;
- writing ready_for_v6=true or equivalent handoff flag without final gate evidence;
- hiding failed tests in long reports;
- calling a version complete when required features are partial.

## Complete Implementation Rule

Every explicitly requested feature MUST be fully implemented or explicitly reported as NOT_IMPLEMENTED with reason.

A feature is not complete unless:

1. code/config/docs are updated as required;
2. command/API/schema integration exists if applicable;
3. tests exist;
4. local targeted test passes;
5. version-level regression does not break existing behavior;
6. artifacts record the result.

FORBIDDEN:

- implementing only schema without required command integration;
- implementing only docs without code when functionality is requested;
- implementing only happy path when error handling is required;
- leaving TODO as completion;
- hiding partial implementation behind vague wording;
- declaring the version complete when any required feature is missing.

Every final report MUST include:

- completed features
- incomplete features
- features not implemented
- blockers
- tests proving each completed feature

## Per-Feature and Version-Level Testing Rule

If a version contains multiple features, each feature MUST have a targeted local test immediately after implementation.

Required sequence:

1. Implement feature A.
2. Run targeted test for feature A.
3. Record result.
4. Implement feature B.
5. Run targeted test for feature B.
6. Record result.
7. Continue for all features.
8. Run full version-level tests after all features are complete.

Version-level tests MUST include:

- build
- version
- relevant command/API tests
- positive tests
- negative tests
- malformed input tests
- boundary tests
- regression tests for old trusted features
- JSON/JSONL parse tests where applicable
- Markdown fence validation
- encoding/mojibake scan
- COMMAND_PROTOCOL consistency
- evidence integrity scan where applicable
- git status snapshot

Testing MUST NOT be overfitted to the implementation.

FORBIDDEN:

- testing only the exact happy path written for the code;
- treating file existence as functional validation;
- testing only docs parse;
- omitting negative tests;
- skipping global tests after multi-feature development;
- writing PASS without command output or verifier result;
- using old invalidated evidence as current evidence.

If a test cannot run due to environment, record SKIP_ENVIRONMENT with reason, do not mark PASS, and assess whether it is blocking.

## Runtime / VLM Boundary Rule

DesktopVisual v6 has two execution modes:

1. Runtime Mode
2. VLM-Assisted Mode

Runtime Mode:

- uses local Runtime capabilities;
- uses UIA/OCR/screenshot/observe/adaptive locate/HumanMode;
- works for known apps, known pages, local workflows, Explorer workflows, browser form templates, and structured repeated tasks;
- does not require VLM.

VLM-Assisted Mode:

- uses external Agent/VLM reasoning for unknown or visually complex screens;
- VLM may interpret screenshots, propose semantic targets, explain failures, and help planning;
- VLM MUST NOT directly execute desktop actions.

Non-negotiable boundary:

- Runtime is the only action executor.
- VLM/LLM/Agent may plan, explain, classify, or propose.
- Real click/type/drag/scroll/hotkey MUST go through Runtime StepContract or equivalent Runtime command path.
- Agent plans MUST compile to StepContract or equivalent Runtime-executable contract before execution.
- No direct DOM/JS/WebDriver/CDP action may be counted as HumanMode Runtime action.
- Provider/API key/account UI is not required for developer version unless explicitly requested later.

## HumanMode Rule

HumanMode MUST NOT be weakened for speed.

FORBIDDEN latency optimizations:

- instant mouse teleport replacing HumanMode;
- removing visible mouse movement;
- removing dwell/click settle verification;
- replacing HumanMode action with backend action;
- replacing HumanMode typing with DOM/JS/UIA ValuePattern as real action;
- removing evidence integrity to improve speed.

Allowed latency optimizations:

- persistent Runtime session;
- reduced process roundtrips;
- hwnd-targeted commands;
- observe/UIA/screenshot cache;
- locator candidate cache;
- task-level batching;
- act-and-verify primitive;
- context-menu primitive;
- better scheduling;
- avoiding repeated full observe when cache is valid.

Current latency is a known limit, not a blocker, unless it causes:

- task failure;
- timeout;
- UI state expiration;
- VLM cost explosion;
- unacceptable task runtime for v6 workflows.

## Safety and Permission Rule

Developer mode MUST remain capability-discovery oriented.

File and dependency boundaries:

- File writes MUST stay under `D:\desktopvisual`, except `D:\testrepo\testwindow` for test-window work, unless the user explicitly approves another path.
- Use Windows native APIs and the Visual Studio C++ toolchain unless the user explicitly approves otherwise.
- MUST NOT download dependencies or use package managers unless explicitly approved.
- MUST NOT add model weights, VLM providers, cloud inference paths, browser profiles, cookies, tokens, API keys, or real user data to the project tree.

Ordinary development/test content MUST NOT be blocked solely because it contains words like:

- test
- exam
- assessment
- challenge
- mail
- submit
- problem
- localhost
- local HTML
- ordinary web

Active protection MUST STOP:

- CAPTCHA
- reCAPTCHA
- hCaptcha
- Turnstile
- human verification
- bot challenge
- automation detected
- script detected
- anti-cheat
- BEService.exe
- EasyAntiCheat
- BattlEye
- Vanguard
- vgc.exe
- lockdown browser
- secure exam browser
- active proctoring

FORBIDDEN:

- bypassing active protection;
- weakening active protection STOP;
- adding broad keyword blocks that prevent ordinary developer testing;
- requiring FULL_ACCESS for basic local/known Runtime tasks unless truly necessary.

## Version State Update Rule

At the end of every version, AGENTS.md Current Development State MUST be updated.

The update MUST include:

- current_trusted_version
- last_completed_version
- last_completed_status
- ready_for_next_version
- next_planned_version
- valid_evidence_index
- handoff_report or test_summary path
- blocking_report if blocked
- known_limits_doc pointer if changed

AGENTS.md MUST NOT include long version summaries.
Long summaries belong in artifacts or `docs/DEVELOPMENT_STATUS.md`.

Version advancement rules:

- current_trusted_version may advance only after required tests/verifiers pass.
- ready_for_next_version may be true only if no blocker remains.
- if the version fails or is partial, ready_for_next_version must be false.
- if blocked, next_planned_version must be a hotfix/retry version, not the next major stage.
- invalidated versions must not be used as valid evidence.

Example if v6.0.0 passes:

- current_trusted_version: 6.0.0
- last_completed_version: 6.0.0
- last_completed_status: accepted
- ready_for_next_version: true
- next_planned_version: 6.1.0

Example if v6.0.0 fails:

- current_trusted_version: 5.10.2
- last_completed_version: 6.0.0
- last_completed_status: blocked
- ready_for_next_version: false
- next_planned_version: 6.0.1
- blocking_report: `artifacts/dev6.0.0_<stage>/blocking_report.md`

## Known Limits Pointers

- Primary known limits: `docs/KNOWN_LIMITATIONS.md`
- Runtime latency known limit MUST be recorded in `docs/KNOWN_LIMITATIONS.md`.
- AGENTS.md MUST keep only known-limit pointers, not long known-limit summaries.

## Roadmap and Protocol Pointers

- Roadmap: `docs/ROADMAP.md`
- Command protocol: `COMMAND_PROTOCOL.md`
- Development protocol: `docs/DEVELOPMENT_PROTOCOL.md`
- Development status: `docs/DEVELOPMENT_STATUS.md`
- Evidence indexes and handoff reports are listed only in Current Development State.
- All AGENTS.md pointer paths MUST exist before `ready_for_next_version: true`.

## Prohibited Behaviors

FORBIDDEN:

- entering v6.0.0 feature development during a non-v6 preparation stage;
- modifying Runtime action logic without explicit request;
- modifying HumanMode behavior without explicit request;
- weakening active protection STOP;
- public release slimming during internal Runtime governance stages;
- deleting valid evidence;
- deleting invalidated evidence;
- writing long version summaries into AGENTS.md;
- referencing nonexistent paths in AGENTS.md;
- using invalidated evidence as valid evidence;
- setting ready_for_next_version=true when VERSION, pointers, and evidence are inconsistent;
- auto committing;
- using git reset --hard unless explicitly requested;
- reporting failed documentation checks as PASS;
- claiming files were read without reading from disk;
- skipping `agent_context_digest.md`.

## Final Output Requirements for Every Development Run

Every final output MUST include:

- current version
- stage objective
- actual modified files
- completed features
- incomplete features
- features not implemented
- blockers
- file discovery summary
- AGENTS.md Current Development State summary
- pointer validation result
- evidence pointer check result
- known limits update result when applicable
- build/version smoke result when applicable
- whether v6 development was entered
- whether the next version may start
- artifacts path
- git status summary
