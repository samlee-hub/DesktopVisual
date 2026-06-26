# WinAgent Command Protocol

Current trusted version: `DesktopVisual 1.1.0`.
Current active development stage: `DesktopVisual 1.1.0 Public Release Permission Alignment, Agent Efficiency, and Release Tree Sync`.
Next planned stage: `post-v1.1.0 GitHub sync on explicit user request`.

## DesktopVisual 1.1.0 Public Permission And Report-Level Protocol

`PUBLIC_DEFAULT` now allows ordinary visible desktop operations without requiring a legacy FULL_ACCESS session: ordinary visible desktop action, third-party app, browser, https, localhost, Explorer/file manager, local file open, cross-window visible workflow, global desktop visible workflow, and validated absolute screen coordinate action.

`PUBLIC_DEFAULT` must not stop merely because a page or title contains broad words such as test, exam, challenge, submit, assessment, ordinary app, ordinary webpage, localhost, IDE, browser, Explorer, mail, communication, or coding practice.

Both public and developer profiles STOP on real active protection or security interception: real exam/proctoring/lockdown browser, CAPTCHA/human verification, bot challenge, automation detected, script detected, credential/security handoff, UAC/protected desktop, `Consent.exe`, `CredentialUIBroker`, ACE, EasyAntiCheat, Vanguard, BattlEye, or equivalent anti-cheat/anti-automation mechanisms.

`permission-status` includes `active_profile`. `safety-report` includes `public_developer_profile_difference` and `report_policy`.

Default report policy:

- `report_level=compact`
- `evidence_level=full`
- `progress_output=compact`
- `step_chat_detail=compact`
- `artifact_evidence=full`

Compact output changes chat/report verbosity only. It must not hide failures, reduce artifacts, or weaken audit evidence. Failure output expands with error, evidence, and next repair.

## DesktopVisual 1.0.5 Full-screen Capture/OCR Performance Pipeline Protocol

The full-screen frame is the source-of-truth for capture, OCR, foreground/window crop OCR, VLM transport, and PNG evidence. Full-screen capture remains mandatory; PNG evidence remains retained; OCR must not read the evidence PNG as its normal path.

New commands:

- `capture-fullscreen-frame [--originating-command <name>] [--async-evidence true|false]`
- `ocr-fullscreen-frame --frame-id <id>` or `ocr-fullscreen-frame --capture-new true`
- `ocr-foreground-from-frame --frame-id <id>`
- `ocr-window-from-frame --frame-id <id>`
- `evidence-flush --frame-id <id>` or `evidence-flush --all-pending true`
- `frame-evidence-flush` alias for `evidence-flush`
- `ocr-cache-status`
- `ocr-cache-clear`
- `vlm-frame-transport-check --frame-id <id> [--provider codex-cli] [--target <text>]`

Required frame metadata fields include `frame_id`, `screenshot_id`, `captured_at`, `screen_width`, `screen_height`, `dpi_scale` or coordinate scale, `pixel_format`, `byte_size`, `source=full_screen`, `evidence_png_path`, `evidence_write_status`, `content_hash`, `originating_command`, `foreground_window_hwnd`, and `foreground_window_rect`.

`capture-fullscreen-frame` output must report `frame_in_memory=true`, `full_screen_capture=true`, assigned `evidence_png_path`, `evidence_write_status=pending|written|failed`, `async_evidence_write`, screen dimensions, `pixel_format`, `content_hash`, `duration_ms`, and `backend_capture_used=false`.

`ocr-fullscreen-frame` output must bind `frame_id` and `screenshot_id`, report `ocr_source=memory_frame`, `png_read_for_ocr=false`, `evidence_png_path`, `evidence_write_status`, `text_blocks`, `text_count`, `duration_ms`, `ocr_cache_hit`, `tile_cache_hit`, `cache_key`, `cache_scope`, `cache_validated=true`, and `ocr_engine`.

`ocr-foreground-from-frame` and `ocr-window-from-frame` must crop from the full-screen frame, not recapture a partial screenshot. Output must include `crop_from_fullscreen_frame=true`, `partial_screenshot_used=false`, `foreground_crop_rect`, `crop_ocr_success`, `full_screen_ocr_fallback_used`, `same_frame_for_fallback=true`, and `screenshot_recaptured_for_fallback=false`.

`evidence-flush` is the flush barrier before failure, BLOCKED, and final reports. If flushing fails, the command must return `EVIDENCE_FLUSH_FAILED` and must not PASS.

OCR cache keys include frame/content hash, crop rect, OCR engine/config, and tile hash when used. A new frame must not reuse old OCR unless the content/tile hash strategy validates equality, and cache outputs must report `cache_validated=true`.

VLM frame transport is provider-dependent. Current Codex CLI provider transport is file-path based because Codex CLI requires `--image <png_path>`. `vlm-frame-transport-check` must report `provider_transport=file_path`, `provider_requires_file_input=true`, `supports_memory_bytes=false`, `vlm_input_image_path`, `vlm_input_generated_from_frame=true`, `screenshot_recaptured_for_vlm=false`, `ocr_read_vlm_png=false`, and `candidate_is_locate_only=true`. The VLM input PNG is a transport artifact generated from the existing frame, not an OCR input and not a recapture.

## DesktopVisual 1.0.4 Visual Studio C++ Complex IDE Workflow Protocol

The Visual Studio C++ complex IDE workflow is path-sensitive. A final project state is not sufficient for PASS unless every project/file/build/run step used visible VS UI or visible IDE shortcuts and recorded step checkpoints.

Required VS workflow evidence fields:

- `step_by_step_visible_execution=true`
- `project_name=SingleTestProject`
- `template_required=Empty Project`
- `template_selected=Empty Project`
- `template_selection_method`
- `project_location_modified=false`
- `actual_project_path`
- `solution_path`
- `vcxproj_path`
- `vs_open_method=desktop_icon_double_click`
- `desktop_vs_icon_found=true`
- `project_opened_by_visible_ui=true`
- `close_method=top_right_x_visible_click`
- `vs_closed_after_each_stage=true`
- `backend_sln_open_used=false`
- `backend_project_creation_used=false`
- `backend_file_creation_used=false`
- `backend_file_write_used=false`
- `backend_build_used=false`
- `backend_run_used=false`
- `old_mock_vlm_used=false`
- `output_verified=true`

Each step checkpoint must include `step_id`, `intended_action`, `visible_observe_before`, `target_source`, `action_command`, `visible_observe_after`, `verification_result`, `recovery_needed`, `recovery_action` when applicable, and `next_step_allowed`. If verification fails, the next step is forbidden until visible recovery succeeds or the run is BLOCKED.

Visual Studio launch must reveal/show the desktop, locate the VS desktop icon by UIA/OCR/visible evidence, move the mouse to it, double-click it, and verify the VS window. Backend launch, direct `devenv.exe`, PowerShell launch, ShellExecute, Start Menu search, and backend `.sln` open are not valid VS open evidence.

`SingleTestProject` must be created once as an Empty Project through VS visible UI. Source/header file creation must use Solution Explorer Add/New Item or the visible `Ctrl+Shift+A` new item fallback. Code input must occur through the visible VS editor and be saved visibly. Build and run must use visible VS UI or visible IDE shortcuts. Backend file writes, `.vcxproj` edits, `msbuild`, and direct exe runs cannot substitute for acceptance.

The three accepted v1.0.4 IDE run stages are: Stage 1 single source output `SingleTestProject single file OK`, Stage 2 multi-source output `multi source OK`, and Stage 3 multi-source plus header output `multi source header OK`.

## DesktopVisual 1.0.3.1 Legacy Mock VLM Quarantine Protocol

The normal v1.0.3+ VLM path is `vlm-capability-probe`, `vlm-assist-locate`, `vlm-candidate-validate`, `RealVlmRuntimeBridge`, and `tools\codex_vlm_provider.ps1`.

Legacy mock VLM commands are Deprecated and Test-only. They remain only as legacy test fixtures for historical selftests and must not be recommended to agents as normal VLM assist workflows. Default calls fail with `LEGACY_MOCK_VLM_DEPRECATED` or `LEGACY_MOCK_VLM_DISABLED` and recommend the real VLM runtime bridge path.

Legacy Mock VLM commands:

- `vlm-observation-run-mock`
- `vlm-assisted-locate`
- `vlm-assisted-locate-dry-run`
- `vlm-assisted-locate-and-click-local-safe`

Legacy test fixture use requires explicit opt-in with `--allow-legacy-mock-vlm true` or `DESKTOPVISUAL_ENABLE_LEGACY_MOCK_VLM=1`. Opt-in output must be marked `legacy_mock_vlm=true`, `real_vlm=false`, and `not_for_agent_workflow=true`.

## DesktopVisual 1.0.3 Automatic Real VLM Runtime Bridge Protocol

This developer-tree layer adds provider-gated real VLM assist without changing Runtime ownership of actions. VLM can analyze screenshots, return structured visual candidates, and help explain unclear visual state. Runtime still owns safety policy, candidate validation, coordinate mapping, mouse/keyboard execution, post-action verification, and fallback decisions.

New commands:

- `vlm-capability-probe --provider codex-cli [--session-id <id>] --probe-image <png> [--timeout-ms <ms>] [--cache true|false]`
- `vlm-assist-locate --provider codex-cli [--session-id <id>] --image <png> --target <description> [--target-window-title <partial>] [--timeout-ms <ms>] [--min-confidence <0..1>]`
- `vlm-candidate-validate --candidate-json <path> --image <png> [--target <description>] [--target-window-title <partial>] [--min-confidence <0..1>]`

Capability gate rules:

- Probe once per large task/session/provider and reuse the file cache under `artifacts\vlm_session_cache`.
- Cached `VLM_AVAILABLE` allows later VLM assist calls without repeating the provider probe.
- Cached `VLM_UNAVAILABLE` or `VLM_UNKNOWN` means Runtime continues Runtime-only visible paths and records the VLM status.
- Failed provider lookup, timeout, invalid probe output, or disabled provider must not be reported as available.

Provider result rules:

- The Codex CLI provider is called through `tools\codex_vlm_provider.ps1`, not complex inline shell quoting in C++.
- Provider output must be strict JSON. Natural language, malformed JSON, low confidence, semantic mismatch, bbox/point out of image bounds, wrong coordinate space, missing evidence binding, or active-protection safety flags reject the candidate.
- `vlm-assist-locate` locates only. It must report `runtime_action_executed=false`, `vlm_action_executed=false`, `candidate_is_locate_only=true`, `requires_coordinate_mapping_before_action=true`, `requires_target_window_lock_before_action=true`, and `requires_post_action_verification=true`.
- A VLM candidate accepted by `vlm-assist-locate` or `vlm-candidate-validate` does not mean action executed, click success, input success, or task success. It only means the candidate can enter Runtime-owned action planning.
- Before any future v1.0.4 complex IDE workflow uses an accepted VLM candidate for a visible action, Runtime must map image pixel coordinates to screen coordinates, lock the target window rect / hwnd / title / process, verify the candidate point is inside the locked target window, execute the visible action itself, and verify the expected post-action state with a fresh observe/report.
- VLM commands must not click, type, move the mouse, open programs, run commands, choose backend fallback, or bypass active protection.

Required VLM evidence fields on visible/fallback-aware outputs:

- `vlm_assist_enabled`
- `vlm_capability_status`
- `vlm_session_id`
- `vlm_assist_attempted`
- `vlm_assist_trigger_reason`
- `vlm_assist_stage`
- `vlm_provider`
- `vlm_raw_response_path`
- `vlm_candidate_accepted`
- `vlm_candidate_rejected_reason`
- `vlm_action_executed=false`
- `vlm_after_backend_attempted=false`
- `fallback_stage_before_vlm`
- `fallback_stage_after_vlm`

Fallback integration rules:

- Visible path may call VLM only after an eligible UIA/OCR/template/perception/location ambiguity, deterministic recovery has run or is not applicable, and backend fallback has not started.
- VLM returns only candidates. Runtime validates candidates and performs any second visible attempt with real mouse/keyboard input.
- Keyboard fallback may use VLM only for visual state verification after a Runtime/Skill/Agent-approved shortcut. VLM does not invent shortcuts.
- Once backend fallback starts, VLM is not called. Backend failure is not rescued by VLM.
- Active protection, CAPTCHA, human verification, bot/automation detection, protected desktop/UAC, anti-cheat, proctoring, lockdown browser, or equivalent interception stops the run instead of invoking VLM.

## DesktopVisual 1.0.2 Skill Contract Hardening Protocol

This developer-tree-only layer does not add Runtime commands. It hardens the Skill, Codex adapter, shared adapter rules, and usage references so agents must use the Runtime discipline introduced in v1.0.1.

Contract rules:

- DesktopVisual is a Windows visible-first desktop runtime, not a background script executor.
- Agent success is path-sensitive: a final state that used an illegal backend shortcut is failure.
- Use `visible-app-launch` for app, URL, local shortcut, `.lnk`, `.url`, and webpage shortcut launches.
- `visible-app-launch` is desktop-first: reveal desktop, observe desktop, locate visible icon/shortcut through UIA/OCR/visible evidence, real mouse double-click, then verify the target window when title/process is supplied.
- Start Menu visible search is a fallback, not the first choice.
- backend launch, ShellExecute, direct file open, and background browser navigation are not default launch paths.
- Entering shortcut fallback requires at least two bounded visible attempts or strict surface-impossible evidence.
- Entering backend fallback requires visible path failure plus keyboard fallback failure, and the backend reason must not be convenience, speed, or test shortcut.
- `target_not_found`, `uia_not_found`, `ocr_not_found`, and `click_failed` alone are not surface-impossible evidence.
- Active protection or security interception is STOP, not fallback.
- v1.0.2 does not enable a real VLM provider. v1.0.3 adds provider-gated VLM assist under Runtime validation.
- Developer permissions are not narrowed in this release. `DEVELOPER_CAPABILITY_DISCOVERY` / `DEVELOPER_FULL_RUNTIME` remain broad developer modes, and broad category or keyword matching is not a developer STOP condition without active protection.

## DesktopVisual 1.0.1 Runtime Visible-First Launch and Fallback Discipline Protocol

This developer-tree-only layer updates Runtime launch and fallback behavior under `D:\desktopvisual`. Its historical public profile behavior is superseded by DesktopVisual 1.1.0, which aligns `PUBLIC_DEFAULT` for ordinary visible desktop operations while preserving active-protection STOP boundaries.

New command:

- `visible-app-launch --target <name> [--app <name>] [--url <url>] [--target-title <partial title>] [--process <process.exe>] [--wait-ms <ms>] [--dry-run true|false] [--latency-profile fast-visible-ui] [--motion-profile 165hz-visible] [--motion-hz 165]`

Launch rules:

- `visible-app-launch` is a generic Runtime command, not an app-specific workflow.
- It first ensures the desktop surface is visible/observable, then searches visible desktop icons and shortcuts through UIA, with OCR as supplemental evidence when available.
- If a matching visible desktop icon, `.lnk`, or `.url` shortcut exists, the Runtime must open it with real mouse movement and double-click.
- If OCR is unavailable, output evidence records `ocr_available=false` or equivalent and must not switch to backend launch because of OCR absence.
- Start Menu / taskbar Search launch is a visible fallback after desktop locate/action failure, not the first choice.
- URL fallback uses visible browser/address-bar navigation, not backend `browser-nav` by default.
- Direct backend `launch-app`/ShellExecute-style launch is not the default path and requires strict fallback evidence before use.
- Target window success requires `--target-title` or `--process` verification when provided. SendInput success alone is not launch success.

Required `visible-app-launch` evidence includes:

- `runtime_visible_first_launch=true`
- `launch_strategy=desktop_first`
- `desktop_surface_attempted`
- `desktop_icon_locate_attempt_count`
- `desktop_icon_double_click_attempt_count`
- `desktop_icon_path_used`
- `start_menu_fallback_attempted`
- `browser_visible_navigation_fallback_attempted`
- `backend_launch_used`
- `pre_action_checkpoint_id`
- `bounded_recovery_attempted`
- `target_verification_method`
- `target_window_verified`
- `operation_priority`

Fallback discipline fields:

- `visible_attempt_count`
- `min_visible_attempts_before_shortcut`
- `pre_action_checkpoint_present`
- `bounded_recovery_attempted`
- `post_recovery_observed`
- `same_surface_after_recovery`
- `surface_impossible`
- `surface_impossible_reason`
- `surface_impossible_evidence_present`
- `visible_stage_satisfied_for_fallback`

Fallback rules:

- One visible failure is not enough to enter keyboard shortcut fallback or backend fallback.
- Attempt 2 requires either two bounded visible attempts with checkpoint/recovery/re-observe evidence, or strict surface-impossible evidence.
- `target_not_found`, `uia_not_found`, `ocr_not_found`, and `click_failed` are not surface-impossible evidence by themselves.
- Backend fallback additionally requires failed keyboard shortcut fallback evidence and a non-empty backend reason that is not convenience, speed, or test shortcut.
- If the final screen appears successful but the operation path violates visible-first/fallback discipline, the result is invalid and reports `RESULT_INVALID_DUE_TO_VISIBLE_FIRST_VIOLATION`.
- Active third-party protection or security interception stops instead of falling back.

## v6.12.1 Visible UI Execution Foundation Hardening Protocol

This developer-tree-only layer hardens visible UI execution primitives under `D:\desktopvisual`. It does not inspect, modify, package, or publish `D:\desktopvisual-release` or `D:\desktopvisual-public-dist`.

## v6.12.1 Visible UI Operation Latency Optimization Protocol

This developer-tree-only layer optimizes the real PyCharm visible UI workflow without changing visible-first priority rules. It preserves foreground preempt, target window lock, screenshot coordinate mapping, global final screenshot evidence, real keyboard input, and no-backend-launch/no-clipboard/no-backend-file-write acceptance rules.

Commands and tools:

- `foreground-preempt --cache-selftest true [--dry-run true]`
- `target-lock-acquire --cache-selftest true [--dry-run true]`
- `global-screenshot --cache-selftest true --out <file>`
- `visible-text-input --typing-profile fast-real-keyboard --char-delay-ms 0 --line-delay-ms 0 --batch-key-events true`
- `visible-action-batch --profile pycharm-current-main-performance --plan <json> --out <result.json>`
- `motion-pacer-selftest --motion-hz 165`
- `visible-show-desktop --latency-profile fast-visible-ui --motion-profile 165hz-visible --motion-hz 165`
- `desktop-icon-double-click --latency-profile fast-visible-ui --motion-profile 165hz-visible --motion-hz 165`

Performance evidence:

- `foreground_preempt_mode`: `full`, `cached_validation`, or `skipped_safe`.
- `foreground_preempt_reason`, `agent_host_overlap_changed`, `target_foreground_changed`, and `duration_ms`.
- `target_lock_mode`: `acquire`, `cached_validate`, or `reacquire`.
- `target_lock_cache_hit` and target lock `duration_ms`.
- `frame_cache_hit`, `frame_cache_valid_ms`, invalidation fields, and `new_global_frame_for_final_verification`.
- `typing_profile`, `char_delay_ms`, `line_delay_ms`, `batch_key_events`, and `keyboard_send_batch_count`.
- `requested_hz`, `measured_avg_hz`, `measured_min_hz`, `measured_max_interval_ms`, and `total_move_duration_ms` for 165Hz motion pacing.

Rules:

- Cached foreground preempt may skip full preempt only when target hwnd, foreground hwnd, and agent-host overlap state remain stable.
- Cached target lock may be reused only for the same hwnd with stable rect and foreground validation.
- Global frames may be reused for planning only when no action/window invalidation has occurred; final verification must capture a new global frame.
- `fast-real-keyboard` still means real `SendInput` keyboard events. Clipboard paste and backend file writes remain invalid.
- Deterministic action batches must preserve per-sub-action operation IDs, priority chain evidence, target lock requirements, coordinate mapper requirements, and final global screenshot evidence.
- Motion profile `165hz-visible` must request 165Hz and report measured timing; if measured average is below 150Hz or max interval exceeds 12ms, the motion selftest blocks.

## v6.12.1 Continuous Operation Timeline Profiling Protocol

This profiling-only layer measures why a sequence can feel slow even when individual Runtime `duration_ms` values are short. It does not optimize parameters, change visible-first policy, modify release/public-dist paths, package public artifacts, or upload GitHub.

Commands and tools:

- `operation-timeline-profiler-selftest`
- `v6_12_1_continuous_operation_timeline_runner.ps1`
- `operation_timeline_profiler_selftest.ps1`

Timeline evidence:

- `operation_timeline.jsonl`
- `operation_timeline.csv`
- `timeline_summary.md`
- `bottleneck_summary.md`
- `runtime_vs_wallclock_report.md`
- `orchestration_overhead_report.md`
- `fixed_sleep_report.md`

Required time distinctions:

- `runtime_duration_ms`: Runtime internal command duration from winagent JSON.
- `wall_clock_ms`: PowerShell wrapper elapsed time from process invocation start to command return.
- `orchestration_overhead_ms`: `wall_clock_ms - runtime_duration_ms`.
- Separate fields report wait condition time, fixed sleep time, process startup overhead estimate, PowerShell wrapper overhead estimate, manual view-image time, and Codex orchestration gap time.

Rules:

- Profiling reports must not be converted into workflow PASS evidence.
- Slow operations over 5 seconds, fixed sleeps over 1000ms, and `runtime_duration_ms < 500 && wall_clock_ms > 5000` overhead suspects must be listed explicitly.
- Optimization candidates may be reported, but no performance optimization is applied in this profiling-only stage.

Commands:

- `global-screenshot --out <file> [--format png|bmp] [--include-metadata true|false]`
- `target-lock-acquire [--target-title <partial_title>|--target-hwnd <hwnd>|--target-process <process>] [--require-target-lock true] [--allow-global-desktop true]`
- `target-lock-release [--target-title <partial_title>|--target-hwnd <hwnd>|--target-process <process>]`
- `coordinate-map --direction pixel-to-screen|screen-to-pixel --capture-scope global_desktop|window_only --capture-left <x> --capture-top <y> --capture-width <w> --capture-height <h> [--target-left <x> --target-top <y> --target-right <x> --target-bottom <y>]`
- `foreground-preempt [--dry-run true|false]`
- `visible-text-input --text <text> [--input-kind form|message|code|search|mail|filename|command|editor|chat] [--input-method real_keyboard_events|line_by_line_keyboard|code_editor_keyboard] --target-title <partial_title> [--require-target-lock true] [--dry-run true]`
- `visible-action-batch --plan <json> --out <result.json>`
- `visible-ui-verify --global-final-frame true --target-lock true|--allow-global-desktop true --expected-output-visible true`
- `visible-operation-policy-check --operation-type <type> [--final-mode-used visible_mouse_keyboard|keyboard_shortcut_fallback|backend_fallback] [--visible-mouse-keyboard-attempted true|false] [--keyboard-shortcut-attempted true|false] [--backend-fallback-used true|false]`
- `taskbar-icon-locate --target <name> [--dry-run true]`
- `taskbar-icon-click --target <name> [--dry-run true]`
- `desktop-icon-locate --target <name> [--dry-run true]`
- `desktop-icon-double-click --target <name> [--dry-run true]`
- `start-menu-visible-launch --app <name> [--dry-run true]`
- `visible-app-launch --target <name> [--app <name>] [--url <url>] [--target-title <partial_title>] [--process <process.exe>] [--wait-ms <ms>] [--dry-run true]`
- `visible-show-desktop [--dry-run true]`
- `visible-window-switch --target-title <partial_title>|--target-process <process> [--max-cycles <n>] [--dry-run true]`
- `visible-page-navigation --target <back|home|url|tab|panel> [--dry-run true]`
- `vlm-runtime-candidate [--global-frame true] [--observation-request true] [--observation-result true] [--candidate-target true] [--runtime-validator true] [--coordinate-mapper true] [--target-lock true] [--action true] [--verification true]`
- `pycharm-visible-demo --project <dir> --file main.py --code-profile two-class-demo [--dry-run true]`

Rules:

- `screenshot --out <file>` defaults to `global-screenshot` and reports `capture_scope=global_desktop` plus `can_be_final_evidence=true`.
- `screenshot --title <title> --out <file>` is a diagnostic `window_only` screenshot and reports `can_be_final_evidence=false`.
- `window_only` screenshots cannot be final PASS evidence; final visible UI verification must use a global DPI-aware frame.
- All visible UI observation and action paths must run `foreground-preempt` before first observation or action.
- All visible UI launch, navigation, window switching, page switching, tab/panel switching, dialog action, save/run/send/submit/confirm/cancel, and text input paths must use the visible-first priority chain: attempt 1 visible mouse/keyboard with bounded retry evidence, attempt 2 keyboard shortcut fallback, attempt 3 backend fallback, then fail/stop.
- Show desktop is a dedicated default policy: attempt 1 clicks the bottom-right taskbar Show Desktop hot area, attempt 2 may use Win+D only after visible click failure evidence, attempt 3 may use backend/system show desktop only after both previous failures. Missing attempt 1 returns `FAIL_SHOW_DESKTOP_VISIBLE_CLICK_NOT_ATTEMPTED`; backend first returns `BLOCKED_BACKEND_SHOW_DESKTOP_USED_BEFORE_VISIBLE_AND_SHORTCUT`.
- Window switching is a dedicated default policy: attempt 1 is Alt held + Tab cycles + Alt release, attempt 2 is visible taskbar/window click fallback, attempt 3 is backend focus fallback only after both prior failures. Backend focus first returns `BLOCKED_BACKEND_FOCUS_USED_BEFORE_ALT_TAB_AND_VISIBLE_CLICK`; direct visible click without Alt+Tab failure evidence must record `window_switch_primary_alt_tab_skipped=true`.
- Backend focus commands (`focus-window`, `activate-window`, `bring-window-front`, `SetForegroundWindow` style paths), backend app launch (`launch-app --path`, direct exe run, `Start-Process` style paths), backend browser navigation (`browser-nav`), backend page navigation, and backend tab/panel/internal commands are blocked as primary paths unless explicit backend request or previous visible and shortcut failure evidence is recorded.
- Operation evidence must include `operation_type`, `attempt_1_mode`, `attempt_1_result`, `attempt_2_mode`, `attempt_2_result`, `attempt_3_mode`, `attempt_3_result`, `final_mode_used`, `visible_mouse_keyboard_attempted`, `visible_attempt_count`, `min_visible_attempts_before_shortcut`, `pre_action_checkpoint_present`, `bounded_recovery_attempted`, `post_recovery_observed`, `same_surface_after_recovery`, `surface_impossible`, `surface_impossible_reason`, `surface_impossible_evidence_present`, `keyboard_shortcut_attempted`, `backend_fallback_used`, `backend_fallback_reason`, `priority_violation`, and `max_attempts_exceeded`.
- Backend fallback without first-stage and second-stage failure evidence returns `FAIL_BACKEND_PRIORITY_VIOLATION` or a specific block code such as `BLOCKED_BACKEND_LAUNCH_USED_BEFORE_VISIBLE_LAUNCH`, `BLOCKED_BACKEND_FOCUS_USED_BEFORE_VISIBLE_SWITCH`, `BLOCKED_BACKEND_BROWSER_NAV_USED_BEFORE_VISIBLE_NAV`, `BLOCKED_BACKEND_PAGE_NAV_USED_BEFORE_VISIBLE_NAV`, or `BLOCKED_BACKEND_TAB_SWITCH_USED_BEFORE_VISIBLE_SWITCH`.
- A successful final UI state with a violated operation path is invalid and must report `RESULT_INVALID_DUE_TO_VISIBLE_FIRST_VIOLATION`; the acceptance-gate failure code is `V6_12_1_BLOCKED_VISIBLE_FIRST_OPERATION_PRIORITY_VIOLATION`.
- App-internal visible clicks, typing, hotkeys, and Run-button fallbacks require `TargetWindowLock`; desktop icons may use `--allow-global-desktop true`.
- App-internal click coordinates must be mapped through `ScreenshotCoordinateMapper`; mixed window/global/DPI coordinate sources are rejected.
- Visible text input defaults to `real_keyboard_events` across code editors, forms, search boxes, messages, email bodies, filenames, command palettes, web fields, IDE editors, and chat windows. `line_by_line_keyboard` and `code_editor_keyboard` are explicit visible keyboard modes for multiline text and code editors.
- Visible text input must map `\r\n` to exactly one Enter key event, `\n` to Enter, `\r` to Enter, `\t` to Tab, and ordinary characters to Unicode keyboard events. Newline and tab characters must not be sent as ordinary Unicode text. First-pass evidence reports `first_pass_multiline_correct`, `code_collapsed_to_single_line`, and `selfself_autocomplete_artifact`.
- Clipboard operations are fallbacks, not default input paths. `clipboard-set` and clipboard paste require the same visible mouse/keyboard failure plus keyboard shortcut failure evidence before use, unless the user explicitly requested backend operation; otherwise they fail with `FAIL_CLIPBOARD_PRIORITY_VIOLATION`.
- Backend file writes are forbidden as visible text input evidence.
- PyCharm real acceptance requires visible desktop-icon, taskbar, or start-menu launch evidence. Backend PyCharm launch, `launch-app --path`, or direct exe launch must block with `BLOCKED_PYCHARM_BACKEND_LAUNCH_PRIORITY_VIOLATION` even if code execution later succeeds.
- VLM-assisted requires Runtime candidate validation: global frame, VLM observation request/result, candidate target, RuntimeCandidateValidator, ScreenshotCoordinateMapper, TargetWindowLock, action, and verification. Current model visual inspection alone must report `vlm_assisted=false`.
- `visible-action-batch` should be preferred for deterministic foreground preempt + target lock + global frame + text input + wait condition + verification chains; fixed long sleeps are rejected.

