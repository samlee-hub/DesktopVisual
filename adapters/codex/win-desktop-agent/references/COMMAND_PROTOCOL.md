# WinAgent Command Protocol

Current version: `v3.0.5`.

Protocol status: frozen for v0.1.6.

This document freezes the v0.1 CLI protocol, case execution surface, JSON envelopes, audit log shape, and report expectations for v0.2 Codex Skill integration. Compatible additions may be made in future versions, but existing command names, required fields, error codes, and log/report formats must not be broken without a documented compatibility note.

v0.3.0 adds Windows UI Automation read-only commands as compatible additions. v0.3.1 adds UIA-located click and type commands. v0.3.2 adds OCR text-location command interfaces. v0.3.3 adds BMP image template location. v0.4.1 adds safety policy checks for input actions and case execution. v0.4.2 is a release-freeze documentation and packaging pass. v1.0.0 is the first formal release publication pass. v1.0.1 adds reliability and safety fixes for focus verification, file-read path allowlists, and capability reporting. v1.1.0 adds controlled input primitives. v1.2.0 adds `instant`, `fast-human`, and `demo-human` motion profiles with legacy `human` compatibility. v1.3.0 adds the read-only `observe` command. v1.4.0 adds the unified Selector locate/act system. v1.5.0 adds Case v2 format with key=value syntax, variables, wait_until, expect, and post-action verification. v2.0.0 adds real Windows OCR when WinRT OCR is available and keeps `OCR_UNAVAILABLE` fallback when it is not. v2.1.0 adds the real-app dogfood matrix. v2.2.0 upgrades the Skill workflow. v2.3.0 adds explicit local service mode. v3.0.0 adds `run-task` for closed-loop observe/locate/act/verify task execution. v3.0.1 adds Operator Motion Profile commands and `operator-human` move-mode. v3.0.1a requires explicit profile `source`, isolates synthetic test profiles, and rejects non-human profiles by default. v3.0.2 adds portable root resolution, `DESKTOPVISUAL_ROOT`, `project_root` in `version`, and `${PROJECT_ROOT}` safety config variables. v3.0.3 adds agent-agnostic adapters and a generic CLI contract. v3.0.4 adds benchmark evidence reports and evidence pack export. v3.0.5 adds the Safety Manifest and consent layer with `safety-report`, `policy-check`, and `consent-check`. Existing v1/v2 case formats, CLI commands, JSON envelopes, and audit log format remain compatible.

Compatibility note for v1.5.0: v1.4.0 and earlier commands remain fully compatible. Case v2 is enabled by `case_version=2` as the first non-comment line in .case files; files without this declaration use v1 format. No CLI commands, JSON envelopes, or audit log formats are changed.

## DesktopVisual v1.0.4 Visual Studio C++ Complex IDE Addendum

Visual Studio C++ complex IDE workflows require step-by-step visible execution. VS opens by visible desktop icon double-click, `SingleTestProject` uses the Empty Project template and default settings, project open is visible VS UI, source/header file-add is visible IDE UI, editor input is visible, build/run are VS UI or visible IDE shortcuts, output verification is visible, and VS closes by visible top-right X at successful boundaries.

Invalid PASS paths include backend `.sln` open, backend project creation, backend source/header writes, `.vcxproj` edits, backend build, direct exe run, old mock VLM, and one-shot batch scripts.

## Stable Commands

- `version`
- `windows`
- `find`
- `screenshot`
- `observe`
- `locate`
- `act`
- `click`
- `double-click`
- `right-click`
- `scroll`
- `drag`
- `press`
- `hotkey`
- `type`
- `clipboard-set`
- `clipboard-paste`
- `focus`
- `active-window`
- `mouse-position`
- `read-file`
- `uia-tree`
- `uia-find`
- `uia-click`
- `uia-type`
- `find-text`
- `click-text`
- `read-window-text`
- `read-region-text`
- `wait-text`
- `assert-text-contains`
- `motion-record`
- `motion-calibrate`
- `motion-profile-info`
- `motion-profile-validate`
- `motion-profile-clear`
- `find-image`
- `click-image`
- `run-case`
- `serve`
- `run-task`

## Unified Command JSON

The following commands use the unified JSON envelope:

- `version`
- `find`
- `screenshot`
- `observe`
- `locate`
- `act`
- `click`
- `double-click`
- `right-click`
- `scroll`
- `drag`
- `press`
- `hotkey`
- `type`
- `clipboard-set`
- `clipboard-paste`
- `focus`
- `active-window`
- `mouse-position`
- `read-file`
- `uia-tree`
- `uia-find`
- `uia-click`
- `uia-type`
- `find-text`
- `click-text`
- `read-window-text`
- `read-region-text`
- `wait-text`
- `assert-text-contains`
- `motion-record`
- `motion-calibrate`
- `motion-profile-info`
- `motion-profile-validate`
- `motion-profile-clear`
- `find-image`
- `click-image`
- `run-case`
- `run-task`

Success:

```json
{
  "ok": true,
  "command": "click",
  "timestamp": "2026-05-25 18:40:01",
  "duration_ms": 123,
  "target": {
    "title": "Agent Test Window",
    "hwnd": "0x123456",
    "pid": 1234
  },
  "data": {}
}
```

Failure:

```json
{
  "ok": false,
  "command": "click",
  "timestamp": "2026-05-25 18:40:01",
  "duration_ms": 123,
  "target": null,
  "error": {
    "code": "WINDOW_NOT_FOUND",
    "message": "Target window was not found."
  },
  "data": {}
}
```

`windows` returns a stable listing envelope:

```json
{
  "ok": true,
  "windows": [
    {
      "hwnd": "0x123456",
      "pid": 1234,
      "title": "Agent Test Window",
      "rect": {
        "left": 10,
        "top": 20,
        "right": 650,
        "bottom": 440
      }
    }
  ]
}
```

## Command Reference

### version

Parameters: none.

Success JSON:

