# DesktopVisual v3.0.1 Release Notes - Operator Motion Profile

## What's New

### Operator Motion Profile

- Added direct mouse trajectory recording with `motion-record`.
- Added calibration from raw samples into `config\operator_motion_profile.json`.
- Added profile inspection, validation, and clear commands.
- Added `operator-human` mouse movement mode for click, double-click, right-click, scroll, drag, click-image, click-text, act, and task.json act steps.
- Added Motion Lab mode to TestWindow for guided local sample collection.

### Safety And Privacy

- Raw samples are generated under `artifacts\motion_profile\raw`.
- Calibrated profiles store aggregate movement statistics, not complete raw traces.
- Motion profile data is local personalization only and must not be described as detection bypass.
- SafetyPolicy, focus verification, F12 interruption, exact final coordinates, and audit logging remain required.

### Verification

- Added `motion_profile_selftest.ps1` with synthetic raw samples, calibration, info, validation, operator-human click/drag/act/run-task coverage, missing/invalid profile checks, and cleanup detection.
- Added `motion_profile_demo.ps1` for optional manual Motion Lab calibration.

## Upgrade Notes

All v3.0.0 commands remain compatible. `operator-human` fails explicitly with `MOTION_PROFILE_NOT_FOUND` or `MOTION_PROFILE_INVALID` when the requested profile is unavailable or invalid.