## Post-v6 Developer Runtime UX Optimization Protocol

This developer-tree-only update improves visible UI task startup and command ergonomics. It does not change public-release safety policy and does not generate a public release package.

Commands:

- `prepare-foreground [--title <partial_title>|--hwnd <hwnd>|--process <process>] [--timeout-ms <ms>]`
- `focus-window --title <partial_title> [--process <process>] [--timeout-ms <ms>]`
- `activate-window --title <partial_title> [--process <process>] [--timeout-ms <ms>]`
- `bring-window-front --title <partial_title> [--process <process>] [--timeout-ms <ms>]`
- `minimize-window --title <partial_title> [--process <process>] [--timeout-ms <ms>]`
- `restore-window --title <partial_title> [--process <process>] [--timeout-ms <ms>]`
- `pycharm-dev-demo --project D:\testrepo\pycharm_sanity --file main.py --code-profile two-class-demo [--latency-profile fast-visible-ui]`

Compatibility aliases and defaults:

- `mouse_position` maps to canonical `mouse-position`.
- `read_window_text` maps to canonical `read-window-text`.
- `focus-window` is accepted as an activation alias and records `canonical_command=activate-window`.
- `right-click --screen-x <x> --screen-y <y>` maps to the desktop right-click path; prefer canonical `desktop-right-click`.
- `double-click --screen-x <x> --screen-y <y>` maps to the desktop double-click path; prefer canonical `desktop-double-click`.
- `screenshot --out <file>` and `observe --out <file>` default to the active foreground window when no target is specified, unless the foreground is the agent host and no safe target can be inferred.
- `uia-tree --process <process>` resolves a visible process main window before reading UIA.
- Unknown commands return `closest_matches`; invalid arguments should return `suggested_command` when a canonical form is known.

Foreground rules:

- Visible UI commands must run foreground preparation before observation or input.
- If the foreground window is the agent host, Codex, CLI, Windows Terminal, PowerShell, or cmd and it overlaps the target, Runtime first attempts to minimize it.
- If minimizing fails, Runtime moves the host window away and records `cli_minimize_failed=true` and `fallback=move_away_or_focus_target`.
- Runtime must activate and verify the target foreground before screenshot, observe, UIA, mouse, keyboard, browser, explorer, or PyCharm visible workflows.

Latency profiles:

- `--latency-profile conservative`
- `--latency-profile normal`
- `--latency-profile fast-visible-ui`

`fast-visible-ui` reduces mouse movement steps, dwell, post-click settle, common launch waits, and retry budget while preserving visible user-level input. It must not turn visible UI actions into backend writes.

Motion pacing:

- `--motion-profile 165hz`
- `--motion-frame-rate 165`

`fast-visible-ui` defaults HumanMode mouse motion to `target_motion_frame_rate_hz=165`, `target_frame_interval_ms=6.06`, and `best_effort=true`. Mouse movement evidence records per-frame timestamps, `average_frame_interval_ms`, `p95_frame_interval_ms`, and `actual_frame_rate_hz`; target lock, foreground preempt, and target epsilon verification remain authoritative.

## Post-v6 F12 Current Task Force Exit Protocol

F12 is a Runtime-owned current-task abort control shared by developer and future release builds. It stops the active task only and must not terminate the winagent process.

Stop code:

- `STOP_USER_FORCE_EXIT_F12`

Required user-facing message:

- Returned through `UserAbortMessage()` for current-task force exit.

Required evidence fields:

- `user_force_exit=true`
- `force_exit_key=F12`
- `force_exit_scope=current_task_only`
- `process_exit=false`

Rules:

- Runtime, session dispatch, input movement, clicking, typing, scrolling, case runner waits, recorder loops, and other long-running execution loops must poll for the abort request.
- Once F12 is observed, input state must be released and no further task actions may execute.
- F12 STOP is not PASS and must not be normalized by runners into PASS.
- F12 STOP remains distinct from active-protection, credential, public-release, and other safety stops.
- This protocol does not implement public-release permission hardening, default/full_access selection, or keyword-based task blocking.

## v6.12.0 Developer RC Gate and Handoff Protocol

v6.12.0 adds metadata, evidence-chain, boundary, policy, and handoff checks for the developer RC. It is not a public release gate and does not implement public-release permission hardening.

Commands:

- `developer-rc-gate --output <result.json>`
- `version-integrity-check --output <result.json>`
- `evidence-chain-verify --output <result.json>`
- `capability-matrix-build --output <matrix.json> [--markdown-output <matrix.md>]`
- `workflow-boundary-audit --output <result.json>`
- `developer-full-access-policy-check --output <result.json>`
- `release-hardening-deferred-ledger --output <ledger.json> [--markdown-output <ledger.md>]`
- `handoff-package-build --output <report.json>`
- `v6-12-rc-handoff-check --output <result.json>`

Rules:

- Developer RC commands are metadata/report commands only and must not rerun old UI workflows.
- Developer full access remains default for this development tree.
- Public release permission policy, user-selectable FULL_ACCESS / limited access UI, exam/test/interview/contest public safety policy, release consent UI, public repo cleanup, artifact slimming, privacy review, installer/packaging, public docs, and strict release rc_check remain deferred.
- Developer mode must not add task keyword denylist behavior for ordinary words such as test, exam, interview, contest, LeetCode, OJ, social, email, or message.
- Runtime must still stop/report on real CAPTCHA/human verification, account/security verification, credential handoff, active proctoring/lockdown browser, anti-cheat, anti-automation, third-party automation interception, and explicit security/risk verification.
- Runner output remains `RAW_COMPLETED_UNVERIFIED`; verifier and acceptance gate own PASS authority.

## v6.11.0 Workflow Template and Batch Protocol

v6.11.0 adds evidence-derived reusable workflow structures and batch compile/validate/mock coordination. Template Learning means extracting candidate templates from accepted evidence or read-only ExperienceMemory and validating them. It is not model training, an optimizer, automatic decision-making, automatic repair, or Runtime execution influence.

Commands:

- `workflow-template-extract --source <accepted_evidence_or_memory> [--workflow-type <type>] --output <candidate_template.json>`
- `workflow-template-validate --input <candidate_template.json> --output <template.json> --report <validation_report.json>`
- `workflow-template-register --input <template.json> [--registry-root <dir>] --output <registered_template.json>`
- `workflow-template-instantiate --template <validated_template.json> --parameters <parameter_values.json> --output <step_contract.json> [--evidence-output <instantiation_evidence.json>]`
- `workflow-template-report [--registry-root <dir>] --output <report.json> [--markdown-output <report.md>]`
- `batch-workflow-plan --input <batch_input.json> --output <batch_plan.json>`
- `batch-workflow-validate --input <batch_plan.json> --output <validation.json>`
- `batch-workflow-run --input <batch_plan.json> --output <runner_result.json>`
- `batch-workflow-report --input <batch_plan.json> --output <report.json>`
- `v6-11-template-batch-check [--registry-root <dir>] [--batch-plan <batch_plan.json>] --output <result.json>`

Rules:

- Candidate templates are not executable. Rejected templates are not executable. Deprecated templates are not executable by default.
- Only `template_status=validated` with `validation_status=pass` can instantiate, and instantiation must call `StepContractValidator`.
- Template records must keep `source_evidence_refs`, `template_hash`, validation status, safety constraints, expected context schema, and verification hint schema.
- Candidate extraction is limited to accepted/pass v6.7 Explorer evidence, v6.8 Browser/Form evidence, v6.9 Communication evidence, v6.10 ExperienceMemory, and v6.9 system stabilization boundary evidence. Dirty/untracked/stash/raw runner-only sources are rejected.
- Browser/Form templates must not store DOM/JS/WebDriver/CDP/Playwright/Selenium backend actions. Communication templates must store only redacted references and never full recipient/body plaintext.
- Batch modes are `compile_only`, `validate_only`, `serial_execute_mock`, and restricted `serial_execute_runtime_safe`. Main gate runner permits only `compile_only`, `validate_only`, and `serial_execute_mock`.
- Batch plans must not use `parallel_real_ui`, concurrent RuntimeSession sharing, unsafe continue-on-verification-failure policy, verifier skipping, evidence skipping, or merged safety boundaries across workflows.
- Runner output remains `RAW_COMPLETED_UNVERIFIED`; verifier and acceptance gate own PASS authority.

## v6.10.0 Experience Memory Protocol

v6.10.0 adds an append-only local record layer and unified failure attribution normalization. These commands record/query/report evidence-derived memory only. They do not execute Explorer, Browser/Form, Communication, VLM, PyCharm, QQ, YouTube, or other UI workflows and do not influence Runtime execution decisions.

Commands:

- `experience-memory-record --input <record_input.json> --store-root <dir> --output <record.json>`
- `experience-memory-query --store-root <dir> [--workflow-type <type>] [--failure-category <category>] [--source-version <version>] --output <result.json>`
- `experience-memory-report --store-root <dir> --output <report.json> [--markdown-output <report.md>]`
- `failure-attribution-normalize --workflow-type <type> --execution-result <result> --failure-code <code> --output <result.json>`
- `memory-safety-check --input <record.json> --output <result.json>`
- `memory-safety-check --store-root <dir> --output <result.json>`
- `v6-10-experience-memory-check --store-root <dir> --output <result.json>`

Rules:

- Memory is append-only structured JSONL under `artifacts\experience_memory\memory_records.jsonl` by default, with `memory_index.json` as a read-only query index.
- Memory may record workflow type, result, evidence reference, evidence hash, source version, trusted version, and normalized failure category.
- Memory must not mutate StepContract, AgentPlanDraft, RuntimeSession, locator selection, retry policy, workflow optimization, or Runtime execution paths.
- `RAW_COMPLETED_UNVERIFIED` normalizes to `EVIDENCE_MISSING` and is never success.
- Unknown failure codes normalize to `UNKNOWN_FAILURE`, never `SUCCESS_NO_FAILURE`.
- Communication memory must redact sensitive content. Full mail/message body, private chat content, credentials, verification codes, tokens, and large screenshot payloads must not be stored.
- Query and report commands are read-only and must not generate workflow actions, StepContracts, execution plans, automatic fixes, or optimization suggestions.
- Runner output remains raw only. Verifier and gate evidence own acceptance.

## v6.9.0 System Stabilization Protocol

v6.9.0 system stabilization adds evidence and workflow boundary commands. These commands perform metadata, hash, artifact, session, and source structure checks only. They do not execute Explorer, Browser/Form, Communication, VLM, PyCharm, QQ, YouTube, or other old UI workflows.

Commands:

- `evidence-consolidate --root artifacts --output <report.json>`
- `session-lifecycle-audit --root artifacts\runtime_sessions --output <report.json>`
- `workflow-boundary-check --output <report.json>`
- `system-stabilization-check --output <result.json>`

Rules:

- Reports are advisory and classification-only unless an explicit future archive operation is separately approved.
- `final_status_report.md`, `evidence_index.md`, and acceptance gate reports are never marked safe to delete.
- Runtime session files are classified as referenced or unreferenced; they are not deleted by these commands.
- Unknown artifacts are retained and `safe_to_delete=false`.
- Workflow boundary checks verify source structure, evidence pointers, runner-only detection, and bypass detection without replaying UI workflows.
- `RAW_COMPLETED_UNVERIFIED` is never PASS.

## v6.8.0 Browser/Form Workflow Protocol

v6.8.0 adds accepted Browser/Form workflow commands. PASS authority belongs to the Browser/Form runner, independent verifier, acceptance gate, and full regression evidence under `artifacts/dev6.8.0_browser_and_web_form_agent_workflows/`.

Commands:

- `compile-browser-workflow --input <workflow.json> --output <step_contract.json>`
- `run-browser-workflow --input <workflow.json> --mode dry-run --output <result.json>`
- `run-browser-workflow --input <workflow.json> --mode execute-local-safe --output <result.json>`
- `verify-browser-workflow --result <execution_result.json> --output <verification.json>`

Rules:

- `dry-run` compiles and validates but does not execute Runtime browser actions.
- `execute-local-safe` main gate execution is limited to `file://`, `localhost`, and `D:\testrepo\testwindow\browser_form_v6_8` fixtures.
- Ordinary external webpages are allowed only for read-only diagnostic open/read/scroll/locate evidence in v6.8.0; real external submit is not a main gate PASS case.
- Every executable Browser/Form workflow must use StepContract, StepContractValidator, CompiledPlanExecutor, RuntimeSession, RuntimeContextGuard, BrowserSurfaceNormalizer where applicable, step-level verification, and an evidence pack.
- Browser/Form action paths must use visible browser UI, UIA/visible text/runtime locator evidence, mouse-first focus, and post-action verification. DOM mutation, JavaScript click/set value, WebDriver, CDP, Playwright, Selenium, direct coordinate actions, and backend API form submission are invalid.
- Active-protection and credential-required surfaces must STOP and include observed context evidence. They must not be normalized away, bypassed, solved, or auto-filled.
- Runner output remains raw only. `RAW_COMPLETED_UNVERIFIED` is never PASS; verifier and gate own acceptance.

## v6.8.0-preflight Validation Consistency Protocol

v6.8.0-preflight adds validation consistency commands for accepted old evidence. These commands are evidence/hash/state checks only. They do not execute Explorer, VLM, browser, app, or form UI workflows and must not be counted as new feature execution PASS.

Commands:

- `validation-fingerprint --feature <id> --evidence <path> --output <fingerprint.json>`
- `validation-consistency-check --feature <id> --evidence <path> --fingerprint <fingerprint.json> --output <result.json>`
- `validation-consistency-check --feature <id> --evidence <path> --fingerprint <fingerprint.json> --blocked-evidence <path> --output <result.json>`
- `regression-skip-evaluate --feature <id> --changed-files <path> --fingerprint <fingerprint.json> --output <result.json>`
- `regression-skip-evaluate --feature <id> --changed-files <path> --fingerprint <fingerprint.json> --consistency <result.json> --output <result.json>`

Supported `feature` ids:

- `v6_7_explorer_move_file`
- `v6_7_explorer_scroll_and_locate`
- `v6_7_explorer_full_regression`
- `v6_6_vlm_candidate_gate`
- `v6_5_vlm_observation_gate`
- `v6_4_runtime_execution_gate`
- `v6_3_plan_compiler_gate`
- `v6_2_session_gate`

Fingerprint JSON includes `fingerprint_id`, `feature_id`, `feature_version`, `evidence_source_path`, `input_spec_hash`, `step_contract_hash`, `execution_summary_hash`, `verification_summary_hash`, `final_status_hash`, `artifact_manifest_hash`, `created_at`, and `fingerprint_version`.

Rules:

- Fingerprints prove evidence drift status only; they are not execution results.
- Consistency checks verify accepted evidence existence, final status, gate status, evidence index references, v6.7 move/scroll repair evidence, full regression rerun state, preserved first-attempt BLOCKED evidence, rc_check non-substitution, runtime session classification, and RAW_COMPLETED_UNVERIFIED misuse.
- Regression skip is allowed for accepted old features only when fingerprint, consistency, trusted-version, and source-change checks are safe.
- If accepted feature source files change, fingerprint mismatches, final status/gate/evidence index conflicts, or trusted-version rollback occurs, skip is invalid and targeted replay is required.
- Browser/Form v6.8 new features must still receive real execution tests; validation consistency cannot substitute for new feature execution.

## v6.7.0 Explorer Agent Workflow Protocol

v6.7.0 adds accepted Explorer workflow commands. v6.7.0 PASS authority belongs to the rerun runner, verifier, acceptance gate, and from-beginning full regression evidence under `artifacts/dev6.7.0_explorer_agent_workflows_rerun/`.

Commands:

- `compile-explorer-workflow --input <workflow.json> --output <step_contract.json>`
- `run-explorer-workflow --input <workflow.json> --mode dry-run --output <result.json> [--evidence-dir <dir>]`
- `run-explorer-workflow --input <workflow.json> --mode execute-local-safe --output <result.json> [--evidence-dir <dir>]`
- `verify-explorer-workflow --result <execution_result.json> --output <verification.json>`

Rules:

- `dry-run` compiles and validates the Explorer StepContract without Runtime execution.
- `execute-local-safe` is limited to `allowed_root`, with fixture acceptance under `D:\testrepo`.
- Every Explorer workflow JSON must include explicit `allowed_root`, `expected_context`, `verification_hint`, and `stop_policy`.
- Delete requires `risk_level=DESTRUCTIVE`, `confirmation_required=true`, and a confirmation token before execution.
- Runtime execution must use StepContractValidator, RuntimeSession, RuntimeContextGuard, step-level verification, and evidence pack output.
- PowerShell runners may create and clean fixtures, invoke commands, and collect evidence; they must not perform the workflow file operation as the main action.
- Direct file API workflow execution, PowerShell-only fake execution evidence, runner-only workflow logic, missing RuntimeSession, missing RuntimeContextGuard, and missing StepContractValidator are verifier failures.
- `explorer_move_file` PASS requires staged evidence for source/destination paths, source exists before, destination exists before, mouse source selection, selection verification, cut attempt/send/method/effect, destination open/focus, paste attempt/send/method/observe, move attempt/execution, retry count, source absent after, destination exists after, result verification, failure stage, fallback use/reason, RuntimeSession, RuntimeContextGuard, StepContract validation, and explicit `power_shell_file_operation_used=false` plus `direct_file_api_used=false`.
- `explorer_scroll_and_locate` PASS requires staged evidence for list-area locate/click/focus, Home reset, visible items before/after, first/last visible item movement, scroll iteration count, wheel event count, PageDown fallback if used, per-iteration visible items, target fixture existence, target seen by UIA/OCR/read-window-text, target rect, target found, target clicked or verified, no stale rect, RuntimeContextGuard per iteration, and a concrete failure stage if blocked.

## Legacy / Deprecated / Test-only v6.6.0 VLM-Assisted Candidate Handling Protocol

This historical v6.6.0 mock-backed candidate path is legacy, deprecated, and test-only in v1.0.3.1. It is not the normal VLM path. Default user/agent calls are quarantined and must fail unless an explicit legacy mock opt-in is supplied for historical selftests. The normal v1.0.3+ VLM path is `vlm-capability-probe`, `vlm-assist-locate`, and `vlm-candidate-validate` through `RealVlmRuntimeBridge`.

v6.6.0 added a Runtime-owned candidate path for unknown UI targets after the normal Runtime locator fails. VLM output remains assistive-only: it can propose semantic candidates, but it cannot execute click/type/scroll and cannot supply a direct click point for immediate action.

Candidate commands:

- `vlm-assisted-locate --target <label> --observe-json <path> --screenshot <path> --result <result.json> [--provider mock] [--scenario <scenario>] [--evidence-dir <dir>]`
- `vlm-assisted-locate-dry-run --target <label> --provider mock --result <result.json> [--scenario <scenario>] [--evidence-dir <dir>]`
- `vlm-assisted-locate-and-click-local-safe --target <label> --expected-marker <marker> --result <result.json> [--provider mock] [--scenario <scenario>] [--title <window title>] [--verification-file <path>] [--evidence-dir <dir>]`

Rules:

- The VLM-assisted bridge is only valid after Runtime locate failed.
- VLM results must pass `VLMObservationValidator` before candidate validation.
- `possible_targets` must be `observation_only=true` and `requires_runtime_validation=true`.
- `RuntimeCandidateValidator` must verify candidates against screenshot/window bounds, viewport, OCR/UIA/visible text/context evidence, expected context, target freshness, uniqueness, and active-protection/credential risk policy.
- A candidate cannot pass only on VLM confidence. It must have Runtime corroboration and a validation method.
- Offscreen, outside-viewport, stale, ambiguous, hallucinated, no-corroboration, low-confidence, active-protection, credential, direct-coordinate, unsupported-role, and schema-invalid candidates are rejected.
- Only Runtime-validated candidates can convert to `LocatorCandidate`.
- Converted locator candidates use `candidate_source=vlm_assisted_runtime_validated`, `coordinate_source_type=vlm_assisted_runtime_validated`, `requires_final_guard_check=true`, `requires_mouse_first_evidence=true`, and `requires_post_action_verification=true`.
- `vlm-assisted-locate` and `vlm-assisted-locate-dry-run` never execute Runtime actions.
- `vlm-assisted-locate-and-click-local-safe` is limited to local/mock-safe TestWindow execution and still uses RuntimeContextGuard, mouse-first click evidence, and post-action verification.
- Runner output is raw only. `RAW_COMPLETED_UNVERIFIED` is not PASS; verifier and gate evidence own acceptance.

## Legacy / Deprecated / Test-only v6.5.0 VLM-Assisted Observation Contract Protocol

This historical v6.5.0 mock observation path is legacy, deprecated, and test-only in v1.0.3.1. It is not the normal VLM path. Default user/agent calls to mock observation commands are quarantined and must fail unless an explicit legacy mock opt-in is supplied for historical selftests.

v6.5.0 added assistive-only VLM observation commands. These commands package Runtime observation evidence, run a mock provider or disabled external placeholder, validate VLM output, and write dry-run diagnostics. They do not execute desktop actions.

Observation commands:

- `vlm-observation-build-request --observe-json <path> --screenshot <path> --output <request.json> [--task-hint <text>] [--expected-context <text>] [--observation-purpose <purpose>]`
- `vlm-observation-run-mock --request <request.json> --scenario <scenario> --output <result.json>`
- `vlm-observation-validate --request <request.json> --result <result.json> --output <validation.json>`
- `vlm-observation-dry-run --request <request.json> --provider mock --result <result.json> --validation <validation.json> [--scenario <scenario>] [--boundary <boundary.json>]`
- `vlm-observation-dry-run --request <request.json> --provider external --result <result.json> --validation <validation.json> [--boundary <boundary.json>]`
- `vlm-observation-selftest`

`VLMObservationRequest` includes `request_id`, `observation_id`, `session_id`, `window_hwnd`, `window_title`, `process_name`, `screen_bounds`, `window_bounds`, `screenshot_path`, `screenshot_region`, `uia_text_summary`, `ocr_text_summary`, `visible_text_hash`, `element_summary`, `task_hint`, `expected_context`, `observation_purpose`, `provider_role`, `allowed_outputs`, `forbidden_outputs`, `active_protection_detected`, `credential_required_detected`, `blocked_context`, `created_at`, and `contract_version`.

`provider_role` must be `assistive_only`. Supported purposes are `scene_summary`, `semantic_elements`, `target_candidates_observation_only`, `layout_understanding`, `text_extraction_assist`, and `unknown_ui_description`.

Allowed VLM result fields are observation fields only: `scene_summary`, `visible_text`, `layout_regions`, `semantic_elements`, `possible_targets`, `uncertainty`, `rejection_reason`, and `safety_notes`.

Forbidden outputs include `direct_click`, `direct_type`, `direct_scroll`, `executable_action`, `coordinate_only_action`, `bypass_instruction`, `credential_handling`, `captcha_solving`, `anti_cheat_evasion`, and `runtime_command`.

`VLMObservationResult` includes `result_id`, `request_id`, `provider_name`, `provider_role`, `schema_version`, `scene_summary`, `visible_text`, `layout_regions`, `semantic_elements`, `possible_targets`, `uncertainty`, `rejection_reason`, `safety_notes`, action/bypass/credential flags, `raw_provider_output_ref`, and `created_at`. Possible targets must have `observation_only=true` and `requires_runtime_validation=true`.

Validator output includes `validation_ok`, `executable=false`, `assistive_only`, `validation_errors`, `validation_warnings`, `blocked_reason`, `safe_for_runtime_candidate_pipeline`, and `safe_for_direct_execution=false`.

Validator error codes include:

- `VLM_SCHEMA_INVALID`
- `VLM_PROVIDER_ROLE_INVALID`
- `VLM_DIRECT_ACTION_REJECTED`
- `VLM_COORDINATE_ACTION_REJECTED`
- `VLM_RUNTIME_COMMAND_REJECTED`
- `VLM_BYPASS_INSTRUCTION_REJECTED`
- `VLM_CREDENTIAL_INSTRUCTION_REJECTED`
- `VLM_ACTIVE_PROTECTION_BYPASS_REJECTED`
- `VLM_PROMPT_INJECTION_CLASSIFIED`
- `VLM_CANDIDATE_REQUIRES_RUNTIME_VALIDATION`
- `VLM_MALFORMED_JSON`

Dry-run writes result, validation, and boundary evidence with `runtime_executed=false`, `mouse_click_sent=false`, `keyboard_type_sent=false`, `boundary_enforced=true`, and `safe_for_direct_execution=false`.

Safety limits:

- No real provider API key UI or login UI is added.
- The external provider path is disabled by default and returns `PROVIDER_EXTERNAL_DISABLED`.
- VLM output is never executed directly in v6.5.
- VLM possible targets are observation-only and wait for a future v6.6 Runtime validation pipeline.
- VLM output cannot enter `StepContract`, `CompiledPlanExecutor`, `RuntimeSession`, or direct click/type/scroll paths.

## v6.4.0 Runtime Task Execution Protocol

v6.4.0 adds Runtime execution commands for compiled and validated `StepContract` JSON. These commands do not accept natural language as a direct execution path. `AgentTaskRequest` and `AgentPlanDraft` inputs must still pass through the PlanCompiler and StepContractValidator before execution.

Execution commands:

- `run-agent-task --request <agent_task_request.json> --mode dry-run --output <result.json> [--evidence-dir <dir>]`
- `run-agent-task --request <agent_task_request.json> --mode execute-local-safe --output <result.json> [--evidence-dir <dir>]`
- `execute-step-contract --input <step_contract.json> --mode dry-run --output <result.json> [--evidence-dir <dir>]`
- `execute-step-contract --input <step_contract.json> --mode execute-local-safe --output <result.json> [--evidence-dir <dir>]`
- `execute-compiled-plan --input <step_contract.json> --session reuse --output <result.json> [--evidence-dir <dir>]`

Verification command:

- `step-execution-verify --input <verification_input.json> --output <verification_result.json>`

Rules:

- Dry-run validates the StepContract and emits a RuntimeSession dispatch plan with `runtime_executed=false`.
- `execute-local-safe` is limited to local/localhost/Explorer/mock-safe tasks for the v6.4 gate.
- Every execution must validate the StepContract before Runtime dispatch.
- Runtime execution must use the v6.2 RuntimeSession path and must not bypass RuntimeContextGuard.
- Every step must have a verification hint and a step-level verification result.
- Failure, wrong context, stale target, missing verification, unsafe risk, or guard failure stops later steps.
- Runner scripts may generate cases and collect raw evidence, but core execution, verification, recovery, and evidence-pack logic live in bottom-layer code.

Execution result JSON includes `execution_id`, `task_id`, `plan_id`, `contract_id`, `session_id`, `execution_mode`, `runtime_executed`, `execution_summary`, `session_steps`, and `step_results`.

Each step result includes `step_id`, `step_index`, `action`, `precondition_ok`, `runtime_action_executed`, `verification_ok`, `verification_type`, `verification_evidence`, `stop_code`, `failure_attribution`, and `duration_ms`.

## v6.3.0 PlanDraft to StepContract Compiler Protocol

v6.3.0 adds compile-only commands. These commands transform reviewed `AgentPlanDraft` JSON into structured `StepContract` JSON and v6.2 session-compatible dry-run step JSON. They do not execute Runtime actions, do not start Runtime sessions, and do not call `runtime-session-dispatch`.

Compile command:

- `plan-compile --input <plan_draft.json> --output <step_contract.json> --diagnostics <diagnostics.json>`

Validation command:

- `step-contract-validate --input <step_contract.json> --result <validation_result.json>`

Dry-run command:

- `step-contract-dry-run --input <step_contract.json> --session-steps-output <session_steps.json>`

Selftest command:

- `plan-compile-selftest`

Legacy compatibility:

- `step-contract-validate --file <legacy_step_contract.json>` remains the v5.1.1 validator path.
- `step-contract-validate --input <step_contract.json>` is the v6.3 validator path.

`StepContract` per-step records include `contract_id`, `task_id`, `plan_id`, `step_id`, `step_index`, `step_type`, `runtime_action`, `target`, `input_text`, `expected_context`, `action_precondition`, `verification_hint`, `risk_level`, `confirmation_policy`, `recovery_policy`, `stop_policy`, `session_policy`, `evidence_policy`, `created_at`, and `compiler_version`.

