# DesktopVisual Public Command Protocol

DesktopVisual 1.0.0 exposes a local Windows CLI through `bin/winagent.exe`.

## Basic commands

```powershell
.\bin\winagent.exe version
.\bin\winagent.exe help
.\bin\winagent.exe safety-report
```

## Visible-first input model

Input commands require an explicit target title and must resolve to a single visible top-level window. Commands use user-level Windows input and record structured JSON output.

Supported public concepts include:

- visible target discovery
- global screenshot capture
- target-window lock
- screenshot-to-screen coordinate mapping
- foreground preparation
- real mouse actions
- real keyboard actions
- structured visible text input
- bounded fallback reporting

## Fallback boundary

Fallbacks are explicit. Agents must not guess coordinates, broaden window titles, switch locator strategy, or continue after an error without user authorization.

## Safety stop examples

Stop on ambiguous windows, missing windows, failed locators, denied safety policy, protected desktops, credential prompts, CAPTCHA or human-verification challenges, anti-cheat or anti-automation systems, proctoring, payment flows, and unclear authorization.