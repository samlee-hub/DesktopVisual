# DesktopVisual Benchmarks

Current version: `v6.1.4`.

## v6.1.4 Dynamic UI Benchmark Evidence

The v6.1.4 evidence pack is written under:

```text
D:\desktopvisual\artifacts\dev6.1.4_dynamic_app_web_click_accuracy\
```

Required benchmark cases are PyCharm dynamic coding/run, WeChat file-transfer-assistant send, QQ Mail compose/send at `https://mail.qq.com`, and one v6.1.2/v6.1.3 baseline regression replay.

The benchmark requires first-attempt success rate >= 0.80, zero misclicks, zero wrong target clicks, zero wrong field inputs, zero cursor-outside-target clicks, no stale target click, no synthetic/placeholder/hardcoded evidence, no JS/DOM/WebDriver/CDP/Playwright/Selenium, and no UIA InvokePattern/ValuePattern strict actions.

Benchmark evidence must include heartbeat/no-progress diagnostics: 15 second heartbeat JSONL, 60 second command-step timeout metadata, bounded case/global timeouts, and blocked partial artifacts for timeout, active protection, login/security, or F12 interruption.

## v6.1.3 Mouse Wheel Scroll Evidence

The v6.1.3 evidence pack is written under:

```text
D:\desktopvisual\artifacts\dev6.1.3_mouse_wheel_scroll_and_scroll_locate\
```

PASS requires real `SendInput` plus `MOUSEEVENTF_WHEEL` evidence for Mouse Wheel Primitive, Browser Long Page Scroll-and-Locate, Mock Friend List Scroll-and-Locate, Explorer List Scroll-and-Locate, Wheel No-Progress Detection, and fresh v6.1.2 baseline replay. The benchmark also requires build/version, command help/targeted tests, HumanMode pacing run1/run2, v6.1 Planner selftest, v6.1.1 and v6.1.2 gate regressions, v6.0 boundary, permission selftest, adaptive loop regression, JSON/JSONL parse, Markdown fence validation, encoding/mojibake scan, COMMAND_PROTOCOL consistency, evidence pointer checks, and final scroll acceptance gate output.

The runner cannot self-certify benchmark PASS. `v6_1_3_wheel_scroll_verifier.ps1` and `v6_1_3_scroll_acceptance_gate.ps1` must reject synthetic evidence, placeholder screenshots, hardcoded hwnd/rect, invalidated evidence, old v6.1.2 artifacts reused as v6.1.3 PASS, scrollbar-first strict scroll, PageDown/ArrowDown strict scroll, JS/DOM/WebDriver/CDP/Playwright/Selenium scroll, UIA ScrollPattern, and missing content-change evidence.

## v6.1.2 Real UI Baseline Sanity Evidence

The v6.1.2 evidence pack is written under:

```text
D:\desktopvisual\artifacts\dev6.1.2_real_ui_baseline_sanity_pre_v6_2_gate\
```

It revalidates the v6.1.1 trusted baseline before v6.2. PASS requires Explorer Real UI Sanity, Browser Mail Mock Real UI Sanity, Browser Mail Mock Repeat Run, two HumanMode pacing regressions, v6.1 Planner selftest, v6.1.1 acceptance gate regression, v6.0 boundary regression, permission selftest, adaptive loop regression, JSON/JSONL parse, Markdown fence validation, encoding/mojibake scan, COMMAND_PROTOCOL consistency, evidence pointer checks, and final pre-v6.2 acceptance gate output.

The runner cannot self-certify benchmark PASS. Benchmark PASS comes only from verified `task_result.json` files and `v6_1_2_pre_v6_2_acceptance_gate.ps1`. Synthetic evidence, placeholder screenshots, hardcoded hwnd/rect, invalidated evidence, diagnostic-only results, backend opens, direct file opens, JS/DOM/WebDriver/CDP/Playwright/Selenium actions, and UIA InvokePattern/ValuePattern actions are invalid benchmark evidence.

## v5.10.2 REBUILT Real TaskRuntime Evidence

