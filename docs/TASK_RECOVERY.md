# Task Recovery Runtime

Current version: `v5.2.5`.

## v5.8 RC Note

v5.x is an internal engineering stage number for the Task-Level Desktop Execution Runtime. Before public release, a Version Normalization Pass will map this internal stage to a `0.x.x` prerelease version; the first formal public stable release remains `1.0.0`. v5 does not depend on VLM providers and does not claim semantic generalization to unfamiliar screens.

DesktopVisual v5.2 adds a task-level recovery and escalation layer over the v5.0 TaskSession core and v5.1 StepContract verification checks. The runtime does not blindly continue after a failed step. It classifies whether a failure can be retried, requires re-observation, requires escalation, or must stop.

v5.2 does not call VLM/Agent providers. Escalation commands create structured local requests only.

## Commands

```powershell
D:\desktopvisual\bin\winagent.exe recovery-policy-validate --file D:\desktopvisual\tasks\recovery_policy\valid_standard_recovery_policy.json
D:\desktopvisual\bin\winagent.exe recovery-evaluate --policy D:\desktopvisual\tasks\recovery_policy\valid_standard_recovery_policy.json --failure-reason TARGET_NOT_READY --context D:\desktopvisual\tasks\recovery_policy\delayed_button_not_ready.json --attempt 1
D:\desktopvisual\bin\winagent.exe escalation-request-create --reason semantic_unresolved --task local_form_fill_submit_mock --step click_submit_and_verify --context D:\desktopvisual\tasks\recovery_policy\escalation_semantic_unresolved.json
D:\desktopvisual\bin\winagent.exe safe-stop-check --reason captcha --context D:\desktopvisual\tasks\recovery_policy\blocked_scene_captcha.json
```

## Recovery Policy

RecoveryPolicy supports these strategies:

- `re_observe`
- `re_locate`
- `wait_and_retry`
- `invalidate_cache`
- `use_profile_fallback`
- `use_visual_provider`
- `ask_user`
- `escalate_to_agent`
- `stop`

The v5.2.1 validator checks schema version, policy id, task type, permission profile, retry budget, route count, strategy names, failure reasons, and audit settings. `retry_budget` includes `max_attempts`, `max_total_recovery_ms`, and `backoff_ms`; `max_wait_ms` remains accepted as a compatibility alias for older v5.2 fixtures. It is read-only.

## Recovery Matrix

| failure reason | strategy | automatic | next action |
|---|---|---:|---|
| `TARGET_NOT_READY` | `wait_and_retry` | yes | bounded wait |
| `TEXT_NOT_FOUND` | `re_observe` | yes | re-observe state |
| `LOCATOR_NOT_FOUND` | `re_locate` | yes | re-run locator |
| `STALE_CANDIDATE` | `invalidate_cache` | yes | invalidate perception cache, then re-observe/re-locate |
| `PROFILE_MISMATCH` | `use_profile_fallback` | no | future profile fallback route |
| `MULTIPLE_CANDIDATES_LOW_CONFIDENCE` | `use_visual_provider` | no | create escalation or stop |
| `UNKNOWN_SCENE` | `ask_user` | no | ask user or stop |
| `SEMANTIC_UNRESOLVED` | `escalate_to_agent` | no runtime call | create EscalationRequest when provider is available, otherwise ask user or stop |
| `SAFETY_DENIED` | `stop` | no | stop |

## Escalation Request

`escalation-request-create` emits:

- `reason`
- `current_task`
- `current_step`
- `scene_state`
- `candidates`
- `candidate_count`
- `screenshot_artifact`
- `element_graph_artifact`
- `risk_level`
- `allowed_routes`
- `recommended_action`
- `fallback_if_provider_unavailable`
- `llm_or_vlm_call_count`

The command records candidate count and artifact paths from a local context JSON file. It does not upload artifacts or call providers.

## Safety Stop Matrix

| condition | recovery | escalation | action |
|---|---:|---:|---|
| captcha | no | no | stop |
| anti-cheat | no | no | stop |
| proctoring | no | no | stop |
| payment | no | no | stop |
| credential/security challenge | no | no | stop |
| game automation | no | no | stop |
| real exam/hiring assessment submission in public profile | no | no | stop |
| `SAFETY_DENIED` | no | no | stop |

SafeStop is terminal. It must not be routed to Agent/VLM as a bypass.

## Artifacts

Recovery decisions include audit-oriented records such as `recovery_attempt_id`, `failure_reason`, `strategy`, `next_action`, `safe_to_retry`, `max_total_recovery_ms`, and configured `artifact_dir`. v5.2 selftests write evidence under:

```text
D:\desktopvisual\artifacts\dev5.2.1
D:\desktopvisual\artifacts\dev5.2.2
D:\desktopvisual\artifacts\dev5.2.3
D:\desktopvisual\artifacts\dev5.2.4
```

## Limits

- v5.2 recovery commands operate on local JSON fixtures and structured context files.
- v5.2 does not perform live desktop retry, live `observe2`, provider calls, or human confirmation UI.
- High-risk contexts stop immediately and cannot be converted into escalation routes.
