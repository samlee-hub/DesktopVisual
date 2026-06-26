# Human Confirmation

Current version: `v5.3.5`.

## v5.8 RC Note

v5.x is an internal engineering stage number for the Task-Level Desktop Execution Runtime. Before public release, a Version Normalization Pass will map this internal stage to a `0.x.x` prerelease version; the first formal public stable release remains `1.0.0`. v5 does not depend on VLM providers and does not claim semantic generalization to unfamiliar screens.

DesktopVisual v5.3 adds code-level confirmation gates for risk-controlled actions. Real send, submit, delete, overwrite, upload, account, public posting, and payment-like actions cannot be executed by the Runtime or an Agent path without an explicit confirmation result. blocked actions cannot be approved by confirmation.

## Commands

```powershell
D:\desktopvisual\bin\winagent.exe risk-action-classify --action "send email" --permission-profile DEFAULT
D:\desktopvisual\bin\winagent.exe confirmation-request-create --action "send email" --risk-level high --summary "Review mock email before send." --target-window "Local Mail Mock" --screenshot artifacts/dev5.3.2/screenshots/pre_send_review.bmp --files artifacts/dev5.3.2/mock_attachment.txt --destination qa@example.invalid --timeout-ms 30000 --allowed-responses confirm,reject
D:\desktopvisual\bin\winagent.exe confirmation-gate-check --action "send email" --response confirm --timeout-ms 30000 --elapsed-ms 0
D:\desktopvisual\bin\winagent.exe confirmation-flow-run --file D:\desktopvisual\tasks\confirmation\local_mail_mock_send_confirm.json --response confirm
```

## Risk Levels

- `low`: local read-only or non-destructive local operation.
- `medium`: local operation with external navigation, clipboard, or app-launch implications.
- `high`: action requires human confirmation before execution.
- `blocked`: action is terminal and cannot be approved by confirmation.

High-risk actions include:

- send email
- submit external form
- delete file
- overwrite file
- external upload
- external download
- account setting change
- public posting
- payment-like action

Blocked actions include captcha, anti-cheat, proctoring, credential/security challenge, and public-release assessment/exam/hiring/certification/rated-contest submission restrictions.

## ConfirmationRequest

`confirmation-request-create` emits and writes:

- `action`
- `risk_level`
- `summary`
- `target_window`
- `screenshot`
- `involved_files`
- `destination`
- `timeout_ms`
- `allowed_responses`
- `audit_id`
- `request_json`
- `report_md`

The request is pending evidence only. It is not an approval.

## Confirmation Gate

`confirmation-gate-check` enforces:

| condition | decision |
|---|---|
| high risk without confirmation | `blocked` |
| high risk with `confirm` | `allowed` |
| high risk with `reject` | `stopped` |
| high risk timeout | `stopped` |
| blocked action with any response | `stopped` |
| public profile high risk without confirmation | `blocked` |

The gate returns a local decision. It does not execute the action.

## Local Mock Flow

`confirmation-flow-run` currently supports only `local_mail_mock_send_confirm`. It composes local mock metadata, creates a confirmation request, checks the gate, writes confirmation audit, records `mock_sent`, and never sends real email.

## Permission Modes

`D:\desktopvisual` is a local development tree. High-risk actions can be modeled with confirmation artifacts for local mock fixtures. Public release trees must use stricter permission profiles: assessment/exam/hiring/certification/rated-contest submissions and blocked safety categories must stop, not request confirmation.
