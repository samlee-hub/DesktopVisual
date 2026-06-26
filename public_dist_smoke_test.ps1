param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $MyInvocation.MyCommand.Path
    if ((Split-Path -Leaf $Root) -ieq 'scripts') {
        $Root = Split-Path -Parent $Root
    }
}
$Root = [System.IO.Path]::GetFullPath($Root)
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'

function Fail($Message) { throw $Message }
function Invoke-AgentJson([string[]]$Args, [switch]$AllowFailure) {
    $output = & $WinAgent @Args 2>&1
    if ($LASTEXITCODE -ne 0 -and -not $AllowFailure) {
        Fail "winagent $($Args -join ' ') exited $LASTEXITCODE with output: $output"
    }
    return ($output | ConvertFrom-Json)
}

if (-not (Test-Path -LiteralPath $WinAgent -PathType Leaf)) { Fail "winagent.exe missing: $WinAgent" }
$version = Invoke-AgentJson -Args @('version')
if (-not $version.ok -or $version.data.version -ne '1.1.0') { Fail 'version smoke failed.' }

$ordinary = Invoke-AgentJson -Args @(
    'policy-check',
    '--title', 'Ordinary HTTPS Page',
    '--process', 'msedge.exe',
    '--action', 'browser_navigate',
    '--permission-mode', 'PUBLIC_DEFAULT'
)
if (-not $ordinary.ok -or -not $ordinary.data.allow) { Fail 'PUBLIC_DEFAULT ordinary browser smoke failed.' }

$stop = Invoke-AgentJson -Args @(
    'policy-check',
    '--title', 'captcha human verification',
    '--process', 'chrome.exe',
    '--action', 'mouse.click',
    '--permission-mode', 'PUBLIC_DEFAULT'
) -AllowFailure
if ($stop.ok -or $stop.error.code -ne 'STOP_ACTIVE_PROTECTION') { Fail 'PUBLIC_DEFAULT active protection smoke failed.' }

Write-Host 'public_dist_smoke_test PASS'