Compile diagnostics include `compile_ok`, `error_code`, `error_message`, `failed_step_id`, `missing_fields`, `unsafe_reason`, `repair_hint`, `emitted_step_count`, and `runtime_executed=false`.

Validation output includes `validation_ok`, `validation_errors`, `validation_warnings`, `executable`, `runtime_session_compatible`, `safe_for_developer_full_access`, and `safe_for_public_release`.

Dry-run output includes `session_steps`, `step_id`, `action`, `compiled_runtime_action`, `target`, `text`, `expected_context`, `action_precondition`, `verification_hint`, `cache_policy`, `force_reobserve`, `stop_on_failure`, `executable`, and `runtime_executed=false`.

Compile error codes:

- `COMPILE_MISSING_EXPECTED_CONTEXT`
- `COMPILE_MISSING_VERIFICATION_HINT`
- `COMPILE_UNSUPPORTED_ACTION`
- `COMPILE_UNSAFE_DIRECT_COORDINATE`
- `COMPILE_RISK_POLICY_MISSING`
- `COMPILE_CONFIRMATION_REQUIRED`
- `COMPILE_RECOVERY_POLICY_INVALID`
- `COMPILE_STOP_POLICY_MISSING`
- `COMPILE_TARGET_AMBIGUOUS`
- `COMPILE_SESSION_POLICY_INVALID`
- `COMPILE_SCHEMA_INVALID`

Safety boundary:

- `AgentPlanDraft` is not executable.
- `PlanCompiler` must run before a plan can become Runtime-consumable.
- Missing expected context or verification cannot compile to executable `StepContract`.
- Direct coordinates without accepted locator/evidence policy are rejected.
- `REAL_COMMIT` and `DESTRUCTIVE` require confirmation or developer-mode policy.
- `ACTIVE_PROTECTION_BLOCKED` and `CREDENTIAL_REQUIRED_BLOCKED` must not produce executable actions.
- Developer full access does not remove StepContract safety structure.

## Baseline Screen Evidence Capture Rule

Visible-screen evidence defaults to a PowerShell full-screen capture using `System.Drawing.Graphics.CopyFromScreen` after the target application is restored to a visible foreground position. This method records the current desktop pixels and is preferred for validating what the operator actually sees, especially when `winagent.exe screenshot --title ...` / `PrintWindow` misses custom-rendered, clipped, minimized, or bottom-layer UI content.

`PrintWindow` screenshots, OCR screenshots, and region reads remain valid diagnostics, but they are secondary to PowerShell full-screen evidence for visible UI state when the two disagree. If PowerShell capture is unavailable or the screenshot shows the wrong foreground, an overlay, a widget surface, a notification, or another window covering the target, the capture is invalid for target-state judgment until the target is made visible and captured again.

## v6.2.0 Persistent Runtime Session Protocol

v6.2.0 adds a bottom-layer persistent Runtime session path. The session path is a Runtime optimization and batching boundary only. It must not bypass RuntimeContextGuard, SafetyPolicy, target uniqueness, viewport checks, stale-target checks, SafeContextRecovery-compatible stop semantics, or HumanMode evidence rules.

Session lifecycle commands:

- `runtime-session-start --title <substring> [--process <exe>] [--hwnd <hwnd>] [--timeout-ms <int>]`
- `runtime-session-status --session-id <id>`
- `runtime-session-close --session-id <id>`
- `runtime-session-list`

Session action commands:

- `runtime-session-observe --session-id <id> [--screenshot true|false] [--uia true|false] [--force-reobserve true|false]`
- `runtime-session-locate --session-id <id> --target <selector> [--force-reobserve true|false]`
- `runtime-session-command --session-id <id> --action <action> [--target <selector>] [--text <text>] [--x <client_x>] [--y <client_y>] [--delta <int>] [--verification-hint <hint>] [--cache-policy <policy>] [--expected-title-pattern <regex>] [--expected-process-pattern <regex>] [--required-marker <regex>]`
- `runtime-session-dispatch --session-id <id> --steps-json <path> --result-json <path>`
- `runtime-session-act-and-verify --session-id <id> --primitive <primitive> ...`
- `runtime-session-type-and-verify --session-id <id> --target <selector> --text <text> [--verification-hint <hint>]`
- `runtime-session-scroll-and-locate --session-id <id> --target <selector> [--delta <int>]`

Every session command returns a structured JSON envelope with `ok`, `command`, `session_id`, `session_alive`, `session_status`, `error`, `data`, `timestamp`, and `duration_ms`.

Structured dispatch accepts JSON steps only. It is not a PlanCompiler and does not accept natural-language tasks. Step fields include `step_id`, `action`, `target`, `text`, `expected_context`, `action_precondition`, `verification_hint`, `cache_policy`, `force_reobserve`, `stop_on_failure`, `move_mode`, `type_mode`, `x`, `y`, and `delta`. A failed step stops later steps by default and records a `step_result`.

Supported session actions include `observe`, `locate`, `verify`, `click`, `type`, `scroll`, `click_and_verify_focus`, `click_and_verify_context`, `click_button_and_verify_marker`, `type_and_verify_text`, `scroll_and_verify_progress`, `scroll_and_locate`, and `scroll_and_locate_and_click`.

Verification hints include `state_contains:<text>`, `file_contains:<path>|<text>`, and session-scoped `uia_contains:<text>`.

Session observe cache stores observe id, hwnd, title/process/bounds, screenshot ref, UIA/OCR summaries, visible-text hash, element count, cache age, `action_since_observe`, and freshness. It is rejected after actions, stale age, window/title/process/bounds changes, foreground mismatch, scroll/page change, or explicit `force_reobserve`.

Session locator cache stores locator key, target metadata, rect/center, source/confidence, observe id, timestamps, valid action id, viewport state, and stale-check state. Cache hits still require freshness, uniqueness, viewport, target-current, and context checks. Stale locator reuse stops with `STOP_TARGET_STALE` unless the caller explicitly forces relocation/reobserve.

New session STOP codes: `STOP_SESSION_TARGET_STALE`, `STOP_SESSION_WINDOW_CLOSED`, `STOP_SESSION_FOREGROUND_CHANGED`, `STOP_SESSION_EXPIRED`, `STOP_SESSION_NOT_FOUND`, `STOP_SESSION_CLOSED`, and `STOP_TARGET_STALE`.

Legacy one-shot commands keep the old path when `--session-id` is absent. Compatible commands may route through the session dispatcher only when `--session-id` is present.

## v6.1.6 Final Scope Reset Protocol Status

v6.1.6 is accepted and the v6.1 series is closed. The accepted scope is Case1 QQ Mail fresh machine evidence PASS/frozen, bottom-layer StepCompletionGate PASS, and Case2 PyCharm visible UI execution closure. Case3/Case4, WeChat, TikTok, and the old integrated sequence are deferred and are not current gate blockers.

Case2 PyCharm accepted evidence records visible UI open/activation, editor click/focus, keyboard input through Runtime SendInput paths, SHIFT+F10 run trigger, ExecutionOutcomeClassifier output fields, and StepCompletionGate trace. The final output closure records PowerShell full-screen CopyFromScreen as the visible UI screenshot method and uses paired current-run console text for `DV616_SEQ`, `DV616_RUN_END`, and exit code verification.

v6.2.0 may begin Persistent Runtime Session and Latency Gate work after v6.1.6 acceptance. v6.1.6 does not implement Persistent Runtime, PlanCompiler, VLM, or Experience Memory.

## v6.1.6 Scope Reset Content1 Historical Protocol Status

The historical v6.1.6 scope-reset content1 gate preserved Case1 QQ Mail fresh machine evidence PASS/frozen and accepted a bottom-layer StepCompletionGate closure for Case2 readiness. During content1 only, `current_trusted_version` remained v6.1.5a and full v6.1.6 was not accepted until Case2 PyCharm passed. After the final Case2 closure, v6.1.6 is accepted.

New Runtime command:

- `step-completion-evaluate --input-json <path> --result-json <path>`

The command reads a `StepCompletionInput` JSON document, evaluates the step in C++ bottom-layer logic, writes a `StepCompletionResult` JSON evidence file, and returns a non-zero process exit when the step is not verified or the next step is not allowed. Failed steps must produce `step_verified=false` and `next_step_allowed=false`.

`StepCompletionInput` fields include `step_id`, `step_name`, `step_type`, `expected_context`, `expected_preconditions`, `action_name`, `action_result`, `raw_action_evidence`, `post_observe_required`, `post_observe_result`, `expected_postconditions`, and `failure_attribution_on_fail`. The evaluator also accepts explicit boolean fields such as `precondition_verified`, `action_executed`, `post_observe_performed`, and `postcondition_verified` for selftest and runner integration.

`StepCompletionResult` fields include `step_id`, `precondition_verified`, `action_executed`, `post_observe_performed`, `postcondition_verified`, `step_verified`, `next_step_allowed`, `stop_code`, `failure_attribution`, `reason`, and `evidence_path`.

Hard stop rules:

- `precondition_verified=false` forces `action_executed=false`, `step_verified=false`, and `next_step_allowed=false`.
- `action_executed=false` forces `step_verified=false` and `next_step_allowed=false`.
- `post_observe_required=true` with `post_observe_performed=false` forces `step_verified=false` and `next_step_allowed=false`.
- `postcondition_verified=false` forces `step_verified=false` and `next_step_allowed=false`.

Content1 does not run Case2, WeChat, TikTok, or the old integrated sequence. The old v6.1.6 four-case and integrated sequence scripts are superseded for the current PASS path. The existing `classify-execution-output` command remains a bottom-layer command, but this content1 pass does not implement or rerun ExecutionOutcomeClassifier work.

## v6.1.6 Execution Outcome Classifier Supplement

New Runtime command:

- `classify-execution-output --profile <profile> --before <path> --after <path> --result-json <path> --expected-start-marker <text> --expected-end-marker <text>`

The command classifies observable IDE/tool output into `run_triggered`, `execution_started`, `execution_completed`, and `execution_success` instead of treating every unexpected output as an untriggered run. The v6.1.6 implementation includes the `python` profile in `config\execution_profiles\python.json`; other language profiles are not claimed as complete support in this release.

The result JSON includes `run_triggered`, `execution_started`, `execution_completed`, `execution_success`, `exit_code_present`, `exit_code`, `runtime_command_observed`, `runtime_command_text`, `compiler_or_interpreter_observed`, `error_detected`, `error_category`, `error_language_hint`, `error_summary`, `output_lines_observed`, `expected_output_verified`, `current_run_verified`, `old_output_reuse_detected`, `raw_output_excerpt`, `classifier_profile`, and `classifier_confidence`.

`IndentationError` is classified as `SYNTAX_OR_INDENTATION_ERROR` with `run_triggered=true` when runtime output and an exit code are visible. Missing visible runtime output is the only normal path to `run_triggered=false`.

## v6.1.5a Visible Mouse-First Interaction Supplement

New script-level evidence commands:

- `v6_1_5a_mouse_first_interaction_runner.ps1`
- `v6_1_5a_mouse_first_interaction_verifier.ps1`
- `v6_1_5a_mouse_first_interaction_acceptance_gate.ps1`

Interaction modes:

- `mouse_first`: visible target must be located, the mouse must move to a locator-derived or explicitly marked coordinate, a click must be sent, and focus/context must be verified before text entry or follow-up action.
- `keyboard_allowed`: keyboard input may be used for text entry or explicitly recorded auxiliary selection after mouse focus, but it must not replace visible-target mouse verification.
- `keyboard_only_diagnostic`: keyboard-only paths may diagnose access or input availability, but they cannot count as v6.1.5a mouse-first PASS evidence.

Mouse-first evidence fields include `interaction_mode`, `mouse_first_required`, `mouse_first_passed`, `mouse_move_count`, `mouse_click_count`, `keyboard_shortcut_used`, `keyboard_only_path_used`, `fallback_used`, `fallback_reason`, `cursor_before`, `cursor_after_move`, `target_name`, `target_role`, `target_rect`, `target_center`, `target_visible`, `target_unique`, `locator_source`, `locator_confidence`, `coordinate_source`, `coordinate_source_type`, `mouse_move_started`, `mouse_move_completed`, `click_point`, `click_sent`, `focus_verified_after_click`, `context_verified_after_click`, `text_verified_after_type`, `action_executed`, `wrong_field_input_count`, and `continued_action_after_wrong_context`.

`coordinate_source_type` values are `locator_derived_coordinate`, `fixed_coordinate`, `fallback_coordinate`, and `vlm_assisted_runtime_validated`. Fixed coordinates must include an explicit reason and must not be represented as locator-derived evidence. VLM-assisted coordinates are valid only after RuntimeCandidateValidator accepts the candidate and Runtime recomputes the target center from the validated rect.

Runner output is raw and UNVERIFIED. Verifier output and gate reports are required before v6.1.5a can be promoted. `RAW_COMPLETED_UNVERIFIED` is not PASS. Keyboard-only focus chains, Win+R launch, Ctrl+L address focus, Tab-based focus, Enter-only search submission, backend opens, and no-mouse paths cannot be counted as v6.1.5a mouse-first PASS.

v6.1.5a only supplements visible mouse-first interaction evidence. Full Dynamic App/Web Developer FULL_ACCESS Automation RC is reserved for v6.1.6, and v6.2 remains disallowed from v6.1.5a.

## v6.1.5 Safe Context Recovery and Dynamic Diagnostics

New Runtime evidence commands:

- `safe-context-recovery --recovery-enabled true|false --recovery-scope <scope> --allowed-recovery-target <target> --disallowed-recovery-pattern <regex> --max-recovery-attempts <n> --recovery-action none|browser_open_url_human|explorer_open_path|observe_only --recovery-url <url> --recovery-path <path> --recovery-window-title-pattern <regex> --recovery-process-pattern <regex> --recovery-expected-marker <regex> --resume-policy <policy> --checkpoint-required true|false --checkpoint-available true|false --reobserve-required true|false --stop-if-active-protection true|false --stop-if-credential-required true|false --context-text <text> --context-file <path> --dry-run true|false --result-json <path> --evidence-jsonl <path>`
- `task-checkpoint-evaluate --task-id <id> --case-id <id> --step-index <n> --step-name <name> --verified-context true|false --verified-marker <marker> --verified-window-title <title> --verified-process <process> --input-state-hash <hash> --page-state-hash <hash> --safe-to-resume true|false --resume-from-step <n> --replay-from-step <n> --recovery-just-executed true|false --reobserve-performed true|false --expected-context-reverified true|false --current-input-state-hash <hash> --current-page-state-hash <hash> --result-json <path>`
- `failure-attribution-classify --error-code <code> --stop-code <code> --failure-reason <text> --context-text <text> --context-file <path> --target-type app|web|desktop --result-json <path>`

New script-level evidence commands:

- `v6_1_5_safe_context_recovery_runner.ps1`
- `v6_1_5_safe_context_recovery_verifier.ps1`
- `v6_1_5_safe_context_recovery_acceptance_gate.ps1`
- `v6_1_5_dynamic_diagnostics_runner.ps1`
- `v6_1_5_dynamic_diagnostics_verifier.ps1`
- `v6_1_5_dynamic_diagnostics_report.ps1`

Runner output is raw and UNVERIFIED. Verifier output and gate reports are required before v6.1.5 can be promoted. `RAW_COMPLETED_UNVERIFIED` is not PASS.

Safe recovery is allowed only for explicit low-risk local/mock/test targets and explicit browser test URLs. It must hard STOP on CAPTCHA, human verification, bot/script detection, account security verification, credential/code handoff, anti-cheat, active proctoring, or unclear targets. Ordinary content words such as test, exam, contest, interview, challenge, assessment, OJ, submit, code, and race are not STOP conditions by themselves.

v6.1.5 is Safe Recovery + Dynamic Diagnostics only. Full Dynamic App/Web Developer FULL_ACCESS Automation RC is reserved for v6.1.6, and v6.2 remains disallowed from v6.1.5.

## v6.1.4-rerun Runtime Guard And Browser Normalization

The following optional guard parameters are supported by Runtime action commands including `desktop-click`, `desktop-double-click`, `desktop-move`, `desktop-type`, `desktop-press`, `desktop-hotkey`, `click`, `double-click`, `right-click`, `scroll`, `adaptive-click`, `adaptive-double-click`, `adaptive-type`, `adaptive-scroll`, and `scroll-and-locate`.

- `--expected-process-pattern <regex>`
- `--expected-title-pattern <regex>`
- `--required-marker <regex>`
- `--wrong-page-pattern <regex>`
- `--active-protection-pattern <regex>`
- `--automation-pattern <regex>`
- `--loading-overlay-pattern <regex>`
- `--stop-on-wrong-context true|false`
- `--require-target-rect true|false`
- `--require-target-current true|false`
- `--require-target-unique true|false`
- `--require-target-inside-viewport true|false`
- `--expected-focus-marker <regex>`
- `--guard-trace-jsonl <path>`
- `--guard-result-json <path>`
- `--browser-normalize-before-action true|false`
- `--browser-normalize-mode conservative|off`

When no expected-context parameter is supplied, legacy command behavior is preserved. When guard parameters are supplied, Runtime evaluates the guard before input is sent. Guard failure returns `ok=false`, a non-zero process exit code, `action_executed=false`, and `continued_action_after_wrong_context=false`.

New browser surface commands:

- `browser-surface-normalize --mode conservative --guard-result-json <path>`
- `browser-open-url-human --url <url> --expected-marker <regex> --browser chrome|edge|auto --permission-mode <mode> --guard-trace-jsonl <path> --result-json <path>`

Browser normalization is conservative: ESC is allowed for browser suggestion/overlay surfaces; unknown page-body close buttons, login, captcha, human-verification, bot challenge, and automation-detection surfaces are not bypassed.

Versioning note for v6.1.4: v6.1.4 is a v6.1.x dynamic App/Web click accuracy and offset diagnostics repair stage. v6.1.3 is the current trusted baseline entering this stage. v6.1.4 adds script-level evidence commands `v6_1_4_dynamic_ui_runner.ps1`, `v6_1_4_dynamic_ui_verifier.ps1`, and `v6_1_4_dynamic_ui_acceptance_gate.ps1`; the same real scripts support the remediation flag `-StateGuardOnly` for wrong-context/precondition/baseline-guard evidence without WeChat or QQ Mail sends. It requires real dynamic UI evidence for PyCharm, WeChat `文件传输助手`, QQ Mail at `https://mail.qq.com`, and a one-time v6.1.2/v6.1.3 baseline regression replay. It does not enter v6.2, develop Persistent Runtime Session, compile PlanDraft to StepContract, execute Runtime natural-language Agent tasks, call or develop a real VLM Provider, add Experience Memory, add Workflow Template behavior, weaken HumanMode, weaken active-protection STOP, narrow public release permissions, or change the developer permission direction. Runner output is raw and UNVERIFIED. The verifier independently checks first-attempt quality, click offset, cursor-inside-target-rect, keyboard focus, wrong target, wrong field, stale target rect, and forbidden strict-action mechanisms. The acceptance gate blocks PASS without real dynamic UI evidence. The WeChat case may only send `这是一条测试信息` to `文件传输助手`; the QQ Mail case may only send to `1581782307@qq.com` with subject `测试邮件` and body `这是一个测试邮件`; login, CAPTCHA, human verification, security verification, account risk verification, or redirection away from QQ Mail must STOP/BLOCKED. The user may press F12 for emergency stop. v6.1.4 does not insert an extra send-confirmation popup, but it must verify the target object and content before send actions.

v6.1.4 runner timeout contract: real UI command steps use a 60 second timeout, PyCharm and QQ Mail cases have 15 minute case timeouts, WeChat has a 10 minute case timeout, the global runner timeout is 45 minutes, and heartbeat JSONL is written every 15 seconds with current case, current step, foreground window, last observe/action/log times, last error, and waiting reason. No-progress, timeout, login/security block, or F12 interruption produces partial artifacts and a blocked result instead of PASS.

Protocol status: frozen for v0.1.6.

Versioning note for v6.1.3: v6.1.3 is a v6.1.x baseline repair for real mouse wheel input and scroll-and-locate. v6.1.2 is the current trusted baseline entering this stage. v6.1.3 adds `adaptive-scroll`, `scroll-and-locate`, `v6_1_3_wheel_scroll_runner.ps1`, `v6_1_3_wheel_scroll_verifier.ps1`, and `v6_1_3_scroll_acceptance_gate.ps1`. It does not enter v6.2, develop Persistent Runtime Session, compile PlanDraft to StepContract, execute Runtime natural-language Agent tasks, call or develop a real VLM Provider, add Experience Memory, add Workflow Template behavior, weaken HumanMode, weaken active-protection STOP, narrow public release permissions, or change the developer permission direction. Strict scroll evidence must use `SendInput` plus `MOUSEEVENTF_WHEEL`; scrollbar track/right-rail click, scrollbar thumb drag, PageDown/ArrowDown, JS/DOM/WebDriver/CDP/Playwright/Selenium scroll, and UIA ScrollPattern cannot count as strict mouse wheel PASS. Runner output is raw and UNVERIFIED; real UI PASS must be decided by the verifier from raw `winagent.exe` output and accepted by the gate. Synthetic evidence, placeholder screenshots, hardcoded hwnd/rect, invalidated evidence, diagnostic-only results, and old v6.1.2 artifacts reused as v6.1.3 PASS are blocked.

Versioning note for v6.1.2: v6.1.2 is a real UI baseline sanity and pre-v6.2 test gate. v6.1.1 is the current trusted baseline entering this stage. v6.1.2 adds script-level evidence commands `v6_1_2_real_ui_baseline_runner.ps1`, `v6_1_2_real_ui_baseline_verifier.ps1`, and `v6_1_2_pre_v6_2_acceptance_gate.ps1`. It does not enter v6.2, compile PlanDraft to StepContract, execute Runtime natural-language Agent tasks, call a real VLM, add Experience Memory, add Workflow Template behavior, modify HumanMode, weaken active-protection STOP, narrow public release permissions, or change the developer permission direction. Runner output is raw and UNVERIFIED; real UI PASS must be decided by the verifier from raw `winagent.exe` HumanMode command output and then accepted by the gate. Synthetic evidence, placeholder screenshots, hardcoded hwnd/rect, invalidated evidence, diagnostic-only results, backend opens, direct file opens, JS/DOM/WebDriver/CDP/Playwright/Selenium actions, and UIA InvokePattern/ValuePattern actions cannot count as PASS. If Explorer Real UI Sanity, Browser Mail Mock Real UI Sanity, or Browser Mail Mock Repeat Run fails, v6.1.2 is blocked and v6.2 must not start.

Versioning note for v6.1.1: v6.1.1 repairs the v6.1 acceptance path. v6.1.0 is a BLOCKED attempt and is not a trusted baseline; the trusted baseline remains v6.0.0 unless v6.1.1 required tests, regressions, evidence integrity checks, and acceptance gate all pass. v6.1.1 adds script-level evidence commands `v6_1_1_humanmode_regression_triage.ps1` and `v6_1_1_evidence_acceptance_gate.ps1`. It does not enter v6.2, compile PlanDraft to StepContract, execute real Agent tasks, call a VLM, add Experience Memory, modify HumanMode, modify active-protection STOP, or change the developer permission direction. Missing required evidence or missing evidence pointers block acceptance; runner and implementation output cannot self-certify PASS.

Versioning note for v6.1.0: v6.1.0 adds the minimal planner/intention boundary commands `agent-intent-parse`, `agent-plan-draft`, and `agent-planner-validate`. It parses natural language into `TaskIntent` and generates non-executable `AgentPlanDraft` records only. `AgentPlanDraft` is not a `StepContract`, is not directly executable, and must be compiled in a future version before any Runtime task execution. Runtime remains the only executor. VLM-assisted mode remains assistive only through `provider_role="assistive_only"` and does not call a real VLM provider. v6.1.0 does not execute tasks, compile StepContract, add provider API key UI/accounts, add Experience Memory, add Failure Attribution, accelerate batch tasks, modify HumanMode, or modify active-protection STOP. Plan-to-StepContract compilation is reserved for v6.3.0 after the accepted v6.2.0 Persistent Runtime baseline.

Versioning note for v6.0.0: v6 starts the Agent Boundary and Runtime/VLM Mode Architecture track. It adds the compatible JSON command `agent-boundary-validate` for mode, executor, action-boundary, AgentTaskRequest, and AgentPlan validation. Runtime remains the only action executor. VLM-assisted mode may assist planning, interpretation, classification, and failure explanation, but it must not directly execute desktop actions. This version does not add a full Planner, real VLM provider calls, provider account/API key UI, Experience Memory, batch acceleration, HumanMode changes, or active-protection STOP changes.

Versioning note for v5.9.0-b: v5.x is an internal engineering stage number. v5.9.0-b is the HumanMode Visible UI Case Runner and remains pre-v6. v6 has not started. Before public release, DesktopVisual requires a later Release Normalization Pass and a separate release hygiene review.

Versioning note for v5.9.0-c: v5.9.0-c remains v5 and only completes strict HumanMode evidence for Case B/D plus Case C third-party App target resolution. It does not add v6 commands, VLM, Agent planning, public release permission narrowing, or a new command envelope.

Versioning note for v5.9.0-d: v5.9.0-d remains v5 and only fixes script-level Case D Explorer content-area locator evidence. It does not add v6 commands, VLM, Agent planning, permission-model changes, public release permission narrowing, or a new command envelope.

Versioning note for v5.9.0-e: v5.9.0-e remains v5 and only fixes HumanMode cursor motion pacing plus the HumanActionResult return contract. It does not add v6 commands, VLM, Agent planning, permission-model changes, public release permission narrowing, or a public release permission pass.

Versioning note for v5.9.1: v5.9.1 remains v5 and is the pre-v6 Runtime handoff gate. It validates HumanMode evidence, Task Runtime integration, CLI/Service exposure, active-protection STOP behavior, core v5 regression status, documentation, and artifacts. It does not enter v6, add VLM providers, add an Agent Planner, or narrow public release permissions.

Versioning note for v5.9.2: v5.9.2 remains v5 and only fixes active-protection STOP policy gaps found by the v5.9.1 gate. It does not add v6 commands, VLM providers, Agent planning, HumanMode locator changes, public release permission narrowing, or a new command envelope.

Versioning note for v5.10.0: v5.10.0 remains v5 and adds the non-VLM Adaptive HumanMode Control Loop core. It adds compatible JSON commands `adaptive-locate`, `adaptive-click`, `adaptive-double-click`, `adaptive-type`, and `adaptive-run-step`. It does not enter v6, add VLM providers, add an Agent Planner, narrow public release permissions, or change developer capability discovery.

Versioning note for v5.10.1 rebuilt: v5.10.1 remains v5 and reruns real UI adaptive Case D/E/F evidence from the trusted v5.10.0 Adaptive HumanMode Control Loop Core baseline. The old script-level `v5_10_1_adaptive_cases_runner.ps1` remains INVALIDATED and must not be used as real HumanMode PASS evidence or v6 handoff evidence. The rebuilt raw runner is `v5_10_1_real_ui_adaptive_cases_runner.ps1`; the independent verifier is `v5_10_1_real_ui_evidence_verifier.ps1`.

Versioning note for v5.10.2 rebuilt: v5.10.2 remains v5 and adds real TaskRuntime integration for `tasks\localhost_form_fill_submit_humanmode.task.json`. The flow must execute through TaskSession, StepContract, TaskRunner, Adaptive HumanMode Loop, real winagent HumanMode input, and runtime verification. TaskRuntime may report execution completion, but only `v5_10_2_taskruntime_evidence_verifier.ps1` may decide `REAL_TASKRUNTIME_HUMANMODE_PASS`.

Old v5.10.2 invalidation note: the previous v5.10.2 TaskRuntime handoff evidence used a hardcoded/simulated browser form flow and cannot be used as `ready_for_v6` evidence.

Rollback note for v5.10 invalidation: the old v5.10.1 and old v5.10.2 evidence remains invalid. v5.10.1 rebuilt evidence must come from raw winagent command output and independent verifier results. v5.10.2 rebuilt TaskRuntime evidence must come from real UI action traces and the independent TaskRuntime verifier. v6 has not started. Synthetic evidence, hardcoded rectangles, placeholder screenshots, and simulated PASS output are not valid command evidence.

v5 boundary note: v5 is a Task-Level Desktop Execution Runtime. It does not depend on VLM, does not add desktop Agent behavior, and does not add v6 commands. Runtime remains the only action executor; SafetyPolicy, PermissionProfile, HumanConfirmation, blocked-action rules, StepContract, Verification, and AuditTrail boundaries must not be bypassed.

This document freezes the v0.1 CLI protocol, case execution surface, JSON envelopes, audit log shape, and report expectations for v0.2 Codex Skill integration. Compatible additions may be made in future versions, but existing command names, required fields, error codes, and log/report formats must not be broken without a documented compatibility note.

