param(
    [int]$Lines = 40
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -StartPath $PSScriptRoot
$Artifacts = Join-Path $Root 'artifacts'
if (!(Test-Path -LiteralPath $Artifacts)) {
    throw "Missing artifacts directory: $Artifacts"
}

$report = Get-ChildItem -LiteralPath $Artifacts -Filter '*_report.md' -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (!$report) {
    throw "No *_report.md files found in $Artifacts"
}

Write-Host "Latest report: $($report.FullName)"
Write-Host "Last write time: $($report.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host ''

Get-Content -LiteralPath $report.FullName -TotalCount $Lines
