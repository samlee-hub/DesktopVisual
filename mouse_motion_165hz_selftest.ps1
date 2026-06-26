param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.12.1_performance_optimization'
$Report = Join-Path $OutDir 'mouse_motion_165hz_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "Missing $WinAgent. Run $Root\build.ps1 first."
}

$output = & $WinAgent motion-pacer-selftest --motion-profile 165hz-visible --motion-hz 165 --duration-ms 180
$exit = $LASTEXITCODE
$text = ($output | Out-String).Trim()
if ($exit -ne 0) { throw "motion-pacer selftest exited $exit`: $text" }
$json = $text | ConvertFrom-Json

Assert ($json.ok -eq $true) '165Hz motion pacer selftest must pass.'
Assert ($json.data.requested_hz -eq 165) 'requested_hz must be 165.'
Assert ([double]$json.data.measured_avg_hz -ge 150.0) 'measured_avg_hz must be at least 150.'
Assert ([double]$json.data.measured_max_interval_ms -le 12.0) 'max frame interval must be <= 12ms.'
Assert ($json.data.high_resolution_timer_enabled -eq $true) 'High resolution timer strategy must be enabled.'

@(
    '# Mouse Motion 165Hz Report',
    '',
    '- result: PASS',
    '- mouse_motion_165hz_enabled: true',
    "- requested_hz: $($json.data.requested_hz)",
    "- measured_avg_hz: $($json.data.measured_avg_hz)",
    "- measured_min_hz: $($json.data.measured_min_hz)",
    "- measured_max_interval_ms: $($json.data.measured_max_interval_ms)",
    "- total_move_duration_ms: $($json.data.total_move_duration_ms)",
    "- high_resolution_timer_enabled: $($json.data.high_resolution_timer_enabled)"
) | Set-Content -Encoding UTF8 -LiteralPath $Report

Write-Host 'PASS mouse_motion_165hz_selftest'
exit 0