v0.3.0 adds Windows UI Automation read-only commands as compatible additions. v0.3.1 adds UIA-located click and type commands. v0.3.2 adds OCR text-location command interfaces. v0.3.3 adds BMP image template location. v0.4.1 adds safety policy checks for input actions and case execution. v0.4.2 is a release-freeze documentation and packaging pass. v1.0.0 is the first formal release publication pass. v1.0.1 adds reliability and safety fixes for focus verification, file-read path allowlists, and capability reporting. v1.1.0 adds controlled input primitives. v1.2.0 adds `instant`, `fast-human`, and `demo-human` motion profiles with legacy `human` compatibility. v1.3.0 adds the read-only `observe` command. v1.4.0 adds the unified Selector locate/act system. v1.5.0 adds Case v2 format with key=value syntax, variables, wait_until, expect, and post-action verification. v2.0.0 adds real Windows OCR when WinRT OCR is available and keeps `OCR_UNAVAILABLE` fallback when it is not. v2.1.0 adds the real-app dogfood matrix. v2.2.0 upgrades the Skill workflow. v2.3.0 adds explicit local service mode. v3.0.0 adds `run-task` for closed-loop observe/locate/act/verify task execution. v3.0.1 adds Operator Motion Profile commands and `operator-human` move-mode. v3.0.1a requires explicit profile `source`, isolates synthetic test profiles, and rejects non-human profiles by default. v3.0.2 adds portable root resolution, `DESKTOPVISUAL_ROOT`, `project_root` in `version`, and `${PROJECT_ROOT}` safety config variables. v3.0.3 adds agent-agnostic adapters and a generic CLI contract. v3.0.4 adds benchmark evidence reports and evidence pack export. v3.0.5 adds the Safety Manifest and consent layer with `safety-report`, `policy-check`, and `consent-check`. v3.1.0 adds advanced selector fields, relative locators, near-text locators, nth disambiguation, and fallback selector chains. v3.1.1 fixes strict JSON validity for the Safety Manifest denied title patterns. v3.2.0 adds WindowSession resolution, foreground confirmation, DPI and monitor diagnostics, title-change detection, and TaskRunner window-session reporting. v3.3.0 adds the task template library and TaskRunner template expansion/reporting. v3.3.1 adds DEFAULT/FULL_ACCESS permission profiles, temporary FULL_ACCESS sessions, permission-status, unlock-full-access, lock-full-access, and permission-aware policy-check/run-task/service auditing. v3.3.2 makes `unlock-full-access` a local interactive CLI selector with explicit FULL_ACCESS phrase confirmation and non-interactive refusal. v3.3.3 adds FULL_ACCESS-gated `launch-app` for normal desktop/app launch with visible-window targeting and loop guard. v3.3.4 adds FULL_ACCESS-gated `browser-nav` for external web/browser navigation with URL audit and web stop conditions. v3.3.5 adds `form-control` and `form_action` form/control semantics so option controls are not treated as textboxes. v3.3.6 adds `decision-eval` and the `type: "decision"` task step for the General Decision Task Runtime, gated on the `content_decision` capability. v3.3.7 adds `SessionCheckpoint` report records and TaskRunner loop guard stops for repeated actions, URL loops, no progress, repeated window opens, scroll no-progress, max steps, and max duration. v3.3.8 adds `communication_step` and `CommunicationAction` report/audit records for user-authorized communication actions gated on the `communication` capability. v3.3.9 adds `coding-eval` and the `type: "coding"` task step for local simulated coding-practice workflows gated on the `content_decision` capability. v3.3.10 adds Full Access benchmark/evidence harness scripts and reports without changing the command envelope. v3.4.0 adds the Recovery Strategy Engine for configured, auditable, max-bounded TaskRunner recovery records. v3.5.0 stabilizes service protocol v1.0 with a unified service response envelope, `/health-check`, `/read-report`, and protocol-versioned service audit entries. v3.6.0 adds a bounded developer-tool dogfood matrix with local HTML and PowerShell scenarios, report metadata, and `dogfood_selftest.ps1` without changing the command envelope. v3.7.0 is the public release-candidate documentation, evidence, adapter, and repository-hygiene pass without new command envelope changes. v4.1.0 adds read-only `observe2` visual source integration, provider registry reporting, image-template provider candidates, and `ACTION_BLOCKED_SEMANTIC_UNRESOLVED` for unresolved visual-only selectors. v4.2.0 adds read-only `observe-loop` and `observe2 --loop` event streams with Screen Delta, Perception Cache accounting, debounce, loop guards, JSONL artifacts, and no action execution. v4.3.0 adds `latency_benchmark.ps1` as a script-level evidence pack without adding new desktop-control commands. v4.4.0 adds read-only Dynamic UI Recovery routing and `dynamic-ui-recovery` for local deterministic fixtures. v4.5.0 adds read-only App Profile reporting and profile locator metadata through `profile-report` and compatible `locate --profile --profile-locator` additions. v4.6.0 adds `v4_visual_dogfood.ps1` as a script-level evidence harness for local visual developer workflow dogfood without adding new desktop-control commands. v4.7.0 adds `v4_rc_check.ps1` as a script-level release candidate evidence aggregator without adding new desktop-control commands. v5.0.5 adds TaskSession validation, dry-run state transitions, a minimal local mock task runner, and task-level artifacts through `task-session-validate`, `task-session-transition`, and `task-session-run`. v5.1.5 adds StepContract validation, precondition checks, post-action verification, and structured failure classification through `step-contract-validate`, `step-precondition-check`, `step-verify`, and `step-failure-classify`. v5.2.5 adds RecoveryPolicy validation, low-risk recovery evaluation, EscalationRequest generation, and SafeStop checks through `recovery-policy-validate`, `recovery-evaluate`, `escalation-request-create`, and `safe-stop-check`. v5.3.5 adds risk action classification, ConfirmationRequest artifacts, confirmation gate checks, and a local mock confirmation flow through `risk-action-classify`, `confirmation-request-create`, `confirmation-gate-check`, and `confirmation-flow-run`. v5.4.6 adds Task Template v2 validation and App Profile binding resolution through `task-template-v2-validate` and `task-template-v2-resolve`. v5.5.6 adds controlled file path, file picker, attachment verification, cross-window, and local mail mock attach commands through `file-path-resolve`, `file-picker-flow`, `attachment-verify`, `cross-window-check`, and `local-mail-attach-flow`. v5.6.6 adds the script-level task dogfood benchmark through `task_dogfood_benchmark.ps1` and `v5_6_acceptance.ps1`; no new command envelope is required. v5.7.6 stabilizes external TaskSession execution through `run-task`, `task-status`, `task-events`, `task-report`, `task-confirm`, `task-cancel`, and the service task API. v5.8.7 is the pre-v6 Task Execution Release Candidate hardening and revalidation consolidation; it adds no new command envelope, records that v5.x is an internal engineering stage before a public Version Normalization Pass, and does not start v6. Existing v1/v2 case formats, legacy TaskRunner `run-task --file --report`, CLI commands, JSON envelopes, and audit log format remain compatible.

Versioning note: the v5.x numbers are internal engineering stage numbers. Before public release, a Version Normalization Pass will map them to `0.x.x` prerelease versions; the first formal stable public release remains `1.0.0`.

Compatibility note for v1.5.0: v1.4.0 and earlier commands remain fully compatible. Case v2 is enabled by `case_version=2` as the first non-comment line in .case files; files without this declaration use v1 format. No CLI commands, JSON envelopes, or audit log formats are changed.

## Stable Commands

- `version`
- `windows`
- `find`
- `screenshot`
- `permission-status`
- `unlock-full-access`
- `lock-full-access`
- `launch-app`
- `browser-nav`
- `form-control`
- `decision-eval`
- `coding-eval`
- `agent-boundary-validate`
- `agent-intent-parse`
- `agent-plan-draft`
- `agent-planner-validate`
- `observe`
- `observe2`
- `observe-loop`
- `dynamic-ui-recovery`
- `adaptive-locate`
- `adaptive-click`
- `adaptive-double-click`
- `adaptive-type`
- `adaptive-run-step`
- `adaptive-scroll`
- `scroll-and-locate`
- `profile-report`
- `target-semantics-guard-check`
- `classify-execution-output`
- `locate`
- `act`
- `click`
- `double-click`
- `right-click`
- `scroll`
- `drag`
- `press`
- `hotkey`
- `type`
- `desktop-move`
- `desktop-click`
- `desktop-double-click`
- `desktop-press`
- `desktop-hotkey`
- `desktop-type`
- `clipboard-set`
- `clipboard-paste`
- `focus`
- `active-window`
- `mouse-position`
- `read-file`
- `uia-tree`
- `uia-find`
- `uia-click`
- `uia-type`
- `find-text`
- `click-text`
- `read-window-text`
- `read-region-text`
- `wait-text`
- `assert-text-contains`
- `motion-record`
- `motion-calibrate`
- `motion-profile-info`
- `motion-profile-validate`
- `motion-profile-clear`
- `task-session-validate`
- `task-session-transition`
- `task-session-run`
- `task-status`
- `task-events`
- `task-report`
- `task-confirm`
- `task-cancel`
- `step-contract-validate`
- `step-precondition-check`
- `step-verify`
- `step-failure-classify`
- `recovery-policy-validate`
- `recovery-evaluate`
- `escalation-request-create`
- `safe-stop-check`
- `risk-action-classify`
- `confirmation-request-create`
- `confirmation-gate-check`
- `confirmation-flow-run`
- `find-image`
- `click-image`
- `adaptive-locate`
- `adaptive-click`
- `adaptive-double-click`
- `adaptive-type`
- `adaptive-run-step`
- `run-case`
- `serve`
- `run-task`

## Unified Command JSON

The following commands use the unified JSON envelope:

- `version`
- `find`
- `screenshot`
- `permission-status`
- `unlock-full-access`
- `lock-full-access`
- `launch-app`
- `browser-nav`
- `form-control`
- `decision-eval`
- `coding-eval`
- `agent-boundary-validate`
- `agent-intent-parse`
- `agent-plan-draft`
- `agent-planner-validate`
- `observe`
- `observe2`
- `observe-loop`
- `dynamic-ui-recovery`
- `adaptive-locate`
- `adaptive-click`
- `adaptive-double-click`
- `adaptive-type`
- `adaptive-run-step`
- `profile-report`
- `locate`
- `act`
- `click`
- `double-click`
- `right-click`
- `scroll`
- `drag`
- `press`
- `hotkey`
- `type`
- `desktop-move`
- `desktop-click`
- `desktop-double-click`
- `desktop-press`
- `desktop-hotkey`
- `desktop-type`
- `clipboard-set`
- `clipboard-paste`
- `focus`
- `active-window`
- `mouse-position`
- `read-file`
- `uia-tree`
- `uia-find`
- `uia-click`
- `uia-type`
- `find-text`
- `click-text`
- `read-window-text`
- `read-region-text`
- `wait-text`
- `assert-text-contains`
- `motion-record`
- `motion-calibrate`
- `motion-profile-info`
- `motion-profile-validate`
- `motion-profile-clear`
- `task-session-validate`
- `task-session-transition`
- `task-session-run`
- `step-contract-validate`
- `step-precondition-check`
- `step-verify`
- `step-failure-classify`
- `recovery-policy-validate`
- `recovery-evaluate`
- `escalation-request-create`
- `safe-stop-check`
- `risk-action-classify`
- `confirmation-request-create`
- `confirmation-gate-check`
- `confirmation-flow-run`
- `find-image`
- `click-image`
- `run-case`
- `run-task`

Success:

```json
{
  "ok": true,
  "command": "click",
  "timestamp": "2026-05-25 18:40:01",
  "duration_ms": 123,
  "target": {
    "title": "Agent Test Window",
    "hwnd": "0x123456",
    "pid": 1234
  },
  "data": {}
}
```

Failure:

```json
{
  "ok": false,
  "command": "click",
  "timestamp": "2026-05-25 18:40:01",
  "duration_ms": 123,
  "target": null,
  "error": {
    "code": "WINDOW_NOT_FOUND",
    "message": "Target window was not found."
  },
  "data": {}
}
```

`windows` returns a stable listing envelope:

```json
{
  "ok": true,
  "windows": [
    {
      "hwnd": "0x123456",
      "pid": 1234,
      "title": "Agent Test Window",
      "rect": {
        "left": 10,
        "top": 20,
        "right": 650,
        "bottom": 440
      }
    }
  ]
}
```

## Command Reference

### version

Parameters: none.

Success JSON:

```json
{
  "ok": true,
  "command": "version",
  "timestamp": "2026-05-25 18:40:01",
  "duration_ms": 0,
  "target": null,
  "data": {
    "version": "1.4.0",
    "build_time": "May 25 2026 19:30:00",
    "platform": "Windows",
    "project_root": "D:\\desktopvisual",
    "capabilities": {
      "available": [
        "window_find",
        "window_screenshot",
        "real_mouse_click",
        "keyboard_press",
        "text_type",
        "read_file",
        "uia_tree",
        "uia_find",
        "uia_click",
        "uia_type",
        "find_image",
        "click_image",
        "safety_policy",
        "read_path_policy",
        "run_case",
        "audit_log",
        "markdown_report"
      ],
      "stub": [
        { "name": "find_text", "ocr_available": false },
        { "name": "click_text", "ocr_available": false }
      ],
      "experimental": [
        "image_template_location"
      ]
    }
  }
}
```

Failure JSON: only invalid process-level failures are expected. If emitted, the unified failure envelope is used with `UNKNOWN_ERROR` or `AUDIT_LOG_FAILED`.

Possible `error.code`: `AUDIT_LOG_FAILED`, `UNKNOWN_ERROR`.

Safety limits: no desktop control is performed.

### safety-report

Parameters: none.

Success JSON includes `manifest_loaded`, `safety_conf_loaded`, `allowed_titles`, `allowed_processes`, `allowed_read_roots`, `allowed_write_roots`, `denied_categories`, `runtime_limits`, `audit_enabled`, `warnings`, `report_json`, and `report_markdown`.

Output files:

```text
D:\desktopvisual\artifacts\safety\safety_report.md
D:\desktopvisual\artifacts\safety\safety_report.json
```

Safety limits: read-only policy inspection. It performs no input and does not enumerate arbitrary windows.

### permission-status

Parameters: none.

Success JSON returns `data.permission_mode`, `data.default_profile`, `data.full_access_profile`, and `data.full_access`. `data.full_access` includes `exists`, `active`, `expired`, `session_id`, `scope`, `ttl_seconds`, `remaining_ttl_seconds`, `created_at_unix_ms`, `expires_at_unix_ms`, and `path`.

Safety limits: read-only permission inspection. It performs no desktop input and does not unlock FULL_ACCESS.

### unlock-full-access

Parameters:

- `--ttl <seconds>`: optional positive TTL in seconds. Default is 900. The runtime caps excessively large values.
- `--scope <task-only|session-only>`: optional scope. Default is `session-only`.

Interactive flow:

1. The command prints permission choices to the local console stderr stream: `[1] DEFAULT` and `[2] FULL_ACCESS`.
2. Choosing `1` removes any active FULL_ACCESS session and returns `data.permission_mode="DEFAULT"`.
3. Choosing `2` prints a risk warning and requires typing `ENABLE FULL_ACCESS` exactly.
4. Only after exact local keyboard confirmation does the command create a temporary FULL_ACCESS session.

Success JSON for FULL_ACCESS returns `data.permission_mode="FULL_ACCESS"`, `data.full_access_session_id`, `data.full_access`, and `data.interactive_selection="FULL_ACCESS"`. Success JSON for DEFAULT returns `data.permission_mode="DEFAULT"` and `data.interactive_selection="DEFAULT"`. The session is temporary and stored under `artifacts\permission`; it is never written as the default permission mode and never records a "do not ask again" state.

Possible `error.code`: `INVALID_ARGUMENT`, `FULL_ACCESS_REQUIRES_INTERACTIVE_CONFIRMATION`, `AUDIT_LOG_FAILED`.

Safety limits: unlocks only the local temporary permission gate after local interactive confirmation. It rejects piped stdin, non-console runners, automated confirmation arguments such as `--confirm` or `--yes`, task-file confirmation, and service endpoint confirmation. It does not perform desktop input, does not create a service session, does not bypass immutable safety stops, and does not change `config\safety.conf`.

### lock-full-access

Parameters: none.

Success JSON returns `data.permission_mode="DEFAULT"` and the inactive `data.full_access` status. It immediately removes the temporary FULL_ACCESS session.

Possible `error.code`: `FILE_WRITE_FAILED`, `AUDIT_LOG_FAILED`.

Safety limits: local permission-state cleanup only. It performs no desktop input.

### policy-check

Parameters:

- `--title <title>`: required target title to check.
- `--process <process>`: required executable name to check.
- `--action <action>`: required action name to check.
- `--path <path>`: optional path for future path-scoped decisions.
- `--permission-mode <DEFAULT|FULL_ACCESS>`: optional permission mode. Default is `DEFAULT`.
- `--full-access-session-id <id>`: required when `--permission-mode FULL_ACCESS`.

Success JSON returns `data.allow=true`, `data.permission_mode`, the allow reason, and `data.permission_decision`. Denial returns `SAFETY_POLICY_DENIED`, `FULL_ACCESS_SESSION_REQUIRED`, or an immutable stop code with `data.allow=false`, `matched_rule`, and `matched_category` when applicable.

Safety limits: dry-run only. It does not focus, click, type, read UI, or execute the action.

### consent-check

Parameters:

- `--title <title>`: required target title substring.

Success JSON returns the resolved visible target, process name, foreground status, and `consent_requirements`. Missing or ambiguous windows return `WINDOW_NOT_FOUND` or `WINDOW_NOT_UNIQUE`. Sensitive categories return `SAFETY_POLICY_DENIED`.

Safety limits: read-only target validation. It does not show UI, request consent interactively, focus the window, or send input.

### launch-app

Parameters:

- `--kind <exe|desktop-shortcut|start-menu|explorer|this-pc>`: launch type. Default is `exe`.
- `--path <path>`: executable, shortcut, shell target, or Explorer target path. Required except for `explorer` and `this-pc`.
- `--target-title <title>`: required visible window title substring expected after launch.
- `--process <process.exe>`: required target process name expected after launch.
- `--permission-mode <DEFAULT|FULL_ACCESS>`: optional permission mode. Default is `DEFAULT`.
- `--full-access-session-id <id>`: required when `--permission-mode FULL_ACCESS`.
- `--wait-ms <milliseconds>`: optional wait for the target window. Default is `5000`.
- `--loop-threshold <n>`: optional repeated-launch threshold. Default is `3`.
- `--max-window-spawn <n>`: optional visible-window growth threshold. Default is `5`.

Success JSON returns `data.kind`, `data.path`, `data.permission_mode`, `data.capability`, `data.full_access_session_id`, `data.window_count_before`, `data.window_count_after`, `data.target_window`, and `data.permission_decision`. `data.target_window` includes `title`, `process`, `hwnd`, `pid`, and `rect`.

Failure JSON uses the unified failure envelope. Possible `error.code`: `INVALID_ARGUMENT`, `SAFETY_POLICY_DENIED`, `FULL_ACCESS_SESSION_REQUIRED`, `USER_TAKEOVER_REQUIRED`, `CREDENTIAL_INPUT_DETECTED`, `PROTECTED_DESKTOP_DETECTED`, `ANTI_AUTOMATION_DETECTED`, `ANTI_CHEAT_DETECTED`, `WINDOW_NOT_VISIBLE`, `WINDOW_NOT_UNIQUE`, `WINDOW_SPAWN_LOOP`, `FILE_NOT_FOUND`, `AUDIT_LOG_FAILED`.

Safety limits: DEFAULT rejects broad app/global desktop launch. FULL_ACCESS requires a valid temporary session id. The command launches only normal user-interactive targets through the Windows shell, then waits for a unique visible target window. It does not control hidden/background windows, does not bypass UAC or protected desktops, and stops on credential, login, anti-cheat, anti-automation, and repeated spawn conditions.

### browser-nav

Parameters:

- `--url <url>`: required URL to open or simulate.
- `--browser <path>`: optional browser executable path. When omitted, the default browser is used.
- `--target-title <title>`: optional visible browser window title substring expected after launch.
- `--process <process.exe>`: optional browser process name expected after launch.
- `--action <open|scroll|click-link|click-button>`: optional browser action. Default is `open`.
- `--permission-mode <DEFAULT|FULL_ACCESS>`: optional permission mode. Default is `DEFAULT`.
- `--full-access-session-id <id>`: required when `--permission-mode FULL_ACCESS` and the URL is external.
- `--no-open <true|false>`: optional test/simulation mode. Default is `false`.
- `--wait-ms <milliseconds>`: optional wait for a target browser window. Default is `8000`.
- `--loop-threshold <n>`: optional repeated URL threshold. Default is `5`.

Success JSON returns `data.url`, `data.final_url`, `data.page_title`, `data.action`, `data.permission_mode`, `data.capability`, `data.full_access_session_id`, `data.opened`, `data.simulated`, `data.load_result`, `data.last_action`, `data.target_window`, and `data.permission_decision`. `data.target_window` is `null` unless a unique visible browser target is requested and found.

Failure JSON uses the unified failure envelope. Possible `error.code`: `INVALID_ARGUMENT`, `SAFETY_POLICY_DENIED`, `FULL_ACCESS_SESSION_REQUIRED`, `USER_TAKEOVER_REQUIRED`, `CAPTCHA_DETECTED`, `ANTI_AUTOMATION_DETECTED`, `URL_REDIRECT_LOOP`, `NO_PROGRESS_DETECTED`, `REPEATED_ACTION_LIMIT`, `WINDOW_NOT_VISIBLE`, `WINDOW_NOT_UNIQUE`, `AUDIT_LOG_FAILED`.

Safety limits: DEFAULT rejects non-local external URLs. FULL_ACCESS requires a valid temporary session id for external web navigation. The command audits every requested URL and never automates login, credential, captcha, payment, anti-automation, or bot-detection flows. URL redirect loops stop with `URL_REDIRECT_LOOP`; no-progress and repeated-action guards use `NO_PROGRESS_DETECTED` and `REPEATED_ACTION_LIMIT` when detected by higher-level browser workflows.

### form-control

Parameters:

- `--html <path>`: required local HTML source for deterministic DOM-like form inspection.
- `--field-id <id>`: field id/name to resolve.
- `--label <label>`: label to resolve when `--field-id` is omitted.
- `--min-confidence <number>`: optional confidence threshold. Default is `0.50`.

Success JSON returns `data.control` as a `FormControl` object:

```json
{
  "field_id": "choice",
  "label": "Choice A; Choice B",
  "control_type": "radio",
  "required": false,
  "options": ["a", "b"],
  "rect": {"left": 0, "top": 0, "right": 0, "bottom": 0},
  "source": "dom_like_visual_hints",
  "confidence": 0.94,
  "recommended_action": "select_radio"
}
```

Supported `control_type` values: `textbox`, `textarea`, `radio`, `checkbox`, `dropdown`, `combobox`, `button`, `link`, `date_picker`, `file_upload`, `code_editor`, `captcha/challenge`, and `unknown`.

Action mapping: `textbox -> fill_text`, `textarea -> fill_textarea`, `radio -> select_radio`, `checkbox -> toggle_checkbox`, `dropdown/combobox -> select_option`, `button -> click_button`, `link -> click_link`, `date_picker -> select_date`, `file_upload -> select_file`, `code_editor -> input_code`, and `captcha/challenge` or `unknown -> stop`.

Failure JSON uses the unified failure envelope. Possible `error.code`: `INVALID_ARGUMENT`, `FILE_NOT_FOUND`, `FILE_READ_FAILED`, `LOCATOR_NOT_FOUND`, `FIELD_NOT_UNIQUE`, `FIELD_CONFIDENCE_LOW`, `CAPTCHA_DETECTED`, `AUDIT_LOG_FAILED`.

Safety limits: this command is local-source inspection and action planning. It does not submit forms, solve captcha/challenge controls, infer unknown controls as textboxes, or act on low-confidence controls.

### decision-eval

Dry-run General Decision Task evaluation over a local HTML/DOM-like fixture. It chooses one action for one resolved control based on an explicit user goal and the current page/control context. It does not click, type, focus, or inspect a live window.

Parameters:

- `--html <path>`: required local HTML source for deterministic DOM-like page/control context.
- `--user-goal <text>`: required explicit user goal. Page content can never supply or change it.
- `--field-id <id>`: target field id/name to resolve.
- `--label <label>`: target label to resolve when `--field-id` is omitted.
- `--control-type <type>`: optional explicit control-type hint.
- `--value <v>` / `--option <o>` / `--text <t>`: optional value to apply.
- `--allow-submit`: authorizes submit decisions. Without it, submit controls stop with `USER_TAKEOVER_REQUIRED`.
- `--min-confidence <number>`: optional confidence threshold. Default is `0.50`.
- `--permission-mode <DEFAULT|FULL_ACCESS>`: recorded into the decision context. Default is `DEFAULT`.
- `--window <title>` / `--url <url>`: optional context recorded into the decision context.

Success JSON returns `data.decision_context` (a `DecisionTaskContext`) and `data.decision_record` (a `DecisionRecord`):

```json
{
  "decision_context": {
    "user_goal": "answer question 1",
    "permission_mode": "DEFAULT",
    "current_window": "",
    "current_url": "",
    "observed_content_summary": "controls=4; text=1; choice=2; action=1; other=0",
    "allowed_actions": ["fill", "select", "click", "scroll"],
    "denied_actions": ["credential_input", "captcha_solve", "anti_automation_bypass", "submit"],
    "risk_level": "low"
  },
  "decision_record": {
    "decision_type": "select",
    "source": "user_goal",
    "reason": "Action mapped from recognized control type to advance the user goal.",
    "selected_action": "select_radio",
    "target_field_id": "q1",
    "target_label": "Answer A; Answer B",
    "control_type": "radio",
    "chosen_value_present": true,
    "confidence": 0.94,
    "user_goal_preserved": true,
    "safety_check_result": "ok",
    "timestamp": "2026-06-05 07:35:02"
  }
}
```

`decision_type` is `select`, `fill`, `click`, `submit`, or `stop`. `source` stays `user_goal` even when the page injects override instructions.

Failure JSON uses the unified failure envelope. Possible `error.code`: `INVALID_ARGUMENT`, `FILE_NOT_FOUND`, `FILE_READ_FAILED`, `LOCATOR_NOT_FOUND`, `FIELD_NOT_UNIQUE`, `FIELD_CONFIDENCE_LOW`, `CAPTCHA_DETECTED`, `ANTI_AUTOMATION_DETECTED`, `CREDENTIAL_INPUT_DETECTED`, `USER_TAKEOVER_REQUIRED`, `AUDIT_LOG_FAILED`.

Safety limits: `decision-eval` is a dry-run check. It does not send input, browse remote URLs, generate goals, let page content override the user goal, bypass captcha/AI-detection/anti-cheat controls, or unlock FULL_ACCESS.

### coding-eval

Dry-run Coding and Problem-Solving Web Workflow evaluation over a local HTML/DOM-like OJ fixture. It reads the problem context, detects a code editor and Run Code control, records the requested workflow action, and classifies visible result text. It does not execute code, browse remote URLs, focus windows, or submit anything.

Parameters:

- `--html <path>`: required local HTML source for deterministic coding page context.
- `--user-goal <text>`: required explicit user goal. Page/problem content can never supply or change it.
- `--action <read_problem|select_language|input_code|run_code|read_result|revise_code|stop_before_submit|submit_if_explicitly_allowed>`: optional action. Default is `read_problem`.
- `--language <language>`: optional language recorded into `CodingWorkflowContext`.
- `--code <text>`: optional code text for summary only. Full code is not written to reports.
- `--code-path <path>`: optional safe local code path recorded instead of full code.
- `--revision-count <n>`: optional revision counter for audit.
- `--allow-submit`: explicitly authorizes `submit_if_explicitly_allowed`; otherwise submit stops with `USER_TAKEOVER_REQUIRED`.
- `--permission-mode <DEFAULT|FULL_ACCESS>`: recorded into the audit context. Task execution still gates coding steps on `content_decision`.
- `--window <title>` / `--url <url>`: optional context recorded for audit.

Success JSON returns `data.coding_workflow_context` and `data.coding_workflow_record`:

```json
{
  "coding_workflow_context": {
    "problem_title": "Two Sum",
    "problem_statement_summary": "Given an array...",
    "examples_summary": "Example: ...",
    "constraints_summary": "2 <= nums.length <= 10000",
    "language": "cpp",
    "editor_detected": true,
    "run_button_detected": true,
    "submit_allowed": false,
    "result_state": "SAMPLE_PASS"
  },
  "coding_workflow_record": {
    "action": "run_code",
    "source": "user_goal",
    "reason": "Coding workflow action recorded from explicit user goal over local page context.",
    "code_summary": "code_length=0; lines=0",
    "code_path": "",
    "revision_count": 0,
    "submit_clicked": false,
    "submit_basis": "default_stop_before_submit",
    "safety_check_result": "ok",
    "timestamp": "2026-06-06 04:59:05"
  }
}
```

