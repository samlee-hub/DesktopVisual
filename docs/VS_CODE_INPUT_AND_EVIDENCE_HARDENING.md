# DesktopVisual v1.1.10 VS Code Input And Evidence Hardening

Current version: `v1.1.10`.

This document defines the v1.1.10 development scope for VS Code input, Visual Studio selector disambiguation/miss evidence, event timeline accuracy, command discovery separation, first-action proxy reporting, and code-input integrity closure. It applies only to the developer tree `E:\desktopvisualproject\desktopvisual`.

## v1.1.8 Field Test Findings

The v1.1.8 Visual Studio C++ projectdd field test passed functionally, including project creation, multi-file C++ code entry, build, and run. It also exposed reliability and evidence accuracy problems:

- Large C++ payloads passed through PowerShell/argv could lose string-literal quotes before reaching Runtime.
- C++ code structure checks produced false positives for legal `main.cpp`, helper functions, template vectors, braces, strings, and control-flow blocks.
- Recovery typing could corrupt brace structure and make the first build fail even though the intended source was valid.
- Visual Studio UIA selectors could match more than one tab, editor surface, Solution Explorer node, dialog target, rename box, or output/build target.
- Outer action timeline evidence could report illegal overlaps, including save actions appearing before typing actions completed.
- Wait saved summaries could double-count summary and detail rows and mix core waits with workflow waits.
- Wrapper errors such as a missing runtime subcommand were not clearly separated from Runtime GUI failures.

## v1.1.9 Scope

v1.1.9 is a targeted hardening release. It may change:

- Code input payload transport into Runtime.
- C++ code input validation and typing planning.
- Visible keyboard fallback metadata.
- Visual Studio selector disambiguation evidence.
- Event timeline v2 fixture/report schema.
- Wait saved de-duplication fixture/report schema.
- Failure classification and wrapper failure attribution.
- Selftests, field-test replay helpers, documentation, and development evidence.

It does not sync `desktop_release`, create a public restricted release, create public-dist, enter v1.2.0, reduce permissions, change PermissionManager semantics, change VLM behavior, or change VLM timeout.

## v1.1.10 Repeat Field Test Residuals

The v1.1.9 repeat Visual Studio C++ projectdd field test passed functionally but left closure blockers:

- code-input corruption count: 4
- target lock failures: present
- timeline obvious overlap count: 2
- command discovery `INVALID_ARGUMENT` failures counted too close to action failures
- `LOCATOR_NOT_UNIQUE` count: 3
- `LOCATOR_NOT_FOUND` count: 3
- first visible action proxy chain partially unavailable

v1.1.10 targets those residuals only. It does not sync `desktop_release`, run a full repeat field test, enter v1.2.0, create public-dist, create a public restricted release, reduce permissions, change PermissionManager semantics, change VLM lazy/cache/degrade behavior, or change VLM timeout.

## v1.1.10 Real Payload Regression

Real v1.1.9 repeat projectdd payloads are stored under `tests\fixtures\vs_projectdd_v119_repeat_payloads\`:

- `GridPathSolver.h.txt`
- `GridPathSolver.cpp.txt`
- `KnapsackPlanner.h.txt`
- `KnapsackPlanner.cpp.txt`
- `main.cpp.txt`

The payloads come from the v1.1.9 repeat field-test `project_snapshot` evidence. The requested `project_snapshot\projectdd\` subdirectory was not present, so the files were copied from the actual snapshot root and recorded in the v1.1.10 evidence. These fixtures must pass pre-input validation without false positives for `main.cpp`, nested functions, `std::vector<std::vector<int>>`, string literals, unmatched braces, function declaration parentheses, struct/class structure, or `#pragma once`.

## Keyboard-Safe Segmentation

Every `visible-text-input` code path now emits `keyboard_safe_segmentation`. Segments are formed on balanced logical boundaries using delimiter accounting that ignores C/C++ string literals, character literals, line comments, and block comments. Template angle brackets such as `std::vector<std::vector<int>>` are preserved as template text, not delimiter nesting.

Each segmentation report includes:

- per-file segment count
- segment risk level
- delimiter balance
- segmentation reason
- chosen typing mode
- clipboard paste and direct file write fallback flags

High-risk or medium-risk code segments prefer `line_by_line_visible_keyboard` over risky structured bulk entry. The payload may enter Runtime through UTF-8 `--text-file`, but final source entry remains Visual Studio editor keyboard input.

## Target Lock Preflight

