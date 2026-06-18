# DesktopVisual Public Release Agent Instructions

When an agent or coding assistant works inside this package, it must read:

skills/desktopvisual-visible-ui-first/SKILL.md

before attempting any user-requested desktop automation task.

For user requests involving DesktopVisual, desktop automation, visible app operation, mouse/keyboard control, browser/page operation, form filling, or file window operation, follow this priority order:

1. Use DesktopVisual visible UI operation first.
2. Use keyboard shortcut fallback only when visible UI operation cannot continue reliably.
3. Use backend/non-UI operation only when the visible window is unusable or the user explicitly asks for backend work.

Do not use backend operations to replace visible UI operation when visible UI is available.

Respect F12 current-task force exit.

Respect the public release safety policy.

Do not bypass CAPTCHA, human verification, account security verification, active proctoring, lockdown browser, anti-cheat, anti-automation tools, or explicit security/risk verification.

Do not treat RAW_COMPLETED_UNVERIFIED as PASS.
