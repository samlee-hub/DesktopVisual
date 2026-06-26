# Real Dev Workflow

Current version: `v2.1.0`.

DesktopVisual keeps a configurable real development workflow template as part of v1.0. It does not access real project paths by default.

v2.1 adds a real-application dogfood matrix for validating controlled desktop operations outside TestWindow. The matrix is intentionally narrow and auditable: it uses Notepad, Calculator, Explorer, Edge, and optionally VS Code, and all file writes stay under `D:\desktopvisual\artifacts\dogfood`.

## Default Behavior

Running without parameters:

```powershell
D:\desktopvisual\run_real_dev_workflow.ps1
```

creates:

```text
D:\desktopvisual\artifacts\real_dev_workflow_report.md
```

with `Result: SKIPPED`. No real project path is accessed.

## Configure A Real Window

Provide a user-approved window title:

```powershell
D:\desktopvisual\run_real_dev_workflow.ps1 -TargetTitle "Approved Window Title"
```

The title must resolve to exactly one visible top-level window.

## Configure A Case

Start from:

```text
D:\desktopvisual\cases\real_dev_workflow.template.case
```

Copy it to another file under `D:\desktopvisual\cases`, replace the placeholders, then pass it with `-CaseFile`.

The template supports screenshots, UIA actions, image actions, key presses, waits, and optional state-file reads. Do not point `read_file` or `assert_file_contains` at a real project path until the user approves that exact path.

## Configure A State File

Use `-StateFile` only after approval:

```powershell
D:\desktopvisual\run_real_dev_workflow.ps1 `
  -TargetTitle "Approved Window Title" `
  -StateFile "D:\approved\path\state.txt" `
  -CaseFile "D:\desktopvisual\cases\approved_workflow.case"
```

By default, only these roots are already authorized:

```text
D:\desktopvisual
D:\testrepo\testwindow
```

Any other project path must be approved by the user first. If an unapproved path is passed, the script writes a SKIPPED report and does not read it.

## Safety Boundary

1. Do not modify real project code.
2. Do not delete real project files.
3. Do not access Client, Server, UE, game, or other project paths without explicit approval.
4. Do not use this for unauthorized game automation, platform risk-control bypass, or other unapproved workflows.
5. Only interact with a user-approved target window.
6. Stop on `error_code`; do not continue with guessed clicks.

## Real Application Validation Strategy

Use `D:\desktopvisual\dogfood_matrix.ps1` when you need evidence that DesktopVisual can operate real Windows applications. A PASS means the app-specific workflow completed inside the bounded dogfood sandbox. A SKIPPED result means the app, a clean target window, or a required capability is unavailable on this system. A FAIL means the script ran and did not achieve its expected result; the generated report must include the reason.

Dogfood scripts must not close pre-existing user windows. They should skip if Notepad, Calculator, Edge, or VS Code already has a user session open. Explorer dogfood operates only inside `D:\desktopvisual\artifacts\dogfood\explorer`.

## Why This Is Not Automatic

Real development projects may contain source code, credentials, build artifacts, editor state, and private data. DesktopVisual requires user-approved paths so a workflow can be audited before any real project file is read.
