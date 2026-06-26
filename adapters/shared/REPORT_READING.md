# DesktopVisual Adapter Report Reading

Agents must read generated Markdown reports after `run-task` and `run-case`.

Default report reading uses compact progress with full evidence retained in artifacts: `report_level=compact`, `evidence_level=full`, `progress_output=compact`, `step_chat_detail=compact`, and `artifact_evidence=full`. compact output must not hide failures; failed reports require the error, evidence, and next repair. Use read-once context with `agent_context_digest.md`, do not repeatedly reread full documents as a default workflow, and do not scan artifacts, `.git`, `bin`, or `obj` unless a verifier explicitly requires that path.

Minimum report summary:

- result: PASS, FAIL, or SKIPPED when a wrapper emits SKIPPED
- task or case name
- failed step index when present
- `error_code`
- report path
- screenshot or artifact paths
- locator method used when known
- recovery attempts and whether recovery succeeded
- visible-first evidence including `runtime_visible_first_launch`, `launch_strategy`, `desktop_surface_attempted`, `start_menu_fallback_attempted`, `backend_launch_used`, `bounded_recovery_attempted`, and `target_window_verified` when a launch was performed
- VLM evidence when present: `vlm_assist_enabled`, `vlm_capability_status`, `vlm_session_id`, `vlm_assist_attempted`, `vlm_assist_stage`, `vlm_candidate_accepted`, `vlm_candidate_rejected_reason`, `vlm_action_executed`, `vlm_after_backend_attempted`, `fallback_stage_before_vlm`, and `fallback_stage_after_vlm`
- Capture/OCR evidence when present: `frame_id`, `screenshot_id`, OCR memory-frame-first source, `png_read_for_ocr=false`, PNG evidence retained, async evidence status, flush evidence, foreground/window crop from full-screen frame, fallback same frame, OCR cache/tile cache evidence, and VLM provider-dependent transport fields.

Safety stop rules apply after reading the report. A report failure is not permission to keep clicking.

Use `observe-locate-act-verify` for follow-up verification. No unrestricted desktop control and no sensitive flows are allowed.

Errors and policy violations must be reported as failure or BLOCKED, not PASS. If final state appears successful but evidence shows a disallowed fallback, report failure.

Active protection or security interception is STOP, not fallback.

For v1.0.3.1 VLM assist, confirm the normal VLM path is `vlm-capability-probe`, `vlm-assist-locate`, and `vlm-candidate-validate`. VLM is assistive only: `vlm_action_executed` must be false, locate commands must keep `runtime_action_executed=false`, `vlm_after_backend_attempted` must be false, and any candidate used by Runtime must have screenshot/frame/provider/session/raw/parsed evidence plus Runtime validation. Legacy mock VLM commands are deprecated test-only fixtures and are not recommended Agent workflows.

For v1.0.3.1+ VLM command JSON, read command-specific root fields first and treat `data` / `evidence` as a compatibility mirror, not a replacement schema. This is the VLM `data/evidence` mirror rule. `vlm-capability-probe`, `vlm-assist-locate`, and `vlm-candidate-validate` include root fields such as `provider`, `capability_status`, `vlm_status`, `candidate_accepted`, `validation_result`, and `runtime_validation_passed`; the same critical values may also be mirrored under `data`, while artifacts, raw/parsed response paths, rejection reasons, and provider status are mirrored under `evidence`. Do not classify natural-language provider text as success, and do not treat a rejected candidate as an executed action.

For v1.0.5 capture/OCR reports, confirm full-screen frame source-of-truth, OCR memory-frame-first, PNG evidence retained, async evidence and failure/BLOCKED flush, foreground/window crop from full-screen frame, same frame fallback, OCR result `frame_id`/`screenshot_id` binding, and VLM input image from frame. Codex CLI VLM currently needs file path `--image`; memory bytes are future provider capability, and old mock VLM is not normal path evidence.
