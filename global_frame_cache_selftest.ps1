param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.12.1_performance_optimization'
$Report = Join-Path $OutDir 'global_frame_cache_report.md'
$Frame = Join-Path $OutDir 'global_frame_cache_selftest.png'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "Missing $WinAgent. Run $Root\build.ps1 first."
}

$output = & $WinAgent global-screenshot --out $Frame --format png --include-metadata true --cache-selftest true
$exit = $LASTEXITCODE
$text = ($output | Out-String).Trim()
if ($exit -ne 0) { throw "global-frame cache selftest command exited $exit`: $text" }
$json = $text | ConvertFrom-Json

Assert ($json.ok -eq $true) 'global-frame cache selftest must return ok=true.'
Assert ($json.data.cache_enabled -eq $true) 'GlobalFrameCache must be enabled.'
Assert ($json.data.new_frame_count -ge 2) 'Initial and final verification must capture fresh global frames.'
Assert ($json.data.cache_hit_count -ge 1) 'Planning frame should be reusable before UI invalidation.'
Assert ($json.data.frames[-1].new_global_frame_for_final_verification -eq $true) 'Final verification must force a new global frame.'
Assert ($json.data.frames[1].frame_cache_hit -eq $true) 'Second planning frame must be a cache hit.'

@(
    '# Global Frame Cache Report',
    '',
    '- result: PASS',
    '- global_frame_cache_enabled: true',
    "- new_frame_count: $($json.data.new_frame_count)",
    "- cache_hit_count: $($json.data.cache_hit_count)",
    "- final_new_frame: $($json.data.frames[-1].new_global_frame_for_final_verification)",
    "- average_capture_duration_ms: $($json.data.average_capture_duration_ms)"
) | Set-Content -Encoding UTF8 -LiteralPath $Report

Write-Host 'PASS global_frame_cache_selftest'
exit 0
