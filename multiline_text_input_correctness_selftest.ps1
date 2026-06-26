param([string]$Root = '')

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.12.1_visible_ui_foundation_hardening'
$Report = Join-Path $OutDir 'multiline_text_input_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Fail([string]$Message) { throw $Message }
function Assert($Condition, [string]$Message) { if (-not $Condition) { Fail $Message } }

function Invoke-Agent {
    param([string[]]$WinArgs, [int[]]$Allowed = @(0))
    $output = & $WinAgent @WinArgs
    $exit = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    if ($Allowed -notcontains $exit) {
        Fail "winagent $($WinArgs -join ' ') exited $exit with output: $text"
    }
    try { return $text | ConvertFrom-Json } catch { Fail "Invalid JSON: $text" }
}

if (-not (Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run $Root\build.ps1 first." }

function Invoke-VisibleTextDryRun([string]$Text, [string]$Method) {
    Invoke-Agent -WinArgs @(
        'visible-text-input',
        '--text', $Text,
        '--input-kind', 'multiline_body',
        '--input-method', $Method,
        '--target-title', 'dry-run-target',
        '--require-target-lock', 'true',
        '--dry-run', 'true',
        '--allow-dry-run-target', 'true'
    )
}

$lf = Invoke-VisibleTextDryRun -Text "line1`nline2`nline3" -Method 'line_by_line_keyboard'
Assert ($lf.ok -eq $true) 'line_by_line_keyboard LF dry-run should pass.'
Assert ($lf.data.input_method -eq 'line_by_line_keyboard') 'input method should be line_by_line_keyboard.'
Assert ([int]$lf.data.typed_line_count -eq 3) 'line1\nline2\nline3 must be counted as three lines.'
Assert ([int]$lf.data.enter_key_event_count -eq 2) 'Two LF separators must produce two Enter key events.'
Assert ([int]$lf.data.lf_newline_count -eq 2) 'LF separator count mismatch.'
Assert ($lf.data.newline_as_unicode -eq $false) 'Newline must not be sent as Unicode text.'
Assert ($lf.data.first_pass_multiline_correct -eq $true) 'First-pass multiline evidence must be true.'
Assert ($lf.data.code_collapsed_to_single_line -eq $false) 'Text must not collapse to one line.'

$crlf = Invoke-VisibleTextDryRun -Text "line1`r`nline2" -Method 'line_by_line_keyboard'
Assert ($crlf.ok -eq $true) 'CRLF dry-run should pass.'
Assert ([int]$crlf.data.typed_line_count -eq 2) 'line1\r\nline2 must be counted as two lines.'
Assert ([int]$crlf.data.enter_key_event_count -eq 1) 'CRLF must produce exactly one Enter key event.'
Assert ([int]$crlf.data.crlf_newline_count -eq 1) 'CRLF pair count mismatch.'
Assert ($crlf.data.newline_as_unicode -eq $false) 'CRLF must not be sent as Unicode text.'

$tab = Invoke-VisibleTextDryRun -Text "line1`n`tindented" -Method 'line_by_line_keyboard'
Assert ($tab.ok -eq $true) 'Tab dry-run should pass.'
Assert ([int]$tab.data.tab_key_event_count -eq 1) 'Tab must produce one Tab key event.'
Assert ($tab.data.tab_as_unicode -eq $false) 'Tab must not be sent as a Unicode character.'
Assert ($tab.data.clipboard_used -eq $false) 'Clipboard must not be used.'
Assert ($tab.data.backend_file_write_used -eq $false) 'Backend file write must not be used.'

@(
    '# Multiline Text Input Correctness Selftest',
    '',
    '- result: PASS',
    '- line1\nline2\nline3 first_pass_multiline_correct: true',
    '- line1\r\nline2 enter_key_event_count: 1',
    '- tab_key_event_count: 1',
    '- newline_as_unicode: false',
    '- tab_as_unicode: false',
    '- clipboard_used: false',
    '- backend_file_write_used: false'
) | Set-Content -Encoding UTF8 -LiteralPath $Report

Write-Host 'PASS multiline_text_input_correctness_selftest'
exit 0
