# Task Templates v2

Current version: `v5.4.6`.

## v5.8 RC Note

v5.x is an internal engineering stage number for the Task-Level Desktop Execution Runtime. Before public release, a Version Normalization Pass will map this internal stage to a `0.x.x` prerelease version; the first formal public stable release remains `1.0.0`. v5 does not depend on VLM providers and does not claim semantic generalization to unfamiliar screens.

Task Template v2 makes v5 tasks profile-bound instead of hard-coded flows. A `TaskTemplateV2` declares parameters, states, steps, preconditions, verification, recovery, confirmation nodes, and final-state policy. The `TaskTemplateResolver` binds those declarations to an App Profile before any runtime action is attempted.

## Commands

```powershell
D:\desktopvisual\bin\winagent.exe task-template-v2-validate --file D:\desktopvisual\tasks\templates_v2\local_form_fill_submit.task-template-v2.json
D:\desktopvisual\bin\winagent.exe task-template-v2-resolve --task D:\desktopvisual\samples\tasks\local_form_fill_submit_v2.task.json
D:\desktopvisual\bin\winagent.exe task-template-v2-resolve --template D:\desktopvisual\tasks\templates_v2\local_mail_mock_compose_attach_no_real_send.task-template-v2.json --profile local_mail_mock --params-file D:\desktopvisual\samples\tasks\local_mail_mock_compose_attach_no_real_send.params.json
```

`task-template-v2-validate` performs schema checks only. `task-template-v2-resolve` validates parameters, loads the required App Profile, and emits resolved step metadata. It does not execute clicks, typing, OCR, browser navigation, file operations, VLM calls, or Agent planning.

## Core Objects

`TaskTemplateV2` required fields:

```json
{
  "schema_version": "5.4.1",
  "runtime_version": "5.8.7",
  "protocol_version": "5.4",
  "template_id": "local_form_fill_submit",
  "required_profile": "browser_local",
  "parameters": [],
  "states": [],
  "steps": [],
  "preconditions": [],
  "verification": {},
  "recovery": {},
  "confirmation_nodes": [],
  "final_state_policy": {
    "success_state": "completed",
    "failure_state": "failed",
    "blocked_state": "blocked",
    "profile_can_override_safety": false
  },
  "allow_unrestricted_desktop": false
}
```

`ProfileBoundLocator` maps a step `locator_ref` to `profile.common_locators`. Missing locators fail with `PROFILE_BINDING_MISSING_LOCATOR`.

`ProfileBoundVerification` maps template verification to profile ROI metadata and strategy fields. `roi_ref` and `output_region` values must exist in `profile.roi_definitions`.

`TaskParameter` records explicit task inputs. v5.4 validates required values, supported parameter types, local URL parameters, local path parameters, and ROI names. Supported parameter types are `string`, `path`, `local_url`, and `roi`. Missing required values fail with `TASK_PARAMETER_MISSING`; unsafe paths fail with `TASK_PARAMETER_PATH_INVALID`.

`TaskTemplateResolver` binds `profile.common_locators`, `profile.roi_definitions`, `profile.visual_strategy`, `profile.recovery_strategy`, and `profile.confirmation_nodes`. The resolved JSON always reports `can_override_safety_manifest=false` and `resolver_executes_actions=false`.

## Built-in Local Templates

- `local_form_fill_submit`
- `local_problem_page_run_read`
- `local_mail_mock_compose_attach_no_real_send`
- `notepad_edit_verify`
- `explorer_file_select_mock`

These templates are deterministic local fixtures or local-app adapters. They are not real web, real account, payment, credential, public assessment, or unrestricted desktop automation templates.

## Safety

Profiles are metadata adapters only. They can provide known locators, ROI names, visual preference order, recovery strategy labels, and confirmation nodes, but they cannot relax Safety Manifest, PermissionManager, confirmation gate, read/write root, or action policy checks.

Task Template v2 rejects fixed-coordinate template markers and requires profile-bound locators or profile-bound ROI verification for local workflows. It does not fall back to arbitrary coordinates when binding fails.
