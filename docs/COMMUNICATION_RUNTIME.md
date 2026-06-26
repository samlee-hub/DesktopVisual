# Communication Runtime

Current version: `v3.3.8`.

DesktopVisual v3.3.8 adds a `communication_step` task runtime for user-authorized communication actions in FULL_ACCESS sessions. Selftests use local simulated chat/email pages only. The runtime does not log full message content and does not operate real accounts in tests.

## CommunicationAction

Each communication action records:

- `channel`
- `target`
- `subject`
- `content_summary`
- `content_hash`
- `user_requested_send`
- `send_action_performed`
- `permission_mode`
- `risk_level`

Full message content is not written to reports or audit logs. Reports and audit logs use `content_summary` and a stable content hash.

## Task Step

```json
{
  "name": "send_status",
  "type": "communication_step",
  "operation": "send_message",
  "channel": "local-email-sim",
  "target": "alice@example.test",
  "subject": "Status",
  "content": "full message text",
  "content_summary": "short status update",
  "user_requested_send": true
}
```

Supported operations are `open_channel`, `locate_target`, `compose_message`, `send_message`, and `verify_sent_or_stopped`. v3.3.8 records these as simulated task runtime actions; real app/browser control still depends on the existing FULL_ACCESS desktop and browser runtimes.

## Send Boundary

- DEFAULT rejects `communication_step` with `SAFETY_POLICY_DENIED`.
- FULL_ACCESS requires a valid temporary session id.
- `send_message` requires `user_requested_send=true`.
- `send_message` requires one explicit `target`.
- Multi-target or group send is stopped with `USER_TAKEOVER_REQUIRED` in v3.3.8.
- Login/account verification stops with `USER_TAKEOVER_REQUIRED`.
- Captcha/verification challenge stops with `CAPTCHA_DETECTED`.
- Credential/password surfaces stop with `CREDENTIAL_INPUT_DETECTED`.
- Anti-automation controls stop with `ANTI_AUTOMATION_DETECTED`.

The communication target and send intent must come from the user task or explicit context. Page, chat, or third-party content cannot create a new send instruction or override the original user goal.