`result_state` is one of `COMPILE_ERROR`, `RUNTIME_ERROR`, `WRONG_ANSWER`, `TIME_LIMIT`, `SAMPLE_PASS`, `ACCEPTED`, or `UNKNOWN_RESULT`.

Failure JSON uses the unified failure envelope. Possible `error.code`: `INVALID_ARGUMENT`, `FILE_NOT_FOUND`, `FILE_READ_FAILED`, `LOCATOR_NOT_FOUND`, `USER_TAKEOVER_REQUIRED`, `CAPTCHA_DETECTED`, `ANTI_AUTOMATION_DETECTED`, `AUDIT_LOG_FAILED`.

Safety limits: `coding-eval` is a dry-run check over local fixtures. It stops on login/password surfaces, captcha, anti-automation/AI-detection text, and missing code editor or Run Code controls for actions that require them. It does not bypass paid limits, scrape problem sets, batch submit, or bypass proctoring, anti-cheat, captcha, credentials, or anti-automation controls. The v3.3.9/v3.3.10 development runtime does not hard-stop solely on exam, assessment, hiring-test, certification, or rated-contest keywords because stage 9 explicitly allowed those categories under a user-authorized task; public releases must add an explicit permission policy before exposing these workflows.

Release packaging policy: `D:\desktopvisual` is the broad local development and evaluation tree for future simulated-exam accuracy and operation-accuracy testing. It must not be submitted as the public release project. Public release work must be prepared in a separate `D:\desktopvisual-release` tree with restricted permission policy for exam, interview assessment, hiring-test, certification, rated-contest, proctored, and similar workflows.

### windows

Parameters: none.

Success JSON: the stable listing envelope shown above.

Failure JSON: this command does not currently emit a structured failure for normal enumeration.

Possible `error.code`: none in the frozen v0.1.6 implementation.

Safety limits: reads visible top-level window titles, process IDs, and rectangles only. It does not click, type, save files, or close windows.

### find

Parameters:

- `--title <substring>`: required target window title substring.

Success JSON:

```json
{
  "ok": true,
  "command": "find",
  "timestamp": "2026-05-25 18:40:01",
  "duration_ms": 1,
  "target": {
    "title": "Agent Test Window",
    "hwnd": "0x123456",
    "pid": 1234
  },
  "data": {
    "requested_title": "Agent Test Window",
    "rect": {
      "left": 10,
      "top": 20,
      "right": 650,
      "bottom": 440
    }
  }
}
```

Failure JSON: unified failure envelope.

Possible `error.code`: `INVALID_ARGUMENT`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `AUDIT_LOG_FAILED`.

Safety limits: requires a non-empty title substring and exactly one visible top-level window match. It does not perform input.

### screenshot

Parameters:

- `--title <substring>`: required target window title substring.
- `--out <path>`: required BMP output path.

Success JSON:

```json
{
  "ok": true,
  "command": "screenshot",
  "timestamp": "2026-05-25 18:40:01",
  "duration_ms": 16,
  "target": {
    "title": "Agent Test Window",
    "hwnd": "0x123456",
    "pid": 1234
  },
  "data": {
    "out": "D:\\desktopvisual\\artifacts\\before.bmp",
    "method": "PrintWindow"
  }
}
```

Failure JSON: unified failure envelope.

Possible `error.code`: `INVALID_ARGUMENT`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `SCREENSHOT_FAILED`, `AUDIT_LOG_FAILED`.

Safety limits: requires exactly one visible top-level window match. It captures a window image only and does not perform input.

### observe

Parameters:

- `--title <substring>`: required target window title substring.
- `--screenshot true|false`: optional, default `true`.
- `--uia true|false`: optional, default `true`.
- `--max-elements <n>`: optional maximum returned UIA elements, default `80`.

Success JSON includes `target_window`, `window_session`, `active_window`, `focus_verified`, `mouse`, `screenshot`, `uia`, `safety`, and `warnings` in `data`. Screenshot output is written under `D:\desktopvisual\artifacts\observe_<timestamp>.bmp` when enabled. `observe` does not focus the target, click, type, paste, or otherwise modify window contents.

`data.window_session` is the v3.2.0 window session record:

```json
{
  "requested_title": "Agent Test Window",
  "requested_process": "TestWindow.exe",
  "title": "Agent Test Window",
  "hwnd": "0x123456",
  "pid": 1234,
  "process_name": "TestWindow.exe",
  "rect": {"left": 10, "top": 10, "right": 410, "bottom": 310},
  "visible": true,
  "iconic": false,
  "foreground": {"is_foreground": true, "foreground_controllable": true},
  "dpi": 96,
  "monitor": {
    "device_name": "\\\\.\\DISPLAY1",
    "primary": true,
    "rect": {"left": 0, "top": 0, "right": 1920, "bottom": 1080},
    "work_rect": {"left": 0, "top": 0, "right": 1920, "bottom": 1040}
  }
}
```

If screenshot capture fails while UIA succeeds, or UIA fails while screenshot capture succeeds, `observe` can still return `ok=true` and records the partial failure in `data.warnings`.

Possible `error.code`: `INVALID_ARGUMENT`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `AUDIT_LOG_FAILED`, `UNKNOWN_ERROR`. Ambiguous window failures include `data.candidates` with each candidate title, hwnd, pid, process name, and rect.

Safety limits: requires exactly one visible top-level window match. It is read-only and does not require input-action safety approval.

### observe2

Parameters:

- `--title <substring>`: required target window title substring.
- `--process <exe>`: optional process filter.
- `--screenshot`: optional flag to capture a screen frame screenshot.
- `--include-uia`: optional flag documenting that UIA should be included. UIA is enabled by default unless `--no-uia` is provided.
- `--no-uia`: optional flag to disable UIA for this observation.
- `--max-elements <n>`: optional maximum UIA candidates, default `50`.
- `--image-template <bmp>`: optional BMP template path for the image-template visual source.
- `--tolerance <0..255>`: optional image-template tolerance, default `0`.

Success JSON includes:

- `data.screen_frame`: frame id, target window, window session, and screenshot metadata.
- `data.providers`: provider registry records for `uia`, `ocr`, `screen_delta`, `image_template`, `local_visual_provider`, `cloud_vlm`, and `agent_provider`.
- `data.perception_sources`: sources that were available or degraded during the observation.
- `data.element_graph`: normalized element nodes built from provider candidates.
- `data.locator_candidates`: standardized candidates with `source`, `source_version`, `label`, `role`, `text`, `rect`, `confidence`, `attributes`, `artifact_path`, `provider_latency_ms`, `semantic_status`, `fusion_status`, and `risk_status`.
- `data.scene_state`: `status`, focus state, candidate count, provider count, and warnings. Supported status values are `normal`, `loading`, `dialog_open`, `error`, `success`, `blocked`, and `unknown`.
- `data.change_events`: initial observation plus dynamic events such as `loading_started`, `dialog_opened`, `error_appeared`, `success_appeared`, and `target_ready` when detected.
- `data.dynamic_recovery`: finite recovery route for the detected scene state.
- `data.routers`: base PerceptionRouter, SemanticResolver, RiskRouter, and ActionExecutor gate decisions.
- `data.action_decision`: one of `AUTO_EXECUTE`, `ESCALATE_TO_VLM`, `REQUIRE_HUMAN_CONFIRMATION`, or `STOP`.

Example:

```powershell
D:\desktopvisual\bin\winagent.exe observe2 --title "Agent Test Window" --screenshot --include-uia --max-elements 50
D:\desktopvisual\bin\winagent.exe observe2 --title "Agent Test Window" --screenshot --image-template D:\desktopvisual\artifacts\dev4.1.0\observe2_template.bmp --tolerance 0
```

`image_template` uses the existing local BMP matcher. `local_visual_provider`, `cloud_vlm`, and `agent_provider` are provider-ready placeholders in v4.1.0. When unset they report `unavailable`; if environment configuration is present they report `degraded` because no external runtime integration is implemented in this version.

Possible `error.code`: `INVALID_ARGUMENT`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `AUDIT_LOG_FAILED`, `UNKNOWN_ERROR`.

Safety limits: `observe2` is read-only. Visual providers only produce candidates and cannot trigger input. Unresolved visual-only candidates are blocked by `act` with `ACTION_BLOCKED_SEMANTIC_UNRESOLVED`.

### observe-loop

`observe-loop` and `observe2 --loop` run a bounded, read-only realtime observation loop. They do not execute clicks, typing, task planning, or VLM calls.

Parameters:

- `--title <substring>`: required target window title substring.
- `--process <exe>`: optional process filter.
- `--interval-ms <n>`: loop interval, default `250`.
- `--max-duration-ms <n>`: maximum loop duration, default `5000`.
- `--max-events <n>`: maximum emitted events, default `20`.
- `--max-no-change-rounds <n>`: maximum unchanged rounds before exit, default `10`.
- `--debounce-ms <n>`: duplicate event suppression window, default `300`.
- `--roi x,y,w,h`: optional client-coordinate region for ROI OCR.
- `--changed-regions-only`: records that high-cost perception is limited to changed rounds.
- `--out <events.jsonl>`: optional JSONL event artifact path.
- `--report <report.md>`: optional Markdown report path.
- `--stop-file <path>`: optional file path; creating the file stops the loop.

Success JSON includes:

- `data.events_path` and `data.report_path`.
- `data.event_count`, `data.loop_count`, `data.duration_ms`, and `data.stop_reason`.
- `data.cache_hits`, `data.cache_misses`, `data.roi_ocr_runs`, `data.uia_refresh_runs`, and `data.screenshot_runs`.
- `data.supported_event_types`: `window_changed`, `foreground_changed`, `region_changed`, `text_changed`, `element_appeared`, `element_disappeared`, `dialog_opened`, `dialog_closed`, `loading_started`, `loading_finished`, `error_appeared`, `success_appeared`, `element_moved`, `element_enabled`, `element_disabled`, `target_ready`, and `safety_blocked`.

Each JSONL event includes `index`, `timestamp`, `type`, `reason`, `target_title`, `region`, `latency_ms`, `artifacts`, `cache`, and `loop_guard`. Unchanged rounds reuse cached perception state and do not run ROI OCR or UIA refresh.

Safety limits: `observe-loop` is observation only. Safety Manifest denied targets emit `safety_blocked` and stop. It must not be used as unattended control for sensitive pages.

### dynamic-ui-recovery

`dynamic-ui-recovery` evaluates Dynamic UI Recovery routes over local deterministic HTML fixtures. It is read-only and does not focus, click, type, browse, or call VLMs.

Parameters:

- `--html <path>`: required local HTML fixture path.
- `--previous-html <path>`: optional previous fixture path for change-event comparison.
- `--candidate-id <id>`: optional candidate id used for element movement/enabled comparisons.
- `--candidate-source <source>`: optional source, default `uia`.
- `--semantic-status <status>`: optional semantic status, default `resolved`.
- `--risk-status <status>`: optional risk status, default `normal`.

Success JSON includes:

- `data.scene_state.status`: `normal`, `loading`, `dialog_open`, `error`, `success`, `blocked`, or `unknown`.
- `data.change_events`: `loading_started`, `loading_finished`, `dialog_opened`, `dialog_closed`, `error_appeared`, `success_appeared`, `element_moved`, `element_enabled`, `element_disabled`, and `target_ready` when detected.
- `data.dynamic_recovery`: finite route such as `loading_wait_observe_loop`, `classify_dialog_safe_route`, `dynamic_reobserve_relocate`, or `blocked_stop_immediately`.
- `data.routers`: base PerceptionRouter, SemanticResolver, RiskRouter, and ActionExecutor gate decisions.
- `data.action_decision`: `AUTO_EXECUTE`, `ESCALATE_TO_VLM`, `REQUIRE_HUMAN_CONFIRMATION`, or `STOP`.

Safety limits: `blocked` is final `STOP` and is not routed to VLM. `dialog_open` never authorizes underlay clicks. `unknown` does not auto-execute. Visual-only unresolved candidates remain blocked by `act` with `ACTION_BLOCKED_SEMANTIC_UNRESOLVED`.

### adaptive-locate / adaptive-click / adaptive-double-click / adaptive-type / adaptive-run-step

The adaptive commands expose the v5.10.0 Adaptive HumanMode Control Loop core and are used by the rebuilt v5.10.1 real UI adaptive cases. They remain v5 Runtime commands and do not add VLM, Agent Planner behavior, DOM actions, WebDriver/CDP/Playwright/Selenium actions, UIA InvokePattern/ValuePattern actions, ShellExecute/Start-Process/Invoke-Item actions, or a public release permission narrowing pass.

`adaptive-locate` parameters:

- `--target <text>`: expected target name/text.
- `--target-kind <kind>`: `explorer_item`, `browser_field`, `browser_button`, `desktop_shortcut`, `app_window`, or `generic_ui_element`.
- `--role <role>`: optional expected UIA/control role.
- `--title <substring>`: optional target window title substring.
- `--process <name>`: optional process name filter.
- `--mock explorer|browser-form`: diagnostic mock locator path used by v5.10.0 selftests.

`adaptive-click` and `adaptive-double-click` accept the same target/title/process fields and return an `AdaptiveActionResult` data object. `adaptive-type --text <text>` sends visible keyboard input through the adaptive action path. `adaptive-run-step --diagnostic <name>` currently supports `candidate-validation`, `coordinate-mapping`, `explorer-locator`, `browser-form-locator`, and `retry-budget`.

`adaptive-locate` JSON data includes:

- `ok`, `target_id`, `selected_candidate`, `candidates`, `rejected_candidates`.
- `locate_attempt_count`, `locator_methods_attempted`, `screenshot_path`, `content_rect`, and `failure_reason`.
- Candidate fields include `candidate_id`, `target_id`, `matched_name`, `matched_text`, `role`, `source`, `hwnd`, `window_title`, `process_name`, `rect`, `center_x`, `center_y`, `confidence`, visibility/offscreen flags, required-region/forbidden-region flags, `reason`, and `rejection_reason`.

`adaptive-click` JSON data includes:

- `target_candidate`, `human_action_result`, `verification_result`, `reobserve_count`, `retry_count`, `final_state`, and `error`.
- `human_action_result.verification.cursor_inside_target_rect_before_click` must be present for click-style results.

Failure reasons include `TARGET_NOT_FOUND`, `MULTIPLE_CANDIDATES_LOW_CONFIDENCE`, `TARGET_RECT_MISSING`, `TARGET_OFFSCREEN`, `TARGET_IN_FORBIDDEN_REGION`, `WRONG_WINDOW`, `FOREGROUND_CHANGED`, `CURSOR_NOT_INSIDE_TARGET_RECT`, `CLICK_NO_EFFECT`, `TEXT_NOT_ENTERED`, `FIELD_NOT_FOCUSED`, `BUTTON_NOT_ACTIVATED`, `VERIFICATION_TIMEOUT`, `ACTIVE_PROTECTION_DETECTED`, `POLICY_DEFECT`, `RETRY_BUDGET_EXHAUSTED`, and `COORDINATE_MAPPING_FAILED`.

HumanMode constraints: each click must come from the current observe/locate candidate rect, must validate the cursor inside that rect before click, must execute through real paced HumanMode input, and must verify state after action or re-observe/retry/stop. Preset coordinate scripts and stale coordinates are not strict adaptive evidence.

### Real UI Evidence Integrity Rule

For rebuilt v5.10.1 Case D/E/F evidence, PASS must be generated only by `v5_10_1_real_ui_evidence_verifier.ps1` from raw `winagent.exe` command evidence collected by `v5_10_1_real_ui_adaptive_cases_runner.ps1`. The runner may write raw command logs, stdout/stderr, result-json files, screenshots, foreground/cursor snapshots, and preliminary observations. It must not write final PASS, `ready_for_v6=true`, synthetic `action_trace`, synthetic `locator_trace`, synthetic `human_action_results`, placeholder screenshots, hardcoded hwnd, hardcoded rect, backend actions, or direct launch evidence as PASS.

This runner/verifier split is mandatory: the runner collects only raw and unverified evidence, while the verifier independently computes every PASS/FAIL result.

The verifier must read raw command lines, stdout JSON, exit codes, timestamps, result-json files when present, screenshots/overlays, foreground windows, cursor positions, and trace timing before deciding `STRICT_MOUSE_TARGET_HUMANMODE_PASS`, `STRICT_ADAPTIVE_HUMANMODE_PASS`, `FAIL`, `SKIP_ENVIRONMENT`, `FAIL_EVIDENCE_INVALID`, `FAIL_SYNTHETIC_EVIDENCE_DETECTED`, `FAIL_BACKEND_ACTION_DETECTED`, `FAIL_HARDCODED_RECT_DETECTED`, or `FAIL_PLACEHOLDER_SCREENSHOT_DETECTED`.

`HumanActionResult` is required for real mouse and keyboard HumanMode actions. Mouse click/double-click evidence must include target rect, cursor actual-before-click point, cursor-inside-target-rect verification, backend/direct-launch flags, and motion timing. Keyboard evidence must include action type, foreground before/after, key/text length metadata, backend/direct-launch flags, and exit code.

## Selector

Selector format is `<method>:key=value,key=value`. Values may contain basic spaces; complex escaping is reserved for a future case format.

Supported selectors:

- `coord:x=80,y=90`
- `uia:name=Click Me`
- `uia:name_contains=Click,type=Button`
- `uia:type=Edit,index=0`
- `uia:automation_id=1001`
- `uia:class_name=Button,name=Click Me,type=Button`
- `image:path=D:\desktopvisual\assets\click_button.bmp,tolerance=10`
- `text:contains=Click Me`
- `relative:relation=below,anchor=uia:name=Click Me,target_role=Edit,nth=0`
- `relative:relation=inside_window,target_role=Button,nth=1`
- `near_text:text=Click Me,target_role=Edit,position=below,nth=0`
- `chain:uia:automation_id=missing||uia:name=Click Me`

UIA selector fields:

- `name`, `name_contains`
- `type` or `role`
- `automation_id`
- `class_name`
- `nth` for explicit zero-based selection when multiple elements match
- `index` remains accepted as a legacy alias for existing tasks

Relative selector fields:

- `relation=right_of|left_of|below|above|inside_window`
- `anchor=<selector>` for all relations except `inside_window`
- target filters: `target_name`, `target_name_contains`, `target_type`, `target_role`, `target_automation_id`, `target_class_name`
- `nth` for explicit zero-based selection when multiple targets match

Near-text selector fields:

- `text=<text>` or `contains=<text>`
- `match=exact|contains`; default is `exact`
- `position=right_of|left_of|below|above`
- target filters: `target_name`, `target_name_contains`, `target_type`, `target_role`, `target_automation_id`, `target_class_name`
- `anchor_nth` disambiguates multiple text anchors; `nth` disambiguates multiple nearby targets

Fallback selector chains use `chain:` followed by child selectors separated with `||`. The first successful child selector wins. Every attempt is recorded in `fallback_attempts` with order, selector, success state, method, error code, and failure reason.

Selector failures use:

- `INVALID_SELECTOR` for unknown selector types or malformed selector fields.
- `LOCATOR_NOT_FOUND` for zero matches.
- `LOCATOR_NOT_UNIQUE` for multiple matches when no `nth` or legacy `index` disambiguates the selector.
- `PROFILE_LOCATOR_NOT_FOUND` when `--profile --profile-locator` cannot resolve a valid built-in profile locator.
- `OCR_UNAVAILABLE` when a `text:` selector is used while OCR is unavailable.

### profile-report

Parameters:

- `--path <path>`: optional profile file or directory. Defaults to `D:\desktopvisual\profiles`.

Success data includes `profiles_root`, `loaded_count`, `invalid_count`, and `profiles`. Each profile record includes path, name, app kind, process/title/window-class match fields, validity, validation errors and warnings, `common_locator_count`, and `effective_capabilities`.

`effective_capabilities.can_override_safety_manifest` is always `false`. App Profiles are application adapters only and cannot grant Permission Profile capabilities or loosen Safety Manifest rules.

Invalid profiles are reported with `valid=false` and do not crash the runtime.

### locate

Parameters:

- `--title <substring>`: required target window title substring.
- `--selector <selector>`: selector string.
- `--profile <name>` and `--profile-locator <name>`: optional alternative to `--selector`. The runtime resolves a common locator from an App Profile and then runs the existing selector locator.

Success data includes `ok`, `selector`, `method`, `locate_method`, `final_method`, `match_count`, `confidence`, `client_point`, `screen_point`, `rect`, optional `element`, `matched_text`, `matched_name`, `source`, `failure_reason`, and `artifacts.report_path`. `chain:` selectors also include `fallback_attempts`. Profile locators also include `profile_candidate` with `source="app_profile"` and `action_gate="requires_runtime_safety_policy"`.

Safety limits: requires exactly one visible target window. It performs no input and does not require input-action safety approval. Profile locators do not bypass later `act` safety approval, foreground checks, semantic gates, visual-only unresolved blocks, or Safety Manifest stops.

### act

Parameters:

- `--title <substring>`: required target window title substring.
- `--selector <selector>`: required selector string.
- `--action click|double-click|right-click|type|focus`: required action.
- `--text <text>`: required for `type`.
- `--move-mode instant|fast-human|demo-human|human|operator-human`: optional for mouse-backed actions.
- `--profile <path>`: optional profile path for `operator-human`; defaults to `D:\desktopvisual\config\operator_motion_profile.json`.
- `--allow-synthetic-profile`: optional test-only flag allowing `source=synthetic` or `source=sample` profiles.
- `--fallback fast-human`: optional explicit fallback when `operator-human` profile is missing, invalid, or rejected by source policy.

Behavior: `act` first runs the selector locator. Input actions then require safety policy approval and focus-verified input paths. For UIA button clicks, `InvokePattern` is preferred when available. For UIA edit typing, `ValuePattern` is preferred when available. Otherwise actions fall back to target-window client-coordinate input at the located center point.

### click

Parameters:

- `--title <substring>`: required target window title substring.
- `--x <int>`: required target client x coordinate.
- `--y <int>`: required target client y coordinate.
- `--move-mode instant|fast-human|demo-human|human|operator-human`: optional, default `human`; `human` maps to `operator-human` and requires a valid local Operator Motion Profile. Use `instant` only when an automated test explicitly needs direct cursor placement.
- `--move-duration-ms <int>`: optional non-negative duration. If omitted for human modes, duration is auto-calculated from distance.
- `--profile <path>`: optional profile path for `operator-human`; defaults to `D:\desktopvisual\config\operator_motion_profile.json`.
- `--allow-synthetic-profile`: optional test-only flag allowing `source=synthetic` or `source=sample` profiles.
- `--fallback fast-human`: optional. Used only when `human`/`operator-human` fails because the profile is missing, invalid, or rejected by source policy.

Success JSON:

```json
{
  "ok": true,
  "command": "click",
  "timestamp": "2026-05-25 18:40:01",
  "duration_ms": 1012,
  "target": {
    "title": "Agent Test Window",
    "hwnd": "0x123456",
    "pid": 1234
  },
  "data": {
    "target_client_x": 80,
    "target_client_y": 90,
    "target_screen_x": 120,
    "target_screen_y": 160,
    "cursor_before_x": 400,
    "cursor_before_y": 300,
    "cursor_after_x": 120,
    "cursor_after_y": 160,
    "move_mode": "operator-human",
    "move_duration_ms": 900,
    "move_steps": 90,
    "move_profile": "operator-human",
    "path_type": "operator-statistical"
  }
}
```

Failure JSON: unified failure envelope.

Possible `error.code`: `INVALID_ARGUMENT`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `WINDOW_FOCUS_FAILED`, `SAFETY_POLICY_DENIED`, `EMERGENCY_STOP`, `MOTION_PROFILE_NOT_FOUND`, `MOTION_PROFILE_INVALID`, `MOTION_PROFILE_NOT_HUMAN`, `MOTION_PROFILE_SOURCE_REQUIRED`, `MOTION_PROFILE_TEST_ONLY`, `CURSOR_MOVE_FAILED`, `SEND_INPUT_FAILED`, `UNKNOWN_ERROR`, `AUDIT_LOG_FAILED`.

Safety limits: uses real desktop input through `SendInput`. Coordinates are target-window client coordinates, not unrestricted full-screen coordinates. The target title must resolve to exactly one visible top-level window and pass `D:\desktopvisual\config\safety.conf` title/process checks. The command does not use `SendMessage`, `PostMessage`, or `BM_CLICK`.

### press

Parameters:

- `--title <substring>`: required target window title substring.
- `--key <KEY>`: required key name.

Supported keys: single letters `A`-`Z`, single digits `0`-`9`, `SPACE`, `ENTER`, `ESC`, `TAB`, `LEFT`, `RIGHT`, `UP`, `DOWN`.

Success JSON:

```json
{
  "ok": true,
  "command": "press",
  "timestamp": "2026-05-25 18:40:01",
  "duration_ms": 10,
  "target": {
    "title": "Agent Test Window",
    "hwnd": "0x123456",
    "pid": 1234
  },
  "data": {
    "key": "SPACE"
  }
}
```

Failure JSON: unified failure envelope.

Possible `error.code`: `INVALID_ARGUMENT`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `WINDOW_FOCUS_FAILED`, `SAFETY_POLICY_DENIED`, `EMERGENCY_STOP`, `SEND_INPUT_FAILED`, `UNKNOWN_ERROR`, `AUDIT_LOG_FAILED`.

Safety limits: sends a single key press to the uniquely matched target window only after title/process safety checks pass.

### type

Parameters:

- `--title <substring>`: required target window title substring.
- `--text <text>`: required text argument.
- `--type-mode instant|fast-human|demo-human|human`: optional, default `human`; `human` maps to `demo-human`. Use `instant` only when an automated test explicitly needs fast Unicode input.
- `--char-delay-ms <int>`: optional non-negative delay for `human` mode, default `80`.

Success JSON:

```json
{
  "ok": true,
  "command": "type",
  "timestamp": "2026-05-25 18:40:01",
  "duration_ms": 500,
  "target": {
    "title": "Agent Test Window",
    "hwnd": "0x123456",
    "pid": 1234
  },
  "data": {
    "type_mode": "human",
    "char_delay_ms": 80,
    "text_length": 5
  }
}
```

Failure JSON: unified failure envelope.

Possible `error.code`: `INVALID_ARGUMENT`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `WINDOW_FOCUS_FAILED`, `SAFETY_POLICY_DENIED`, `EMERGENCY_STOP`, `SEND_INPUT_FAILED`, `UNKNOWN_ERROR`, `AUDIT_LOG_FAILED`.

Safety limits: sends Unicode keyboard input to the uniquely matched target window only after title/process safety checks pass. Human type checks the configured emergency stop key. Audit logging records type metadata, not the full typed text. Case files and reports can contain test text, so this version is not appropriate for passwords or secrets.

### input primitives

v1.1.0 adds these unified-envelope commands:

- `double-click --title <substring> --x <client_x> --y <client_y> [--move-mode instant|fast-human|demo-human|human|operator-human] [--move-duration-ms <int>] [--profile <path>] [--allow-synthetic-profile] [--fallback fast-human]`
- `right-click --title <substring> --x <client_x> --y <client_y> [--move-mode instant|fast-human|demo-human|human|operator-human] [--move-duration-ms <int>] [--profile <path>] [--allow-synthetic-profile] [--fallback fast-human]`
- `scroll --title <substring> --x <client_x> --y <client_y> --delta <int> [--move-mode instant|fast-human|demo-human|human|operator-human] [--profile <path>] [--allow-synthetic-profile] [--fallback fast-human]`
- `adaptive-scroll --title <substring>|--hwnd <hwnd> [--x <client_x> --y <client_y>] [--direction up|down|left|right] [--notches <n>|--delta <int>] [--move-mode instant|fast-human|demo-human|human|operator-human] [--verify-content-change true|false] [--output-json <path>] [--screenshot-dir <path>]`
- `scroll-and-locate --title <substring>|--hwnd <hwnd> --target-text <text> [--region auto|client|content|list] [--direction down|up] [--max-scrolls <n>] [--notches-per-scroll <n>] [--move-mode instant|fast-human|demo-human|human|operator-human] [--locator uia|ocr|hybrid|auto] [--output-json <path>] [--screenshot-dir <path>]`
- `drag --title <substring> --from-x <client_x> --from-y <client_y> --to-x <client_x> --to-y <client_y> [--move-mode instant|fast-human|demo-human|human|operator-human] [--duration-ms <int>] [--profile <path>] [--allow-synthetic-profile] [--fallback fast-human]`
- `hotkey --title <substring> --keys <combo>`
- `clipboard-set --text <text>`
- `clipboard-paste --title <substring> [--text <text>]`
- `focus --title <substring>`
- `active-window`
- `mouse-position`

All target-window input primitives require a unique `--title`, pass `SafetyPolicy`, verify focus before input, write the unified JSON envelope, and append to `artifacts\agent_audit.log`. `clipboard-set` does not target a window, but it is still treated as a clipboard/backend fallback and must pass `VisibleOperationPolicy` before writing clipboard content; success returns `text_length` and `operation_priority`. `active-window` returns `hwnd`, `pid`, `title`, `process_name`, and `rect`; `mouse-position` returns `screen_x` and `screen_y`.

