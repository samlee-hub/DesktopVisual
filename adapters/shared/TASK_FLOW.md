# DesktopVisual Adapter Task Flow

This shared rule applies to every DesktopVisual adapter.

Required loop: `observe-locate-act-verify`.

DesktopVisual is a Windows visible-first desktop runtime, not a background script executor. The adapter's goal is not the fastest path; it must prefer visible, auditable, human-like desktop operations.

Default progress output is compact progress with full evidence retained in artifacts. Use `report_level=compact` and `evidence_level=full`; compact output must not hide failures. On failure, report the error, evidence, and next repair. For long context, create or reuse `agent_context_digest.md`, do not repeatedly reread full documents as a default workflow, and do not scan artifacts, `.git`, `bin`, or `obj` unless a verifier explicitly requires that path.

1. Call `version` first and confirm `project_root`.
2. Confirm the authorized target window.
3. Use visible-app-launch for app, URL, local shortcut, .lnk, .url, and webpage shortcut launches.
4. App launch is desktop-first. Start Menu visible search is a fallback, not the first choice.
5. Prefer a reviewed `task.json` and `run-task` for multi-step work.
6. Before writing low-level task steps, check `tasks\templates` and use a matching template such as `click_button`, `fill_form`, `wait_until_text`, `wait_until_window`, `copy_text`, or `save_file`.
7. For single custom actions, run `observe`, then `locate`, then `act`, then verify with a fresh `observe` or report expectation.
8. Read the report after `run-task` or `run-case`; for template tasks, inspect the `## Templates` section.

Safety stop rules: stop on any non-empty `error_code`, failed report step, or unexpected target state. Do not continue with arbitrary clicks after failure.

No unrestricted desktop control: adapters may only operate on user-authorized windows and configured safe paths.

Templates are deterministic expanders. They do not bypass SafetyPolicy, Safety Manifest, foreground focus checks, selector uniqueness, or report review.

No sensitive flows: adapters must not operate credential prompts, banking, payment, security-control, protected desktop, admin/elevated, anti-cheat, or privacy-sensitive workflows.

Fallback discipline: Layer 1: visible UI path. Layer 2: visible keyboard fallback. Layer 3: backend fallback. Entering fallback requires two bounded visible attempts or strict surface-impossible evidence. Entering backend fallback requires visible path failure plus keyboard fallback failure. backend fallback is not the default path.

target_not_found, uia_not_found, ocr_not_found, and click_failed alone are not surface-impossible evidence. Do not disguise clipboard/backend write as visible input success.

Active protection or security interception is STOP, not fallback.

VLM assist in v1.0.3.1 uses the v1.0.3+ normal path: `vlm-capability-probe`, `vlm-assist-locate`, and `vlm-candidate-validate`. Probe once per large task/session, reuse the cache, and call VLM only for frontend perception/locate failure or unclear keyboard-fallback visual state. VLM returns locate-only candidate evidence; Runtime validates candidates, maps coordinates, executes actions, verifies results, and keeps fallback discipline. If `VLM_UNAVAILABLE`, continue Runtime-only. VLM must not directly operate the computer, participate in backend fallback, run after backend fallback starts, or bypass active protection. Legacy mock VLM commands are deprecated test-only fixtures, not normal Agent workflows.

v1.0.4 complex IDE work must use `RealVlmRuntimeBridge` / the real VLM bridge path.

v1.0.5 capture/OCR work keeps the full-screen capture source-of-truth and requires OCR memory-frame-first. PNG evidence must be retained and saved asynchronously; flush evidence before failure or BLOCKED. Foreground/window OCR must crop from the full-screen frame, and fallback must use the same frame for full-screen OCR. OCR results must bind `frame_id` and `screenshot_id` and report cache/tile cache fields when present. VLM provider-dependent transport uses a frame-bound input image; Codex CLI currently needs file path `--image`, and old mock VLM is not a normal path.

Visual Studio C++ complex IDE workflow rules for v1.0.4: launch VS only by visible desktop icon double-click; create `SingleTestProject` as an Empty Project through visible VS UI; keep the default project location/settings; add `.cpp` and `.h` files through Solution Explorer visible Add/New Item or visible `Ctrl+Shift+A`; edit code only through the visible VS editor; build and run only through VS UI or visible IDE shortcuts; verify output from visible console/output evidence; close successful boundaries by visible top-right X. Backend `.sln` open, backend project/file creation, backend file writes, `.vcxproj` edits, backend build, direct exe run, old mock VLM, and one-shot batch scripts are invalid PASS evidence.

Benchmark reference: run `benchmark_matrix.ps1` when evidence is required for repeatable capability claims.
