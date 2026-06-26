# Case Format

Current version: `v1.5.0`.

Protocol status: frozen for v0.1.6. Case v2 added in v1.5.0.

Case files are UTF-8 text files with one command per line. Empty lines and lines whose first character is `#` are ignored. Case execution stops on the first failed step. The maximum step count and runtime are controlled by `D:\desktopvisual\config\safety.conf`.

## Case v2 Format (v1.5.0+)

Enable by adding `case_version=2` as the first non-comment line:

```text
case_version=2
```

### Syntax

All commands use `key=value` parameter syntax. Values may be unquoted (no spaces) or quoted with `"..."` for spaces and escapes.

Quoted string escapes: `\"` (literal quote), `\\` (literal backslash), `\n` (newline).

Comments: lines starting with `#` are ignored.

Variables:
```text
set name="btn" value="uia:name=Click Me"
act selector="${btn}" action="click"
```

### Commands

**target_title** -Set target window:
```text
target_title="Agent Test Window"
```

**set** -Define variable:
```text
set name="var" value="value"
```

**wait** -Sleep milliseconds:
```text
wait ms=300
```

**wait_until** -Poll until condition met or timeout:
```text
wait_until selector="uia:name=Click Me" timeout_ms=5000
wait_until file_contains path="D:\desktopvisual\artifacts\state.txt" text="clicked=true" timeout_ms=5000
wait_until window_title_contains="Notepad" timeout_ms=5000
```

**expect** -Assert condition (fails with ASSERTION_FAILED):
```text
expect selector_exists="uia:name=Click Me"
expect file_contains path="..." text="..."
expect active_window_title_contains="Agent Test Window"
```

**act** -Locate and perform action with optional post-verification:
```text
act selector="uia:name=Click Me" action="click"
act selector="uia:type=Edit,index=0" action="type" text="hello world"
act selector="uia:name=Click Me" action="click" expect_selector_exists="uia:name=Click Me"
act selector="uia:name=Click Me" action="click" expect_file_contains_path="D:\testrepo\testwindow\runtime\state.txt" expect_file_contains_text="clicks="
```

**locate** -Resolve selector without action:
```text
locate selector="uia:name=Click Me"
```

**click / double_click / right_click** -Mouse click at client coordinates:
```text
click x=80 y=90
double_click x=80 y=90 move_mode="demo-human" move_duration_ms=800
```

**scroll / drag** -Scroll and drag:
```text
scroll x=90 y=150 delta=-120
drag from_x=120 from_y=160 to_x=180 to_y=160
```

**press / hotkey / type** -Keyboard input:
```text
press key="SPACE"
hotkey keys="CTRL+A"
type text="hello world"
type selector="uia:type=Edit,index=0" text="hello world"
```

**focus** -Focus target window:
```text
focus
```

**clipboard_set / clipboard_paste** -Clipboard operations:
```text
clipboard_set text="hello"
clipboard_paste text="hello"
```

**screenshot** -Capture window screenshot:
```text
screenshot out="D:\desktopvisual\artifacts\before.bmp"
```

**observe** -Observe window state:
```text
observe out="D:\desktopvisual\artifacts\observe_data.json"
```

**read_file / assert_file_contains** -File operations:
```text
read_file path="D:\testrepo\testwindow\runtime\state.txt"
assert_file_contains path="D:\testrepo\testwindow\runtime\state.txt" text="clicks="
```

### Report Enhancements

Case v2 reports include additional sections:
- `case_version` field (2 for v2 cases)
- `## Variables` table
- `## Wait Results` table
- `## Expect Results` table
- `## Observation Before` / `## Observation After` (when populated)

## Case v1 Format (v0.1.6+, backward compatible)

Cases without `case_version=2` use the v1 format below.

Set target window title:

```text
target_title=Agent Test Window
```

Capture target window screenshot:

```text
screenshot D:\desktopvisual\artifacts\before.bmp
```

Observe target window state:

```text
observe
observe D:\desktopvisual\artifacts\observe_case_data.json
```

`observe` captures read-only target metadata, active-window metadata, focus status, mouse position, screenshot, UIA summary, safety summary, and warnings. If an output JSON path is provided, the observation data is written there. Case reports include a `## Observations` section.

Locate with a selector:

```text
locate uia:name=Click Me
locate coord:x=80,y=90
```

Act through a selector:

```text
act uia:name=Click Me click
act uia:type=Edit,index=0 type hello
act coord:x=80,y=90 click
```

Selector priority for agent-authored cases should be UIA first, then text, then image, then coordinates.

Instant click at target-window client coordinates:

```text
click 80 90
```

Human-visible click at target-window client coordinates:

```text
click 80 90 demo-human 900
```

Additional mouse primitives:

```text
double_click 80 90 fast-human
right_click 90 150 human
scroll 90 150 -120 fast-human
drag 120 160 180 160 fast-human 300
```

Press a supported key:

```text
press SPACE
```

Send a supported hotkey combination:

```text
hotkey CTRL+S
```

Instant text input:

```text
type hello
```

Human-visible text input:

```text
type hello demo-human 120
```

Clipboard actions:

```text
clipboard_set hello clipboard text
clipboard_paste pasted text
```

`clipboard_set` and `clipboard_paste` read the rest of the line after the command as text. Other text commands keep the v1 word-based limitation.

Focus the target window:

```text
focus
```

Wait for a bounded number of milliseconds:

```text
wait 300
```

Read a text file into the report:

```text
read_file D:\testrepo\testwindow\runtime\state.txt
```

Assert that a file contains text:

```text
assert_file_contains D:\testrepo\testwindow\runtime\state.txt last_text=hello
```

Click a UI Automation element by name:

```text
uia_click Click Me
```

Type into a UI Automation element by name:

```text
uia_type Input hello
```

## Supported Keys

`press` supports single letters `A`-`Z`, single digits `0`-`9`, `SPACE`, `ENTER`, `ESC`, `TAB`, `LEFT`, `RIGHT`, `UP`, and `DOWN`.

`hotkey` supports `CTRL`, `SHIFT`, `ALT`, `WIN`, `A`-`Z`, `0`-`9`, `ENTER`, `ESC`, `TAB`, `SPACE`, `LEFT`, `RIGHT`, `UP`, `DOWN`, and `F1`-`F12`, joined with `+`.

## Motion Modes

Mouse actions accept `human`, `operator-human`, `instant`, `fast-human`, and `demo-human`. If omitted, the default is `human`, which maps to `operator-human` and requires a valid local `source=human` profile. Use `instant` in reviewed automated tests that do not need calibrated movement.

## Limits

1. Text with spaces is not supported.
2. Variables are not supported.
3. Conditional branches are not supported.
4. Loops are not supported.
5. Automatic recovery is not supported.
6. Case commands cannot save files in real applications unless a future case explicitly does so and the user approves that behavior.
7. Coordinates are target-window client coordinates.
8. The target title must resolve to exactly one visible top-level window before input actions run.
9. `uia_click` treats all text after the command as the UIA element name, so names with spaces such as `Click Me` are supported.
10. `uia_type` currently supports `uia_type name text`; the element name and typed text cannot contain spaces.
11. Input actions must pass the safety policy title/process whitelist.
12. `run-case` stops when `max_steps`, `max_duration_ms`, or the F12 emergency stop boundary is reached.

