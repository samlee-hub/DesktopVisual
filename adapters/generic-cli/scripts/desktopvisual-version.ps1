param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot '..\..\..\scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$raw = & (Join-Path $Root 'bin\winagent.exe') version 2>&1
$exit = $LASTEXITCODE
try { $json = ($raw | Out-String) | ConvertFrom-Json } catch { $json = $null }

[pscustomobject]@{
    ok = ($exit -eq 0 -and $null -ne $json -and $json.ok -eq $true)
    error_code = $(if ($exit -eq 0) { '' } else { 'COMMAND_FAILED' })
    data = $(if ($json) { $json.data } else { @{ raw = ($raw | Out-String).Trim() } })
    artifacts = @()
    report_path = ''
} | ConvertTo-Json -Depth 10