```json
{
  "ok": true,
  "command": "version",
  "timestamp": "2026-05-25 18:40:01",
  "duration_ms": 0,
  "target": null,
  "data": {
    "version": "1.4.0",
    "build_time": "May 25 2026 19:30:00",
    "platform": "Windows",
    "project_root": "D:\\desktopvisual",
    "capabilities": {
      "available": [
        "window_find",
        "window_screenshot",
        "real_mouse_click",
        "keyboard_press",
        "text_type",
        "read_file",
        "uia_tree",
        "uia_find",
        "uia_click",
        "uia_type",
        "find_image",
        "click_image",
        "safety_policy",
        "read_path_policy",
        "run_case",
        "audit_log",
        "markdown_report"
      ],
      "stub": [
        { "name": "find_text", "ocr_available": false },
        { "name": "click_text", "ocr_available": false }
      ],
      "experimental": [
        "image_template_location"
      ]
    }
  }
}
```

Failure JSON: only invalid process-level failures are expected. If emitted, the unified failure envelope is used with `UNKNOWN_ERROR` or `AUDIT_LOG_FAILED`.

Possible `error.code`: `AUDIT_LOG_FAILED`, `UNKNOWN_ERROR`.

Safety limits: no desktop control is performed.

### safety-report

Parameters: none.

Success JSON includes `manifest_loaded`, `safety_conf_loaded`, `allowed_titles`, `allowed_processes`, `allowed_read_roots`, `allowed_write_roots`, `denied_categories`, `runtime_limits`, `audit_enabled`, `warnings`, `report_json`, and `report_markdown`.

Output files:

```text
D:\desktopvisual\artifacts\safety\safety_report.md
D:\desktopvisual\artifacts\safety\safety_report.json
```

Safety limits: read-only policy inspection. It performs no input and does not enumerate arbitrary windows.

### policy-check

Parameters:

- `--title <title>`: required target title to check.
- `--process <process>`: required executable name to check.
- `--action <action>`: required action name to check.
- `--path <path>`: optional path for future path-scoped decisions.

Success JSON returns `data.allow=true` and the allow reason. Denial returns `SAFETY_POLICY_DENIED` with `data.allow=false`, `matched_rule`, and `matched_category` when applicable.

Safety limits: dry-run only. It does not focus, click, type, read UI, or execute the action.

### consent-check

Parameters:

- `--title <title>`: required target title substring.

Success JSON returns the resolved visible target, process name, foreground status, and `consent_requirements`. Missing or ambiguous windows return `WINDOW_NOT_FOUND` or `WINDOW_NOT_UNIQUE`. Sensitive categories return `SAFETY_POLICY_DENIED`.

Safety limits: read-only target validation. It does not show UI, request consent interactively, focus the window, or send input.

### windows

Parameters: none.

Success JSON: the stable listing envelope shown above.

Failure JSON: this command does not currently emit a structured failure for normal enumeration.

Possible `error.code`: none in the frozen v0.1.6 implementation.

Safety limits: reads visible top-level window titles, process IDs, and rectangles only. It does not click, type, save files, or close windows.

### find

Parameters:

- `--title <substring>`: required target window title substring.

Success JSON:

```json
{
  "ok": true,
  "command": "find",
  "timestamp": "2026-05-25 18:40:01",
  "duration_ms": 1,
  "target": {
    "title": "Agent Test Window",
    "hwnd": "0x123456",
    "pid": 1234
  },
  "data": {
    "requested_title": "Agent Test Window",
    "rect": {
      "left": 10,
      "top": 20,
      "right": 650,
      "bottom": 440
    }
  }
}
```

Failure JSON: unified failure envelope.

Possible `error.code`: `INVALID_ARGUMENT`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `AUDIT_LOG_FAILED`.

Safety limits: requires a non-empty title substring and exactly one visible top-level window match. It does not perform input.

### screenshot

Parameters:

- `--title <substring>`: required target window title substring.
- `--out <path>`: required BMP output path.

Success JSON:

```json
{
  "ok": true,
  "command": "screenshot",
  "timestamp": "2026-05-25 18:40:01",
  "duration_ms": 16,
  "target": {
    "title": "Agent Test Window",
    "hwnd": "0x123456",
    "pid": 1234
  },
  "data": {
    "out": "D:\\desktopvisual\\artifacts\\before.bmp",
    "method": "PrintWindow"
  }
}
```

Failure JSON: unified failure envelope.

Possible `error.code`: `INVALID_ARGUMENT`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `SCREENSHOT_FAILED`, `AUDIT_LOG_FAILED`.

Safety limits: requires exactly one visible top-level window match. It captures a window image only and does not perform input.

### observe

Parameters:

- `--title <substring>`: required target window title substring.
- `--screenshot true|false`: optional, default `true`.
- `--uia true|false`: optional, default `true`.
- `--max-elements <n>`: optional maximum returned UIA elements, default `80`.

Success JSON includes `target_window`, `active_window`, `focus_verified`, `mouse`, `screenshot`, `uia`, `safety`, and `warnings` in `data`. Screenshot output is written under `D:\desktopvisual\artifacts\observe_<timestamp>.bmp` when enabled. `observe` does not focus the target, click, type, paste, or otherwise modify window contents.

If screenshot capture fails while UIA succeeds, or UIA fails while screenshot capture succeeds, `observe` can still return `ok=true` and records the partial failure in `data.warnings`.

Possible `error.code`: `INVALID_ARGUMENT`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `AUDIT_LOG_FAILED`, `UNKNOWN_ERROR`.

Safety limits: requires exactly one visible top-level window match. It is read-only and does not require input-action safety approval.

## Selector

Selector format is `<method>:key=value,key=value`. Values may contain basic spaces; complex escaping is reserved for a future case format.

Supported selectors:

- `coord:x=80,y=90`
- `uia:name=Click Me`
- `uia:name_contains=Click,type=Button`
- `uia:type=Edit,index=0`
- `image:path=D:\desktopvisual\assets\click_button.bmp,tolerance=10`
- `text:contains=Click Me`

Selector failures use:

- `INVALID_SELECTOR` for unknown selector types or malformed selector fields.
- `LOCATOR_NOT_FOUND` for zero matches.
- `LOCATOR_NOT_UNIQUE` for multiple matches when no `index` disambiguates the selector.
- `OCR_UNAVAILABLE` when a `text:` selector is used while OCR is unavailable.

### locate

Parameters:

