# Step Contract

Current version: `v5.1.5`.

## v5.8 RC Note

v5.x is an internal engineering stage number for the Task-Level Desktop Execution Runtime. Before public release, a Version Normalization Pass will map this internal stage to a `0.x.x` prerelease version; the first formal public stable release remains `1.0.0`. v5 does not depend on VLM providers and does not claim semantic generalization to unfamiliar screens.

DesktopVisual v5.1 adds Step Contract and Verification Engine support. Each task step can declare preconditions, action intent, verification expectations, timeout, retry policy, failure behavior, safety requirements, expected scene state, expected change events, and expected elements.

## Commands

```powershell
D:\desktopvisual\bin\winagent.exe step-contract-validate --file D:\desktopvisual\tasks\step_contract\valid_local_form_submit.step.json
D:\desktopvisual\bin\winagent.exe step-precondition-check --contract D:\desktopvisual\tasks\step_contract\valid_local_form_submit.step.json --perception D:\desktopvisual\tasks\step_contract\perception_pass.json
D:\desktopvisual\bin\winagent.exe step-verify --contract D:\desktopvisual\tasks\step_contract\valid_local_form_submit.step.json --before D:\desktopvisual\tasks\step_contract\verification_before_submit.json --after D:\desktopvisual\tasks\step_contract\verification_after_success.json --timeout-ms 1000 --elapsed-ms 50
D:\desktopvisual\bin\winagent.exe step-failure-classify --error-code VERIFICATION_TIMEOUT --step-id click_submit_and_verify
```

## Required Fields

```json
{
  "schema_version": "5.1.1",
  "step_id": "click_submit_and_verify",
  "name": "Click mock submit and verify success",
  "preconditions": [
    { "type": "scene_state", "expected": "normal" },
    { "type": "element_exists", "element_id": "submit-button" },
    { "type": "target_ready", "expected": true },
    { "type": "window_focused", "expected": true },
    { "type": "profile_active", "profile": "browser_local" },
    { "type": "safety_allowed", "action": "click_submit_mock" },
    { "type": "capability_available", "capability": "minimal_task_session_runner" }
  ],
  "action": {
    "type": "click_submit_mock",
    "locator": "id:submit-button"
  },
  "verification": {
    "type": "text_appeared",
    "expected_text": "Success: local mock form submitted",
    "expected_scene_state": "success",
    "expected_change_events": ["text_appeared", "target_ready", "region_changed"],
    "expected_elements": [
      {
        "element_id": "result",
        "condition": "appeared"
      }
    ]
  },
  "timeout_ms": 1000,
  "retry_policy": {
    "max_attempts": 1,
    "backoff_ms": 100
  },
  "on_failure": {
    "strategy": "stop_task",
    "failure_reason": "VERIFICATION_TIMEOUT"
  },
  "safety_requirements": {
    "permission_profile": "DEFAULT",
    "allow_unrestricted_desktop": false
  },
  "expected_scene_state": "success",
  "expected_change_events": ["text_appeared", "target_ready", "region_changed"],
  "expected_elements": ["result"]
}
```

## Supported Preconditions

- `scene_state`
- `element_exists`
- `target_ready`
- `window_focused`
- `profile_active`
- `safety_allowed`
- `capability_available`

The precondition checker is contract-field driven: `profile_active.profile`, `capability_available.capability`, `safety_allowed.action`, `scene_state.expected`, and `element_exists.element_id` determine the local perception checks. If an action locator is present and no explicit `element_exists.element_id` is declared, the checker uses the locator id as a compatibility fallback for v5.1 fixtures.

## Supported Verification Checks

- expected ChangeEvent
- expected SceneState
- expected ElementGraph condition
- text appeared
- text disappeared
- element appeared
- element disappeared
- region changed
- timeout handling

v5.1.5 validates these over local mock perception JSON. Expected change events and expected element ids are read from the StepContract instead of a fixed local-form fixture. Live `observe2` integration remains a later runtime integration step.

## Failure Reasons

- `PRECONDITION_FAILED`
- `LOCATOR_NOT_FOUND`
- `TARGET_NOT_READY`
- `ACTION_FAILED`
- `ACTION_NO_EFFECT`
- `VERIFICATION_TIMEOUT`
- `UNEXPECTED_SCENE`
- `SAFETY_DENIED`
- `SEMANTIC_UNRESOLVED`

## Safety Boundary

StepContract commands are read-only checks over local JSON fixtures. They do not click, type, focus windows, browse external web, or call VLM.
