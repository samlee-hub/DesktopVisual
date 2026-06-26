# Explorer Dogfood

Tests Windows Explorer file operations via DesktopVisual.

## Expected Outcome
- Explorer opens to a temp directory under dogfood artifacts.
- File/folder operations succeed.
- Results verified via filesystem.

## Failure Cases
- Explorer not responsive 鈫?FAIL.
- Path outside allowed roots 鈫?SAFETY_POLICY_DENIED.

## Safety
- Only operates in D:\desktopvisual\artifacts\dogfood\explorer\.
- Temp directory is cleaned up after test.
- Does NOT touch Desktop, Downloads, or user directories.
