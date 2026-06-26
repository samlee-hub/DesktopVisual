param([string]$Root = '')

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.12.1_visible_ui_foundation_hardening'
$Report = Join-Path $OutDir 'pycharm_real_workflow_report.md'
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

$project = Join-Path $OutDir 'pycharm_sanity'
$demo = Invoke-Agent -WinArgs @(
    'pycharm-visible-demo',
    '--project', $project,
    '--file', 'main.py',
    '--code-profile', 'two-class-demo',
    '--dry-run', 'true'
)

Assert ($demo.ok -eq $true) 'pycharm-visible-demo dry-run should pass.'
Assert ($demo.data.backend_launch_used -eq $false) 'backend_launch_used must be false.'
Assert ($demo.data.launch_app_path_used -eq $false) 'launch_app_path_used must be false.'
Assert ($demo.data.input_method -in @('real_keyboard_events', 'code_editor_keyboard')) 'input method must be keyboard based.'
Assert ($demo.data.clipboard_used -eq $false) 'clipboard_used must be false.'
Assert ($demo.data.backend_file_write_used -eq $false) 'backend_file_write_used must be false.'
Assert ($demo.data.first_pass_multiline_correct -eq $true) 'first_pass_multiline_correct must be true.'
Assert ($demo.data.code_collapsed_to_single_line -eq $false) 'code must not collapse to one line.'
Assert ($demo.data.selfself_autocomplete_artifact -eq $false) 'selfself artifact must be false.'
Assert ($demo.data.global_dpi_aware_final_screenshot -eq $true) 'global DPI-aware final screenshot evidence must be true.'
Assert ($demo.data.output_verified -eq $true) 'output_verified must be true.'
Assert ($demo.data.operation_interval_budget_pass -eq $true) 'operation interval budget must pass.'

@(
    '# PyCharm First-Pass Multiline Input Selftest',
    '',
    '- result: PASS_DRY_RUN_VISIBLE_PATH',
    "- input_method: $($demo.data.input_method)",
    '- backend_launch_used: false',
    '- launch_app_path_used: false',
    '- clipboard_used: false',
    '- backend_file_write_used: false',
    '- first_pass_multiline_correct: true',
    '- code_collapsed_to_single_line: false',
    '- selfself_autocomplete_artifact: false',
    '- global_dpi_aware_final_screenshot: true',
    '- output_verified: true',
    '- operation_interval_budget_pass: true'
) | Set-Content -Encoding UTF8 -LiteralPath $Report

Write-Host 'PASS pycharm_first_pass_multiline_input_selftest'
exit 0
