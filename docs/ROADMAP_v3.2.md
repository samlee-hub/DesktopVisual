# DesktopVisual v3.2 Roadmap

Current version: `v3.2.0`.

## Completed in v3.2.0

- Added `WindowSession` as the shared window-resolution record for title, optional process, hwnd, pid, process name, rect, visible/iconic state, foreground state, foreground controllability, DPI, monitor device name, monitor bounds, and monitor work-area bounds.
- Updated `observe` to return `data.window_session` while preserving existing `target_window`, `active_window`, `focus_verified`, `mouse`, `screenshot`, `uia`, `safety`, and `warnings` fields.
- Updated duplicate-window failures to return auditable candidate diagnostics instead of choosing the first visible match.
- Added conservative title-change detection for TaskRunner reconfirmation. If the previously selected hwnd no longer matches the requested title, TaskRunner stops with `WINDOW_TITLE_CHANGED`.
- Updated `act` and `run-task` act steps to confirm the target can be foregrounded before UIA or input actions.
- Integrated TaskRunner startup and step-level WindowSession checks, including initial and per-step Markdown report diagnostics.
- Added `window_session_selftest.ps1`.

## WindowSession Fields

- `requested_title`
- `requested_process`
- `title`
- `hwnd`
- `pid`
- `process_name`
- `rect`
- `visible`
- `iconic`
- `foreground.is_foreground`
- `foreground.foreground_controllable`
- `dpi`
- `monitor.device_name`
- `monitor.primary`
- `monitor.rect`
- `monitor.work_rect`

## Safety Boundary

v3.2.0 does not add background control, unrestricted desktop control, sensitive application automation, protected desktop support, UAC control, cloud remote control, or bypass behavior. WindowSession is diagnostic and gating metadata; it does not loosen SafetyPolicy, Safety Manifest, policy-check, consent-check, or focus-verified input requirements.

## Follow-Up Candidates

- v3.3.0 should build on WindowSession for service session continuity and richer report summarization.
- A v3.2.x patch is appropriate if mixed-DPI or multi-monitor tests expose coordinate conversion defects that require localized fixes before v3.3.0.
