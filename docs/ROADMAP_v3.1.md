# DesktopVisual v3.1 Roadmap

Current version: `v3.1.1`.

## Theme

Advanced Selectors and Relative Locators.

## Completed in v3.1.0

- Added UIA `automation_id` selector support.
- Added UIA `class_name` selector support as an auxiliary filter.
- Added `relative:` selector support for `right_of`, `left_of`, `below`, `above`, and `inside_window`.
- Added `near_text:` selector support using UIA text anchors and target filters.
- Added explicit `nth` disambiguation for new multi-candidate selector forms while preserving legacy `index`.
- Added `chain:` fallback selector support with ordered attempt diagnostics.
- Extended selector result JSON with audit-friendly fields: `ok`, `method`, `final_method`, `confidence`, `matched_text`, `matched_name`, `source`, `failure_reason`, and `artifacts.report_path`.
- Extended `run-task` reports so selector failures and fallback chains are visible in task reports.

## Completed in v3.1.1

- Fixed Safety Manifest strict JSON parsing by replacing corrupted denied title pattern strings with ASCII deny patterns.
- Added strict manifest JSON parsing to `safety_manifest_selftest.ps1`.

## Safety Boundary

v3.1.0 does not add unrestricted desktop control, background control, sensitive application automation, protected desktop support, cloud control, or complex VLM behavior. All actions still require explicit target windows, SafetyPolicy/Safety Manifest checks, and existing focus-verified input paths.

## Follow-up Candidates

- v3.1.x: improve parser escaping if selector values need commas or `||`.
- v3.1.x: add richer selector report artifacts if task reports need standalone JSON sidecars.
- v3.2.0: proceed only after v3.1 selector behavior passes full regression and no protocol/documentation mismatch remains.