v1.2.0 mouse actions return these motion fields in `data`: `move_profile`, `path_type`, `distance_px`, `duration_ms`, `step_count`, and `emergency_stop_checked`. `instant` uses direct cursor placement. `fast-human` and `demo-human` remain explicit legacy curved-path modes. v3.0.1 adds `operator-human`, which returns `operator_profile_path`, `operator_profile_quality`, and `synthesized_point_count` when a valid local profile is used. Since v3.0.2, mouse `human` resolves to `operator-human` by default and does not silently fall back to legacy curved paths.

v6.1.3 real wheel commands:

- `scroll` remains compatible and now reports `input_type="mouse_wheel"`, `sendinput_used`, `mouseeventf_wheel_used`, and `wheel_event_count` on successful wheel output.
- `adaptive-scroll` is the strict wheel primitive wrapper. It sends real mouse wheel input through `SendInput` and `MOUSEEVENTF_WHEEL` after moving the cursor to a safe client scroll region point. It records `data.wheel_action_result` with wheel delta/notches/direction, cursor positions, foreground hwnd, window/client rects, scroll region, before/after screenshots, before/after content signatures, `content_changed`, and `change_score`.
- `scroll-and-locate` runs observe/locate -> wheel -> reobserve -> content-change verification -> locate target. It stops with `WHEEL_NO_CONTENT_CHANGE` when wheel input does not move visible content and with `FAIL_TARGET_NOT_FOUND_AFTER_SCROLL` at `--max-scrolls`. It does not auto-click the target.
- Strict v6.1.3 PASS evidence cannot use scrollbar track click, right-rail click, scrollbar thumb drag, PageDown/ArrowDown, JS/DOM/WebDriver/CDP/Playwright/Selenium scroll, or UIA ScrollPattern. Any scrollbar fallback must be diagnostic-only unless real wheel was attempted first, content did not change after reobserve, and `fallback_reason` is recorded.

The v6.1.3 script-level evidence commands are:

```powershell
D:\desktopvisual\v6_1_3_wheel_scroll_runner.ps1 -Root D:\desktopvisual -SkipBuild
D:\desktopvisual\v6_1_3_wheel_scroll_verifier.ps1 -Root D:\desktopvisual
D:\desktopvisual\v6_1_3_scroll_acceptance_gate.ps1 -Root D:\desktopvisual
```

### read-file

Parameters:

- `--path <path>`: required file path.

Success JSON:

```json
{
  "ok": true,
  "command": "read-file",
  "timestamp": "2026-05-25 18:40:01",
  "duration_ms": 1,
  "target": null,
  "data": {
    "path": "D:\\testrepo\\testwindow\\runtime\\state.txt",
    "content": "window_title=Agent Test Window\n",
    "content_length": 32
  }
}
```

Failure JSON: unified failure envelope.

Possible `error.code`: `INVALID_ARGUMENT`, `SAFETY_POLICY_DENIED`, `FILE_NOT_FOUND`, `FILE_READ_FAILED`, `AUDIT_LOG_FAILED`.

Safety limits: reads a text file only after the normalized path is inside `allowed_read_roots`. Paths containing `..` traversal are denied before file access.

### uia-tree

Parameters:

- `--title <substring>`: required target window title substring.

Success JSON:

```json
{
  "ok": true,
  "command": "uia-tree",
  "timestamp": "2026-05-26 00:30:01",
  "duration_ms": 12,
  "target": {
    "title": "Agent Test Window",
    "hwnd": "0x123456",
    "pid": 1234
  },
  "data": {
    "elements": [
      {
        "name": "Click Me",
        "control_type": "Button",
        "rect": {
          "left": 250,
          "top": 283,
          "right": 370,
          "bottom": 319
        },
        "enabled": true,
        "offscreen": false
      }
    ]
  }
}
```

Failure JSON: unified failure envelope.

Possible `error.code`: `INVALID_ARGUMENT`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `UIA_INIT_FAILED`, `UIA_TREE_FAILED`, `AUDIT_LOG_FAILED`.

Safety limits: reads Windows UI Automation element metadata only. It does not click, type, invoke controls, use OCR, or use image/template matching. The target title must resolve to exactly one visible top-level window.

### uia-find

Parameters:

- `--title <substring>`: required target window title substring.
- `--name <text>`: required UI Automation element name. Matching accepts exact matches and substring matches.

Success JSON:

```json
{
  "ok": true,
  "command": "uia-find",
  "timestamp": "2026-05-26 00:30:01",
  "duration_ms": 12,
  "target": {
    "title": "Agent Test Window",
    "hwnd": "0x123456",
    "pid": 1234
  },
  "data": {
    "requested_name": "Click Me",
    "name": "Click Me",
    "control_type": "Button",
    "rect": {
      "left": 250,
      "top": 283,
      "right": 370,
      "bottom": 319
    },
    "enabled": true,
    "offscreen": false
  }
}
```

Failure JSON: unified failure envelope.

Possible `error.code`: `INVALID_ARGUMENT`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `UIA_INIT_FAILED`, `UIA_TREE_FAILED`, `UIA_ELEMENT_NOT_FOUND`, `UIA_ELEMENT_NOT_UNIQUE`, `AUDIT_LOG_FAILED`.

Safety limits: reads Windows UI Automation element metadata only. It does not invoke the matched control. If no element or multiple elements match, the command fails instead of guessing.

### uia-click

Parameters:

- `--title <substring>`: required target window title substring.
- `--name <text>`: required UI Automation element name. Matching accepts exact matches and substring matches.

Success JSON:

```json
{
  "ok": true,
  "command": "uia-click",
  "timestamp": "2026-05-26 00:40:01",
  "duration_ms": 44,
  "target": {
    "title": "Agent Test Window",
    "hwnd": "0x123456",
    "pid": 1234
  },
  "data": {
    "locate_method": "uia",
    "action_method": "invoke_pattern",
    "element_name": "Click Me",
    "control_type": "Button",
    "rect": {
      "left": 250,
      "top": 283,
      "right": 370,
      "bottom": 319
    },
    "result": "success"
  }
}
```

Failure JSON: unified failure envelope.

Possible `error.code`: `INVALID_ARGUMENT`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `WINDOW_FOCUS_FAILED`, `SAFETY_POLICY_DENIED`, `EMERGENCY_STOP`, `UIA_INIT_FAILED`, `UIA_TREE_FAILED`, `UIA_ELEMENT_NOT_FOUND`, `UIA_ELEMENT_NOT_UNIQUE`, `CURSOR_MOVE_FAILED`, `SEND_INPUT_FAILED`, `UNKNOWN_ERROR`, `AUDIT_LOG_FAILED`.

Safety limits: requires exactly one target window, a title/process safety policy match, and exactly one UIA element match. It first tries `InvokePattern`; if unavailable, it clicks the element rectangle center through the existing real mouse input path.

### uia-type

Parameters:

- `--title <substring>`: required target window title substring.
- `--name <text>`: required UI Automation element name. Matching accepts exact matches and substring matches.
- `--text <text>`: required text argument.

Success JSON:

```json
{
  "ok": true,
  "command": "uia-type",
  "timestamp": "2026-05-26 00:40:01",
  "duration_ms": 44,
  "target": {
    "title": "Agent Test Window",
    "hwnd": "0x123456",
    "pid": 1234
  },
  "data": {
    "locate_method": "uia",
    "action_method": "value_pattern",
    "element_name": "Input",
    "control_type": "Edit",
    "rect": {
      "left": 250,
      "top": 353,
      "right": 610,
      "bottom": 381
    },
    "text_length": 5,
    "type_mode": "value_pattern"
  }
}
```

Failure JSON: unified failure envelope.

Possible `error.code`: `INVALID_ARGUMENT`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `WINDOW_FOCUS_FAILED`, `SAFETY_POLICY_DENIED`, `EMERGENCY_STOP`, `UIA_INIT_FAILED`, `UIA_TREE_FAILED`, `UIA_ELEMENT_NOT_FOUND`, `UIA_ELEMENT_NOT_UNIQUE`, `CURSOR_MOVE_FAILED`, `SEND_INPUT_FAILED`, `UNKNOWN_ERROR`, `AUDIT_LOG_FAILED`.

Safety limits: requires exactly one target window, a title/process safety policy match, and exactly one UIA element match. It first tries `ValuePattern`; if unavailable, it clicks the element rectangle center and uses the existing keyboard input path. It does not use OCR or image/template matching.

### find-text

Parameters:

- `--title <substring>`: required target window title substring.
- `--text <text>`: required text to locate.

Success JSON when OCR is available:

```json
{
  "ok": true,
  "command": "find-text",
  "timestamp": "2026-05-26 00:50:01",
  "duration_ms": 44,
  "target": {
    "title": "Agent Test Window",
    "hwnd": "0x123456",
    "pid": 1234
  },
  "data": {
    "requested_text": "Click Me",
    "matched_text": "Click Me",
    "bounding_box": {
      "left": 250,
      "top": 283,
      "right": 370,
      "bottom": 319
    },
    "coordinate_space": "screen",
    "confidence": null,
    "ocr_available": true
  }
}
```

Current v2.0+ behavior: the command uses Windows built-in WinRT OCR when available. If the build or runtime does not provide OCR, it returns a unified failure envelope with `OCR_UNAVAILABLE`; if no usable OCR language is available, it returns `OCR_LANGUAGE_UNAVAILABLE`.

Possible `error.code`: `INVALID_ARGUMENT`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `SAFETY_POLICY_DENIED`, `OCR_INIT_FAILED`, `OCR_UNAVAILABLE`, `OCR_LANGUAGE_UNAVAILABLE`, `LOCATOR_NOT_FOUND`, `LOCATOR_NOT_UNIQUE`, `OCR_FAILED`, `AUDIT_LOG_FAILED`.

Safety limits: OCR is only for user-authorized test windows. Do not use it for security-control bypass, credential extraction, or unauthorized workflow automation. Prefer UI Automation over OCR when available.

### click-text

Parameters:

- `--title <substring>`: required target window title substring.
- `--text <text>`: required text to locate.
- `--move-mode instant|fast-human|demo-human|human|operator-human`: optional, default `human`; `human` maps to `operator-human` and requires a valid local Operator Motion Profile.
- `--move-duration-ms <int>`: optional non-negative duration. If omitted for human modes, duration is auto-calculated from distance.
- `--profile <path>`: optional profile path for `operator-human`.
- `--allow-synthetic-profile`: optional test-only flag allowing `source=synthetic` or `source=sample` profiles.
- `--fallback fast-human`: optional explicit fallback for missing, invalid, or source-rejected operator profile.

Success JSON when OCR is available:

```json
{
  "ok": true,
  "command": "click-text",
  "timestamp": "2026-05-26 00:50:01",
  "duration_ms": 900,
  "target": {
    "title": "Agent Test Window",
    "hwnd": "0x123456",
    "pid": 1234
  },
  "data": {
    "requested_text": "Click Me",
    "matched_text": "Click Me",
    "bounding_box": {
      "left": 250,
      "top": 283,
      "right": 370,
      "bottom": 319
    },
    "coordinate_space": "screen",
    "confidence": null,
    "ocr_available": true,
    "action_method": "mouse_center",
    "move_mode": "human",
    "move_duration_ms": 800
  }
}
```

Current v2.0+ behavior: `click-text` first calls the OCR text locator. It clicks only after a unique OCR text match and returns `OCR_UNAVAILABLE` or `OCR_LANGUAGE_UNAVAILABLE` without clicking when OCR cannot run.

Possible `error.code`: `INVALID_ARGUMENT`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `WINDOW_FOCUS_FAILED`, `SAFETY_POLICY_DENIED`, `EMERGENCY_STOP`, `MOTION_PROFILE_NOT_FOUND`, `MOTION_PROFILE_INVALID`, `MOTION_PROFILE_NOT_HUMAN`, `MOTION_PROFILE_SOURCE_REQUIRED`, `MOTION_PROFILE_TEST_ONLY`, `OCR_INIT_FAILED`, `OCR_UNAVAILABLE`, `OCR_LANGUAGE_UNAVAILABLE`, `LOCATOR_NOT_FOUND`, `LOCATOR_NOT_UNIQUE`, `OCR_FAILED`, `CURSOR_MOVE_FAILED`, `SEND_INPUT_FAILED`, `AUDIT_LOG_FAILED`.

Safety limits: requires exactly one target window and a title/process safety policy match. Clicking is permitted only after a unique OCR text match. The OCR bounding box is reported in window-bitmap coordinates and converted to target client coordinates before input.

### read-window-text

Parameters:

- `--title <substring>`: required target window title substring.
- `--out <path>`: optional text output path under `allowed_write_roots`.

Success data includes `text`, `line_count`, `word_count`, `language`, `coordinate_space`, `screenshot_path`, `ocr_available`, `lines`, and `words`. OCR uses Windows built-in WinRT OCR when available. The target window must pass the same title/process safety policy used by input actions.

Possible `error.code`: `INVALID_ARGUMENT`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `SAFETY_POLICY_DENIED`, `SCREENSHOT_FAILED`, `OCR_UNAVAILABLE`, `OCR_LANGUAGE_UNAVAILABLE`, `OCR_FAILED`, `AUDIT_LOG_FAILED`.

### read-region-text

Parameters:

- `--title <substring>`: required target window title substring.
- `--x <client_x> --y <client_y> --w <width> --h <height>`: required client-area region.

Success data has the same OCR shape as `read-window-text`, limited to the requested client-area region. The target window must pass safety policy before OCR runs.

### wait-text

Parameters:

- `--title <substring>`: required target window title substring.
- `--text <text>`: required OCR text to poll for.
- `--timeout-ms <int>`: optional, default `5000`.
- `--interval-ms <int>`: optional, default `300`.

Returns success when OCR finds the requested text before timeout. Returns `LOCATOR_NOT_FOUND`, `OCR_UNAVAILABLE`, `OCR_LANGUAGE_UNAVAILABLE`, or `OCR_FAILED` on failure.

### assert-text-contains

Parameters:

- `--title <substring>`: required target window title substring.
- `--text <text>`: required OCR text assertion.

Returns `ASSERTION_FAILED` if OCR runs but the requested text is absent. The target window must pass safety policy before OCR runs.

### find-image

Parameters:

- `--title <substring>`: required target window title substring.
- `--template <path>`: required BMP template path.
- `--tolerance <0-255>`: optional per-channel pixel tolerance, default `0`.

Success JSON:

```json
{
  "ok": true,
  "command": "find-image",
  "timestamp": "2026-05-26 13:30:01",
  "duration_ms": 44,
  "target": {
    "title": "Agent Test Window",
    "hwnd": "0x123456",
    "pid": 1234
  },
  "data": {
    "match_found": true,
    "x": 68,
    "y": 101,
    "width": 120,
    "height": 36,
    "score": 1.0,
    "match_count": 1,
    "coordinate_space": "window_bitmap",
    "template": "D:\\desktopvisual\\assets\\click_button.bmp",
    "screenshot_path": "D:\\desktopvisual\\artifacts\\find_image_source.bmp"
  }
}
```

Failure JSON: unified failure envelope.

Possible `error.code`: `INVALID_ARGUMENT`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `SCREENSHOT_FAILED`, `IMAGE_FILE_NOT_FOUND`, `IMAGE_UNSUPPORTED_FORMAT`, `IMAGE_MATCH_NOT_FOUND`, `IMAGE_MATCH_NOT_UNIQUE`, `IMAGE_MATCH_FAILED`, `AUDIT_LOG_FAILED`.

Safety limits: requires exactly one target window and exactly one template match. Supports only uncompressed 24-bit and 32-bit BMP files. Template matching is for authorized GUI testing only and must not be used for security-control bypass or unauthorized workflows.

### click-image

Parameters:

- `--title <substring>`: required target window title substring.
- `--template <path>`: required BMP template path.
- `--tolerance <0-255>`: optional per-channel pixel tolerance, default `0`.
- `--move-mode instant|fast-human|demo-human|human|operator-human`: optional, default `human`; `human` maps to `operator-human` and requires a valid local Operator Motion Profile.
- `--move-duration-ms <int>`: optional non-negative duration. If omitted for human modes, duration is auto-calculated from distance.
- `--profile <path>`: optional profile path for `operator-human`.
- `--allow-synthetic-profile`: optional test-only flag allowing `source=synthetic` or `source=sample` profiles.
- `--fallback fast-human`: optional explicit fallback for missing, invalid, or source-rejected operator profile.

Success JSON:

```json
{
  "ok": true,
  "command": "click-image",
  "timestamp": "2026-05-26 13:30:01",
  "duration_ms": 900,
  "target": {
    "title": "Agent Test Window",
    "hwnd": "0x123456",
    "pid": 1234
  },
  "data": {
    "match_found": true,
    "x": 68,
    "y": 101,
    "width": 120,
    "height": 36,
    "score": 1.0,
    "match_count": 1,
    "coordinate_space": "window_bitmap",
    "template": "D:\\desktopvisual\\assets\\click_button.bmp",
    "screenshot_path": "D:\\desktopvisual\\artifacts\\click_image_source.bmp",
    "action_method": "mouse_center",
    "target_client_x": 128,
    "target_client_y": 119,
    "move_mode": "human",
    "move_duration_ms": 800
  }
}
```

Failure JSON: unified failure envelope.

Possible `error.code`: `INVALID_ARGUMENT`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `WINDOW_FOCUS_FAILED`, `SAFETY_POLICY_DENIED`, `EMERGENCY_STOP`, `MOTION_PROFILE_NOT_FOUND`, `MOTION_PROFILE_INVALID`, `MOTION_PROFILE_NOT_HUMAN`, `MOTION_PROFILE_SOURCE_REQUIRED`, `MOTION_PROFILE_TEST_ONLY`, `SCREENSHOT_FAILED`, `IMAGE_FILE_NOT_FOUND`, `IMAGE_UNSUPPORTED_FORMAT`, `IMAGE_MATCH_NOT_FOUND`, `IMAGE_MATCH_NOT_UNIQUE`, `IMAGE_MATCH_FAILED`, `CURSOR_MOVE_FAILED`, `SEND_INPUT_FAILED`, `AUDIT_LOG_FAILED`.

Safety limits: calls the image locator first and clicks only after a unique match and title/process safety policy approval. The click uses the existing real mouse input path and target-window client coordinates converted from the match center. No OpenCV or third-party image library is used.

### agent-boundary-validate

Parameters:

- `--check <mode|executor|action|request|plan>`: required validation target.
- `--mode <runtime|vlm_assisted>`: required for `--check mode`.
- `--executor <runtime>`: required for `--check executor`.
- `--humanmode-action <true|false>` and `--action-type <type>`: used by `--check action`.
- `--file <path>`: required for `--check request` and `--check plan`.

Examples:

```powershell
D:\desktopvisual\bin\winagent.exe agent-boundary-validate --check mode --mode runtime
D:\desktopvisual\bin\winagent.exe agent-boundary-validate --check mode --mode vlm_assisted
D:\desktopvisual\bin\winagent.exe agent-boundary-validate --check executor --executor runtime
D:\desktopvisual\bin\winagent.exe agent-boundary-validate --check action --humanmode-action true --action-type runtime_step_contract
D:\desktopvisual\bin\winagent.exe agent-boundary-validate --check request --file D:\desktopvisual\artifacts\dev6.0.0_agent_boundary\fixtures\agent_task_request_valid.json
D:\desktopvisual\bin\winagent.exe agent-boundary-validate --check plan --file D:\desktopvisual\artifacts\dev6.0.0_agent_boundary\fixtures\agent_plan_valid.json
```

Success JSON uses the unified envelope and includes `data.schema_version="6.0.0.agent_boundary"`, `data.check`, and check-specific fields. Request validation reports `request_type="AgentTaskRequest"` and required fields. Plan validation reports `plan_type="AgentPlan"` and `step_count`.

Failure JSON uses the unified failure envelope. Possible `error.code`: `INVALID_ARGUMENT`, `FILE_NOT_FOUND`, `FILE_READ_FAILED`, `MALFORMED_JSON`, `AGENT_MODE_INVALID`, `AGENT_EXECUTOR_INVALID`, `AGENT_ACTION_BOUNDARY_INVALID`, `AGENT_REQUEST_INVALID`, and `AGENT_PLAN_INVALID`.

Mode boundary:

- Valid modes are `runtime` and `vlm_assisted`.
- Unknown, empty, or missing mode values fail.

Runtime-only executor boundary:

- `executor=runtime` is valid.
- `executor=vlm`, `executor=agent_direct`, missing executor, and any non-runtime executor fail.
- VLM/LLM/Agent may plan, explain, classify, or propose, but real click/type/drag/scroll/hotkey execution must go through Runtime StepContract or an equivalent Runtime command path.
- JS, DOM, WebDriver, CDP, UIA InvokePattern, and UIA ValuePattern are not HumanMode Runtime actions.

Minimal schemas:

`AgentTaskRequest` requires `task_id`, `mode`, `user_goal`, `risk`, `executor`, and `compile_required=true`.

`AgentPlan` requires `plan_id`, `task_id`, `mode`, `user_goal`, `risk`, `executor`, `compile_required=true`, and non-empty `steps`.

Each `AgentPlanStep` requires `step_id`, `description`, `executor=runtime`, `compile_required=true`, and `action_type`.

Safety limits: this command is validation-only. It does not execute desktop actions, does not call a real VLM provider, does not read provider API keys, and does not modify HumanMode or active-protection STOP behavior.

### agent-intent-parse

Parses a natural-language task goal into the minimal v6.1.x `TaskIntent` structure. This command is planner/intention-only. It does not execute desktop actions, does not compile StepContract, and does not call a real VLM provider.

Parameters:

- `--mode <runtime|vlm_assisted>`: required. Unknown, empty, or missing mode fails with `AGENT_MODE_INVALID`.
- `--goal <text>`: required natural-language user goal. Empty or missing goal fails with `FAIL_EMPTY_TASK`.

Examples:

```powershell
D:\desktopvisual\bin\winagent.exe agent-intent-parse --mode runtime --goal "打开 D:\testrepo\testwindow"
D:\desktopvisual\bin\winagent.exe agent-intent-parse --mode runtime --goal "删除 D:\testrepo\testwindow\da.txt"
D:\desktopvisual\bin\winagent.exe agent-intent-parse --mode vlm_assisted --goal "打开普通网页读取标题"
```

Success JSON uses the unified envelope and includes `data.schema_version="6.1.2.task_intent_planner"` and `data.intent`.

`TaskIntent` fields:

- `task_id`
- `raw_user_goal`
- `normalized_goal`
- `intent_type`
- `mode`
- `target_app`
- `target_path`
- `target_object`
- `user_constraints`
- `risk_level`
- `requires_confirmation`
- `assumptions`
- `unsupported_reason`

Supported `intent_type` values are `explorer_open_path`, `explorer_open_file`, `explorer_delete_file`, `browser_open_page`, `browser_fill_form`, `local_mock_mail_fill`, and `unknown`.

Supported `risk_level` values are `low`, `medium`, `high`, and `blocked`.

Active-protection bypass semantics are classified as `risk_level="blocked"` with `unsupported_reason="active_protection_bypass"`. Ambiguous tasks are classified as `intent_type="unknown"` with `unsupported_reason="ambiguous_task"`.

### agent-plan-draft

Generates a minimal v6.1.x `AgentPlanDraft` from a `TaskIntent`. This command is planner-only. It does not execute tasks, does not compile StepContract, does not produce click/type/drag action steps, and does not call a real VLM provider.

Parameters:

- `--mode <runtime|vlm_assisted>` and `--goal <text>`: parse a goal into `TaskIntent` and then draft a plan.
- `--intent-file <path>`: optional path to an existing `TaskIntent` JSON file. When provided, the file is validated before drafting.

Examples:

```powershell
D:\desktopvisual\bin\winagent.exe agent-plan-draft --mode runtime --goal "打开 D:\testrepo\testwindow"
D:\desktopvisual\bin\winagent.exe agent-plan-draft --mode vlm_assisted --goal "打开普通网页读取标题"
D:\desktopvisual\bin\winagent.exe agent-plan-draft --intent-file D:\desktopvisual\artifacts\dev6.1.0_task_intent_planner\fixtures\task_intent_valid.json
```

Success JSON uses the unified envelope and includes `data.schema_version="6.1.2.task_intent_planner"` and `data.plan_draft`.

`AgentPlanDraft` fields:

- `plan_id`
- `task_id`
- `mode`
- `intent_type`
- `draft_steps`
- `required_runtime_capabilities`
- `assumptions`
- `risk_level`
- `requires_confirmation`
- `compile_required`
- `executor`
- `provider_role`
- `is_executable`

`AgentPlanDraft` invariants:

- `AgentPlanDraft` is not `StepContract`.
- `is_executable` must be `false`.
- `executor` must be `runtime`.
- `compile_required` must be `true`.
- Runtime mode uses `provider_role="none"`.
- VLM-assisted mode uses `provider_role="assistive_only"` and still uses `executor="runtime"`.
- Draft steps describe expected Runtime capabilities and must not contain directly executable click/type/drag action instructions.

Each `draft_steps` item contains `step_id`, `description`, `expected_runtime_capability`, `target`, `precondition_hint`, `verification_hint`, and `risk`.

Blocked TaskIntent values fail with `AGENT_PLAN_DRAFT_BLOCKED`. Ambiguous/unknown TaskIntent values fail with `FAIL_AMBIGUOUS_TASK`.

### agent-planner-validate

Validates v6.1.x `TaskIntent` and `AgentPlanDraft` JSON files without executing tasks or compiling StepContract.

Parameters:

- `--check <intent|plan-draft>`: required validation target.
- `--file <path>`: required JSON file path.

Examples:

```powershell
D:\desktopvisual\bin\winagent.exe agent-planner-validate --check intent --file D:\desktopvisual\artifacts\dev6.1.0_task_intent_planner\fixtures\task_intent_valid.json
D:\desktopvisual\bin\winagent.exe agent-planner-validate --check plan-draft --file D:\desktopvisual\artifacts\dev6.1.0_task_intent_planner\fixtures\agent_plan_draft_valid.json
```

Failure JSON uses the unified failure envelope. Possible `error.code` values include `INVALID_ARGUMENT`, `FILE_NOT_FOUND`, `FILE_READ_FAILED`, `MALFORMED_JSON`, `TASK_INTENT_INVALID`, `AGENT_PLAN_DRAFT_INVALID`, `AGENT_PLAN_DRAFT_EXECUTABLE`, `AGENT_MODE_INVALID`, `AGENT_EXECUTOR_INVALID`, and `AGENT_PROVIDER_ROLE_INVALID`.

Safety limits: these v6.1.x planner commands do not execute desktop actions, do not modify HumanMode, do not alter active-protection STOP, do not call real VLM APIs, and do not produce a `StepContract`. Plan-to-StepContract compilation is reserved for a future accepted post-v6.1 stage.

### task-session-validate

Parameters:

- `--file <path>`: required TaskSession JSON file.

Success JSON returns `data.schema_version`, `runtime_version`, `protocol_version`, `task_id`, `task_type`, `profile`, `permission_profile`, `current_state`, `artifacts`, `context`, `progress`, `state_count`, `task_states`, `transition_schemas`, `step_contracts`, `task_result`, and `escalation_provider`. Generated v5.0 task artifacts include stable `schema_version`, `runtime_version`, and `protocol_version` fields.

Failure JSON uses `TASK_SESSION_SCHEMA_INVALID`, `FILE_NOT_FOUND`, `FILE_READ_FAILED`, or `INVALID_ARGUMENT`.

Safety limits: read-only schema validation. It does not observe the screen, focus windows, send input, run task steps, or call VLM/Agent providers.

### task-session-transition

Parameters:

- `--file <path>`: required TaskSession JSON file.
- `--action <start_task|enter_state|transition_to|fail_task|stop_task|complete_task|timeout_task>`: required transition action.
- `--from-state <state>`: optional source state override for dry-run tests. Defaults to the session `current_state`.
- `--to-state <state>`: required for `enter_state` and `transition_to`.
- `--reason <text>`: optional transition reason.
- `--timeout-ms <n>` and `--elapsed-ms <n>`: used by `timeout_task`.

Success JSON returns `data.previous_state`, `data.current_state`, `data.transition`, `data.timeout`, and `data.task_result`.

Failure JSON uses `TASK_TRANSITION_INVALID`, `TASK_SESSION_SCHEMA_INVALID`, `FILE_NOT_FOUND`, `FILE_READ_FAILED`, or `INVALID_ARGUMENT`.

Safety limits: dry-run transition validation only. It does not persist state back to the input file and does not execute desktop actions.

### task-session-run

Parameters:

- `--file <path>`: required TaskSession JSON file.

v5.0.5 supports only the local mock task type `local_form_fill_submit_mock`. Success JSON returns `data.task_id`, `task_type`, `current_state`, step counts, `llm_or_vlm_call_count`, and task artifact paths.

