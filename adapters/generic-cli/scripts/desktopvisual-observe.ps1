param(
    [Parameter(Mandatory=$true)][string]$Title,
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot '..\..\..\scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$raw = & (Join-Path $Root 'bin\winagent.exe') observe --title $Title 2>&1
$exit = $LASTEXITCODE
try { $json = ($raw | Out-String) | ConvertFrom-Json } catch { $json = $null }
$errorCode = ''
if ($json -and $json.error -and $json.error.code) { $errorCode = $json.error.code }
elseif ($exit -ne 0) { $errorCode = 'COMMAND_FAILED' }

[pscustomobject]@{
    ok = ($exit -eq 0 -and $null -ne $json -and $json.ok -eq $true)
    error_code = $errorCode
    data = $(if ($json) { $json.data } else { @{ raw = ($raw | Out-String).Trim() } })
    artifacts = $(if ($json -and $json.data -and $json.data.screenshot) { @($json.data.screenshot) } else { @() })
    report_path = ''
} | ConvertTo-Json -Depth 10