- `--title <substring>`: required target window title substring.
- `--selector <selector>`: required selector string.

Success data includes `selector`, `locate_method`, `match_count`, `client_point`, `screen_point`, `rect`, and optional `element`.

Safety limits: requires exactly one visible target window. It performs no input and does not require input-action safety approval.

### act

Parameters:

- `--title <substring>`: required target window title substring.
- `--selector <selector>`: required selector string.
- `--action click|double-click|right-click|type|focus`: required action.
- `--text <text>`: required for `type`.
- `--move-mode instant|fast-human|demo-human|human|operator-human`: optional for mouse-backed actions.
- `--profile <path>`: optional profile path for `operator-human`; defaults to `D:\desktopvisual\config\operator_motion_profile.json`.
- `--allow-synthetic-profile`: optional test-only flag allowing `source=synthetic` or `source=sample` profiles.
- `--fallback fast-human`: optional explicit fallback when `operator-human` profile is missing, invalid, or rejected by source policy.

Behavior: `act` first runs the selector locator. Input actions then require safety policy approval and focus-verified input paths. For UIA button clicks, `InvokePattern` is preferred when available. For UIA edit typing, `ValuePattern` is preferred when available. Otherwise actions fall back to target-window client-coordinate input at the located center point.

### click

Parameters:

- `--title <substring>`: required target window title substring.
- `--x <int>`: required target client x coordinate.
- `--y <int>`: required target client y coordinate.
- `--move-mode instant|fast-human|demo-human|human|operator-human`: optional, default `human`; `human` maps to `operator-human` and requires a valid local Operator Motion Profile. Use `instant` only when an automated test explicitly needs direct cursor placement.
- `--move-duration-ms <int>`: optional non-negative duration. If omitted for human modes, duration is auto-calculated from distance.
- `--profile <path>`: optional profile path for `operator-human`; defaults to `D:\desktopvisual\config\operator_motion_profile.json`.
- `--allow-synthetic-profile`: optional test-only flag allowing `source=synthetic` or `source=sample` profiles.
- `--fallback fast-human`: optional. Used only when `human`/`operator-human` fails because the profile is missing, invalid, or rejected by source policy.

Success JSON:

```json
{
  "ok": true,
  "command": "click",
  "timestamp": "2026-05-25 18:40:01",
  "duration_ms": 1012,
  "target": {
    "title": "Agent Test Window",
    "hwnd": "0x123456",
    "pid": 1234
  },
  "data": {
    "target_client_x": 80,
    "target_client_y": 90,
    "target_screen_x": 120,
    "target_screen_y": 160,
    "cursor_before_x": 400,
    "cursor_before_y": 300,
    "cursor_after_x": 120,
    "cursor_after_y": 160,
    "move_mode": "operator-human",
    "move_duration_ms": 900,
    "move_steps": 90,
    "move_profile": "operator-human",
    "path_type": "operator-statistical"
  }
}
```

Failure JSON: unified failure envelope.

Possible `error.code`: `INVALID_ARGUMENT`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `WINDOW_FOCUS_FAILED`, `SAFETY_POLICY_DENIED`, `EMERGENCY_STOP`, `MOTION_PROFILE_NOT_FOUND`, `MOTION_PROFILE_INVALID`, `MOTION_PROFILE_NOT_HUMAN`, `MOTION_PROFILE_SOURCE_REQUIRED`, `MOTION_PROFILE_TEST_ONLY`, `CURSOR_MOVE_FAILED`, `SEND_INPUT_FAILED`, `UNKNOWN_ERROR`, `AUDIT_LOG_FAILED`.

Safety limits: uses real desktop input through `SendInput`. Coordinates are target-window client coordinates, not unrestricted full-screen coordinates. The target title must resolve to exactly one visible top-level window and pass `D:\desktopvisual\config\safety.conf` title/process checks. The command does not use `SendMessage`, `PostMessage`, or `BM_CLICK`.

### press

Parameters:

- `--title <substring>`: required target window title substring.
- `--key <KEY>`: required key name.

Supported keys: single letters `A`-`Z`, single digits `0`-`9`, `SPACE`, `ENTER`, `ESC`, `TAB`, `LEFT`, `RIGHT`, `UP`, `DOWN`.

Success JSON:

```json
{
  "ok": true,
  "command": "press",
  "timestamp": "2026-05-25 18:40:01",
  "duration_ms": 10,
  "target": {
    "title": "Agent Test Window",
    "hwnd": "0x123456",
    "pid": 1234
  },
  "data": {
    "key": "SPACE"
  }
}
```

Failure JSON: unified failure envelope.

Possible `error.code`: `INVALID_ARGUMENT`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `WINDOW_FOCUS_FAILED`, `SAFETY_POLICY_DENIED`, `EMERGENCY_STOP`, `SEND_INPUT_FAILED`, `UNKNOWN_ERROR`, `AUDIT_LOG_FAILED`.

Safety limits: sends a single key press to the uniquely matched target window only after title/process safety checks pass.

### type

Parameters:

- `--title <substring>`: required target window title substring.
- `--text <text>`: required text argument.
- `--type-mode instant|fast-human|demo-human|human`: optional, default `human`; `human` maps to `demo-human`. Use `instant` only when an automated test explicitly needs fast Unicode input.
- `--char-delay-ms <int>`: optional non-negative delay for `human` mode, default `80`.

Success JSON:

```json
{
  "ok": true,
  "command": "type",
  "timestamp": "2026-05-25 18:40:01",
  "duration_ms": 500,
  "target": {
    "title": "Agent Test Window",
    "hwnd": "0x123456",
    "pid": 1234
  },
  "data": {
    "type_mode": "human",
    "char_delay_ms": 80,
    "text_length": 5
  }
}
```

Failure JSON: unified failure envelope.

Possible `error.code`: `INVALID_ARGUMENT`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `WINDOW_FOCUS_FAILED`, `SAFETY_POLICY_DENIED`, `EMERGENCY_STOP`, `SEND_INPUT_FAILED`, `UNKNOWN_ERROR`, `AUDIT_LOG_FAILED`.

