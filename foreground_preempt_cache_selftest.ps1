param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.12.1_performance_optimization'
$Report = Join-Path $OutDir 'foreground_preempt_cache_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "Missing $WinAgent. Run $Root\build.ps1 first."
}

$output = & $WinAgent foreground-preempt --dry-run true --cache-selftest true
$exit = $LASTEXITCODE
$text = ($output | Out-String).Trim()
if ($exit -ne 0) { throw "foreground-preempt cache selftest command exited $exit`: $text" }
$json = $text | ConvertFrom-Json

Assert ($json.ok -eq $true) 'foreground-preempt cache selftest must return ok=true.'
Assert ($json.data.cache_enabled -eq $true) 'ForegroundPreemptCache must be enabled.'
Assert ($json.data.full_preempt_count -eq 1) 'First observation must run exactly one full preempt.'
Assert ($json.data.cached_validation_count -ge 1) 'Subsequent unchanged operation must use cached validation.'
Assert ($json.data.results[0].foreground_preempt_mode -eq 'full') 'First mode must be full.'
Assert ($json.data.results[0].foreground_preempt_reason.Length -gt 0) 'Full preempt must record a reason.'
Assert ($json.data.results[1].foreground_preempt_mode -in @('cached_validation', 'skipped_safe')) 'Second mode must avoid redundant full preempt.'

@(
    '# Foreground Preempt Cache Report',
    '',
    '- result: PASS',
    '- foreground_preempt_cache_enabled: true',
    "- full_preempt_count: $($json.data.full_preempt_count)",
    "- cached_validation_count: $($json.data.cached_validation_count)",
    "- skipped_safe_count: $($json.data.skipped_safe_count)",
    "- first_mode: $($json.data.results[0].foreground_preempt_mode)",
    "- second_mode: $($json.data.results[1].foreground_preempt_mode)"
) | Set-Content -Encoding UTF8 -LiteralPath $Report

Write-Host 'PASS foreground_preempt_cache_selftest'
exit 0
