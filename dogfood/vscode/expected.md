# VS Code Dogfood

Tests VS Code text editing via DesktopVisual.

## Expected Outcome
- VS Code opens a sample text file.
- Text is typed via DesktopVisual.
- File is saved (Ctrl+S).
- File content is verified.

## Failure Cases
- VS Code (`code` command or Code.exe) not found 鈫?SKIPPED.
- File save failed 鈫?FAIL.
- File content mismatch 鈫?FAIL.

## Safety
- Only edits files under D:\desktopvisual\artifacts\dogfood\vscode\.
- Does NOT open user projects, settings, or extensions.