Safety limits: sends Unicode keyboard input to the uniquely matched target window only after title/process safety checks pass. Human type checks the configured emergency stop key. Audit logging records type metadata, not the full typed text. Case files and reports can contain test text, so this version is not appropriate for passwords or secrets.

### input primitives

v1.1.0 adds these unified-envelope commands:

- `double-click --title <substring> --x <client_x> --y <client_y> [--move-mode instant|fast-human|demo-human|human|operator-human] [--move-duration-ms <int>] [--profile <path>] [--allow-synthetic-profile] [--fallback fast-human]`
- `right-click --title <substring> --x <client_x> --y <client_y> [--move-mode instant|fast-human|demo-human|human|operator-human] [--move-duration-ms <int>] [--profile <path>] [--allow-synthetic-profile] [--fallback fast-human]`
- `scroll --title <substring> --x <client_x> --y <client_y> --delta <int> [--move-mode instant|fast-human|demo-human|human|operator-human] [--profile <path>] [--allow-synthetic-profile] [--fallback fast-human]`
- `drag --title <substring> --from-x <client_x> --from-y <client_y> --to-x <client_x> --to-y <client_y> [--move-mode instant|fast-human|demo-human|human|operator-human] [--duration-ms <int>] [--profile <path>] [--allow-synthetic-profile] [--fallback fast-human]`
- `hotkey --title <substring> --keys <combo>`
- `clipboard-set --text <text>`
- `clipboard-paste --title <substring> [--text <text>]`
- `focus --title <substring>`
- `active-window`
- `mouse-position`

All target-window input primitives require a unique `--title`, pass `SafetyPolicy`, verify focus before input, write the unified JSON envelope, and append to `artifacts\agent_audit.log`. `clipboard-set` does not target a window and returns only `text_length`. `active-window` returns `hwnd`, `pid`, `title`, `process_name`, and `rect`; `mouse-position` returns `screen_x` and `screen_y`.

v1.2.0 mouse actions return these motion fields in `data`: `move_profile`, `path_type`, `distance_px`, `duration_ms`, `step_count`, and `emergency_stop_checked`. `instant` uses direct cursor placement. `fast-human` and `demo-human` remain explicit legacy curved-path modes. v3.0.1 adds `operator-human`, which returns `operator_profile_path`, `operator_profile_quality`, and `synthesized_point_count` when a valid local profile is used. Since v3.0.2, mouse `human` resolves to `operator-human` by default and does not silently fall back to legacy curved paths.

### read-file

Parameters:

- `--path <path>`: required file path.

Success JSON:

```json
{
  "ok": true,
  "command": "read-file",
  "timestamp": "2026-05-25 18:40:01",
  "duration_ms": 1,
  "target": null,
  "data": {
    "path": "D:\\testrepo\\testwindow\\runtime\\state.txt",
    "content": "window_title=Agent Test Window\n",
    "content_length": 32
  }
}
```

Failure JSON: unified failure envelope.

Possible `error.code`: `INVALID_ARGUMENT`, `SAFETY_POLICY_DENIED`, `FILE_NOT_FOUND`, `FILE_READ_FAILED`, `AUDIT_LOG_FAILED`.

Safety limits: reads a text file only after the normalized path is inside `allowed_read_roots`. Paths containing `..` traversal are denied before file access.

### uia-tree

Parameters:

- `--title <substring>`: required target window title substring.

Success JSON:

```json
{
  "ok": true,
  "command": "uia-tree",
  "timestamp": "2026-05-26 00:30:01",
  "duration_ms": 12,
  "target": {
    "title": "Agent Test Window",
    "hwnd": "0x123456",
    "pid": 1234
  },
  "data": {
    "elements": [
      {
        "name": "Click Me",
        "control_type": "Button",
        "rect": {
          "left": 250,
          "top": 283,
          "right": 370,
          "bottom": 319
        },
        "enabled": true,
        "offscreen": false
      }
    ]
  }
}
```

Failure JSON: unified failure envelope.

Possible `error.code`: `INVALID_ARGUMENT`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `UIA_INIT_FAILED`, `UIA_TREE_FAILED`, `AUDIT_LOG_FAILED`.

Safety limits: reads Windows UI Automation element metadata only. It does not click, type, invoke controls, use OCR, or use image/template matching. The target title must resolve to exactly one visible top-level window.

### uia-find

Parameters:

- `--title <substring>`: required target window title substring.
- `--name <text>`: required UI Automation element name. Matching accepts exact matches and substring matches.

Success JSON:

```json
{
  "ok": true,
  "command": "uia-find",
  "timestamp": "2026-05-26 00:30:01",
  "duration_ms": 12,
  "target": {
    "title": "Agent Test Window",
    "hwnd": "0x123456",
    "pid": 1234
  },
  "data": {
    "requested_name": "Click Me",
    "name": "Click Me",
    "control_type": "Button",
    "rect": {
      "left": 250,
      "top": 283,
      "right": 370,
      "bottom": 319
    },
    "enabled": true,
    "offscreen": false
  }
}
```

Failure JSON: unified failure envelope.

Possible `error.code`: `INVALID_ARGUMENT`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `UIA_INIT_FAILED`, `UIA_TREE_FAILED`, `UIA_ELEMENT_NOT_FOUND`, `UIA_ELEMENT_NOT_UNIQUE`, `AUDIT_LOG_FAILED`.

Safety limits: reads Windows UI Automation element metadata only. It does not invoke the matched control. If no element or multiple elements match, the command fails instead of guessing.

### uia-click

Parameters:

- `--title <substring>`: required target window title substring.
- `--name <text>`: required UI Automation element name. Matching accepts exact matches and substring matches.

Success JSON:

```json
{
  "ok": true,
  "command": "uia-click",
  "timestamp": "2026-05-26 00:40:01",
  "duration_ms": 44,
  "target": {
    "title": "Agent Test Window",
    "hwnd": "0x123456",
    "pid": 1234
  },
  "data": {
    "locate_method": "uia",
    "action_method": "invoke_pattern",
    "element_name": "Click Me",
    "control_type": "Button",
    "rect": {
      "left": 250,
      "top": 283,
      "right": 370,
      "bottom": 319
    },
    "result": "success"
  }
}
```

Failure JSON: unified failure envelope.

