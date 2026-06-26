# Developer Tool Dogfood

Current version: `v4.7.0`.

DesktopVisual v3.6.0 uses `dogfood_matrix.ps1` as a bounded evidence harness for real local developer-tool scenarios. It is not a general desktop-control benchmark.

## Tasks

| Task | Safety Boundary | Expected Result | SKIPPED Condition |
|---|---|---|---|
| Notepad | Clean Notepad process and generated file under `artifacts\dogfood\notepad`. | Type and save a generated marker, then verify file content. | Existing Notepad process or clean target unavailable. |
| Calculator | Normal-user Calculator, skipped if a Calculator window already exists. | Compute `12+30` and verify `42` through OCR or UIA. | Missing Calculator or unverifiable localized UI. |
| Explorer | Explorer opened only in `artifacts\dogfood\explorer\explorer_work`. | Create a generated folder and verify it in the artifacts directory. | Explorer target window or shell shortcut unavailable. |
| Local HTML | Generated local HTML fixture under `artifacts\dogfood\local_html`. | Classify textbox, radio, checkbox, dropdown, textarea, and button controls. | `form-control` or local fixture parsing unavailable. |
| PowerShell | Local non-admin read-only/test output under `artifacts\dogfood\powershell`. | Verify generated output through `winagent read-file`. | PowerShell execution or read-file allowlist unavailable. |
| VS Code | Generated file and isolated user-data dir under `artifacts\dogfood\vscode`. | Append text and verify saved file content. | VS Code missing, existing user Code process, or editor focus unavailable. |

## Reports

`dogfood_matrix.ps1` writes:

- `artifacts\dogfood\dogfood_report.md`
- `artifacts\dogfood\dogfood_summary.json`
- `artifacts\dogfood_matrix_report.md` as a compatibility copy

Each task report records `task_id`, `status`, `safety_boundary`, `expected_result`, `skipped_condition`, `reason`, `steps`, `duration_ms`, `locators`, `screenshots`, and `report_path`.

## Boundaries

Dogfood tasks must not use external web, real accounts, browser profiles, payments, passwords, captcha, social apps, games, anti-cheat, UAC, administrator windows, or arbitrary user files. They must skip pre-existing user app sessions instead of closing or typing into them.

A PASS proves only that the scripted scenario worked on the current machine. SKIPPED is not PASS, and dogfood cannot prove arbitrary software compatibility.

## v4 Visual Dogfood

v4.6.0 adds `v4_visual_dogfood.ps1` for Hybrid Screen Perception dogfood on local developer workflow fixtures.

v4.7.0 keeps this suite as release-candidate evidence and aggregates it through `v4_rc_check.ps1`.

```powershell
D:\desktopvisual\v4_visual_dogfood.ps1
```

It writes:

- `artifacts\dev4.6.0\dogfood_report.md`
- `artifacts\dev4.6.0\dogfood_summary.json`

Required cases:

| Case | Boundary | Required Evidence |
|---|---|---|
| `local_html_form_flow` | Generated local HTML only. | `observe2`, form-control locators, SceneState, ChangeEvent, observe-loop delta/ROI. |
| `local_problem_page_run_and_read_result` | Local mock problem page; development benchmark only. | `coding-eval`, loading/success events, App Profile metadata. |
| `local_mail_mock_compose_attach_verify_no_real_send` | Local mock mail page only; no real send. | Compose/to/subject/attachment/send mock locators, upload complete text, sent mock state. |
| `explorer_temp_file_select_flow` | Temp file under artifacts only. | Explorer App Profile metadata and allowed `read-file` verification. |
| `notepad_text_edit_verify` | Clean Notepad temp file only; skip existing user sessions. | Notepad observe2 and saved temp-file verification when available. |
| `powershell_command_result_read` | Local non-admin command output under artifacts. | Allowed `read-file` verification and v4 perception probe. |

The v4 dogfood suite must not use real email, real accounts, external websites, browser profiles, real exam or hiring assessment submission, captcha bypass, anti-cheat bypass, payment flows, credential flows, or arbitrary user files.

