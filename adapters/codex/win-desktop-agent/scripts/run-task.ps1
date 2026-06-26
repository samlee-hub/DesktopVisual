param(
    [Parameter(Mandatory=$true)][string]$TaskFile,
    [string]$ReportFile = ""
)

$Resolver = Join-Path $PSScriptRoot 'Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'

if (-not (Test-Path $WinAgent)) { Write-Error "winagent.exe not found. Build first."; exit 1 }
if (-not (Test-Path $TaskFile)) { Write-Error "Task file not found: $TaskFile"; exit 1 }

if (-not $ReportFile) {
    $taskName = [System.IO.Path]::GetFileNameWithoutExtension($TaskFile)
    $ReportFile = Join-Path $Root "artifacts\task_${taskName}_report.md"
}

Write-Host "=== Run Task: $TaskFile ===" -ForegroundColor Cyan
Write-Host "Report: $ReportFile"

$output = & $WinAgent run-task --file $TaskFile --report $ReportFile 2>&1
$json = $output | ConvertFrom-Json

Write-Host "Task: $($json.data.task)"
Write-Host "Result: $(if ($json.ok) { 'PASS' } else { 'FAIL' })"
Write-Host "Steps: $($json.data.steps) total, $($json.data.passed) passed"
Write-Host "Recoveries: $($json.data.recoveries)"
Write-Host "Duration: $($json.data.duration_ms)ms"

if (-not $json.ok) {
    Write-Host "FAILED: $($json.error.code) - $($json.error.message)" -ForegroundColor Red
    Write-Host "Report: $ReportFile"
    exit 1
}

Write-Host "Task PASSED" -ForegroundColor Green
