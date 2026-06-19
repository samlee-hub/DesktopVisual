---
name: desktopvisual-visible-ui-first
description: Use for authorized Windows desktop GUI tasks with the DesktopVisual public binary. Prefer visible-first observation, target-window lock, global screenshots, real mouse and keyboard input, and explicit fallback boundaries. Stop on errors and safety denials.
---

# DesktopVisual Visible UI First

Use DesktopVisual only for authorized local Windows desktop workflows.

## Startup

1. Run `bin\winagent.exe version`.
2. Run `bin\winagent.exe safety-report` when input is involved.
3. Identify exactly one visible target window.
4. Use visible observation before input.
5. Use target-locked real mouse and keyboard actions.

## Boundaries

- Stop on missing or ambiguous windows.
- Stop on locator failures.
- Stop on safety denials.
- Do not guess coordinates.
- Do not broaden target titles without user approval.
- Do not automate credentials, protected desktops, CAPTCHA, proctoring, anti-cheat, payment, banking, or unauthorized workflows.

## Fallback

Fallbacks must be explicit, bounded, and reported. Clipboard or backend writes are not part of the accepted visible input path.