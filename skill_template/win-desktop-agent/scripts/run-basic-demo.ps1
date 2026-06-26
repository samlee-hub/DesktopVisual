$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
& (Join-Path $Root 'run_demo.ps1') -Root $Root
exit $LASTEXITCODE
