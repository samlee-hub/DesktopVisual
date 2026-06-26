param(
    [Parameter(Mandatory=$true)][string]$CaseFile,
    [Parameter(Mandatory=$true)][string]$ReportFile
)

$Resolver = Join-Path $PSScriptRoot 'Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'

if (-not (Test-Path $WinAgent)) { Write-Error "winagent.exe not found. Build first."; exit 1 }
if (-not (Test-Path $CaseFile)) { Write-Error "Case file not found: $CaseFile"; exit 1 }

Write-Host "=== Run Case v2 ===" -ForegroundColor Cyan
Write-Host "Case: $CaseFile"
Write-Host "Report: $ReportFile"

$caseDir = Split-Path $ReportFile -Parent
if ($caseDir -and -not (Test-Path $caseDir)) { New-Item -ItemType Directory -Force -Path $caseDir | Out-Null }

$output = & $WinAgent run-case --file $CaseFile --report $ReportFile 2>&1
$exit = $LASTEXITCODE

try { $json = $output | ConvertFrom-Json } catch { Write-Error "Not JSON: $output"; exit 1 }

Write-Host "Steps: $($json.data.step_count) total, $($json.data.passed_step_count) passed"
if (-not $json.ok) {
    Write-Host "CASE FAILED: $($json.error.code)" -ForegroundColor Red
    Write-Host "Failed step: $($json.data.failed_step_index)" -ForegroundColor Red
    Write-Host "Report: $ReportFile"
    if (Test-Path $ReportFile) {
        $reportContent = Get-Content $ReportFile -Raw
        if ($reportContent -match 'Failure error_code: `(\w+)`') { Write-Host "Error: $($Matches[1])" -ForegroundColor Red }
        if ($reportContent -match 'Failure message: (.+)') { Write-Host "Message: $($Matches[1])" -ForegroundColor Red }
    }
    exit 1
}

Write-Host "Case PASSED" -ForegroundColor Green
Write-Host "Report: $ReportFile"