Possible `error.code`: `INVALID_ARGUMENT`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `WINDOW_FOCUS_FAILED`, `SAFETY_POLICY_DENIED`, `EMERGENCY_STOP`, `UIA_INIT_FAILED`, `UIA_TREE_FAILED`, `UIA_ELEMENT_NOT_FOUND`, `UIA_ELEMENT_NOT_UNIQUE`, `CURSOR_MOVE_FAILED`, `SEND_INPUT_FAILED`, `UNKNOWN_ERROR`, `AUDIT_LOG_FAILED`.

Safety limits: requires exactly one target window, a title/process safety policy match, and exactly one UIA element match. It first tries `InvokePattern`; if unavailable, it clicks the element rectangle center through the existing real mouse input path.

### uia-type

Parameters:

- `--title <substring>`: required target window title substring.
- `--name <text>`: required UI Automation element name. Matching accepts exact matches and substring matches.
- `--text <text>`: required text argument.

Success JSON:

```json
{
  "ok": true,
  "command": "uia-type",
  "timestamp": "2026-05-26 00:40:01",
  "duration_ms": 44,
  "target": {
    "title": "Agent Test Window",
    "hwnd": "0x123456",
    "pid": 1234
  },
  "data": {
    "locate_method": "uia",
    "action_method": "value_pattern",
    "element_name": "Input",
    "control_type": "Edit",
    "rect": {
      "left": 250,
      "top": 353,
      "right": 610,
      "bottom": 381
    },
    "text_length": 5,
    "type_mode": "value_pattern"
  }
}
```

Failure JSON: unified failure envelope.

Possible `error.code`: `INVALID_ARGUMENT`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `WINDOW_FOCUS_FAILED`, `SAFETY_POLICY_DENIED`, `EMERGENCY_STOP`, `UIA_INIT_FAILED`, `UIA_TREE_FAILED`, `UIA_ELEMENT_NOT_FOUND`, `UIA_ELEMENT_NOT_UNIQUE`, `CURSOR_MOVE_FAILED`, `SEND_INPUT_FAILED`, `UNKNOWN_ERROR`, `AUDIT_LOG_FAILED`.

Safety limits: requires exactly one target window, a title/process safety policy match, and exactly one UIA element match. It first tries `ValuePattern`; if unavailable, it clicks the element rectangle center and uses the existing keyboard input path. It does not use OCR or image/template matching.

### find-text

Parameters:

- `--title <substring>`: required target window title substring.
- `--text <text>`: required text to locate.

Success JSON when OCR is available:

```json
{
  "ok": true,
  "command": "find-text",
  "timestamp": "2026-05-26 00:50:01",
  "duration_ms": 44,
  "target": {
    "title": "Agent Test Window",
    "hwnd": "0x123456",
    "pid": 1234
  },
  "data": {
    "requested_text": "Click Me",
    "matched_text": "Click Me",
    "bounding_box": {
      "left": 250,
      "top": 283,
      "right": 370,
      "bottom": 319
    },
    "coordinate_space": "screen",
    "confidence": null,
    "ocr_available": true
  }
}
```

Current v2.0+ behavior: the command uses Windows built-in WinRT OCR when available. If the build or runtime does not provide OCR, it returns a unified failure envelope with `OCR_UNAVAILABLE`; if no usable OCR language is available, it returns `OCR_LANGUAGE_UNAVAILABLE`.

Possible `error.code`: `INVALID_ARGUMENT`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `SAFETY_POLICY_DENIED`, `OCR_INIT_FAILED`, `OCR_UNAVAILABLE`, `OCR_LANGUAGE_UNAVAILABLE`, `LOCATOR_NOT_FOUND`, `LOCATOR_NOT_UNIQUE`, `OCR_FAILED`, `AUDIT_LOG_FAILED`.

Safety limits: OCR is only for user-authorized test windows. Do not use it for security-control bypass, credential extraction, or unauthorized workflow automation. Prefer UI Automation over OCR when available.

### click-text

Parameters:

- `--title <substring>`: required target window title substring.
- `--text <text>`: required text to locate.
- `--move-mode instant|fast-human|demo-human|human|operator-human`: optional, default `human`; `human` maps to `operator-human` and requires a valid local Operator Motion Profile.
- `--move-duration-ms <int>`: optional non-negative duration. If omitted for human modes, duration is auto-calculated from distance.
- `--profile <path>`: optional profile path for `operator-human`.
- `--allow-synthetic-profile`: optional test-only flag allowing `source=synthetic` or `source=sample` profiles.
- `--fallback fast-human`: optional explicit fallback for missing, invalid, or source-rejected operator profile.

Success JSON when OCR is available:

```json
{
  "ok": true,
  "command": "click-text",
  "timestamp": "2026-05-26 00:50:01",
  "duration_ms": 900,
  "target": {
    "title": "Agent Test Window",
    "hwnd": "0x123456",
    "pid": 1234
  },
  "data": {
    "requested_text": "Click Me",
    "matched_text": "Click Me",
    "bounding_box": {
      "left": 250,
      "top": 283,
      "right": 370,
      "bottom": 319
    },
    "coordinate_space": "screen",
    "confidence": null,
    "ocr_available": true,
    "action_method": "mouse_center",
    "move_mode": "human",
    "move_duration_ms": 800
  }
}
```

Current v2.0+ behavior: `click-text` first calls the OCR text locator. It clicks only after a unique OCR text match and returns `OCR_UNAVAILABLE` or `OCR_LANGUAGE_UNAVAILABLE` without clicking when OCR cannot run.

Possible `error.code`: `INVALID_ARGUMENT`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `WINDOW_FOCUS_FAILED`, `SAFETY_POLICY_DENIED`, `EMERGENCY_STOP`, `MOTION_PROFILE_NOT_FOUND`, `MOTION_PROFILE_INVALID`, `MOTION_PROFILE_NOT_HUMAN`, `MOTION_PROFILE_SOURCE_REQUIRED`, `MOTION_PROFILE_TEST_ONLY`, `OCR_INIT_FAILED`, `OCR_UNAVAILABLE`, `OCR_LANGUAGE_UNAVAILABLE`, `LOCATOR_NOT_FOUND`, `LOCATOR_NOT_UNIQUE`, `OCR_FAILED`, `CURSOR_MOVE_FAILED`, `SEND_INPUT_FAILED`, `AUDIT_LOG_FAILED`.

