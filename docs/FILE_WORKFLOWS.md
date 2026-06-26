# File Workflows

Current version: `v5.5.6`.

## v5.8 RC Note

v5.x is an internal engineering stage number for the Task-Level Desktop Execution Runtime. Before public release, a Version Normalization Pass will map this internal stage to a `0.x.x` prerelease version; the first formal public stable release remains `1.0.0`. v5 does not depend on VLM providers and does not claim semantic generalization to unfamiliar screens.

DesktopVisual v5.5 adds a controlled local file and attachment workflow layer. It supports mock file picker flows, local attachment state verification, and cross-window context checks. It does not send real email, upload to real accounts, or allow arbitrary sensitive paths.

## Commands

```powershell
D:\desktopvisual\bin\winagent.exe file-path-resolve --path D:\desktopvisual\artifacts\dev5.5.1\allowed\mock_attachment.txt --allowed-roots D:\desktopvisual\artifacts\dev5.5.1\allowed --extensions .txt,.md --max-bytes 4096
D:\desktopvisual\bin\winagent.exe file-picker-flow --file D:\desktopvisual\tasks\file_workflows\local_mock_file_picker_success.json
D:\desktopvisual\bin\winagent.exe attachment-verify --file D:\desktopvisual\tasks\file_workflows\local_mail_mock_upload_success.json --expected-file mock_attachment.txt --timeout-ms 3000 --elapsed-ms 800
D:\desktopvisual\bin\winagent.exe cross-window-check --file D:\desktopvisual\tasks\file_workflows\cross_window_success.json
D:\desktopvisual\bin\winagent.exe local-mail-attach-flow --file D:\desktopvisual\samples\tasks\local_mail_mock_attach_v55.task.json
```

## Core Objects

`FilePathResolver` validates local file paths before they can be used by an attachment workflow. It supports absolute paths, allowed roots, existence checks, file size checks, extension policy, traversal rejection, and metadata-only audit.

`FilePathResolver` is default-deny: every call must provide explicit allowed roots. v5.5 does not silently allow user directories, project directories, or attachment paths.

`FilePickerFlow` models the controlled system picker path: detect file picker window, input file path, confirm Open, and verify the picker closed or the target app changed. v5.5 uses local mock fixtures for this flow.

`AttachmentState` records local upload UI state: file name visible, upload started, spinner/progress detected, spinner gone, upload completed, upload failed, file too large, and retry shown.

`UploadVerification` evaluates an `AttachmentState` fixture against an expected file name and timeout budget.

`CrossWindowTaskContext` records parent task window, child dialog window, return-to-parent state, foreground verification, `window_changed` event, and focus restore.

`FileActionRisk` classifies file action metadata. v5.5 treats small allowed `.txt`, `.md`, and `.json` files as low risk. Other allowed files are medium risk and still require downstream policy checks.

## Safety

- Allowed roots must be explicit.
- File workflows audit metadata only: resolved path, file name, extension, size, allowed-root status, and risk. They do not read or emit file contents.
- Path traversal is rejected.
- Paths outside allowed roots are rejected.
- Dangerous or oversized files are rejected by extension and size policy.
- File picker support is preferred over drag/drop.
- Local mail mock attachment flows never send real email.
- v5.5 file picker and attachment upload checks are local mock/fixture workflows, not product-grade arbitrary file picker automation or real external upload support.
- Real external upload, real mail clients, credentials, payment, public assessment submission, and sensitive file exfiltration remain blocked unless a future reviewed policy explicitly supports them.
