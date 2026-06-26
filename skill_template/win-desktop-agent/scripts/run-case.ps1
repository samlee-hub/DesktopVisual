param(
    [Parameter(Mandatory = $true)]
    [string]$CaseFile,

    [Parameter(Mandatory = $true)]
    [string]$ReportFile
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
if (!(Test-Path -LiteralPath $WinAgent)) {
    throw "Missing $WinAgent. Run $Root\build.ps1 first."
}

& $WinAgent run-case --file $CaseFile --report $ReportFile
exit $LASTEXITCODE