Safety limits: requires exactly one target window and a title/process safety policy match. Clicking is permitted only after a unique OCR text match. The OCR bounding box is reported in window-bitmap coordinates and converted to target client coordinates before input.

### read-window-text

Parameters:

- `--title <substring>`: required target window title substring.
- `--out <path>`: optional text output path under `allowed_write_roots`.

Success data includes `text`, `line_count`, `word_count`, `language`, `coordinate_space`, `screenshot_path`, `ocr_available`, `lines`, and `words`. OCR uses Windows built-in WinRT OCR when available. The target window must pass the same title/process safety policy used by input actions.

Possible `error.code`: `INVALID_ARGUMENT`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `SAFETY_POLICY_DENIED`, `SCREENSHOT_FAILED`, `OCR_UNAVAILABLE`, `OCR_LANGUAGE_UNAVAILABLE`, `OCR_FAILED`, `AUDIT_LOG_FAILED`.

### read-region-text

Parameters:

- `--title <substring>`: required target window title substring.
- `--x <client_x> --y <client_y> --w <width> --h <height>`: required client-area region.

Success data has the same OCR shape as `read-window-text`, limited to the requested client-area region. The target window must pass safety policy before OCR runs.

### wait-text

Parameters:

- `--title <substring>`: required target window title substring.
- `--text <text>`: required OCR text to poll for.
- `--timeout-ms <int>`: optional, default `5000`.
- `--interval-ms <int>`: optional, default `300`.

Returns success when OCR finds the requested text before timeout. Returns `LOCATOR_NOT_FOUND`, `OCR_UNAVAILABLE`, `OCR_LANGUAGE_UNAVAILABLE`, or `OCR_FAILED` on failure.

### assert-text-contains

Parameters:

- `--title <substring>`: required target window title substring.
- `--text <text>`: required OCR text assertion.

Returns `ASSERTION_FAILED` if OCR runs but the requested text is absent. The target window must pass safety policy before OCR runs.

### find-image

Parameters:

- `--title <substring>`: required target window title substring.
- `--template <path>`: required BMP template path.
- `--tolerance <0-255>`: optional per-channel pixel tolerance, default `0`.

Success JSON:

```json
{
  "ok": true,
  "command": "find-image",
  "timestamp": "2026-05-26 13:30:01",
  "duration_ms": 44,
  "target": {
    "title": "Agent Test Window",
    "hwnd": "0x123456",
    "pid": 1234
  },
  "data": {
    "match_found": true,
    "x": 68,
    "y": 101,
    "width": 120,
    "height": 36,
    "score": 1.0,
    "match_count": 1,
    "coordinate_space": "window_bitmap",
    "template": "D:\\desktopvisual\\assets\\click_button.bmp",
    "screenshot_path": "D:\\desktopvisual\\artifacts\\find_image_source.bmp"
  }
}
```

Failure JSON: unified failure envelope.

Possible `error.code`: `INVALID_ARGUMENT`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `SCREENSHOT_FAILED`, `IMAGE_FILE_NOT_FOUND`, `IMAGE_UNSUPPORTED_FORMAT`, `IMAGE_MATCH_NOT_FOUND`, `IMAGE_MATCH_NOT_UNIQUE`, `IMAGE_MATCH_FAILED`, `AUDIT_LOG_FAILED`.

Safety limits: requires exactly one target window and exactly one template match. Supports only uncompressed 24-bit and 32-bit BMP files. Template matching is for authorized GUI testing only and must not be used for security-control bypass or unauthorized workflows.

### click-image

Parameters:

- `--title <substring>`: required target window title substring.
- `--template <path>`: required BMP template path.
- `--tolerance <0-255>`: optional per-channel pixel tolerance, default `0`.
- `--move-mode instant|fast-human|demo-human|human|operator-human`: optional, default `human`; `human` maps to `operator-human` and requires a valid local Operator Motion Profile.
- `--move-duration-ms <int>`: optional non-negative duration. If omitted for human modes, duration is auto-calculated from distance.
- `--profile <path>`: optional profile path for `operator-human`.
- `--allow-synthetic-profile`: optional test-only flag allowing `source=synthetic` or `source=sample` profiles.
- `--fallback fast-human`: optional explicit fallback for missing, invalid, or source-rejected operator profile.

Success JSON:

```json
{
  "ok": true,
  "command": "click-image",
  "timestamp": "2026-05-26 13:30:01",
  "duration_ms": 900,
  "target": {
    "title": "Agent Test Window",
    "hwnd": "0x123456",
    "pid": 1234
  },
  "data": {
    "match_found": true,
    "x": 68,
    "y": 101,
    "width": 120,
    "height": 36,
    "score": 1.0,
    "match_count": 1,
    "coordinate_space": "window_bitmap",
    "template": "D:\\desktopvisual\\assets\\click_button.bmp",
    "screenshot_path": "D:\\desktopvisual\\artifacts\\click_image_source.bmp",
    "action_method": "mouse_center",
    "target_client_x": 128,
    "target_client_y": 119,
    "move_mode": "human",
    "move_duration_ms": 800
  }
}
```

Failure JSON: unified failure envelope.

Possible `error.code`: `INVALID_ARGUMENT`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `WINDOW_FOCUS_FAILED`, `SAFETY_POLICY_DENIED`, `EMERGENCY_STOP`, `MOTION_PROFILE_NOT_FOUND`, `MOTION_PROFILE_INVALID`, `MOTION_PROFILE_NOT_HUMAN`, `MOTION_PROFILE_SOURCE_REQUIRED`, `MOTION_PROFILE_TEST_ONLY`, `SCREENSHOT_FAILED`, `IMAGE_FILE_NOT_FOUND`, `IMAGE_UNSUPPORTED_FORMAT`, `IMAGE_MATCH_NOT_FOUND`, `IMAGE_MATCH_NOT_UNIQUE`, `IMAGE_MATCH_FAILED`, `CURSOR_MOVE_FAILED`, `SEND_INPUT_FAILED`, `AUDIT_LOG_FAILED`.

