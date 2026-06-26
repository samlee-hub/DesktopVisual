param(
    [Parameter(Mandatory=$true)][string]$ReportFile
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $ReportFile)) {
    throw "Report not found: $ReportFile"
}
Get-Content -LiteralPath $ReportFile -Raw
