# DesktopVisual Public Agent Rules

Use DesktopVisual only for authorized local Windows GUI workflows.

Before any GUI input:

1. Run `bin\winagent.exe version`.
2. Run `bin\winagent.exe safety-report` for policy visibility.
3. Identify one explicit target window.
4. Prefer visible observation and target-locked actions.
5. Stop on any non-empty error code.

Do not automate credentials, payments, banking, protected desktops, elevated windows, CAPTCHA, human verification, proctoring, anti-cheat, anti-automation bypass, platform abuse, or unauthorized third-party workflows.

DesktopVisual is not a universal autonomous developer. Complex workflows require concrete goals, allowed applications, allowed files, expected outputs, and user review.