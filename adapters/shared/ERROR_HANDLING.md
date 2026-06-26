# DesktopVisual Adapter Error Handling

Adapters must parse the JSON envelope from `winagent.exe` and preserve reports.

Unified handling:

1. If `ok=false`, read `error.code` or `error_code`.
2. If a report was produced, read the report before deciding any next step.
3. Summarize the failed command, failed step, `error_code`, report path, artifacts, and recommended user action.
4. Apply safety stop rules before retrying.
5. Errors and policy violations must be reported as failure or BLOCKED, not PASS.

Expected stop codes include:

- `SAFETY_POLICY_DENIED`
- `WINDOW_NOT_FOUND`
- `WINDOW_NOT_UNIQUE`
- `LOCATOR_NOT_FOUND`
- `LOCATOR_NOT_UNIQUE`
- `ASSERTION_FAILED`
- `EMERGENCY_STOP`
- `OCR_UNAVAILABLE`
- `OCR_LANGUAGE_UNAVAILABLE`
- `MOTION_PROFILE_NOT_FOUND`
- `MOTION_PROFILE_INVALID`
- `MOTION_PROFILE_NOT_HUMAN`
- `MOTION_PROFILE_TEST_ONLY`

Limited recovery is only the configured Recovery Strategy Engine declared by `run-task`: re-observe, OCR fallback, target-window re-resolution/activation, wait and re-observe, or explicit stop. Do not retry `SAFETY_POLICY_DENIED`, auto-pick after `LOCATOR_NOT_UNIQUE`, or use unrestricted desktop control after recovery fails.

Use `observe-locate-act-verify`; do not enter sensitive flows.

Fallback discipline violations are failures even when the final state looks correct. One failure cannot directly move to fallback. Entering fallback requires two bounded visible attempts or strict surface-impossible evidence, and entering backend fallback requires visible path failure plus keyboard fallback failure.

Active protection or security interception is STOP, not fallback.

Public permission alignment: `PUBLIC_DEFAULT` allows ordinary visible desktop operations, third-party app workflows, browser/https, localhost, Explorer/file manager, local file open, cross-window visible workflow, global desktop visible workflow, and validated absolute screen coordinate action. It still stops on real exam/proctoring/lockdown browser, CAPTCHA/human verification, bot challenge, automation detected, script detected, credential/security handoff, UAC/protected desktop, and anti-cheat mechanisms. Broad content words alone are not errors.

VLM assist errors are not PASS evidence. If `VLM_UNAVAILABLE`, `VLM_TIMEOUT`, `VLM_INVALID_RESPONSE`, or `VLM_CANDIDATE_REJECTED` appears, do not invent a candidate and do not jump directly to backend. Continue Runtime-only visible fallback discipline. If evidence shows `vlm_action_executed=true`, `runtime_action_executed=true` from a locate command, or `vlm_after_backend_attempted=true`, report failure/BLOCKED. Active protection in VLM safety flags is STOP, not a prompt to bypass. Legacy mock VLM errors such as `LEGACY_MOCK_VLM_DEPRECATED` are expected quarantine failures for normal Agent work; use the normal path `vlm-capability-probe`, `vlm-assist-locate`, and `vlm-candidate-validate`.

Capture/OCR errors in v1.0.5 must preserve the frame/evidence chain. OCR is memory-frame-first and must not silently fall back to reading evidence PNG as the normal path. Before reporting failure or BLOCKED, flush evidence for the relevant frame; if flush fails, report `EVIDENCE_FLUSH_FAILED`. Foreground/window OCR fallback must use full-screen OCR on the same frame. VLM provider-dependent transport errors must preserve frame-bound input evidence; Codex CLI currently needs file path transport, and old mock VLM is not a normal recovery path.
