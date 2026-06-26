param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.12.1_performance_optimization'
$Report = Join-Path $OutDir 'pycharm_performance_acceptance_report.md'
$Result = Join-Path $OutDir 'pycharm_performance_acceptance_result.json'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "Missing $WinAgent. Run $Root\build.ps1 first."
}

$output = & $WinAgent pycharm-visible-demo --dry-run true --performance-acceptance true --target-total-ms 120000 --max-total-ms 180000
$exit = $LASTEXITCODE
$text = ($output | Out-String).Trim()
if ($exit -ne 0) { throw "PyCharm performance acceptance command exited $exit`: $text" }
$json = $text | ConvertFrom-Json
$text | Set-Content -Encoding UTF8 -LiteralPath $Result

Assert ($json.ok -eq $true) 'PyCharm performance acceptance must return ok=true.'
Assert ($json.data.performance_acceptance -eq $true) 'Performance acceptance flag missing.'
Assert ([int64]$json.data.optimized_total_task_time_ms -le 180000) 'optimized_total_task_time_ms must be <= 180000.'
Assert ([int64]$json.data.operation_gap_gt_5s_count -eq 0) 'operation gaps over 5s must be zero.'
Assert ([int64]$json.data.silent_gap_gt_5s_count -eq 0) 'silent gaps over 5s must be zero.'
Assert ([int64]$json.data.fixed_sleep_total_ms -eq 0) 'fixed sleep total must be zero.'
Assert ([double]$json.data.average_click_latency_ms -lt 700.0) 'average click latency must be below 700ms.'
Assert ($json.data.visible_first_preserved -eq $true) 'visible-first must be preserved.'
Assert ($json.data.clipboard_used -eq $false) 'clipboard must be false.'
Assert ($json.data.backend_file_write_used -eq $false) 'backend file write must be false.'
Assert ($json.data.backend_launch_used -eq $false) 'backend launch must be false.'
Assert ($json.data.output_verified -eq $true) 'output must be verified.'
Assert ($json.data.global_final_screenshot -eq $true) 'final screenshot must be global.'
Assert ($json.data.mouse_motion_requested_hz -eq 165) 'mouse motion requested Hz must be 165.'
Assert ([double]$json.data.mouse_motion_measured_avg_hz -ge 150.0) 'mouse motion measured avg Hz must be >= 150.'

@(
    '# PyCharm Performance Acceptance Report',
    '',
    '- result: PASS',
    "- optimized_total_task_time_ms: $($json.data.optimized_total_task_time_ms)",
    "- performance_grade: $($json.data.performance_grade)",
    "- operation_gap_gt_5s_count: $($json.data.operation_gap_gt_5s_count)",
    "- silent_gap_gt_5s_count: $($json.data.silent_gap_gt_5s_count)",
    "- fixed_sleep_total_ms: $($json.data.fixed_sleep_total_ms)",
    "- average_click_latency_ms: $($json.data.average_click_latency_ms)",
    "- mouse_motion_requested_hz: $($json.data.mouse_motion_requested_hz)",
    "- mouse_motion_measured_avg_hz: $($json.data.mouse_motion_measured_avg_hz)",
    "- visible_first_preserved: $($json.data.visible_first_preserved)",
    "- clipboard_used: $($json.data.clipboard_used)",
    "- backend_file_write_used: $($json.data.backend_file_write_used)",
    "- backend_launch_used: $($json.data.backend_launch_used)",
    "- output_verified: $($json.data.output_verified)",
    "- global_final_screenshot: $($json.data.global_final_screenshot)"
) | Set-Content -Encoding UTF8 -LiteralPath $Report

Write-Host 'PASS pycharm_performance_acceptance_selftest'
exit 0
