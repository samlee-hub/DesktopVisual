# Error Codes

Current version: `v4.7.0`.

Protocol status: frozen-compatible through v4.7.0.

WinDesktopAgent v0.1.6 froze the original stable error codes in command JSON, audit logs, and case reports. v0.3.x adds UI Automation, OCR, and image-location error codes without changing the v0.1.x codes. v0.4.1 adds safety boundary error codes as compatible stop conditions. v1.0.1 adds `WINDOW_FOCUS_FAILED` as a compatible stop condition for real input focus verification. v1.4.0 adds selector locator stop codes for unified `locate` and `act`. v2.0.0 adds real OCR runtime/language availability errors. v3.0.1 adds Operator Motion Profile errors as compatible explicit stop conditions. v3.0.1a adds explicit source and test-profile stop codes. v3.3.1 adds permission profile and immutable FULL_ACCESS stop codes. v3.3.2 adds local interactive FULL_ACCESS confirmation refusal. v3.3.3 adds global desktop launch targeting and loop guard stop codes. v3.3.4 adds browser URL loop/no-progress/repeated-action stop codes. v3.3.5 adds form field uniqueness and confidence stop codes. v3.3.6 reuses existing stop codes for the General Decision Task Runtime. v3.3.7 adds `SCROLL_NO_PROGRESS` and makes TaskRunner emit loop guard stops with existing `WINDOW_SPAWN_LOOP`, `URL_REDIRECT_LOOP`, `NO_PROGRESS_DETECTED`, `REPEATED_ACTION_LIMIT`, and `LOOP_GUARD_STOP`. v3.3.8 reuses existing permission and safety stop codes for communication actions. v3.4.0 adds `TEXT_NOT_FOUND` as the normalized TaskRunner recovery category for missing expected text. v4.1.0 adds `ACTION_BLOCKED_SEMANTIC_UNRESOLVED` for unresolved visual-only LocatorCandidates. v4.5.0 adds `PROFILE_LOCATOR_NOT_FOUND` for missing App Profile common locators. v4.7.0 adds no new error codes and keeps the v4 stop-code surface stable for the release candidate.

