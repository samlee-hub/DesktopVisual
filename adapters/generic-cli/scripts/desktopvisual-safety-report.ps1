param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

if (-not $Root) {
    $Root = $env:DESKTOPVISUAL_ROOT
}
if (-not $Root) {
    $Root = 'D:\desktopvisual'
}

$WinAgent = Join-Path $Root 'bin\winagent.exe'
& $WinAgent safety-report
exit $LASTEXITCODE
