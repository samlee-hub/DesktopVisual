# Notepad Dogfood

Tests real Windows Notepad text input and verification.

## Expected Outcome
- Notepad starts with a blank window (no existing file).
- Text is typed and verified.
- Window is closed without saving.

## Failure Cases
- Notepad opens with an existing file 鈫?SKIPPED.
- Text verification fails 鈫?FAIL.
- Window not found 鈫?FAIL.

## Safety
- Does NOT save to user directories.
- Does NOT modify existing files.
- Closes Notepad after test.
