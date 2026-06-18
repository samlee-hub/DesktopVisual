---
name: desktopvisual-visible-ui-first
description: Prefer DesktopVisual visible UI automation for desktop tasks, with keyboard shortcuts as fallback and backend operation as last resort.
version: 1.0.0-public-rc3
---

# DesktopVisual Visible-UI-First Skill

## Purpose

Use DesktopVisual for Windows desktop automation when the user requests desktop control, visible app operation, mouse/keyboard interaction, browser/page operation, file window operation, form filling, or explicitly mentions DesktopVisual.

Priority order:

1. Visible UI operation with mouse, keyboard, wheel, and normal user-like interaction.
2. Keyboard shortcut fallback when visible mouse/UI interaction cannot continue reliably.
3. Backend/non-UI operation only when the visible window is unusable or the user explicitly asks for backend work.

## Trigger Conditions

Use this skill when the user asks or implies:

* DesktopVisual
* desktop automation
* visible UI automation
* operate the current window
* use mouse and keyboard
* open an app
* click/type/search/send
* operate a browser page
* fill a form
* operate File Explorer
* simulate normal user operation
* 桌面操控
* 鼠标键盘操作
* 打开软件
* 点击、输入、搜索、发送
* 操作浏览器或网页
* 填写表单
* 文件窗口操作
* 像真人一样操作电脑

Do not use this skill for pure explanation, code review, writing, or static analysis unless the user asks to operate the desktop UI.

## Runtime Discovery

For a downloaded public release package, discover DesktopVisual runtime in this order:

1. .\bin\winagent.exe from the current package root.
2. bin\winagent.exe relative to the working directory.
3. %DESKTOPVISUAL_HOME%\bin\winagent.exe if DESKTOPVISUAL_HOME is set.
4. winagent.exe from PATH.
5. A user-provided runtime path.

Run a lightweight check:

```powershell
.\bin\winagent.exe version
```

If the runtime is unavailable, report the checked paths and stop.

Do not use developer-private paths in public release instructions.

## Operation Priority

Visible UI first:

* move mouse
* click
* double-click
* drag
* scroll with wheel
* type text
* press keys
* inspect visible UI
* verify after each meaningful action

Keyboard shortcut fallback second:

* Ctrl+L
* Ctrl+F
* Ctrl+C / Ctrl+V
* Ctrl+A
* Alt+Tab
* Tab / Shift+Tab
* Enter / Esc
* Ctrl+S
* F5 / Ctrl+R

Use shortcut fallback only when visible UI interaction is unavailable or unreliable.

Backend operation last:

Use backend/non-UI operation only when:

* the visible window is frozen
* the visible window cannot be focused
* controls are invisible or unreachable
* visible UI interaction repeatedly fails
* target cannot be located after reasonable visible UI attempts
* the user explicitly asks for backend/non-UI work

Backend operation must not replace visible UI operation when the visible UI is available.

## Safety Boundaries

Do not bypass:

* CAPTCHA
* human verification
* account security verification
* username/password/verification-code handoff
* active proctoring
* lockdown browser
* anti-cheat
* anti-automation tools
* third-party automation interception
* explicit security/risk verification

Stop and report the reason.

## Public Release Safety Policy

Do not stop merely because the page contains words such as:

* test
* exam
* quiz
* 考试
* 测试
* 练习
* OJ
* LeetCode

Stop only when explicit restricted-assistance or exam-integrity rules are present, such as:

* 禁止作弊
* 禁止外部辅助
* 禁止 AI 辅助
* 禁止自动化
* proctored exam
* lockdown browser
* no cheating
* external assistance prohibited
* third-party tools prohibited

Use stop code:

STOP_PUBLIC_RELEASE_EXAM_INTEGRITY_POLICY

## F12 User Abort

If F12 is detected:

* stop the current task
* do not terminate the agent process
* do not continue mouse/keyboard actions
* report STOP_USER_FORCE_EXIT_F12

## Verification

Do not claim success from raw execution alone.

Use visible UI state, OCR/UIA observation, command result, evidence, screenshot comparison, or expected visible target to verify the result.

If only raw execution completed:

RAW_COMPLETED_UNVERIFIED

must not be reported as PASS.

## Reporting Format

Report:

mode_used: visible_ui | keyboard_shortcut_fallback | backend_fallback
desktopvisual_runtime: <path>
result: PASS | BLOCKED | STOPPED | RAW_COMPLETED_UNVERIFIED | FAILED
fallback_used: true/false
fallback_reason: <reason if any>
safety_stop: true/false
f12_abort: true/false
evidence_summary: <brief evidence>
