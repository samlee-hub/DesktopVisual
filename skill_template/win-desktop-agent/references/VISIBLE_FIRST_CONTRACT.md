# Visible-First Contract

Current version: `DesktopVisual 1.0.5`.

This reference is the source-of-truth contract for how an agent must use DesktopVisual v1.0.3.1. It documents the Runtime discipline added in v1.0.1, the provider-gated VLM assist added in v1.0.3, and the legacy mock VLM quarantine added in v1.0.3.1.

For v1.0.5 it also documents the full-screen frame source-of-truth and OCR memory-frame-first pipeline.

## DesktopVisual Positioning Contract

DesktopVisual is a Windows visible-first desktop runtime, not a background script executor.

The agent's goal is not the fastest path; it must prefer visible, auditable, human-like desktop operations. Every input action must have observe / locate / act / verify evidence, or an equivalent task/visible command evidence chain.

Task success is path-sensitive. A task can fail because the path was illegal even when the final application state appears correct. A backend shortcut that reaches the desired final state still fails the contract when it skipped required visible-first evidence.

## Visible-App-Launch Contract

Use visible-app-launch for app, URL, local shortcut, .lnk, .url, and webpage shortcut launches. visible-app-launch is desktop-first.

Desktop-first launch requires this order:

1. Reveal the desktop surface.
2. Observe the desktop surface.
3. Locate the target through UIA, OCR, visible icon evidence, `.lnk`, `.url`, or visible webpage shortcut evidence.
4. Open a matching desktop icon or shortcut with real mouse movement and double-click.
5. Verify the target window when a target title or process is supplied.

Start Menu visible search is a fallback, not the first choice. It may be used only after desktop-first evidence fails through the fallback gate. backend launch, ShellExecute, direct file open, and background browser navigation are not default launch paths.

If the first desktop locate or double-click fails, do not immediately switch to Start Menu. The agent must perform bounded recovery and a second desktop visible attempt, or provide two bounded desktop visible attempts or strict surface-impossible evidence.

If target-title or process is provided, target_window_verified must be true before the launch is reported successful. Command dispatch success alone is not launch success.

Required launch evidence includes:

- `runtime_visible_first_launch`
- `launch_strategy`
- `desktop_surface_attempted`
- `desktop_icon_path_used`
- `start_menu_fallback_attempted`
- `backend_launch_used`
- `bounded_recovery_attempted`
- `target_window_verified`

Other useful evidence includes `desktop_icon_locate_attempt_count`, `desktop_icon_double_click_attempt_count`, `target_verification_method`, and `operation_priority`.

## Three-Layer Fallback Contract

Layer 1: visible UI path. This includes UIA, OCR, visible icons, image/template evidence, real mouse/keyboard, target-window lock, coordinate mapping, and post-action verification.

Layer 2: visible keyboard fallback. This includes shortcuts, Start Menu visible search, address-bar visible navigation, and similar visible keyboard-driven operation. It is allowed only after Layer 1 is proven unavailable by bounded visible evidence.

Layer 3: backend fallback. This includes direct launch, ShellExecute, backend browser navigation, file writes, clipboard/backend injection, script execution, and similar non-visible shortcuts. It is allowed only after visible path failure plus keyboard fallback failure. backend fallback is not the default path.

Do not jump to shortcuts because they are faster. Do not jump to backend because it is convenient. Do not switch layers after one locator failure. Do not switch layers after one click failure. Do not disguise clipboard/backend write as visible input success.

target_not_found, uia_not_found, ocr_not_found, and click_failed alone are not surface-impossible evidence.

Entering shortcut fallback requires at least two bounded visible attempts or strict surface-impossible evidence.

Two bounded visible attempts must include:

1. pre-action checkpoint
2. observe / locate / action
3. failure reason
4. bounded recovery
5. re-observe / re-locate
6. second visible action

Entering backend fallback requires visible path failure plus keyboard fallback failure. The backend fallback reason must be non-empty and must not be convenience, speed, or test shortcut.

Active protection or security interception is STOP, not fallback. Do not treat CAPTCHA, human verification, automation detection, security verification, protected desktop, proctoring, lockdown browser, secure exam browser, anti-cheat, or similar interception as a reason to try a lower layer.

## Developer Permission Contract

The developer tree uses `DEVELOPER_CAPABILITY_DISCOVERY` / `DEVELOPER_FULL_RUNTIME` style permissions. It is a broad local development and capability-discovery tree, not the public release policy.

