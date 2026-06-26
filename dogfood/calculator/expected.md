# Calculator Dogfood

Tests real Windows Calculator using UIA and hotkey input.

## Expected Outcome
- Calculator starts.
- 12+30=42 entered via keyboard.
- Result "42" verified via UIA or OCR.

## Failure Cases
- Calculator not found on system 鈫?SKIPPED.
- UIA or OCR unavailable for result verification 鈫?SKIPPED.
- Calculation result mismatch 鈫?FAIL.

## Safety
- Calculator is closed after test.
- No system settings modified.