Safety limits: calls the image locator first and clicks only after a unique match and title/process safety policy approval. The click uses the existing real mouse input path and target-window client coordinates converted from the match center. No OpenCV or third-party image library is used.

### run-case

Parameters:

- `--file <path>`: required case file path.
- `--report <path>`: required Markdown report output path.

Success JSON:

```json
{
  "ok": true,
  "command": "run-case",
  "timestamp": "2026-05-25 18:40:01",
  "duration_ms": 2000,
  "target": null,
  "data": {
    "case_file": "D:\\desktopvisual\\cases\\basic_click.case",
    "report": "D:\\desktopvisual\\artifacts\\basic_click_report.md",
    "step_count": 13,
    "passed_step_count": 13,
    "failed_step_index": 0
  }
}
```

Failure JSON: unified failure envelope.

Possible `error.code`: `FILE_NOT_FOUND`, `FILE_READ_FAILED`, `CASE_PARSE_FAILED`, `CASE_STEP_LIMIT_EXCEEDED`, `CASE_DURATION_LIMIT_EXCEEDED`, `SAFETY_POLICY_DENIED`, `EMERGENCY_STOP`, `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `WINDOW_FOCUS_FAILED`, `INVALID_ARGUMENT`, `SCREENSHOT_FAILED`, `CURSOR_MOVE_FAILED`, `SEND_INPUT_FAILED`, `ASSERTION_FAILED`, `UNKNOWN_ERROR`, `AUDIT_LOG_FAILED`.

Safety limits: executes only the frozen case commands documented in `D:\desktopvisual\docs\CASE_FORMAT.md`. Case execution loads `D:\desktopvisual\config\safety.conf`, enforces `max_steps`, `max_duration_ms`, window/process whitelists for input actions, and stops on first failure.

### run-task

Runs a v3 task file through the closed-loop task runner.

```powershell
winagent.exe run-task --file <task.json> --report <report.md>
```

Required arguments:

- `--file <path>`: task JSON file.
- `--report <path>`: Markdown task report output.

The task runner performs `observe_before`, `locate`, `act`, `observe_after`, expectation verification, failure classification, and bounded recovery where permitted by the task budget. Input actions still require the same SafetyPolicy checks and focus-verified input paths as direct CLI actions. Recovery never guesses coordinates or broadens the target window title.

Success JSON:

```json
{
  "ok": true,
  "command": "run-task",
  "data": {
    "task": "testwindow_basic",
    "ok": true,
    "steps": 3,
    "passed": 3,
    "recoveries": 0,
    "duration_ms": 125,
    "report": "D:\\desktopvisual\\artifacts\\mvp_testwindow_report.md"
  }
}
```

Failure JSON uses the unified failure envelope. Primary error codes include `WINDOW_NOT_FOUND`, `WINDOW_NOT_UNIQUE`, `WINDOW_FOCUS_FAILED`, `SAFETY_POLICY_DENIED`, `LOCATOR_NOT_FOUND`, `LOCATOR_NOT_UNIQUE`, `OCR_UNAVAILABLE`, `OCR_FAILED`, `ACTION_FAILED`, `EXPECT_FAILED`, `TIMEOUT`, and `UNKNOWN_ERROR`.

### motion-record

Parameters:

- `--title <substring>`: required target window title substring, usually `Motion Lab`.
- `--scenario <name>`: required scenario label such as `horizontal_lr` or `drag_line`.
- `--duration-ms <int>`: required recording duration.
- `--out <path>`: required raw trajectory JSON path under an allowed write root.

This command records mouse trajectory points only. It does not move the cursor, click, type, read window contents, or record keyboard text. Each point includes screen/client coordinates, timestamp, and button state. `F12` stops recording with `EMERGENCY_STOPPED`.

Success `data` includes `scenario`, `sample_id`, `point_count`, `duration_ms`, `distance_px`, `bounding_box`, and `out_path`.

### motion-calibrate

Parameters:

- `--source human|synthetic|sample`: required profile source. Human calibration scripts pass `human`; selftests pass `synthetic`.
- `--input <dir>`: directory containing raw motion JSON samples.
- `--out <path>`: profile output path, normally `D:\desktopvisual\config\operator_motion_profile.json` for human profiles or `D:\desktopvisual\artifacts\motion_profile\synthetic\operator_motion_profile.synthetic.json` for tests.

Reads raw trajectory files and writes aggregate operator statistics plus explicit `source`, `device_context`, and `privacy` metadata. It does not store full raw traces in the profile. Omitting `--source` returns `MOTION_PROFILE_SOURCE_REQUIRED`; fewer than 12 valid raw samples returns `MOTION_PROFILE_INSUFFICIENT_SAMPLES`; 12/32/64 samples produce `low`/`usable`/`good` quality.

### motion-profile-info

Parameters:

- `--profile <path>`: optional profile path. Defaults to `D:\desktopvisual\config\operator_motion_profile.json`.

Returns `exists`, `version`, `profile_id`, `source`, `created_at`, `created_by`, `sample_count`, `scenario_count`, `quality`, `device_context`, `privacy`, `direction_coverage`, `distance_coverage`, `supported_modes`, and `warnings`.

### motion-profile-validate

Parameters:

- `--profile <path>`: optional profile path.
- `--out <path>`: required Markdown validation report path.

Synthesizes sample paths from the profile and checks final target accuracy, duration range, bounded screen coordinates, non-perfect-line curvature, and non-perfect-linear timing. The JSON result and Markdown report include `source`. Invalid profiles return `MOTION_PROFILE_INVALID`.

### motion-profile-clear

Parameters:

- `--profile <path>`: optional profile path.

Deletes the profile only after the path passes `allowed_write_roots`. Success `data` includes `profile`, `existed`, and `deleted`.

### operator-human move-mode

`operator-human` is accepted by `click`, `double-click`, `right-click`, `scroll`, `drag`, `click-image`, `click-text`, `act`, and task.json act steps through `move_mode`. Mouse `human` is an alias for `operator-human` and is the default when no move mode is supplied. It reads `config\operator_motion_profile.json` by default and requires `source=human`. Missing, invalid, missing-source, or non-human profiles fail with `MOTION_PROFILE_NOT_FOUND`, `MOTION_PROFILE_INVALID`, `MOTION_PROFILE_SOURCE_REQUIRED`, `MOTION_PROFILE_NOT_HUMAN`, or `MOTION_PROFILE_TEST_ONLY` and do not silently fall back. Synthetic/sample profiles are test-only and require both an explicit profile path and `--allow-synthetic-profile` on CLI actions, or `"profile"` plus `"allow_synthetic_profile": true` in task.json. The only explicit fallback is `--fallback fast-human` on CLI actions or `"fallback": "fast-human"` in task.json act steps. Successful mouse action JSON adds `operator_profile_path`, `operator_profile_quality`, `operator_profile_source`, and `synthesized_point_count` while preserving final coordinate accuracy, focus verification, SafetyPolicy checks, F12 interruption, and audit logging.

## Agent Contract Summary

v3.0.3 introduces agent-agnostic adapters. The generic CLI adapter defines these contract commands:

- `version`
- `observe`
- `locate`
- `act`
- `run-case`
- `run-task`
- `read-report`

The normalized adapter return shape is:

```json
{
  "ok": true,
  "error_code": "",
  "data": {},
  "artifacts": [],
  "report_path": ""
}
```

Adapters must use `observe-locate-act-verify`, safety stop rules, no unrestricted desktop control, and no sensitive flows. `version` output includes `data.project_root` so adapters can confirm which portable root is active.

## Benchmark Evidence

v3.0.4 adds benchmark reports outside the frozen CLI envelope. `benchmark_matrix.ps1` writes:

```text
artifacts\benchmark\benchmark_report.md
artifacts\benchmark\benchmark_summary.json
```

`benchmark_summary.json` includes version, timestamp, machine summary, Windows version, OCR/operator profile availability, PASS/FAIL/SKIPPED counts, pass rate excluding skipped, average duration, locator method counts, failure category counts, skipped reason counts, recovery metrics, report completeness, and artifact paths.

## DesktopVisual Service API

`winagent.exe serve --host 127.0.0.1 --port 17873 --token <optional> --max-session-ms <int>` starts an explicit local service wrapper around existing commands. The current implementation uses a local named pipe (`\\.\pipe\DesktopVisualService`) while keeping the documented endpoint abstraction stable.

Defaults:

- `host=127.0.0.1`
- `port=17873` (documented API port; named-pipe transport currently ignores it)
- `max-session-ms=3600000`

If no token is provided, the service is local-only and prints a warning. If a token is provided, requests must include the same token. Service requests do not bypass SafetyPolicy, required `--title`, focus verification, allowed read roots, or audit logging.

Supported endpoints:

- `GET /version`
- `GET /safety-report`
- `POST /policy-check`
- `POST /consent-check`
- `POST /observe`
- `POST /locate`
- `POST /act`
- `POST /run-case`
- `POST /run-task`
- `GET /report?path=...`
- `POST /shutdown`

The service maintains `session_id`, `start_time`, `last_target_title`, `last_observe_summary`, `request_count`, `action_count`, and `error_count`. Every request is appended to `D:\desktopvisual\artifacts\service_audit.log` with timestamp, endpoint, title, ok, error_code, duration_ms, and session_id.

## Safety Policy

`D:\desktopvisual\config\safety.conf` is a project-local key/value file:

```text
allowed_titles=Agent Test Window;Untitled - Notepad
allowed_processes=TestWindow.exe;notepad.exe
allowed_read_roots=D:\desktopvisual;D:\testrepo\testwindow
allowed_write_roots=D:\desktopvisual;D:\testrepo\testwindow
max_steps=100
max_duration_ms=120000
emergency_stop_key=F12
allow_absolute_screen_click=false
```

`D:\desktopvisual\config\safety_manifest.json` is the machine-readable Safety Manifest. It is merged with `safety.conf` and cannot loosen `safety.conf` hard limits. It adds denied sensitive categories, consent settings, runtime limits, and audit settings. `version` reports `manifest_loaded`, `safety-report` writes machine-readable and Markdown reports, and `policy-check`/`consent-check` expose dry-run decisions.

The input commands `act`, `click`, `double-click`, `right-click`, `scroll`, `drag`, `press`, `hotkey`, `type`, `clipboard-paste`, `focus`, `uia-click`, `uia-type`, `click-text`, and `click-image` must pass the configured title and process whitelist plus manifest denied-category checks. Real input paths must verify that `GetForegroundWindow()` equals the target HWND after `SetForegroundWindow`/`ShowWindow`; failure returns `WINDOW_FOCUS_FAILED`. `read-file`, `read_file`, and `assert_file_contains` must pass `allowed_read_roots` after path normalization. `allowed_write_roots` documents the approved project output roots. If the config is missing, actions still require explicit `--title` and do not switch to unrestricted desktop control. `allow_absolute_screen_click=false` documents that no absolute full-screen click command exists.

## Audit Log

Each audit line uses this frozen text format:

```text
timestamp="2026-05-25 18:40:01" command="click" target_title="Agent Test Window" result="ok" error_code="" duration_ms=1012 data="..."
```

Fields are always present in this order: `timestamp`, `command`, `target_title`, `result`, `error_code`, `duration_ms`, `data`.

## Case Reports

`run-case` writes Markdown reports with:

- `# WinDesktopAgent Case Report`
- case metadata bullets
- `## Artifacts`
- `## Steps`
- a step table containing `index`, `action`, `params`, `start_time`, `end_time`, `duration_ms`, `result`, `error_code`, `message`, and `json_output`
- optional `## Read State`

## Compatibility Boundary

v3.0.5 is a Windows Agent Desktop Runtime, not official Codex built-in Computer Use. It provides authorized-window observe, locate, act, verify, Case v2, real OCR when available, dogfood scripts, explicit service mode, bounded task recovery, local operator motion personalization, portable root resolution, agent adapters, benchmark evidence reporting, and a machine-readable Safety Manifest/consent layer. It still does not provide unrestricted desktop control, MCP, automatic Skill installation, protected-desktop/admin-window control, autonomous decision-making, or detection-bypass automation.