| Code | Meaning | Used By |
|---|---|---|
| `WINDOW_NOT_FOUND` | The requested target window was not found. | `find`, `screenshot`, `click`, `press`, `type`, `run-case` |
| `WINDOW_NOT_UNIQUE` | The requested target title matched multiple visible top-level windows. | `find`, `screenshot`, `click`, `press`, `type`, `run-case` |
| `WINDOW_NOT_VISIBLE` | A launched target did not expose a visible matching top-level window. | `launch-app` |
| `WINDOW_FOCUS_FAILED` | The target window could not be made foreground before real input. | `click`, `press`, `type`, UIA fallback input, `click-text`, `click-image`, `run-case` |
| `INVALID_ARGUMENT` | A command or case step argument was missing, unsupported, or outside allowed bounds. | All argument-taking commands and case steps |
| `INVALID_SELECTOR` | A selector string was malformed, used an unknown selector type, or omitted required selector fields. | `locate`, `act`, selector case steps |
| `LOCATOR_NOT_FOUND` | A valid selector resolved to zero matches. | `locate`, `act`, selector case steps |
| `LOCATOR_NOT_UNIQUE` | A valid selector resolved to multiple matches where one unique target was required. | `locate`, `act`, selector case steps |
| `PROFILE_LOCATOR_NOT_FOUND` | A requested App Profile or common locator was missing or invalid. | `locate --profile --profile-locator` |
| `SCREENSHOT_FAILED` | Window screenshot capture or BMP write failed. | `screenshot`, `run-case` |
| `CURSOR_MOVE_FAILED` | The system cursor could not be moved or read. | `click`, `run-case` |
| `SEND_INPUT_FAILED` | `SendInput` failed or sent fewer events than requested. | `click`, `press`, `type`, `run-case` |
| `FILE_NOT_FOUND` | The requested file path does not exist or points to a directory. | `read-file`, `run-case` |
| `FILE_READ_FAILED` | The requested file could not be opened or read. | `read-file`, `run-case` |
| `ASSERTION_FAILED` | A case assertion failed. | `run-case` |
| `CASE_PARSE_FAILED` | A case file or case step could not be parsed. | `run-case` |
| `CASE_STEP_LIMIT_EXCEEDED` | A case exceeded the 100-step execution limit. | `run-case` |
| `SAFETY_POLICY_DENIED` | The target title or process is not allowed by `D:\desktopvisual\config\safety.conf`, or a required safety boundary was not satisfied. | `click`, `press`, `type`, `uia-click`, `uia-type`, `click-text`, `click-image`, `run-case` |
| `FULL_ACCESS_SESSION_REQUIRED` | FULL_ACCESS was requested without a valid active temporary session id. | `policy-check`, `run-task`, service `/policy-check`, service `/run-task` |
| `FULL_ACCESS_REQUIRES_INTERACTIVE_CONFIRMATION` | FULL_ACCESS unlock was attempted outside a local interactive CLI confirmation flow. | `unlock-full-access` |
| `USER_TAKEOVER_REQUIRED` | The runtime requires human takeover before continuing. | `policy-check`, `run-task` |
| `CREDENTIAL_INPUT_DETECTED` | Credential, password, or secret input was detected. | `policy-check`, `run-task` |
| `CAPTCHA_DETECTED` | Captcha or verification challenge was detected. | `policy-check`, `run-task` |
| `ANTI_AUTOMATION_DETECTED` | Anti-automation or AI-detection control was detected. | `policy-check`, `run-task` |
| `ANTI_CHEAT_DETECTED` | Anti-cheat protected software was detected. | `policy-check`, `run-task` |
| `PROTECTED_DESKTOP_DETECTED` | UAC, protected desktop, or protected system surface was detected. | `launch-app` |
| `LOOP_GUARD_STOP` | Loop guard stopped a repeated or no-progress action. | `policy-check`, `run-task` |
| `WINDOW_SPAWN_LOOP` | Repeated app launch or abnormal window spawning was detected. | `launch-app` |
| `URL_REDIRECT_LOOP` | Repeated URL redirect or repeated navigation to the same URL was detected. | `browser-nav` |
| `NO_PROGRESS_DETECTED` | A browser or task workflow made no observable progress within its guard threshold. | `browser-nav`, future browser workflows |
| `REPEATED_ACTION_LIMIT` | The same browser or task action repeated without state change beyond its guard threshold. | `browser-nav`, future browser workflows |
| `SCROLL_NO_PROGRESS` | Repeated scroll actions did not reveal new content. | `run-task` |
| `FIELD_NOT_UNIQUE` | A form-control query matched multiple candidate fields. | `form-control`, `run-task` `form_action`, `decision-eval`, `run-task` `decision` |
| `FIELD_CONFIDENCE_LOW` | A form-control query resolved an unknown or low-confidence field. | `form-control`, `run-task` `form_action`, `decision-eval`, `run-task` `decision` |
| `ACTION_BLOCKED_SEMANTIC_UNRESOLVED` | A visual-only LocatorCandidate did not have enough semantic support to execute. | `act` with `visual:` selectors |
| `TEXT_NOT_FOUND` | Expected or requested text was not found after observe/OCR text checks. | `run-task`, Recovery Strategy Engine |
| `EMERGENCY_STOP` | The configured emergency stop key was pressed before or during an input action. | `click`, `press`, `type`, `run-case` |
| `CASE_DURATION_LIMIT_EXCEEDED` | A case exceeded the configured `max_duration_ms` safety limit. | `run-case` |
| `UIA_INIT_FAILED` | Windows UI Automation COM initialization or object creation failed. | `uia-tree`, `uia-find`, `uia-click`, `uia-type` |
| `UIA_TREE_FAILED` | Reading the Windows UI Automation element tree failed. | `uia-tree`, `uia-find`, `uia-click`, `uia-type` |
| `UIA_ELEMENT_NOT_FOUND` | No UI Automation element matched the requested name. | `uia-find`, `uia-click`, `uia-type` |
| `UIA_ELEMENT_NOT_UNIQUE` | The requested UI Automation element name matched multiple elements. | `uia-find`, `uia-click`, `uia-type` |
| `OCR_INIT_FAILED` | Windows native OCR initialization failed. | `find-text`, `click-text` |
| `OCR_UNAVAILABLE` | OCR is not available in the current build or environment. | `find-text`, `click-text`, `locate`, `act` with `text:` selectors |
| `OCR_LANGUAGE_UNAVAILABLE` | Windows OCR is present but no usable OCR language is available for the current user profile. | `read-window-text`, `read-region-text`, `find-text`, `click-text`, `wait-text`, `assert-text-contains`, `text:` selectors |
| `OCR_TEXT_NOT_FOUND` | OCR ran but did not find the requested text. | `find-text`, `click-text` |
| `OCR_TEXT_NOT_UNIQUE` | OCR found multiple matches for the requested text. | `find-text`, `click-text` |
| `OCR_FAILED` | OCR or OCR coordinate conversion failed. | `find-text`, `click-text` |
| `IMAGE_FILE_NOT_FOUND` | The template image file was not found or could not be opened. | `find-image`, `click-image` |
| `IMAGE_UNSUPPORTED_FORMAT` | The image file is not an uncompressed 24-bit or 32-bit BMP. | `find-image`, `click-image` |
| `IMAGE_MATCH_NOT_FOUND` | No image template match was found. | `find-image`, `click-image` |
| `IMAGE_MATCH_NOT_UNIQUE` | The image template matched multiple locations. | `find-image`, `click-image` |
| `IMAGE_MATCH_FAILED` | Image template matching failed or exceeded supported limits. | `find-image`, `click-image` |
| `MOTION_PROFILE_NOT_FOUND` | `operator-human` was requested but the configured profile does not exist. | `click`, `double-click`, `right-click`, `scroll`, `drag`, `click-text`, `click-image`, `act`, `run-task`, `motion-profile-info` |
| `MOTION_PROFILE_INVALID` | A motion profile or raw motion sample could not be parsed or validated. | `motion-calibrate`, `motion-profile-info`, `motion-profile-validate`, `operator-human` input actions |
| `MOTION_PROFILE_NOT_HUMAN` | `operator-human` loaded a profile whose `source` is not `human` for default operator use. | `click`, `double-click`, `right-click`, `scroll`, `drag`, `click-text`, `click-image`, `act`, `run-task` |
| `MOTION_PROFILE_SOURCE_REQUIRED` | `motion-calibrate` or profile loading found no required `source` value. | `motion-calibrate`, `motion-profile-info`, `motion-profile-validate`, `operator-human` input actions |
| `MOTION_PROFILE_TEST_ONLY` | A `synthetic` or `sample` profile was requested without explicit test authorization. | `click`, `double-click`, `right-click`, `scroll`, `drag`, `click-text`, `click-image`, `act`, `run-task` |
| `MOTION_PROFILE_INSUFFICIENT_SAMPLES` | Calibration found fewer than 12 valid raw samples. | `motion-calibrate` |
| `EMERGENCY_STOPPED` | F12 stopped a recording or calibration-related long-running motion command before completion. | `motion-record` |
| `AUDIT_LOG_FAILED` | An audit log line could not be written. | Unified command emit path |
| `UNKNOWN_ERROR` | An unexpected error occurred. | Any command when no more specific frozen code applies |

