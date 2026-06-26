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
    $ReportFile = Join-Path $Root "artifacts\claude_code_${name}_report.md"
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ReportFile) | Out-Null
& (Join-Path $Root 'bin\winagent.exe') run-task --file $TaskFile --report $ReportFile
