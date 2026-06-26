param(
    [Parameter(Mandatory=$true)][string]$TaskFile,
    [string]$ReportFile = '',
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot '..\..\..\scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

if (-not $ReportFile) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($TaskFile)
    $ReportFile = Join-Path $Root "artifacts\generic_cli_${name}_report.md"
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ReportFile) | Out-Null

$raw = & (Join-Path $Root 'bin\winagent.exe') run-task --file $TaskFile --report $ReportFile 2>&1
$exit = $LASTEXITCODE
try { $json = ($raw | Out-String) | ConvertFrom-Json } catch { $json = $null }
$errorCode = ''
if ($json -and $json.error -and $json.error.code) { $errorCode = $json.error.code }
elseif ($exit -ne 0) { $errorCode = 'COMMAND_FAILED' }

[pscustomobject]@{
    ok = ($exit -eq 0 -and $null -ne $json -and $json.ok -eq $true)
    error_code = $errorCode
    data = $(if ($json) { $json.data } else { @{ raw = ($raw | Out-String).Trim() } })
    artifacts = @()
    report_path = $ReportFile
} | ConvertTo-Json -Depth 10