## Failure JSON Shape

Commands that fail through the unified envelope include:

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

## Skill Guidance

Codex Skill integration should treat any non-empty `error.code` as a stop condition. A Skill must explain the failure and preserve the report/artifacts instead of retrying arbitrary clicks or typing.

Safety and permission failures are also stop conditions. `SAFETY_POLICY_DENIED`, `FULL_ACCESS_SESSION_REQUIRED`, `FULL_ACCESS_REQUIRES_INTERACTIVE_CONFIRMATION`, `USER_TAKEOVER_REQUIRED`, `CREDENTIAL_INPUT_DETECTED`, `PROTECTED_DESKTOP_DETECTED`, `CAPTCHA_DETECTED`, `ANTI_AUTOMATION_DETECTED`, `ANTI_CHEAT_DETECTED`, `LOOP_GUARD_STOP`, `WINDOW_SPAWN_LOOP`, `URL_REDIRECT_LOOP`, `NO_PROGRESS_DETECTED`, `REPEATED_ACTION_LIMIT`, `SCROLL_NO_PROGRESS`, `EMERGENCY_STOP`, `EMERGENCY_STOPPED`, `CASE_DURATION_LIMIT_EXCEEDED`, and Motion Profile errors must not be auto-recovered by broadening target windows, switching to absolute clicks, or continuing input.
