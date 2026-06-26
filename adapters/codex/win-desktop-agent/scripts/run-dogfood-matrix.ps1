$Resolver = Join-Path $PSScriptRoot 'Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$MatrixScript = Join-Path $Root 'dogfood_matrix.ps1'

if (-not (Test-Path $MatrixScript)) {
    Write-Error "dogfood_matrix.ps1 not found at $MatrixScript"
    exit 1
}

Write-Host "=== Running Dogfood Matrix ===" -ForegroundColor Cyan
& powershell -ExecutionPolicy Bypass -File $MatrixScript -SkipBuild
$exit = $LASTEXITCODE

$report = Join-Path $Root 'artifacts\dogfood_matrix_report.md'
if (Test-Path $report) {
    Write-Host "`nMatrix report: $report" -ForegroundColor Green
    $content = Get-Content $report -Raw
    if ($content -match 'Pass: (\d+)') { Write-Host "Pass: $($Matches[1])" -ForegroundColor Green }
    if ($content -match 'Fail: (\d+)') { Write-Host "Fail: $($Matches[1])" -ForegroundColor Red }
    if ($content -match 'Skipped: (\d+)') { Write-Host "Skipped: $($Matches[1])" -ForegroundColor Yellow }
    if ($content -match 'Pass rate \(excluding skipped\): ([\d.]+)%') { Write-Host "Pass rate: $($Matches[1])%" -ForegroundColor Cyan }
}

exit $exit
