param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.12.1_visible_ui_foundation_hardening'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Invoke-Agent([string[]]$WinArgs, [int[]]$Allowed = @(0)) {
    $output = & $WinAgent @WinArgs
    $exit = $LASTEXITCODE
    if ($Allowed -notcontains $exit) { throw "winagent $($WinArgs -join ' ') exited $exit with output: $output" }
    return $output | ConvertFrom-Json
}
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }

$project = Join-Path $OutDir 'pycharm_sanity'
$demo = Invoke-Agent -WinArgs @('pycharm-visible-demo', '--project', $project, '--file', 'main.py', '--code-profile', 'two-class-demo', '--dry-run', 'true')
Assert ($demo.ok -eq $true) 'pycharm-visible-demo dry-run should pass.'
Assert ($demo.data.uses_global_dpi_aware_frame -eq $true) 'PyCharm workflow must use global DPI-aware frame.'
Assert ($demo.data.uses_target_window_lock -eq $true) 'PyCharm workflow must use target lock.'
Assert ($demo.data.uses_coordinate_mapper -eq $true) 'PyCharm workflow must use coordinate mapper.'
Assert ($demo.data.input_method -in @('real_keyboard_events', 'code_editor_keyboard')) 'PyCharm code input must use real keyboard events or code_editor_keyboard.'
Assert ($demo.data.clipboard_used -eq $false) 'PyCharm workflow must not use clipboard in default path.'
Assert ($demo.data.backend_file_write_used -eq $false) 'PyCharm workflow must not use backend file write.'
Assert ($demo.data.first_pass_multiline_correct -eq $true) 'PyCharm workflow must prove first-pass multiline correctness.'
Assert ($demo.data.code_collapsed_to_single_line -eq $false) 'PyCharm workflow must not accept collapsed single-line code.'
Assert ($demo.data.selfself_autocomplete_artifact -eq $false) 'PyCharm workflow must not contain selfself autocomplete artifact.'
Assert ($demo.data.final_evidence_global_dpi_aware -eq $true) 'PyCharm final evidence must be global DPI-aware.'
Assert ($demo.data.global_dpi_aware_final_screenshot -eq $true) 'PyCharm final screenshot must be global DPI-aware.'
Assert ($demo.data.output_verified -eq $true) 'PyCharm output must be verified.'
Assert ($demo.data.pycharm_opened_by_desktop_icon_or_taskbar -eq $true) 'PyCharm acceptance must require visible desktop/taskbar launch evidence.'
Assert ($demo.data.backend_launch_used -eq $false) 'PyCharm workflow must not use backend launch.'
Assert ($demo.data.launch_app_path_used -eq $false) 'PyCharm workflow must not use launch-app --path.'
Assert ($demo.data.desktop_or_taskbar_icon_clicked -eq $true) 'PyCharm workflow must require desktop/taskbar icon click evidence.'
Assert ($demo.data.visible_switch_or_launch_attempted -eq $true) 'PyCharm workflow must require visible switch/launch attempt evidence.'
Assert ($demo.data.operation_interval_budget_pass -eq $true) 'PyCharm workflow must record operation interval budget pass.'

$report = Join-Path $OutDir 'pycharm_real_workflow_report.md'
@(
    '# PyCharm Visible Workflow Selftest',
    '',
    '- result: PASS_DRY_RUN_POLICY',
    '- real workflow execution: NOT_RUN_SCOPE_RESTRICTED',
    "- input_method: $($demo.data.input_method)",
    '- clipboard_used: false',
    '- backend_file_write_used: false',
    '- first_pass_multiline_correct: true',
    '- code_collapsed_to_single_line: false',
    '- selfself_autocomplete_artifact: false',
    '- pycharm_opened_by_desktop_icon_or_taskbar: true',
    '- backend_launch_used: false',
    '- launch_app_path_used: false',
    '- desktop_or_taskbar_icon_clicked: true',
    '- visible_switch_or_launch_attempted: true',
    '- final_evidence_global_dpi_aware: true',
    '- global_dpi_aware_final_screenshot: true',
    '- output_verified: true',
    '- operation_interval_budget_pass: true'
) | Set-Content -Encoding UTF8 -LiteralPath $report
Write-Host "PASS pycharm_visible_workflow_selftest"
exit 0