Generated artifacts for the formal v5.0.4 fixture are:

- `task_events.jsonl`
- `task_result.json`
- `task_report.md`
- `current_state.json`
- `failure_dump.json`

Failure JSON uses `UNSUPPORTED_TASK_TYPE`, `TASK_SESSION_SCHEMA_INVALID`, `EXPECT_FAILED`, `SAFETY_POLICY_DENIED`, `FILE_NOT_FOUND`, `FILE_READ_FAILED`, `FILE_WRITE_FAILED`, or `INVALID_ARGUMENT`.

Safety limits: local mock HTML only. It does not launch a browser, access external web, focus windows, click, type, use OCR/UIA, or call VLM/Agent providers.

### run-task for TaskSession

Parameters:

- `--file <path>`: required TaskSession JSON file.

When `--file` is a valid TaskSession, `run-task` routes through the stable v5.7 TaskSession API and `--report` is optional. Legacy TaskRunner task files still require `--report <path>` and keep the existing behavior.

Success JSON returns `data.task_id`, `task_type`, `current_state`, `machine_readable_status`, and artifact paths for `task_result_json`, `task_events_jsonl`, `task_report_md`, `current_state_json`, `failure_dump_json`, `evidence_index_md`, and `status_record_json`.

### task-status

Parameters:

- `--task-id <id>` or `--file <path>`: required.

Returns the registered task status with `machine_readable_status.state`, `ok`, `terminal`, `cancellable`, and `error_code`.

### task-events

Parameters:

- `--task-id <id>` or `--file <path>`: required.

Returns `events_path`, `event_count`, and JSONL content. Each line is a separate task event.

### task-report

Parameters:

- `--task-id <id>` or `--file <path>`: required.

Returns `report_path`, `content_length`, and Markdown report content.

### task-confirm

Parameters:

- `--task-id <id>` or `--file <path>`: required.
- `--response <confirm|reject|text>`: optional, defaults to `confirm`.

Writes a confirmation artifact with `safety_override=false`. Confirmation never overrides SafetyPolicy or blocked actions.

### task-cancel

Parameters:

- `--task-id <id>` or `--file <path>`: required.
- `--reason <text>`: optional.

Cancels non-terminal or pre-run TaskSessions by producing stopped artifacts. Completed, failed, stopped, and blocked tasks return a stable no-op with `cancelled=false`. Supported machine-readable stop codes include `TASK_CANCELLED`, `TASK_TIMEOUT_CANCELLED`, `SAFETY_STOP`, `PROVIDER_UNAVAILABLE_STOP`, and `CONFIRMATION_TIMEOUT_STOP`.

Stopped cancellation writes `task_result.json`, `task_events.jsonl`, `task_report.md`, `failure_dump.json`, `cancel_audit.json`, and `evidence_index.md`. `cancel_audit.json` records the stop code and `safety_override=false`.

### task-template-v2-validate

Parameters:

- `--file <path>`: required TaskTemplateV2 JSON file.

Success JSON returns `data.schema_version`, `runtime_version`, `protocol_version`, `template_id`, `required_profile`, `parameters`, `states`, `steps`, `preconditions`, `verification`, `recovery`, `confirmation_nodes`, `final_state_policy`, and safety fields. `runtime_version` is the current internal runtime version and `protocol_version` is `5.4`.

Failure JSON uses `TASK_TEMPLATE_V2_SCHEMA_INVALID`, `FILE_NOT_FOUND`, `FILE_READ_FAILED`, or `INVALID_ARGUMENT`. Unsupported parameter types are rejected; supported TaskParameter types are `string`, `path`, `local_url`, and `roi`.

Safety limits: schema validation only. It does not execute task actions, click, type, browse, access files, call VLM/Agent providers, or allow profiles to override Safety Manifest.

### task-template-v2-resolve

Parameters:

- `--task <path>`: optional template task JSON containing `template_id`, `profile`, and `parameters`.
- `--template <path>`: optional TaskTemplateV2 JSON file when not using `--task`.
- `--profile <name>`: optional profile name for direct template resolution.
- `--params-file <path>`: optional JSON file containing TaskParameter values for direct template resolution.

Success JSON returns `data.template_id`, `required_profile`, `profile_name`, `bound_profile`, `profile_bound_verification`, `profile_recovery_strategy_bound`, `resolved_steps`, `final_state_policy`, and safety fields. Profile binding uses `profile.common_locators`, `profile.roi_definitions`, `profile.visual_strategy`, `profile.recovery_strategy`, and `profile.confirmation_nodes`.

Failure JSON uses `PROFILE_BINDING_PROFILE_NOT_FOUND`, `PROFILE_BINDING_PROFILE_MISMATCH`, `PROFILE_BINDING_MISSING_LOCATOR`, `PROFILE_BINDING_MISSING_ROI`, `PROFILE_BINDING_MISSING_CONFIRMATION_NODE`, `TASK_PARAMETER_MISSING`, `TASK_PARAMETER_PATH_INVALID`, `TASK_PARAMETER_LOCAL_URL_INVALID`, `TASK_PARAMETER_ROI_INVALID`, `TASK_TEMPLATE_V2_SCHEMA_INVALID`, `FILE_NOT_FOUND`, `FILE_READ_FAILED`, or `INVALID_ARGUMENT`.

Safety limits: resolver output is metadata only. It does not execute the resolved steps, does not fall back to fixed coordinates, and always reports that profiles cannot override Safety Manifest.

### file-path-resolve

Parameters:

- `--path <path>`: required local file path. Project-relative paths are resolved under the DesktopVisual project root.
- `--allowed-roots <paths>`: required semicolon-separated allowlist of local roots.
- `--extensions <items>`: optional comma-separated allowed extensions such as `.txt,.md`.
- `--max-bytes <n>`: optional maximum file size in bytes.

Success JSON returns `data.schema_version`, `resolved_path`, `file_name`, `extension`, `exists`, `size_bytes`, `under_allowed_root`, `file_action_risk`, `metadata_only`, and `content_leaked=false`.

Failure JSON uses `INVALID_ARGUMENT`, `FILE_ALLOWED_ROOTS_REQUIRED`, `FILE_PATH_TRAVERSAL_DENIED`, `FILE_PATH_OUTSIDE_ALLOWED_ROOT`, `FILE_PICKER_FILE_NOT_FOUND`, `FILE_EXTENSION_DENIED`, `FILE_METADATA_FAILED`, or `FILE_TOO_LARGE`.

Safety limits: file path resolution is default-deny without explicit allowed roots and audits metadata only. It does not read or emit file contents, upload files, send email, or weaken SafetyPolicy.

### file-picker-flow

Parameters:

- `--file <path>`: required local mock file picker fixture JSON.

Success JSON returns `data.schema_version`, `flow_id`, `parent_window`, `picker_window`, `file_path`, `picker_detected`, `path_input`, `open_confirmed`, `picker_closed`, `target_app_changed`, and `no_real_upload=true`.

Failure JSON uses `INVALID_ARGUMENT`, `FILE_NOT_FOUND`, `FILE_READ_FAILED`, `FILE_PICKER_TIMEOUT`, `FILE_PICKER_CANCELLED`, `FILE_PICKER_NOT_FOUND`, `FILE_PICKER_INPUT_FAILED`, or `FILE_PICKER_CLOSE_VERIFY_FAILED`.

Safety limits: v5.5 file picker support is fixture-backed mock validation. It does not operate arbitrary product file pickers or perform real uploads.

### attachment-verify

Parameters:

- `--file <path>`: required local AttachmentState fixture JSON.
- `--expected-file <name>`: optional visible file-name expectation.
- `--timeout-ms <n>`: optional timeout budget.
- `--elapsed-ms <n>`: optional elapsed time for timeout checks.

Success JSON returns `data.schema_version`, `file_name`, `file_name_visible`, `upload_started`, `spinner_detected`, `progress_detected`, `spinner_gone`, `upload_completed`, `upload_failed=false`, `retry_shown=false`, and `no_real_send=true`.

Failure JSON uses `INVALID_ARGUMENT`, `FILE_NOT_FOUND`, `FILE_READ_FAILED`, `UPLOAD_VERIFICATION_TIMEOUT`, `UPLOAD_FILE_NAME_MISMATCH`, `UPLOAD_FILE_TOO_LARGE`, `UPLOAD_FAILED`, or `UPLOAD_NOT_COMPLETE`.

Safety limits: attachment verification reads local UI-state fixtures only. It does not upload data, access real mail accounts, or approve external sends.

### cross-window-check

Parameters:

- `--file <path>`: required local CrossWindowTaskContext fixture JSON.

Success JSON returns `data.schema_version`, `context_id`, `parent_task_window`, `child_dialog_window`, `returned_to_parent`, `foreground_verified`, `window_changed_event`, and `focus_restored`.

Failure JSON uses `INVALID_ARGUMENT`, `FILE_NOT_FOUND`, `FILE_READ_FAILED`, `CROSS_WINDOW_WRONG_FOREGROUND`, or `CROSS_WINDOW_RETURN_FAILED`.

Safety limits: cross-window validation is a gate before continuing a controlled workflow. Wrong foreground or failed return must stop or recover through Runtime policy.

### local-mail-attach-flow

Parameters:

- `--file <path>`: required local mail mock attachment task JSON.

Success JSON returns `data.schema_version`, `task_id`, `template_id`, `file`, `file_picker`, `upload`, `cross_window`, `upload_completed`, `no_real_send=true`, and `real_email_sent=false`.

Failure JSON uses `INVALID_ARGUMENT`, `FILE_NOT_FOUND`, `FILE_READ_FAILED`, `REAL_SEND_BLOCKED`, or the underlying file path, picker, upload, and cross-window error codes.

Safety limits: local mail attach flow is mock-only. It does not send real email, upload real files to accounts, bypass confirmation, or provide a v6 Agent template.

### step-contract-validate

Parameters:

- `--file <path>`: required StepContract JSON file.

Success JSON returns `data.schema_version`, `step_id`, `name`, `precondition_count`, parsed precondition requirements, `action`, `verification`, `timeout_ms`, retry policy, expected scene state, expected change events, expected elements, safety requirements, and failure behavior.

Failure JSON uses `STEP_CONTRACT_SCHEMA_INVALID`, `FILE_NOT_FOUND`, `FILE_READ_FAILED`, or `INVALID_ARGUMENT`.

Safety limits: read-only schema validation. It does not observe the screen, focus windows, send input, run task steps, or call VLM/Agent providers.

### step-precondition-check

Parameters:

- `--contract <path>`: required StepContract JSON file.
- `--perception <path>`: required local perception JSON file.

Success JSON returns `data.step_id`, `passed_count`, `failed_count`, and the checked precondition names for `scene_state`, `element_exists`, `target_ready`, `window_focused`, `profile_active`, `safety_allowed`, and `capability_available`. The expected scene, element id, active profile, allowed action, and capability are read from the StepContract fields.

Failure JSON uses `PRECONDITION_FAILED`, `STEP_CONTRACT_SCHEMA_INVALID`, `FILE_NOT_FOUND`, `FILE_READ_FAILED`, or `INVALID_ARGUMENT`.

Safety limits: read-only comparison of StepContract expectations against local perception JSON. It does not execute the action.

### step-verify

Parameters:

- `--contract <path>`: required StepContract JSON file.
- `--before <path>`: required local before-action perception JSON file.
- `--after <path>`: required local after-action perception JSON file.
- `--timeout-ms <n>`: optional verification timeout override.
- `--elapsed-ms <n>`: optional elapsed time for timeout simulation.

Success JSON returns `data.step_id`, expected scene state status, expected change event status, element/text/region checks, timeout status, and elapsed time. Failures include a structured `failure_reason` in `data` where available.

Failure JSON uses `VERIFICATION_TIMEOUT`, `VERIFICATION_FAILED`, `STEP_CONTRACT_SCHEMA_INVALID`, `FILE_NOT_FOUND`, `FILE_READ_FAILED`, or `INVALID_ARGUMENT`.

Safety limits: read-only post-action verification over local before/after perception JSON. It does not retry, recover, click, type, or call VLM/Agent providers.

### step-failure-classify

Parameters:

- `--error-code <code>`: required source error code or failure reason.
- `--step-id <id>`: optional step id to include in the classification record.

Success JSON returns `data.step_id`, `raw_error_code`, normalized `failure_reason`, `category`, and `recommended_action`.

Supported failure reasons are `PRECONDITION_FAILED`, `LOCATOR_NOT_FOUND`, `TARGET_NOT_READY`, `ACTION_FAILED`, `ACTION_NO_EFFECT`, `VERIFICATION_TIMEOUT`, `UNEXPECTED_SCENE`, `SAFETY_DENIED`, and `SEMANTIC_UNRESOLVED`.

Safety limits: pure classification only. It does not execute actions, change state, or call VLM/Agent providers.

### recovery-policy-validate

Parameters:

- `--file <path>`: required RecoveryPolicy JSON file.

Success JSON returns `data.schema_version`, `policy_id`, `task_type`, `permission_profile`, `retry_budget`, `route_count`, audit settings, and supported strategies. `retry_budget` includes `max_attempts`, `max_total_recovery_ms`, compatibility `max_wait_ms`, and `backoff_ms`.

Failure JSON uses `RECOVERY_POLICY_SCHEMA_INVALID`, `FILE_NOT_FOUND`, `FILE_READ_FAILED`, or `INVALID_ARGUMENT`.

Safety limits: read-only schema validation. It does not observe the screen, retry an action, recover a task, or call VLM/Agent providers.

### recovery-evaluate

Parameters:

- `--policy <path>`: required RecoveryPolicy JSON file.
- `--failure-reason <reason>`: required failure reason.
- `--context <path>`: required local recovery context JSON file.
- `--attempt <n>`: optional attempt number. Defaults to 1.

Success JSON returns `data.failure_reason`, `strategy`, `next_action`, attempt budget fields, `safe_to_retry`, wait/reobserve/relocate/cache flags, context summary, and `audit_record`.

Failure JSON uses `RECOVERY_POLICY_SCHEMA_INVALID`, `RECOVERY_ROUTE_NOT_FOUND`, `RECOVERY_REQUIRES_ESCALATION_OR_STOP`, `RETRY_BUDGET_EXHAUSTED`, `FILE_NOT_FOUND`, `FILE_READ_FAILED`, or `INVALID_ARGUMENT`.

Safety limits: local decision only. It does not perform real waiting, observe the screen, re-locate a target, mutate cache, click, type, or call VLM/Agent providers.

### escalation-request-create

Parameters:

- `--reason <reason>`: required escalation reason.
- `--task <task>`: required current task id or type.
- `--step <step>`: required current step id.
- `--context <path>`: required local escalation context JSON file.

Success JSON returns `data.reason`, `current_task`, `current_step`, `scene_state`, `candidates`, `candidate_count`, `screenshot_artifact`, `element_graph_artifact`, `risk_level`, `allowed_routes`, `recommended_action`, `fallback_if_provider_unavailable`, and `llm_or_vlm_call_count`.

Failure JSON uses `FILE_NOT_FOUND`, `FILE_READ_FAILED`, or `INVALID_ARGUMENT`.

Safety limits: creates a local structured request only. It does not upload artifacts, call providers, execute an Agent/VLM route, or bypass SafeStop. High-risk contexts allow only `stop`.

### safe-stop-check

Parameters:

- `--reason <reason>`: required stop reason or safety category.
- `--context <path>`: optional local context JSON file.

Success JSON returns `data.safe_stop`, `recovery_allowed`, `escalation_allowed`, `recommended_action`, scene/risk fields, and `llm_or_vlm_call_count`.

SafeStop reasons include captcha, anti-cheat, proctoring, payment, credential/security challenge, game automation, real exam/hiring assessment submission in public profile, and `SAFETY_DENIED`.

Failure JSON uses `FILE_NOT_FOUND`, `FILE_READ_FAILED`, or `INVALID_ARGUMENT`.

Safety limits: terminal safety classification. SafeStop must not be recovered and must not be escalated to Agent/VLM as a bypass.

### risk-action-classify

Parameters:

- `--action <text>`: required action description.
- `--permission-profile <profile>`: optional permission profile. Defaults to `DEFAULT`.

Success JSON returns `data.action`, `risk_level`, `requires_confirmation`, `blocked`, `reason`, and `permission_profile`.

Risk levels are `low`, `medium`, `high`, and `blocked`. High-risk actions include send email, external form submission, delete file, overwrite file, external upload, external download, account setting change, public posting, and payment-like actions. Blocked actions include captcha, anti_cheat, proctoring, real_exam, real_hiring_assessment, certification or rated-contest submission, payment_confirmation, credential_security_challenge, game_cheating, phishing, bulk harassment, unconfirmed external send, protected desktop, and elevated/admin prompts.

Failure JSON uses `INVALID_ARGUMENT`.

Safety limits: classification only. It does not execute the action, ask for confirmation, call VLM/Agent providers, or downgrade a blocked action.

### confirmation-request-create

Parameters:

- `--action <text>`: required action description.
- `--risk-level <level>`: required risk level.
- `--summary <text>`: required human-readable summary.
- `--target-window <text>`: optional target window title.
- `--screenshot <path>`: optional screenshot artifact path.
- `--files <paths>`: optional comma-separated involved files.
- `--destination <text>`: optional destination, recipient, or target.
- `--timeout-ms <n>`: optional timeout in milliseconds. Defaults to the runtime confirmation default.
- `--artifact-dir <path>`: optional output directory. Defaults to the project artifact directory for v5.3.2.

Success JSON returns `data.action`, `risk_level`, `summary`, `target_window`, `screenshot`, `involved_files`, `destination`, `timeout_ms`, `allowed_responses`, `audit_id`, `request_json`, and `report_md`.

Failure JSON uses `INVALID_ARGUMENT`, `CONFIRMATION_REQUEST_WRITE_FAILED`, or unified file/artifact errors.

Safety limits: creates local confirmation artifacts only. It does not grant approval, execute the action, send data externally, or allow blocked actions.

### confirmation-gate-check

Parameters:

- `--action <text>`: required action description.
- `--risk-level <level>`: required risk level.
- `--response <confirm|reject|timeout>`: optional human response.
- `--permission-profile <profile>`: optional permission profile. Defaults to `DEFAULT`.

Success JSON returns `data.action`, `risk_level`, `response`, `decision`, `allowed`, `requires_confirmation`, `blocked`, `reason`, and `audit_record`.

Gate behavior:

- High-risk action with no response: `decision="blocked"`, `allowed=false`.
- High-risk action with `confirm`: `decision="allowed"`, `allowed=true`.
- `reject`: `decision="stopped"`, `allowed=false`.
- `timeout`: `decision="stopped"`, `allowed=false`.
- Blocked action with any response: `decision="stopped"`, `allowed=false`.

Failure JSON uses `INVALID_ARGUMENT`.

Safety limits: checks the gate only. A blocked action cannot be approved through confirmation, and Agent/VLM escalation cannot bypass this gate.

### confirmation-flow-run

Parameters:

- `--file <path>`: required local confirmation flow fixture.
- `--response <confirm|reject|timeout>`: optional human response.

Success JSON returns `data.flow_id`, `risk_level`, `confirmation_required`, `allowed`, `mock_sent`, `real_email_sent`, `audit_path`, `sent_state_path`, and `request_artifacts`.

The v5.3.4 local fixture is `tasks\confirmation\local_mail_mock_send_confirm.json`. It composes a mock mail payload, writes a local ConfirmationRequest, blocks without confirmation, and writes local audit/sent-state artifacts only after explicit `confirm`.

Failure JSON uses `INVALID_ARGUMENT`, `FILE_NOT_FOUND`, `FILE_READ_FAILED`, `CONFIRMATION_REQUIRED`, `CONFIRMATION_REJECTED`, or `CONFIRMATION_TIMEOUT`.

Safety limits: local mock flow only. It does not send real email, upload files, access accounts, or use real external services.

### run-case

Parameters:

- `--file <path>`: required case file path.
- `--report <path>`: required Markdown report output path.

Success JSON:

```json
{
  "ok": true,
  "command": "run-case",
  "timestamp": "2026-05-25 18:40:01",
  "duration_ms": 2000,
  "target": null,
  "data": {
    "case_file": "D:\\desktopvisual\\cases\\basic_click.case",
    "report": "D:\\desktopvisual\\artifacts\\basic_click_report.md",
    "step_count": 13,
    "passed_step_count": 13,
    "failed_step_index": 0
  }
}
```

Failure JSON: unified failure envelope.

Possible `error.code`: `FILE_NOT_FOUND`, `FILE_READ_FAILED`, `CASE_PARSE_FAILED`, `CASE_STEP_LIMIT_EXCEEDED`, `CASE_DURATION_LIMIT_EXCEEDED`, `SAFETY_POLICY_DENIED`, `EMERGENCY_STOP`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `WINDOW_FOCUS_FAILED`, `INVALID_ARGUMENT`, `SCREENSHOT_FAILED`, `CURSOR_MOVE_FAILED`, `SEND_INPUT_FAILED`, `ASSERTION_FAILED`, `UNKNOWN_ERROR`, `AUDIT_LOG_FAILED`.

Safety limits: executes only the frozen case commands documented in `D:\desktopvisual\docs\CASE_FORMAT.md`. Case execution loads `D:\desktopvisual\config\safety.conf`, enforces `max_steps`, `max_duration_ms`, window/process whitelists for input actions, and stops on first failure.

### run-task

Runs a v3 task file through the closed-loop task runner.

```powershell
winagent.exe run-task --file <task.json> --report <report.md>
winagent.exe run-task --file <task.json> --report <report.md> --permission-mode FULL_ACCESS --full-access-session-id <id>
```

Required arguments:

- `--file <path>`: task JSON file.
- `--report <path>`: Markdown task report output.

Optional arguments:

- `--permission-mode <DEFAULT|FULL_ACCESS>`: overrides the task file `permission_mode` for this invocation.
- `--full-access-session-id <id>`: supplies the temporary FULL_ACCESS session id. Required for FULL_ACCESS.

Task files may include root fields `permission_mode` and `full_access_session_id`. `DEFAULT` remains the safe default and keeps the current authorized-window boundary. `FULL_ACCESS` requires an active temporary session and records a Permission Decision in the task report. The task runner performs template expansion, initial PermissionManager and Safety Manifest checks, initial WindowSession resolution, `observe_before`, `locate`, foreground confirmation, `act`, `form_action`, `hotkey`, `wait`, `checkpoint`, `observe_after`, expectation verification, checkpoint recording, loop guard checks, failure classification, and Recovery Strategy Engine handling where permitted by the effective task budget. Input actions still require foreground verification and immutable safety stops. Recovery never guesses coordinates, chooses ambiguous matches, or broadens the target window title. Selector and form-control failures are written into the task report with the full selector or `FormControl` result JSON, including fallback attempt order for `chain:` selectors. Reports include an initial permission decision, initial policy check, initial window session, `## Recovery Strategy Engine`, per-step `Window session before` / `Window session after` diagnostics, `## Session Checkpoints`, and a `## Templates` section when templates are used.

Recovery strategy table:

| Error | Strategy |
| --- | --- |
| `LOCATOR_NOT_FOUND` | `re-observe -> OCR fallback -> stop` |
| `WINDOW_NOT_FOUND` | `find process/window -> activate -> stop` |
| `LOCATOR_NOT_UNIQUE` | require explicit selector or `nth`; no automatic recovery |
| `TEXT_NOT_FOUND` | `wait -> re-observe -> stop` |
| `SAFETY_POLICY_DENIED` | `stop_immediately`; no recovery |

Each recovery record contains `error`, `strategy`, `attempt`, `result`, `details`, and `strategy_steps`. The CLI `run-task` data object includes `recoveries` and `recovery_records`. Service `/run-task` uses the same TaskRunner path and returns the same counts while the Markdown report stores the full record.

The `checkpoint` task step records a manual `SessionCheckpoint` without desktop input:

```json
{
  "name": "checkpoint_before_submit",
  "type": "checkpoint",
  "observed_summary": "form is complete; submit not clicked yet"
}
```

Optional root configuration:

```json
{
  "checkpoint": {
    "enabled": true,
    "interval_ms": 300000,
    "cleanup_on_end": true
  },
  "loop_guard": {
    "repeated_action_limit": 5,
    "url_redirect_limit": 5,
    "no_progress_limit": 5,
    "window_spawn_limit": 5,
    "scroll_no_progress_limit": 5
  }
}
```

`SessionCheckpoint` fields are `checkpoint_id`, `timestamp`, `permission_mode`, `task_id`, `step_index`, `window_title`, `process_name`, `url`, `screenshot_path`, `observed_summary`, `recent_actions`, `form_state_summary`, and `suggested_recovery_actions`. Checkpoints are observable anchors only; they do not guarantee rollback for sent messages, submitted forms, or remote state changes. Temporary checkpoint files are cleaned at session end when `cleanup_on_end=true`; the Markdown report retains the checkpoint summary.

The `form_action` task step is available for local HTML form/control semantics and explicit control-type action mapping:

```json
{
  "name": "select choice",
  "type": "form_action",
  "html_path": "D:\\desktopvisual\\artifacts\\form_semantics\\form_semantics.html",
  "field_id": "choice",
  "value": "b"
}
```

`form_action` records `form_control`, candidates, match count, `control_type`, `recommended_action`, source, confidence, and action result. It stops on `FIELD_NOT_UNIQUE`, `FIELD_CONFIDENCE_LOW`, and `CAPTCHA_DETECTED`.

The `decision` task step (v3.3.6) runs the General Decision Task Runtime for one resolved control. It is gated on the `content_decision` capability: `DEFAULT` stops with `SAFETY_POLICY_DENIED`, and `FULL_ACCESS` requires a valid unlocked `full_access_session_id`.

```json
{
  "name": "decide_answer",
  "type": "decision",
  "user_goal": "answer question 1",
  "html_path": "D:\\desktopvisual\\artifacts\\decision_task\\decision_page.html",
  "field_id": "q1",
  "value": "b",
  "allow_submit": false,
  "min_confidence": 0.50
}
```

Fields: `user_goal` (required explicit goal), `html_path` (local page context), `field_id`/`label` (one required target), optional `control_type`, `value`/`option`/`text`, `allow_submit`, and `min_confidence` (default `0.50`). The step records the `DecisionTaskContext` and `DecisionRecord` into the task report. It stops on `SAFETY_POLICY_DENIED`, `FULL_ACCESS_SESSION_REQUIRED`, `FIELD_CONFIDENCE_LOW`, `FIELD_NOT_UNIQUE`, `LOCATOR_NOT_FOUND`, `CAPTCHA_DETECTED`, `ANTI_AUTOMATION_DETECTED`, `CREDENTIAL_INPUT_DETECTED`, and `USER_TAKEOVER_REQUIRED`. Page content can never override `user_goal`, and unauthorized submit stops with `USER_TAKEOVER_REQUIRED`.

The `communication_step` task step (v3.3.8) runs the Communication Action Runtime. It is gated on the `communication` capability: `DEFAULT` stops with `SAFETY_POLICY_DENIED`, and `FULL_ACCESS` requires a valid unlocked `full_access_session_id`.

```json
{
  "name": "send_status",
  "type": "communication_step",
  "operation": "send_message",
  "channel": "local-email-sim",
  "target": "alice@example.test",
  "subject": "Status",
  "content": "full message text",
  "content_summary": "short status update",
  "user_requested_send": true
}
```

Supported operations are `open_channel`, `locate_target`, `compose_message`, `send_message`, and `verify_sent_or_stopped`. The step records a `CommunicationAction` with `channel`, `target`, `subject`, `content_summary`, `content_hash`, `user_requested_send`, `send_action_performed`, `permission_mode`, and `risk_level`. Full message content is not written to reports or audit logs. Sending requires `user_requested_send=true` and one explicit `target`; missing target, missing user send authorization, or multi-target send stops with `USER_TAKEOVER_REQUIRED`. Login/account verification stops with `USER_TAKEOVER_REQUIRED`; captcha stops with `CAPTCHA_DETECTED`; credentials stop with `CREDENTIAL_INPUT_DETECTED`; anti-automation surfaces stop with `ANTI_AUTOMATION_DETECTED`.

The `coding` task step (v3.3.9) runs the Coding and Problem-Solving Web Workflow. It is gated on the `content_decision` capability: `DEFAULT` stops with `SAFETY_POLICY_DENIED`, and `FULL_ACCESS` requires a valid unlocked `full_access_session_id`.

```json
{
  "name": "run local oj sample",
  "type": "coding",
  "action": "run_code",
  "user_goal": "practice two sum",
  "html_path": "D:\\desktopvisual\\artifacts\\coding_workflow\\oj_sample_pass.html",
  "language": "cpp",
  "code_path": "D:\\desktopvisual\\artifacts\\coding_workflow\\solution.cpp",
  "allow_submit": false,
  "revision_count": 1
}
```

