param(
    [Parameter(Mandatory=$true)][string]$ReportFile
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $ReportFile)) {
    [pscustomobject]@{
        ok = $false
        error_code = 'REPORT_NOT_FOUND'
        data = @{ path = $ReportFile }
        artifacts = @()
        report_path = $ReportFile
    } | ConvertTo-Json -Depth 10
    exit 1
}

[pscustomobject]@{
    ok = $true
    error_code = ''
    data = @{ content = (Get-Content -LiteralPath $ReportFile -Raw) }
    artifacts = @()
    report_path = $ReportFile
} | ConvertTo-Json -Depth 10
