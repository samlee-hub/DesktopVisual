# DesktopVisual Launch Contract

Current version: `v1.1.12`.

This is the authoritative launch contract for all DesktopVisual app, browser, software, `.lnk`, `.url`, and desktop shortcut startup workflows. `visible-app-launch`, adapter launch helpers, field-test runners, and manual command templates must follow this contract.

## Required Launch Layers

Layer 1 is always desktop icon double-click first.

- If the desktop icon or desktop shortcut is visible, the runtime must move the real mouse to that icon and double-click it.
- Desktop icon locate may use UIA, visual target evidence, or OCR-assisted evidence, but the launch action remains visible mouse double-click.
- `visible-app-launch` and any generic app-launch helper cannot override desktop icon first.
- Start Menu search is not the first choice when a desktop icon exists.
- Backend launch is never the default startup path.

Layer 2 is keyboard or Start Menu fallback only after Layer 1 fails.

- Layer 2 requires explicit evidence that Layer 1 was attempted or unavailable.
- Valid evidence includes two failed `desktop-icon-locate` attempts, a desktop icon double-click that did not produce the target window, or a target-window verification failure after the desktop double-click.
- If the desktop icon was located successfully, Layer 2 is allowed only after the desktop icon double-click was attempted and failed to verify the target window.

Layer 3 is backend fallback only after Layer 1 and Layer 2 both fail.

- Layer 3 requires explicit evidence for the Layer 1 failure and the Layer 2 failure.
- Backend launch cannot be selected by default and cannot be used to skip visible launch paths.
- Direct file write fallback and clipboard paste are not startup defaults.

Any fallback must record:

- `fallback_layer`
- `fallback_reason`
- `fallback_evidence`
- `allowed_by_contract`

Skipping a required earlier layer without evidence is a `launch_contract_violation`.

## Runtime Evidence Fields

Launch commands must emit or record these fields:

- `launch_contract_version`
- `launch_target`
- `desktop_icon_visible`
- `desktop_icon_locate_attempts`
- `desktop_icon_double_click_attempted`
- `desktop_icon_double_click_result`
- `keyboard_or_start_menu_fallback_attempted`
- `keyboard_or_start_menu_fallback_reason`
- `backend_fallback_attempted`
- `backend_fallback_reason`
- `final_launch_layer`
- `fallback_evidence`
- `allowed_by_contract`
- `launch_contract_violation`
- `priority_violation`

If `desktop_icon_visible=true` and the command directly enters Start Menu or backend launch without `desktop_icon_double_click_attempted=true`, the command must return or record `launch_contract_violation=true`.

## Safe CLI Discovery

Visible/action subcommands are non-executing for help discovery.

- `--help`, `-h`, or `/?` anywhere after a visible/action subcommand must return help or `NON_EXECUTING_HELP`.
- No desktop action may occur during visible/action help discovery.
- Bare `--dry-run` is invalid for visible/action subcommands and must return `INVALID_ARGUMENT_NON_EXECUTING`.
- Bare `--dry-run` must not move the mouse, click, show desktop, open an app, switch windows, or type text.
- Valid explicit dry-run, when supported, is `--dry-run true` or `--dry-run false`.
- Field-test runners must not probe visible subcommands with `--help`; they must use `winagent.exe help`, `COMMAND_PROTOCOL.md`, approved scripts, or fixed command templates.

## Visual Studio Startup Contract

Visual Studio IDE startup is stricter than generic app launch.

Default VS startup path:

1. `visible-show-desktop`
2. `desktop-icon-locate --target "Visual Studio"`
3. Move the real mouse to the located desktop icon.
4. Double-click the icon.
5. Wait for `devenv.exe` or a Microsoft Visual Studio main window.
6. Exclude Visual Studio Installer.
7. Verify exactly one VS IDE main window.
8. Only then allow project creation or code input.

Hard rules:

- Visual Studio Installer is not Visual Studio IDE.
- VS target lock must not lock Installer.
- Multiple VS or `devenv.exe` windows return `WINDOW_NOT_UNIQUE` or `TARGET_NOT_UNIQUE`.
- Code input and project creation are blocked until a unique VS IDE main window is verified.
- If Installer appears, close it only by a visible reviewed recovery action; if safe closure is unclear, stop.
- VS field-test templates must not use generic `visible-app-launch --target "Visual Studio"` as their default path unless that command internally follows the VS desktop-icon path and emits the launch contract fields.

## Adapter Contract

Adapters must reference this document for current startup behavior. Historical rules may remain in archived evidence, but they cannot override this contract.