Every visible text input result now emits `target_lock_preflight`. The preflight records active window/title evidence when available, expected Visual Studio window/process, active document, expected file, editor presence/focusability, caret or text insertion target status, project context, and readback availability.

If target lock fails, Runtime performs a bounded retry path before typing:

1. reobserve/reacquire target context
2. refocus through the existing target lock path
3. verify active document or expected file when available
4. retry target preflight
5. record unresolved target lock failure if still blocked

The v1.1.10 fixture target is `target_lock_failure_count = 0` and records recovery and unresolved counts separately.

## Code-Input Integrity v2

Every code-input result now emits `code_input_integrity_v2`. At minimum it records the intended payload hash, observed hash when available, marker checks, delimiter/structure checks, per-file corruption count, retry count, and explicit unavailability reasons when live editor readback is not available.

The v1.1.10 fixture report requires:

- real payload corruption count = 0
- `main.cpp` false-positive count = 0
- `std::vector<std::vector<int>>` false-positive count = 0
- function declaration parenthesis corruption count = 0
- struct/class corruption count = 0
- header guard / `#pragma once` false-positive count = 0

If live verification fails in a real workflow, recovery must use visible keyboard retry/rewrite. Direct file write fallback and clipboard paste remain non-default and disallowed for PASS evidence.

## Event Timeline v2.1

`event_timeline.v2.1` separates synchronous `action` events from parallel `observation` and `logging` events. Synchronous action `started_ts` values must not precede the previous synchronous action `completed_ts`. Observation and logging events must declare relation fields such as `parallel_child_of` or `async_evidence_write` instead of being counted as action overlap.

v2.1 requires:

- `timestamp_precision_ms`
- explicit `timestamp_inferred`
- explicit unavailable timestamps instead of reconstructed fake values
- `timeline_overlap_count`
- `typing_save_overlap_count`
- `inferred_timestamp_count`
- `unavailable_timestamp_count`

The v1.1.10 no-overlap fixture count is 0.

## Command Discovery Separation

Command discovery is not a user-visible action. It must use a safe explicit command list or version/help introspection and must not send an empty command. Any discovery-side `INVALID_ARGUMENT` is classified as `command_discovery_failure` or wrapper/test-harness failure, not Runtime GUI action failure.

The v1.1.10 command discovery report records:

- `invalid_argument_count`
- `invalid_argument_action_failure_count`
- `command_discovery_failure_count`
- `runner_wrapper_failure_count`
- whether empty command probing was used

The v1.1.10 fixture requires `invalid_argument_action_failure_count = 0` and `runner_wrapper_failure_count = 0`.

## Locator Disambiguation And Miss Evidence

Visual Studio locator reports now separate ambiguity and miss handling. Disambiguation reports include matched count, chosen reason, active document, project context, expected file, fallback selector, and ambiguity remaining. Miss reports include miss reason, reobserve count, recovery result, active document, project context, expected file, fallback selector, and evidence presence.

The v1.1.10 target is to keep `LOCATOR_NOT_UNIQUE <= 1` in the repeat field-test scenario and to make each `LOCATOR_NOT_FOUND` miss explainable.

## First-Action Proxy Chain

v1.1.10 does not claim hidden Codex reasoning timestamps. It records the observable proxy chain:

- `user_instruction_received_ts`, or `unavailable`
- `field_test_instruction_start_ts`
- `first_runtime_command_issued_ts`
- `first_runtime_command_completed_ts`
- `first_visible_action_proxy_ts`
- `proxy_first_visible_action_latency_ms`
- unavailable reason

The proxy chain is evidence clarity only; it does not change VLM behavior, VLM timeout, permissions, or Runtime safety policy.

## C++ Code-Input Hardening

Runtime accepts a UTF-8 `--text-file` payload for `visible-text-input`. This file is only a request payload into Runtime; source code is still entered through the Visual Studio editor using visible keyboard input. The payload path prevents shell/argv quote escaping from changing string literals before the visible typing policy sees the text.

The C++ validator now strips non-structural text from C-style languages before structural checks:

- String literals and escaped quotes.
- Character literals.
- Line comments.
- Block comments.

Brace, bracket, parenthesis, function, `main`, and block checks run against structural text while reports still reference the original line content. Legal `std::vector<std::vector<int>>`, `if/else`, `for`, class/struct methods, namespace-level helpers, `main`, and return statements must validate. Lambdas are recognized as lambda expressions; if a future validator cannot fully support a lambda form, it must report unsupported lambda syntax rather than a nested-function false positive.

## Visible Keyboard Fallback Ladder

Code input fallback levels are reported as:

1. Structured visible keyboard typing.
2. Line-by-line visible keyboard typing.
3. Raw visible keyboard typing after focus/buffer verification.
4. Retry after reobserve/refocus.
5. STOP or require explicit user fallback permission.

Each code input result records:

- `fallback_ladder`
- `fallback_level`
- `fallback_reason`
- `previous_failure`
- `allowed_by_policy`
- `code_integrity_check_before`
- `code_integrity_check_after`

Clipboard paste and direct file write are not default fallback paths. `.vcxproj` editing is not a code input fallback path.

## VS Selector Disambiguation

Visual Studio selector reports must carry enough context to explain a choice when multiple UIA elements match:

- `selector`
- `matched_count`
- `chosen_element_name`
- `chosen_control_type`
- `chosen_bounding_box`
- `active_window_title`
- `active_document_name`
- `project_name`
- `expected_file_name`
- `disambiguation_reason`
- `fallback_selector_used`
- `ambiguity_remaining`

The v1.1.9 fixture covers active document tabs, editor pane selection, Solution Explorer file nodes, Add New Item dialog targets, rename text boxes, Output/Build windows, and Build/Run command targets at the report-schema level. Real VS field validation remains a post-sync repeat field test.

## Event Timeline Schema v2

`event_timeline.v2` records action and logging events separately. Each event includes:

- `event_id`
- `parent_event_id`
- `sequence_id`
- `monotonic_index`
- `event_type`
- `action_id`
- `runtime_command_id`
- `issued_ts`
- `started_ts`
- `completed_ts`
- `duration_ms`
- `source`
- `target`
- `success`
- `failure_class`
- `evidence_path`

For synchronous commands, the next action must not start before the previous action completes. Logging-only events use `event_type=logging`. Unmeasurable fields are explicitly `unavailable`; v1.1.9 must not invent timestamps for Codex thinking, failure analysis, or next execution gaps when the wrapper cannot measure them.

## Wait Saved Deduplication

Wait saved accounting is keyed by wait event and action identity instead of regex totals. Each row records:

- `wait_event_id`
- `action_id`
- `wait_site`
- `wait_kind`
- `replaced_from_sleep_ms`
- `actual_wait_ms`
- `saved_ms`
- `unique_counted`
- `duplicate_of`
- `aggregation_source`

Aggregates include:

- `unique_wait_saved_ms`
- `core_wait_saved_ms`
- `workflow_wait_saved_ms`
- `summary_wait_saved_ms`
- `detail_wait_saved_ms`
- `duplicate_wait_saved_ms`
- `wait_deduplication_report`

The final saved total must use de-duplicated events. Summary and detail totals must not be added together as final saved time.

## Failure Classification

The hardening path recognizes these failure classes:

- `runtime_gui_failure`
- `code_input_policy_failure`
- `selector_ambiguity_failure`
- `command_discovery_failure`
- `runner_wrapper_failure`
- `codex_orchestration_failure`
- `test_harness_failure`
- `environment_failure`
- `user_visible_stop_condition`
- `build_compile_failure`
- `program_correctness_failure`

Missing command, empty runtime subcommand, wrapper variable error, command-not-found, and PowerShell parameter binding failures are classified as `runner_wrapper_failure`, not Runtime GUI failure. Command discovery/probing failures are classified as `command_discovery_failure` and do not enter user-visible action failure counts.

## Non-Goals

- No permission reduction.
- No PermissionManager semantic change.
- No safety manifest or safety.conf permission semantic change.
- No public restricted release.
- No public-dist tree.
- No v1.2.0 work.
- No `desktop_release` sync during development.
- No clipboard paste default.
- No direct file write default fallback.
- No Visual Studio UI bypass for code input.
- No VLM behavior or timeout change.
- No removal of v1.1.8 evidence.

## Repeat Field Test Criteria

After v1.1.10 development acceptance and only after explicit future user approval to sync `desktop_release`, a repeat Visual Studio C++ projectdd field test should verify:

- No Runtime code-input policy corruption of C++ quote, brace, vector, template, `main`, or helper-function structure.
- First build does not fail because Runtime transformed valid C++ input into invalid source.
- `UIA_ELEMENT_NOT_UNIQUE` is reduced, and remaining ambiguity has a selector disambiguation report.
- Action timeline has no obvious illegal serial action overlap.
- Unmeasurable outer timing fields are explicitly unavailable.
- Wait saved totals use de-duplicated unique event accounting.
- Wrapper/test harness and command discovery failures are not counted as Runtime GUI failures.