The rebuilt v5.10.2 evidence pack is written under:

```text
D:\desktopvisual\artifacts\dev5.10.2_real_taskruntime_final_gate\
```

It integrates `tasks\localhost_form_fill_submit_humanmode.task.json` through real TaskRuntime UI execution. PASS can only be counted when `v5_10_2_taskruntime_evidence_verifier.ps1` reports `REAL_TASKRUNTIME_HUMANMODE_PASS`; TaskRuntime execution completion alone is not benchmark PASS evidence.

Required v5.10.2 checks cover build/version, v5.10.1 rebuilt verifier evidence, TaskRuntime real integration, TaskRuntime verifier, final Pre-v6 Gate, active-protection STOP, CLI/service surface, core v5 regressions, JSON/JSONL parsing, Markdown fence validation, encoding/mojibake scan, documentation consistency, tree hygiene, and git status snapshots.

## v5.10.1 REBUILT Real UI Adaptive Case Evidence

The rebuilt v5.10.1 evidence pack is written under:

```text
D:\desktopvisual\artifacts\dev5.10.1_real_ui_adaptive_cases\
```

It reruns real UI adaptive Case D/E/F from the trusted v5.10.0 core baseline. The old `artifacts\dev5.10.1_adaptive_cases\` evidence remains invalidated and must not be counted. The runner writes raw evidence only; the independent verifier writes verified task results and trace artifacts. Synthetic evidence, placeholder screenshots, hardcoded hwnd/rect, backend/direct-launch actions, JS/DOM/WebDriver/CDP, UIA InvokePattern/ValuePattern actions, and runner self-PASS are invalid benchmark evidence.

Required v5.10.1 checks cover build/version, developer permission selftest, HumanMode pacing, adaptive loop diagnostics, real UI raw runner, independent verifier, synthetic evidence guard, JSON/JSONL parsing, Markdown fence validation, encoding/mojibake scan, COMMAND_PROTOCOL consistency, and git status snapshots.

## v5.10.1/v5.10.2 Invalidated Evidence

The v5.10.1 evidence pack under `D:\desktopvisual\artifacts\dev5.10.1_adaptive_cases\` is INVALIDATED because it contains synthetic Adaptive HumanMode evidence. The v5.10.2 evidence pack under `D:\desktopvisual\artifacts\dev5.10.2_final_pre_v6_gate\` is INVALIDATED because it contains hardcoded/simulated TaskRuntime browser form handoff evidence.

Invalidated evidence must not be counted in valid evidence indexes, PASS totals, benchmark readiness, or v6 handoff readiness. `ready_for_v6` true is revoked; the next benchmark work is a real UI adaptive cases rerun.

## v5.10.0 Adaptive HumanMode Control Loop Evidence

The v5.10.0 evidence pack is scoped to the Adaptive HumanMode Control Loop core. It does not enter v6, introduce VLM, develop an Agent Planner, narrow public release permissions, change developer capability discovery, or claim full Case D/E/F completion. Evidence is written under:

```text
D:\desktopvisual\artifacts\dev5.10.0_adaptive_humanmode_loop\
```

Required checks cover candidate validation, coordinate mapping, Explorer locator readiness, browser form locator readiness, HumanActionResult integration, retry budget handling, build/version output, developer permission reset regression, HumanMode motion pacing regression, JSON/JSONL parsing, Markdown fence validation, encoding/mojibake scan, COMMAND_PROTOCOL consistency, and git status snapshots.

Explorer readiness verifies that `testrepo` is accepted while wrong candidates such as `devTool`, left-navigation matches, address-bar matches, offscreen/stale hwnd candidates, and missing selected item rects are rejected or failed with explicit reasons.

Browser form readiness verifies label-to-field targets for Recipient, Subject, Body, and Send. It distinguishes an actual Send button from paragraph text such as "send real email" and rejects address/search-bar or stale/off-viewport candidates.

## v5.9.3 Explorer Mouse Target Strictness Evidence

The v5.9.3 evidence pack is scoped to Explorer Case D mouse-target strictness only. It does not enter v6, introduce VLM, develop an Agent Planner, narrow public release permissions, change the developer permission model direction, fix Case E/F, or integrate TaskRuntime HumanMode browser flow. Evidence is written under:

```text
D:\desktopvisual\artifacts\dev5.9.3_explorer_mouse_target_strictness\
```

Case D now passes only as `STRICT_MOUSE_TARGET_HUMANMODE_PASS`. This PC / fixture, D:, `testrepo`, `testwindow`, and `desktopvisual_mail_mock.html` must each have a visible target item rect, cursor verification inside that rect before click, real double-click inside that rect, overlay evidence, and open verification. Incremental search is locator-only; incremental search + Enter, keyboard-assisted/default selection opens, Explorer address-bar path input, direct file open, ShellExecute, Start-Process, Invoke-Item, UIA InvokePattern/ValuePattern, and backend opens are not strict evidence. v5.9.0-d Case D artifacts are content-locator evidence and are no longer sufficient as strict mouse-target evidence.

DesktopVisual benchmarks are evidence packs, not marketing claims. A PASS means the required local behavior was observed on the current machine. A SKIPPED result is not a PASS.

## v5.9.2 Active Protection STOP Policy Evidence

The v5.9.2 evidence pack is scoped to policy behavior only. It does not rerun HumanMode Case D/E/F, does not introduce VLM or Agent Planner behavior, and does not narrow developer capability discovery. Evidence is written under:

```text
D:\desktopvisual\artifacts\dev5.9.2_active_protection_stop_policy\
```

The required checks verify that ordinary content words and pages remain `ALLOW_AUDITED`, concrete active-protection signals return `STOP_ACTIVE_PROTECTION`, bypass requests stop, JSON/JSONL artifacts parse, Markdown fences are balanced, and command protocol documentation remains consistent.

## v4 Latency Evidence

Run:

```powershell
D:\desktopvisual\latency_benchmark.ps1
```

Outputs:

```text
D:\desktopvisual\artifacts\dev4.3.0\latency\latency_results.json
D:\desktopvisual\artifacts\dev4.3.0\latency\latency_summary.md
D:\desktopvisual\artifacts\dev4.3.0\latency\benchmark_config.json
D:\desktopvisual\artifacts\dev4.3.0\latency\raw_logs
```

Tracked metrics include:

- `screenshot_latency_ms`
- `uia_latency_ms`
- `full_ocr_latency_ms`
- `roi_ocr_latency_ms`
- `screen_delta_latency_ms`
- `element_graph_build_ms`
- `hybrid_locate_latency_ms`
- `visual_provider_latency_ms`
- `observe2_latency_ms`
- `observe_loop_event_latency_ms`
- `act_to_verify_latency_ms`
- `cache_hit_ratio`
- `llm_or_vlm_call_count`

The default v4 runtime should record `llm_or_vlm_call_count = 0` because v4 does not call real VLM providers.

## v4 RC Evidence

Run:

```powershell
D:\desktopvisual\v4_rc_check.ps1
```

Outputs:

```text
D:\desktopvisual\artifacts\dev4.7.0\v4_release_candidate_report.md
D:\desktopvisual\artifacts\dev4.7.0\v4_release_candidate_summary.json
D:\desktopvisual\artifacts\dev4.7.0\logs
```

The RC check aggregates:

- v4.1 provider evidence.
- v4.2 observe-loop evidence.
- v4.3 latency evidence.
- v4.4 dynamic recovery evidence.
- v4.5 App Profile evidence.
- v4.6 visual dogfood evidence.
- Safety, public hygiene, JSON, Markdown, and command/version checks.

## v5.6 Task-Level Dogfood Benchmark

Run:

```powershell
D:\desktopvisual\task_dogfood_benchmark.ps1 -Root D:\desktopvisual
D:\desktopvisual\task_dogfood_report_selftest.ps1 -Root D:\desktopvisual
D:\desktopvisual\v5_6_acceptance.ps1 -Root D:\desktopvisual
```

Outputs:

```text
D:\desktopvisual\artifacts\dev5.6.6\task_dogfood_report.md
D:\desktopvisual\artifacts\dev5.6.6\task_dogfood_summary.json
D:\desktopvisual\artifacts\dev5.6.6\case_registry.json
D:\desktopvisual\artifacts\dev5.6.6\cases
```

The v5.6 benchmark is task-level evidence for controlled local workflows. It is not a real external task benchmark and must not be described as proof of arbitrary desktop understanding or complete Agent behavior.

Required registry coverage:

- `local_form_fill_submit`
- `notepad_edit_verify`
- `local_problem_page_run_read_result`
- `compile_runtime_error_mock`
- `local_mail_mock_attachment_flow`
- `explorer_file_select_flow`
- `powershell_run_read_report_flow`

Each case records PASS, FAIL, or SKIPPED. A SKIPPED case must include a justification. Notepad may be SKIPPED when a clean interactive desktop window cannot be guaranteed without touching user state; that is not a fake PASS.

Reports include task states, step results, recovery attempts, confirmations, measured wall-clock latency, artifacts, failure reasons, audit path, workflow scope, fixed-coordinate usage, and external-operation flags.

v5.6 distinguishes:

- `local_mock`: generated local fixtures or mock app/profile flows.
- `local_desktop_skip`: intentionally skipped local desktop case with a reason.
- `real_external`: not allowed in this benchmark.

The mail attachment case uses local mock file picker and upload state fixtures and must not send real email or upload real files to an account. The problem-solving cases use local mock HTML only and must not automate exams, hiring assessments, contests, proctoring, or public submissions.

## Safety And Scope

Benchmarks operate against local fixtures, TestWindow, generated HTML, and `artifacts`. They do not use real accounts, real email, real exams, hiring assessments, certifications, proctored pages, rated contests, captcha, anti-cheat, payments, credentials, or account-security bypass.

## Limits

Latency numbers are current-machine evidence. They are not cross-machine service-level objectives and must not be used for uncontrolled claims against other tools.

Cache, ROI, OCR, UIA, and visual-provider timings depend on Windows version, OCR language availability, display scaling, target app accessibility metadata, CPU load, and local graphics behavior.

## v5.9.0-a Runtime Boundary Dogfood

v5.9.0-a adds Runtime Boundary Dogfood for developer permission reset evidence:

- Case A `desktop_mouse_open_chrome_visible_flow`: open Chrome or Edge through visible desktop UI or Start-menu fallback, record screenshots, and never count direct launch as strict UI evidence.
- Case B `chrome_address_bar_external_url_navigation_flow`: click/focus address bar or use Ctrl+L fallback, type an ordinary URL such as example.com or baidu.com, press Enter, and stop on active protection.
- Case C `third_party_app_launch_flow`: launch PyCharm or another specified third-party app only to verify startup/window recognition; missing app is `SKIP_ENVIRONMENT`.
- Case D `explorer_open_local_html_flow`: use Explorer UI/address-bar fallback to open `D:\testrepo\testwindow\desktopvisual_mail_mock.html` and verify a file URL appears.
- Case E `local_mail_mock_browser_fill_and_send_flow`: operate a local mock mail page with real clicks/keyboard input, verify fields clear and `Mock sent successfully`, and send no real email.

Allowed result categories are `STRICT_HUMANMODE_PASS`, `HUMANMODE_FALLBACK_PASS`, `SKIP_ENVIRONMENT`, `FAIL`, `BLOCKED_BY_ACTIVE_PROTECTION`, and `FAIL_POLICY_DEFECT`. The mock mail case does not send real mail or access external services. External URL testing is ordinary navigation capability testing, not captcha/anti-bot/protection bypass testing.


## v5.9.0-b HumanMode Visible UI Case Runner

Run:

```powershell
D:\desktopvisual\v5_9_0_b_humanmode_case_runner.ps1 -Root D:\desktopvisual
```

Outputs:

```text
D:\desktopvisual\artifacts\dev5.9.0-b_humanmode_case_runner\
```

Case categories are `STRICT_HUMANMODE_PASS`, `HUMANMODE_FALLBACK_PASS`, `SKIP_ENVIRONMENT`, `FAIL`, `BLOCKED_BY_ACTIVE_PROTECTION`, and `FAIL_POLICY_DEFECT`. The runner records Chrome/Edge desktop open, browser address-bar navigation, third-party app launch or environment skip, Explorer local HTML open, and local mock mail fill/send. The local mail mock sends no real email. External webpage coverage is ordinary navigation only and stops on active protection.

## v5.9.0-c Strict HumanMode Case B/D/C Completion

Run:

```powershell
D:\desktopvisual\v5_9_0_c_strict_case_bdc.ps1 -Root D:\desktopvisual
```

Outputs:

```text
D:\desktopvisual\artifacts\dev5.9.0-c_strict_case_bdc\
```

This stage remains v5 and only addresses Case B, Case D, and Case C target resolution. Case B must locate the browser address bar and use real mouse click plus real keyboard URL entry, with Ctrl+A allowed only after mouse focus. Case D must open `D:\testrepo\testwindow\desktopvisual_mail_mock.html` through visible Explorer UI by selecting This PC, D:, `testrepo`, `testwindow`, and the HTML file. Case C resolves explicit/env/common/registry/Start Menu safe GUI App targets before SKIP, and may substitute Chrome as an available third-party GUI App target when PyCharm / VS Code are absent.

## v5.9.0-d Case D Explorer Content Locator Fix

Run:

```powershell
D:\desktopvisual\v5_9_0_d_case_d_explorer_locator_fix.ps1 -Root D:\desktopvisual
```

Outputs:

```text
D:\desktopvisual\artifacts\dev5.9.0-d_case_d_explorer_locator_fix\
```

This stage remains v5 and only fixes Case D. PASS requires visible Explorer UI traversal through This PC or the This PC fixture, D:, `testrepo`, `testwindow`, and `desktopvisual_mail_mock.html`. The runner may read Explorer address/breadcrumb text for verification, may normalize the current folder view, and may use current-folder incremental search after focusing the content area. It must not use Explorer address-bar path input, ShellExecute, Start-Process, Invoke-Item, direct file open, WebDriver, CDP, DOM mutation, UIA InvokePattern, or UIA ValuePattern as PASS evidence.

## v5.9.0-e HumanMode Motion Pacing Evidence

Run:

```powershell
D:\desktopvisual\v5_9_0_e_humanmode_motion_pacing_test.ps1 -Root D:\desktopvisual -SkipBuild
```

Outputs:

```text
D:\desktopvisual\artifacts\dev5.9.0-e_humanmode_motion_pacing\
```

This benchmark is local pacing evidence for HumanMode mouse primitives and case runner result contracts. It checks that `desktop-move`, `desktop-click`, and `desktop-double-click` return parseable `human_action_result.v1` JSON, use visible move duration and steps, verify cursor epsilon before click, dwell before click, and preserve double-click interval. It also verifies failure output as `ok=false` with `error.code`.

HumanMode case results must record pacing fields such as `humanmode_pacing_checked`, minimum move/dwell/double-click interval metrics, click-before-move-end count, instant-click-after-move count, HumanActionResult count, parse errors, and contract version.

## v5.9.1 Pre-v6 Runtime Handoff Evidence

Run:

```powershell
D:\desktopvisual\v5_9_1_pre_v6_handoff_gate.ps1 -Root D:\desktopvisual -SkipBuild
```

Outputs:

```text
D:\desktopvisual\artifacts\dev5.9.1_pre_v6_handoff\
```

This evidence gate verifies whether v5.9.x can serve as the Runtime base for v6. It audits HumanMode case artifacts, runs stability checks where possible, records localhost HumanMode and Task Runtime integration status, verifies CLI/Service surfaces, confirms active-protection STOP behavior, runs available v5 regression scripts, and validates documentation/artifact consistency. A NOT_RUN or SKIP is recorded as such and is not a PASS.



