param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.12.1_performance_optimization'
$Report = Join-Path $OutDir 'target_lock_cache_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "Missing $WinAgent. Run $Root\build.ps1 first."
}

$output = & $WinAgent target-lock-acquire --target-title dry-run-target --require-target-lock true --allow-dry-run-target true --cache-selftest true
$exit = $LASTEXITCODE
$text = ($output | Out-String).Trim()
if ($exit -ne 0) { throw "target-lock cache selftest command exited $exit`: $text" }
$json = $text | ConvertFrom-Json

Assert ($json.ok -eq $true) 'target-lock cache selftest must return ok=true.'
Assert ($json.data.cache_enabled -eq $true) 'TargetWindowLockCache must be enabled.'
Assert ($json.data.acquire_count -eq 1) 'First lock must acquire.'
Assert ($json.data.cache_hit_count -ge 1) 'Second lock must hit cache.'
Assert ($json.data.results[0].target_lock_mode -eq 'acquire') 'First target lock mode mismatch.'
Assert ($json.data.results[1].target_lock_mode -eq 'cached_validate') 'Second target lock mode mismatch.'
Assert ($json.data.results[1].target_lock_cache_hit -eq $true) 'Second target lock must report cache hit.'

@(
    '# Target Lock Cache Report',
    '',
    '- result: PASS',
    '- target_lock_cache_enabled: true',
    "- acquire_count: $($json.data.acquire_count)",
    "- cache_hit_count: $($json.data.cache_hit_count)",
    "- reacquire_count: $($json.data.reacquire_count)",
    "- first_mode: $($json.data.results[0].target_lock_mode)",
    "- second_mode: $($json.data.results[1].target_lock_mode)"
) | Set-Content -Encoding UTF8 -LiteralPath $Report

Write-Host 'PASS target_window_lock_cache_selftest'
exit 0