ordinary app, ordinary webpage, https, localhost, IDE, browser, file manager, mail page, communication page, coding practice page, test, exam, challenge, submit, and assessment keywords are not developer STOP conditions by themselves.

If there is no active protection or security interception, developer mode must not stop because of broad category or keyword matching.

Developer mode must stop when an actual active-protection or security-interception mechanism is present, including CAPTCHA, human verification, bot challenge, automation detected, script detected, security verification, `CredentialUIBroker`, `Consent.exe`, UAC/protected desktop, proctoring, lockdown browser, secure exam browser, ACE, EasyAntiCheat, Vanguard, BattlEye, or other anti-cheat/anti-automation interception. The correct action is to stop and report the boundary, not to investigate bypasses.

DesktopVisual v1.1.0 aligns `PUBLIC_DEFAULT` for ordinary visible desktop operations while preserving STOP boundaries for real active protection, security interception, proctoring/lockdown, protected desktop/UAC, and anti-cheat.

## VLM Assist Contract

v1.0.3.1 keeps the v1.0.3+ normal VLM path on provider-gated real VLM assist. Probe VLM capability once per large task or session with `vlm-capability-probe`, then reuse the cache. Do not probe or call VLM on every step.

If `VLM_AVAILABLE`, Runtime may call `vlm-assist-locate` only for frontend perception/locate failures such as UIA target not found, OCR text without a reliable click region, icon-only targets, custom-drawn UI, image/template low confidence, ambiguous first visible click result, or unclear visual state after keyboard fallback. Runtime validates candidates with `vlm-candidate-validate` before action planning. If `VLM_UNAVAILABLE`, continue Runtime-only visible paths and the normal fallback gate; do not invent a VLM candidate.

VLM is assistive perception, not the controller. It may identify text, icons, regions, bbox/point candidates, uncertainty, and safety flags. It must not click, type, move the mouse, execute commands, choose backend fallback, or bypass SafetyPolicy. Every VLM candidate must be Runtime validated, coordinate-mapped, bound to `screenshot_id` or `frame_id`, and recorded with provider/session/raw/parsed evidence.

VLM does not participate in backend fallback. Once backend fallback starts, do not call VLM. Active protection or security interception is STOP, not a reason to ask VLM for a bypass.

Do not use legacy mock VLM commands for normal Agent work. They are deprecated test-only fixtures and not real VLM success.

v1.0.4 complex IDE workflows must use `RealVlmRuntimeBridge` / the real VLM bridge path, with coordinate mapping, target-window lock, Runtime visible action execution, and post-action verification before any accepted candidate can influence an action.

## Capture/OCR Pipeline Contract

The full-screen capture source-of-truth remains mandatory. `capture-fullscreen-frame` creates a frame-bound `frame_id` and `screenshot_id`; OCR, foreground/window crop OCR, PNG evidence, and VLM transport must derive from that same full-screen frame.

OCR memory-frame-first is required. Normal OCR must not read the evidence PNG as the OCR input path and must report `png_read_for_ocr=false`. OCR results must bind `frame_id` and `screenshot_id`.

PNG evidence must be retained and is saved asynchronously by default. Before failure or BLOCKED, flush evidence with `evidence-flush`; a failed flush is `EVIDENCE_FLUSH_FAILED`, not PASS.

Foreground/window OCR must crop from full-screen frame memory. If crop OCR fails or is insufficient, fallback must use full-screen OCR on the same frame.

OCR cache and tile hash cache are allowed only when cache evidence is validated and the frame/content hash, crop rect, OCR engine/config, and tile hash match the cache policy.

VLM transport is provider-dependent transport. Codex CLI currently needs file path `--image`, so the VLM input image is generated from frame bytes and is not a recaptured screenshot. Memory bytes/base64 VLM transport is future provider capability. Old mock VLM must not be used as a normal path.

## Error Handling Contract

command error, safety denial, ambiguous window, locator failure, verification failure, and fallback discipline violation cannot be reported as PASS.

If final state appears successful but evidence shows a disallowed fallback, report failure. Visible-first path legality is part of the result.

Report the failed command, error_code, whether input was executed, artifacts/report path, and the next minimal repair entry.

Do not broaden title, guess coordinates, click nearby areas, or switch to a backend plan to keep going.

Required failure summary fields:

- failed command or task step
- `error_code`
- input executed: yes/no/unknown
- report path
- artifact paths
- fallback layer reached
- next minimal repair entry