Supported actions are `read_problem`, `select_language`, `input_code`, `run_code`, `read_result`, `revise_code`, `stop_before_submit`, and `submit_if_explicitly_allowed`. The step records `CodingWorkflowContext` and `CodingWorkflowRecord` into the task report. Full code text is redacted; reports store a code summary or `code_path`. Submit is never marked as clicked unless `allow_submit=true`. It stops on `SAFETY_POLICY_DENIED`, `FULL_ACCESS_SESSION_REQUIRED`, `USER_TAKEOVER_REQUIRED`, `CAPTCHA_DETECTED`, `ANTI_AUTOMATION_DETECTED`, and `LOCATOR_NOT_FOUND`.

v3.3.0 task templates live under `tasks\templates\<name>.task-template.json`. Every template must declare:

- `name`
- `required_permissions`
- `allowed_window`
- `expected_result`
- `failure_behavior`
- `steps`

Supported template names in the bundled library are `open_app`, `focus_window`, `fill_form`, `click_button`, `wait_until_text`, `wait_until_window`, `copy_text`, `save_file`, `open_local_html`, and `run_local_test_page`.

Task files use templates through a `type: "template"` step:

```json
{
  "name": "click via template",
  "type": "template",
  "template": "click_button",
  "parameters": {
    "selector": "uia:name=Click Me,type=Button",
    "expect_selector": "uia:name=Click Me"
  }
}
```

Template expansion substitutes `${parameter}` placeholders inside the template `steps` array and then executes the expanded steps through the existing TaskRunner paths. Template names are restricted to lowercase letters, digits, and underscore. Missing templates, invalid template manifests, missing parameters, and unsupported expanded step types fail with `INVALID_ARGUMENT`. Templates cannot set `allow_unrestricted_desktop=true`.

The `hotkey` task step is available for template expansion and explicit task files:

```json
{
  "name": "copy selection",
  "type": "hotkey",
  "keys": "CTRL+C"
}
```

`hotkey` uses the same target WindowSession, SafetyPolicy/Safety Manifest, foreground focus, and SendInput path as the CLI `hotkey` command.

Success JSON:

```json
{
  "ok": true,
  "command": "run-task",
  "data": {
    "task": "testwindow_basic",
    "ok": true,
    "steps": 3,
    "passed": 3,
    "recoveries": 0,
    "duration_ms": 125,
    "report": "D:\\desktopvisual\\artifacts\\mvp_testwindow_report.md"
  }
}
```

Failure JSON uses the unified failure envelope. Primary error codes include `FULL_ACCESS_SESSION_REQUIRED`, `FULL_ACCESS_REQUIRES_INTERACTIVE_CONFIRMATION`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `WINDOW_NOT_VISIBLE`, `WINDOW_TITLE_CHANGED`, `WINDOW_FOCUS_FAILED`, `WINDOW_SPAWN_LOOP`, `URL_REDIRECT_LOOP`, `NO_PROGRESS_DETECTED`, `REPEATED_ACTION_LIMIT`, `SCROLL_NO_PROGRESS`, `SAFETY_POLICY_DENIED`, `USER_TAKEOVER_REQUIRED`, `CREDENTIAL_INPUT_DETECTED`, `PROTECTED_DESKTOP_DETECTED`, `CAPTCHA_DETECTED`, `ANTI_AUTOMATION_DETECTED`, `ANTI_CHEAT_DETECTED`, `LOOP_GUARD_STOP`, `LOCATOR_NOT_FOUND`, `LOCATOR_NOT_UNIQUE`, `FIELD_NOT_UNIQUE`, `FIELD_CONFIDENCE_LOW`, `TEXT_NOT_FOUND`, `OCR_UNAVAILABLE`, `OCR_FAILED`, `ACTION_FAILED`, `EXPECT_FAILED`, `TIMEOUT`, and `UNKNOWN_ERROR`.

### motion-record

Parameters:

- `--title <substring>`: required target window title substring, usually `Motion Lab`.
- `--scenario <name>`: required scenario label such as `horizontal_lr` or `drag_line`.
- `--duration-ms <int>`: required recording duration.
- `--out <path>`: required raw trajectory JSON path under an allowed write root.

This command records mouse trajectory points only. It does not move the cursor, click, type, read window contents, or record keyboard text. Each point includes screen/client coordinates, timestamp, and button state. `F12` stops recording with `EMERGENCY_STOPPED`.

Success `data` includes `scenario`, `sample_id`, `point_count`, `duration_ms`, `distance_px`, `bounding_box`, and `out_path`.

### motion-calibrate

Parameters:

- `--source human|synthetic|sample`: required profile source. Human calibration scripts pass `human`; selftests pass `synthetic`.
- `--input <dir>`: directory containing raw motion JSON samples.
- `--out <path>`: profile output path, normally `D:\desktopvisual\config\operator_motion_profile.json` for human profiles or `D:\desktopvisual\artifacts\motion_profile\synthetic\operator_motion_profile.synthetic.json` for tests.

Reads raw trajectory files and writes aggregate operator statistics plus explicit `source`, `device_context`, and `privacy` metadata. It does not store full raw traces in the profile. Omitting `--source` returns `MOTION_PROFILE_SOURCE_REQUIRED`; fewer than 12 valid raw samples returns `MOTION_PROFILE_INSUFFICIENT_SAMPLES`; 12/32/64 samples produce `low`/`usable`/`good` quality.

### motion-profile-info

Parameters:

- `--profile <path>`: optional profile path. Defaults to `D:\desktopvisual\config\operator_motion_profile.json`.

Returns `exists`, `version`, `profile_id`, `source`, `created_at`, `created_by`, `sample_count`, `scenario_count`, `quality`, `device_context`, `privacy`, `direction_coverage`, `distance_coverage`, `supported_modes`, and `warnings`.

### motion-profile-validate

Parameters:

- `--profile <path>`: optional profile path.
- `--out <path>`: required Markdown validation report path.

Synthesizes sample paths from the profile and checks final target accuracy, duration range, bounded screen coordinates, non-perfect-line curvature, and non-perfect-linear timing. The JSON result and Markdown report include `source`. Invalid profiles return `MOTION_PROFILE_INVALID`.

### motion-profile-clear

Parameters:

- `--profile <path>`: optional profile path.

Deletes the profile only after the path passes `allowed_write_roots`. Success `data` includes `profile`, `existed`, and `deleted`.

### operator-human move-mode

`operator-human` is accepted by `click`, `double-click`, `right-click`, `scroll`, `drag`, `click-image`, `click-text`, `act`, and task.json act steps through `move_mode`. Mouse `human` is an alias for `operator-human` and is the default when no move mode is supplied. It reads `config\operator_motion_profile.json` by default and requires `source=human`. Missing, invalid, missing-source, or non-human profiles fail with `MOTION_PROFILE_NOT_FOUND`, `MOTION_PROFILE_INVALID`, `MOTION_PROFILE_SOURCE_REQUIRED`, `MOTION_PROFILE_NOT_HUMAN`, or `MOTION_PROFILE_TEST_ONLY` and do not silently fall back. Synthetic/sample profiles are test-only and require both an explicit profile path and `--allow-synthetic-profile` on CLI actions, or `"profile"` plus `"allow_synthetic_profile": true` in task.json. The only explicit fallback is `--fallback fast-human` on CLI actions or `"fallback": "fast-human"` in task.json act steps. Successful mouse action JSON adds `operator_profile_path`, `operator_profile_quality`, `operator_profile_source`, and `synthesized_point_count` while preserving final coordinate accuracy, focus verification, SafetyPolicy checks, F12 interruption, and audit logging.

## Agent Contract Summary

v3.0.3 introduces agent-agnostic adapters. The generic CLI adapter defines these contract commands:

- `version`
- `observe`
- `locate`
- `act`
- `run-case`
- `run-task`
- `read-report`

The normalized adapter return shape is:

```json
{
  "ok": true,
  "error_code": "",
  "data": {},
  "artifacts": [],
  "report_path": ""
}
```

Adapters must use `observe-locate-act-verify`, safety stop rules, no unrestricted desktop control, and no sensitive flows. `version` output includes `data.project_root` so adapters can confirm which portable root is active.

## Benchmark Evidence

v3.0.4 adds benchmark reports outside the frozen CLI envelope. `benchmark_matrix.ps1` writes:

```text
artifacts\benchmark\benchmark_report.md
artifacts\benchmark\benchmark_summary.json
```

`benchmark_summary.json` includes version, timestamp, machine summary, Windows version, OCR/operator profile availability, PASS/FAIL/SKIPPED counts, pass rate excluding skipped, average duration, locator method counts, failure category counts, skipped reason counts, recovery metrics, report completeness, and artifact paths.

v3.3.10 adds the Full Access benchmark harness outside the frozen CLI envelope. `full_access_benchmark_matrix.ps1` writes:

```text
artifacts\benchmark\full_access\full_access_benchmark_report.md
artifacts\benchmark\full_access\full_access_benchmark_summary.json
```

`full_access_benchmark_summary.json` includes scenario results for DEFAULT denial, FULL_ACCESS unlock evidence, safe app launch, local external-web simulation, mixed form semantics, decision-task forms, checkpoint loop guard, simulated communication, simulated coding workflow, and public-release assessment permission notice coverage. Metrics include `full_access_unlock_success`, `permission_mode_success`, `form_control_classification_accuracy`, `decision_task_success_rate`, `loop_guard_trigger_success`, `user_takeover_trigger_success`, `communication_simulation_success`, `coding_workflow_success`, `stop_condition_success_rate`, and `report_completeness_score`.

`export_full_access_evidence_pack.ps1` writes:

```text
artifacts\evidence\DesktopVisual-v3.3.10-full-access-evidence-pack.zip
```

The evidence pack includes selected reports and safety/runtime docs. It must not include real account information, real chat/email content, browser profiles, raw motion data, build outputs, or sensitive logs.

## Developer Tool Dogfood

`dogfood_matrix.ps1` is a bounded script/report harness outside the frozen CLI envelope. v3.6.0 writes:

```text
artifacts\dogfood\dogfood_report.md
artifacts\dogfood\dogfood_summary.json
artifacts\dogfood_matrix_report.md
```

`dogfood_summary.json` includes task results for Notepad, Calculator, Explorer, Local HTML, PowerShell, and VS Code when available. Each task records `task_id`, `status`, `safety_boundary`, `expected_result`, `skipped_condition`, `reason`, `steps`, `duration_ms`, `locators`, `screenshots`, and `report_path`.

Dogfood scripts must stay within `artifacts\dogfood`, skip pre-existing user app sessions, avoid external web, real accounts, browser profiles, payment, password, captcha, social apps, games, anti-cheat, UAC, and administrator windows, and report SKIPPED separately from PASS. A PASS is evidence for the listed scripted scenario only, not proof of arbitrary software control.

`v4_visual_dogfood.ps1` is the v4.6.0 visual dogfood evidence harness. It is also outside the frozen CLI envelope and writes:

```text
artifacts\dev4.6.0\dogfood_report.md
artifacts\dev4.6.0\dogfood_summary.json
```

The v4.6 summary records `local_html_form_flow`, `local_problem_page_run_and_read_result`, `local_mail_mock_compose_attach_verify_no_real_send`, `explorer_temp_file_select_flow`, `notepad_text_edit_verify`, and `powershell_command_result_read`. Each case records commands run, artifacts, observed events, locator methods used, v4 perception evidence, latency, status, and failure or skip reason.

The v4.6 harness must not use real accounts, real email sending, external websites, real assessment/exam submission, captcha bypass, anti-cheat bypass, payment flows, or credential flows. `local_mail_mock` is mock-only and `local_problem_page` is a development benchmark fixture.

## DesktopVisual Service API

`winagent.exe serve --host 127.0.0.1 --port 17873 --token <optional> --max-session-ms <int>` starts an explicit local service wrapper around existing commands. The current implementation uses a local named pipe (`\\.\pipe\DesktopVisualService`) while keeping the documented endpoint abstraction stable.

Defaults:

- `host=127.0.0.1`
- `port=17873` (documented API port; named-pipe transport currently ignores it)
- `max-session-ms=3600000`

If no token is provided, the service is local-only and prints a warning. If a token is provided, requests must include the same token. Service requests do not bypass PermissionManager, SafetyPolicy, required `--title`, focus verification, allowed read roots, or audit logging. Service requests may use an already unlocked FULL_ACCESS session by passing `permission_mode` and `full_access_session_id`, but the service does not expose an unlock endpoint, cannot provide interactive confirmation, and cannot create FULL_ACCESS sessions by itself.

v3.5.0 stabilizes DesktopVisual service protocol version `1.0`.

Supported endpoints:

- `GET /version`
- `GET /health-check`
- `GET /safety-report`
- `GET /profile-report`
- `POST /policy-check`
- `POST /consent-check`
- `POST /observe`
- `POST /locate`
- `POST /act`
- `POST /run-case`
- `POST /run-task`
- `GET /read-report?path=...`
- `GET /report?path=...`
- `POST /shutdown`

Every service response uses this envelope:

```json
{
  "ok": true,
  "error_code": "",
  "message": "OK",
  "data": {},
  "artifacts": [],
  "report_path": "",
  "duration_ms": 0,
  "service_protocol_version": "1.0"
}
```

Failed service responses also retain `error.code` and `error.message` for compatibility, but new callers should use top-level `error_code` and `message`.

`/policy-check`, `/run-task`, and compatible action endpoints accept optional body fields `permission_mode` and `full_access_session_id`. The service maintains `session_id`, `start_time`, `last_target_title`, `last_observe_summary`, `request_count`, `action_count`, and `error_count`. Every request is appended to `D:\desktopvisual\artifacts\service_audit.log` with timestamp, endpoint, title, permission_mode, service_protocol_version, ok, error_code, duration_ms, and session_id.

## Safety Policy

`D:\desktopvisual\config\safety.conf` is a project-local key/value file:

```text
allowed_titles=Agent Test Window;Untitled - Notepad
allowed_processes=TestWindow.exe;notepad.exe
allowed_read_roots=D:\desktopvisual;D:\testrepo\testwindow
allowed_write_roots=D:\desktopvisual;D:\testrepo\testwindow
max_steps=100
max_duration_ms=120000
emergency_stop_key=F12
allow_absolute_screen_click=true
```

`D:\desktopvisual\config\safety_manifest.json` is the machine-readable Safety Manifest. It is merged with `safety.conf` and cannot loosen `safety.conf` hard limits. It adds denied sensitive categories, consent settings, runtime limits, and audit settings. `version` reports `manifest_loaded`, `safety-report` writes machine-readable and Markdown reports, and `policy-check`/`consent-check` expose dry-run decisions.

The input commands `act`, `click`, `double-click`, `right-click`, `scroll`, `drag`, `press`, `hotkey`, `type`, `clipboard-paste`, `focus`, `uia-click`, `uia-type`, `click-text`, and `click-image` must pass the configured title and process whitelist plus manifest denied-category checks when they operate inside a target window. Real input paths must verify that `GetForegroundWindow()` equals the target HWND after `SetForegroundWindow`/`ShowWindow`; failure returns `WINDOW_FOCUS_FAILED`. `read-file`, `read_file`, and `assert_file_contains` must pass `allowed_read_roots` after path normalization. `allowed_write_roots` documents the approved project output roots. If the config is missing, actions still require explicit target context and do not switch to unrestricted backend control. `allow_absolute_screen_click=true` records the current developer-tree global desktop capability; it does not bypass visible-first launch/fallback evidence or active-protection STOP boundaries.

## Audit Log

Each audit line uses this frozen text format:

```text
timestamp="2026-05-25 18:40:01" command="click" target_title="Agent Test Window" result="ok" error_code="" duration_ms=1012 data="..."
```

Fields are always present in this order: `timestamp`, `command`, `target_title`, `result`, `error_code`, `duration_ms`, `data`.

## Case Reports

`run-case` writes Markdown reports with:

- `# WinDesktopAgent Case Report`
- case metadata bullets
- `## Artifacts`
- `## Steps`
- a step table containing `index`, `action`, `params`, `start_time`, `end_time`, `duration_ms`, `result`, `error_code`, `message`, and `json_output`
- optional `## Read State`

## RC Check Script

`rc_check.ps1` is the non-release RC validation runner by default. A default run must not call `package_source.ps1`, `release.ps1`, or `verify_release.ps1`.

Default behavior:

```powershell
D:\desktopvisual\rc_check.ps1
```

The report records the release steps as `SKIPPED` and prints:

```text
Release packaging skipped. Use -IncludeRelease only when user explicitly requests a release package.
```

Release packaging is opt-in only:

```powershell
D:\desktopvisual\rc_check.ps1 -IncludeRelease
```

Use `-IncludeRelease` only when the user explicitly requests a release package. `-PackageRelease` is accepted as a compatibility alias for the same explicit opt-in behavior.

## Compatibility Boundary

v3.7.0 is a Windows-only, agent-agnostic, auditable, safety-bounded Computer Use Runtime, not official Codex built-in Computer Use. It provides authorized-window observe, WindowSession diagnostics, task templates, DEFAULT/FULL_ACCESS permission profiles, interactive temporary FULL_ACCESS sessions, FULL_ACCESS-gated normal desktop/app launch, FULL_ACCESS-gated external web/browser navigation, form/control semantics, General Decision Task Runtime, session checkpoints, loop guard stops, Communication Action Runtime, Coding and Problem-Solving Web Workflow dry-runs, Full Access benchmark/evidence harness reports, Recovery Strategy Engine records, service protocol v1.0, developer-tool dogfood evidence, advanced selector locate, relative locator support, act, verify, Case v2, real OCR when available, explicit service mode, bounded task recovery, local operator motion personalization, portable root resolution, agent adapters, benchmark evidence reporting, and a strict-JSON Safety Manifest/consent layer. It still does not provide protected-desktop/admin-window control, permanent FULL_ACCESS defaults, service-side FULL_ACCESS unlock, task/service-side confirmation, credential/captcha/payment automation, hidden/background browser or app control, unknown-field guessing, checkpoint rollback for remote state, communication sends without explicit user target/intent, public-release assessment workflows without a dedicated permission policy, high-frequency batch submit, paid-limit bypass, problem-set scraping, or detection-bypass automation.













## v5.9.0-a Developer Runtime Permission Mode

`DEVELOPER_CAPABILITY_DISCOVERY` is the default permission mode for the internal `D:\desktopvisual` development tree. It is equivalent to the accepted alias `DEVELOPER_FULL_RUNTIME` for parsing compatibility. Lowercase aliases `developer_capability_discovery` and `developer_full_runtime` are also accepted.

Developer mode allows audited low-level desktop UI commands and ordinary runtime exploration without a legacy FULL_ACCESS session: `mouse.move`, `mouse.click`, `mouse.double_click`, `mouse.drag`, `keyboard.type_text`, `keyboard.press`, `keyboard.hotkey`, `window.focus`, `window.switch`, `app.launch`, `third_party_app.launch`, `explorer.open`, `explorer.navigate`, `file.open_local`, `browser.open`, `browser.address_bar_input`, `browser.navigate`, `local_html.interact`, `localhost.interact`, `external_web.navigate`, `ordinary_form.fill`, `ordinary_button.click`, and mock workflow actions.

`FULL_ACCESS` remains a legacy profile and may still require a temporary unlocked session. It must not be required for developer-mode low-level UI primitives.

Developer mode must not deny an action merely because title, URL, file, or task text contains ordinary content words such as test, exam, assessment, quiz, homework, problem, challenge, coding, oj, submit, form, mail, message, recipient, hiring, recruitment, interview, browser, app, chrome, explorer, localhost, baidu, google, network test, or connectivity test.

Active protection is different from content category. When Runtime detects captcha, reCAPTCHA, hCaptcha, Turnstile, human verification, automation/script/bot detection, active anti-cheat, active proctoring/lockdown browser, protected desktop/UAC, or a request to bypass third-party protection, it must STOP and return `STOP_ACTIVE_PROTECTION` / `BLOCKED_BY_ACTIVE_PROTECTION` style status. Runtime must not hook, inject, patch memory, hide automation, disable a protection process, solve a human verification challenge, or simulate human behavior to evade detection.

Desktop/global screen coordinate actions are allowed in developer mode for observe/locate-derived execution. Reports must distinguish `locator_derived_coordinate_count`, `fixed_coordinate_count`, and `manual_coordinate_count`. Fixed coordinates are not valid proof of general capability.

Runtime Boundary Dogfood result categories are strict: `STRICT_HUMANMODE_PASS`, `HUMANMODE_FALLBACK_PASS`, `SKIP_ENVIRONMENT`, `FAIL`, `BLOCKED_BY_ACTIVE_PROTECTION`, and `FAIL_POLICY_DEFECT`. `SKIP_ENVIRONMENT` is not PASS, `FAIL_POLICY_DEFECT` means developer-mode base UI action was wrongly blocked by policy, and fake PASS is forbidden.


## v5.9.0-b HumanMode Visible UI Commands

`DEVELOPER_CAPABILITY_DISCOVERY` is the developer permission mode for visible desktop capability discovery. It allows audited low-level UI primitives without a legacy FULL_ACCESS session while still stopping on active protection. Ordinary words such as test, exam, assessment, quiz, problem, challenge, submit, mail, hiring, and recruitment are not active protection signals by themselves.

HumanMode action commands must use real visible input events. `desktop-move`, `desktop-click`, and `desktop-double-click` accept `--screen-x`, `--screen-y`, and optional `--permission-mode DEVELOPER_CAPABILITY_DISCOVERY`; they move the real cursor and use real mouse input at screen coordinates. `desktop-press`, `desktop-hotkey`, and `desktop-type` send real global keyboard input for foreground desktop workflows such as Win+D, Win+E, Start Menu search, and Explorer address-bar fallback.

Screen coordinates in Case evidence must be marked as `locator_derived`, `fallback_keyboard`, `manual_fixed`, or `setup_only`. `locator_derived` coordinates come from observe/UIA/OCR/ElementGraph. Fixed coordinates are not valid proof of general HumanMode capability.

Allowed HumanMode Case result categories are `STRICT_HUMANMODE_PASS`, `HUMANMODE_FALLBACK_PASS`, `SKIP_ENVIRONMENT`, `FAIL`, `BLOCKED_BY_ACTIVE_PROTECTION`, and `FAIL_POLICY_DEFECT`. Direct launch, ShellExecute, backend typing, no-open mock, DOM mutation, JavaScript click/set value, UIA InvokePattern, UIA ValuePattern, Selenium, Playwright, WebDriver, and CDP cannot be recorded as `STRICT_HUMANMODE_PASS`.

## v5.9.0-c Strict HumanMode Case B/D/C Evidence

`v5_9_0_c_strict_case_bdc.ps1` is a script-level evidence runner, not a new CLI command. It writes artifacts under `artifacts\dev5.9.0-c_strict_case_bdc\` and preserves the existing v5.9.0-b HumanMode command surface. Case B records address-bar locator evidence before mouse click and URL typing; Case D records Explorer path item locator evidence for each path level; Case C records explicit/env/common/registry/Start Menu third-party App target resolution before launch evidence.

## v5.9.0-d Case D Explorer Content Locator Evidence

`v5_9_0_d_case_d_explorer_locator_fix.ps1` is a script-level evidence runner, not a new CLI command. It writes artifacts under `artifacts\dev5.9.0-d_case_d_explorer_locator_fix\` and only runs Case D. The runner locks the foreground Explorer hwnd opened by real mouse double-click on the This PC fixture, derives a content rect excluding title/address/search/navigation/status regions, scopes UIA/OCR locator evidence to that locked hwnd content area, and verifies each navigation level before continuing.

Explorer address-bar text may be read as verification evidence, but Explorer address-bar path input is not a valid strict action. Current-folder incremental search is allowed only after the locked Explorer window is verified at the expected current folder and the content area is focused by real input.

## v5.9.0-e HumanMode Pacing And Result Contract

HumanMode mouse actions require visible pacing, not only use of Windows input APIs. The required order is `move_start`, multiple `move_steps`, `move_end`, cursor-at-target verification, `dwell_before_click`, click or double-click, and `post_click_settle`. `desktop-click` and `desktop-double-click` must not batch cursor movement and click into an invisible instant action.

`desktop-move`, `desktop-click`, and `desktop-double-click` default to `--humanmode true`. Supported pacing options are:

- `--move-duration-ms <int>`
- `--dwell-before-click-ms <int>`
- `--double-click-interval-ms <int>`
- `--post-click-settle-ms <int>`
- `--target-epsilon-px <int>`
- `--result-json <path>`
- `--target-description <text>`
- `--coordinate-source <locator_derived|heuristic_locator_derived|manual_fixed|fallback_keyboard>`
- `--target-rect-left <int> --target-rect-top <int> --target-rect-right <int> --target-rect-bottom <int>` for strict item-rect evidence.

Default HumanMode pacing is visible: move duration 500 ms, at least 18 steps, dwell before click 180 ms, post-click settle 180 ms, double-click interval 140 ms, and target epsilon 3 px. Short moves still last at least 250 ms with at least 8 steps. Medium moves last at least 350 ms. Long moves last at least 550 ms.

Instant mode is retained only for explicit non-HumanMode diagnostics via `--humanmode false`; it is not valid for HumanMode Case PASS.

HumanMode mouse command JSON includes `data.human_action_result` with `schema_version="human_action_result.v1"`, `runtime_version`, `action_id`, `action_type`, `humanmode`, `backend_action`, `direct_launch`, `fallback_used`, `actual_click_sent`, `actual_double_click_sent`, `exit_code`, `target`, `cursor`, `motion`, `timing`, `verification`, and `error`. When target rect arguments are provided, `target.target_rect`, `target.target_center_x`, `target.target_center_y`, `cursor.inside_target_rect_before_click`, `cursor.distance_to_target_center_px`, `verification.target_rect_verified`, and `verification.cursor_inside_target_rect_before_click` are populated for strict mouse-target evidence. `drag` returns a `human_action_result` with mouse drag start/end screen points and mouse down/up verification.

HumanMode keyboard command JSON for `desktop-press`, `desktop-hotkey`, and `desktop-type` includes `data.human_action_result` with `schema_version="human_action_result.v1"`, `runtime_version`, `action_id`, `action_type`, `humanmode=true`, backend/direct-launch flags, foreground before/after, key/keys/text length metadata, exit code, verification fields, and error fields. `ok=false` results must include `error.code`, and non-diagnostic failures return a non-zero process exit code.

## v5.9.1 Pre-v6 Runtime Handoff Gate

v5.9.1 adds no new v6 command surface. It validates that existing CLI and service commands can expose Runtime and HumanMode capabilities for the future v6 Agent boundary. Handoff evidence is written under `artifacts\dev5.9.1_pre_v6_handoff\` and records PASS, FAIL, SKIP, or NOT_RUN without converting missing evidence into PASS.

## v5.9.2 Active Protection STOP Policy Fix

v5.9.2 adds no new command surface. It fixes policy classification so developer mode still allows ordinary capability discovery while stopping concrete active-protection signals before allow decisions. Ordinary content words such as test, exam, assessment, quiz, problem, challenge, submit, mail, localhost, local HTML, and ordinary web are not hard STOP signals by themselves.

`policy-check` and permission-aware commands return `STOP_ACTIVE_PROTECTION` / `BLOCKED_BY_ACTIVE_PROTECTION` style failures for CAPTCHA / human verification, bot challenge, automation or script detection, anti-cheat process/service names such as `BEService.exe`, `EasyAntiCheat.exe`, `vgc.exe`, and `Riot Vanguard`, lockdown / secure exam browser names, active proctoring signals, screen monitoring protection, and bypass requests such as bypassing CAPTCHA, avoiding bot detection, disabling anti-cheat, hooking protection services, hiding automation, or patching protection processes.

## v5.9.3 Explorer Mouse Target Strictness Evidence

`v5_9_3_explorer_mouse_target_strictness.ps1` is a script-level evidence runner, not a new v6 surface. It writes artifacts under `artifacts\dev5.9.3_explorer_mouse_target_strictness\` and only runs Case D.

Case D strict result is `STRICT_MOUSE_TARGET_HUMANMODE_PASS`. Before opening This PC / fixture, D:, `testrepo`, `testwindow`, and `desktopvisual_mail_mock.html`, the runner must resolve a visible target item rect from the locked foreground Explorer hwnd or desktop fixture, move the real cursor inside that rect, verify `cursor_inside_target_rect_before_click=true` with `GetCursorPos`, save overlay evidence, perform a real double-click inside the rect, and verify the next location or final browser/file open.

Incremental search is allowed only as a locator aid after the current Explorer location is verified and content is focused. The selected item name must match the expected target and selected item rect must be available before mouse double-click. Incremental search + Enter, keyboard-assisted/default selection open, Explorer address bar / address-bar path input, direct file open, ShellExecute, Start-Process, Invoke-Item, UIA InvokePattern/ValuePattern, and backend opens cannot be recorded as `STRICT_MOUSE_TARGET_HUMANMODE_PASS`. Reading Explorer address/breadcrumb text remains allowed as verification.

The handoff gate checks `version`, desktop HumanMode commands, task status/report/event commands, service health/run-task surfaces when available, active-protection STOP behavior, core v5 regression scripts, documentation consistency, and historical HumanMode case artifacts.


