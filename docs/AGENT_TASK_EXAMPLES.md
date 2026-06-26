# Agent Task Examples

These examples show the expected DesktopVisual workflow for agents. Start with `version`, use `observe`, choose the highest-priority selector, act through reviewed commands or task files, observe again, and stop on any error.

## TestWindow

```powershell
D:\desktopvisual\bin\winagent.exe version
D:\desktopvisual\bin\winagent.exe observe --title "Agent Test Window"
D:\desktopvisual\bin\winagent.exe locate --title "Agent Test Window" --selector "uia:name=Click Me,type=Button"
D:\desktopvisual\bin\winagent.exe act --title "Agent Test Window" --selector "uia:name=Click Me,type=Button" --action click
D:\desktopvisual\bin\winagent.exe observe --title "Agent Test Window"
```

Preferred v3 task:

```powershell
D:\desktopvisual\bin\winagent.exe run-task --file D:\desktopvisual\tasks\testwindow_basic.task.json --report D:\desktopvisual\artifacts\mvp_testwindow_report.md
```

## Notepad

Use only a new temporary file under `D:\desktopvisual\artifacts`. If an existing Notepad process or user file is open, stop or mark the task SKIPPED.

```powershell
$file = "D:\desktopvisual\artifacts\notepad_output.txt"
"" | Set-Content $file
Start-Process notepad.exe -ArgumentList "`"$file`""
D:\desktopvisual\bin\winagent.exe observe --title "Notepad"
D:\desktopvisual\bin\winagent.exe type --title "Notepad" --text "Hello from DesktopVisual"
D:\desktopvisual\bin\winagent.exe hotkey --title "Notepad" --keys CTRL+S
D:\desktopvisual\bin\winagent.exe read-file --path $file
```

## Calculator

Calculator varies by Windows version and language. Prefer UIA, then OCR. If neither can verify the result, mark SKIPPED rather than guessing coordinates.

```powershell
Start-Process calc.exe
D:\desktopvisual\bin\winagent.exe observe --title "Calculator"
D:\desktopvisual\bin\winagent.exe type --title "Calculator" --text "12+30"
D:\desktopvisual\bin\winagent.exe press --title "Calculator" --key ENTER
D:\desktopvisual\bin\winagent.exe read-window-text --title "Calculator"
```

Expected result: text or UIA state contains `42`.

## Dogfood Matrix

```powershell
D:\desktopvisual\dogfood_matrix.ps1
Get-Content D:\desktopvisual\artifacts\dogfood_matrix_report.md
```

`SKIPPED` is acceptable for missing apps or existing user windows. `FAIL` must be reported with the reason and artifacts.

## OCR_UNAVAILABLE

Before using `text:` selectors, check:

```powershell
D:\desktopvisual\bin\winagent.exe version
```

If `data.ocr_available=false`, do not use text selectors. Try UIA. If UIA cannot locate the target, stop and explain that OCR is unavailable; do not click approximate coordinates.

## WINDOW_NOT_UNIQUE

If observe or locate returns `WINDOW_NOT_UNIQUE`, run:

```powershell
D:\desktopvisual\bin\winagent.exe windows
```

Report the matching titles and ask the user for a more precise title. Do not choose the first match automatically.

## Golden Loop

```text
version -> observe -> locate -> act -> observe -> verify -> report
```

For complex tasks:

```text
version -> observe -> generate reviewed task.json -> run-task -> read report -> summarize
```
