param(
    [string]$Root = '',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$AuditPath = Join-Path $Root 'artifacts\agent_audit.log'
$WebDir = Join-Path $Root 'artifacts\external_web'
$PermissionDir = Join-Path $Root 'artifacts\permission'
$SessionPath = Join-Path $PermissionDir 'full_access_session.json'

function Fail($Message) { throw $Message }

function Invoke-AgentJson([string[]]$CmdArgs, [switch]$AllowFailure) {
    $output = & $WinAgent @CmdArgs 2>&1
    $exit = $LASTEXITCODE
    if ($exit -ne 0 -and -not $AllowFailure) {
        Fail "winagent $($CmdArgs -join ' ') exited $exit with output: $output"
    }
    try { return ($output | ConvertFrom-Json) } catch { Fail "Invalid JSON: $output" }
}

function New-TestFullAccessSession {
    New-Item -ItemType Directory -Force -Path $PermissionDir | Out-Null
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    [pscustomobject]@{
        session_id = 'external-web-selftest-session'
        permission_mode = 'FULL_ACCESS'
        scope = 'session-only'
        ttl_seconds = 600
        created_at_unix_ms = $now
        expires_at_unix_ms = $now + 600000
    } | ConvertTo-Json | Set-Content -LiteralPath $SessionPath -Encoding UTF8
    return 'external-web-selftest-session'
}

if (-not $SkipBuild) {
    & "$Root\build.ps1" -Root $Root
    if ($LASTEXITCODE -ne 0) { Fail 'Build failed.' }
}

New-Item -ItemType Directory -Force -Path $WebDir | Out-Null
$normalPage = Join-Path $WebDir 'normal.html'
$captchaPage = Join-Path $WebDir 'captcha.html'
$loopPage = Join-Path $WebDir 'redirect-loop.html'
'<html><head><title>DesktopVisual Local Normal</title></head><body><a href="#next">Next</a><button>OK</button></body></html>' | Set-Content -LiteralPath $normalPage -Encoding UTF8
'<html><head><title>captcha verification</title></head><body>captcha challenge</body></html>' | Set-Content -LiteralPath $captchaPage -Encoding UTF8
'<html><head><title>redirect-loop</title></head><body>redirect-loop</body></html>' | Set-Content -LiteralPath $loopPage -Encoding UTF8

Remove-Item -LiteralPath $AuditPath -ErrorAction SilentlyContinue
[void](Invoke-AgentJson -CmdArgs @('lock-full-access') -AllowFailure)

$defaultExternal = Invoke-AgentJson -CmdArgs @('browser-nav', '--url', 'https://example.com/', '--permission-mode', 'DEFAULT') -AllowFailure
if ($defaultExternal.ok -or $defaultExternal.error.code -ne 'SAFETY_POLICY_DENIED') { Fail 'DEFAULT allowed external URL.' }

$fullNoSession = Invoke-AgentJson -CmdArgs @('browser-nav', '--url', 'https://example.com/', '--permission-mode', 'FULL_ACCESS', '--full-access-session-id', 'missing') -AllowFailure
if ($fullNoSession.ok -or $fullNoSession.error.code -ne 'FULL_ACCESS_SESSION_REQUIRED') { Fail 'FULL_ACCESS external URL without session was not denied.' }

$sessionId = New-TestFullAccessSession
$localUrl = (New-Object System.Uri($normalPage)).AbsoluteUri
$captchaUrl = (New-Object System.Uri($captchaPage)).AbsoluteUri
$loopUrl = (New-Object System.Uri($loopPage)).AbsoluteUri

$open = Invoke-AgentJson -CmdArgs @('browser-nav', '--url', $localUrl, '--permission-mode', 'FULL_ACCESS', '--full-access-session-id', $sessionId, '--no-open', 'true')
if (-not $open.ok -or $open.data.load_result -ne 'simulated') { Fail 'FULL_ACCESS local simulated navigation failed.' }
if ($open.data.url -ne $localUrl) { Fail 'browser-nav did not record URL.' }

$captcha = Invoke-AgentJson -CmdArgs @('browser-nav', '--url', $captchaUrl, '--permission-mode', 'FULL_ACCESS', '--full-access-session-id', $sessionId, '--no-open', 'true') -AllowFailure
if ($captcha.ok -or $captcha.error.code -ne 'CAPTCHA_DETECTED') { Fail 'Captcha simulated page did not stop.' }

$login = Invoke-AgentJson -CmdArgs @('browser-nav', '--url', 'https://example.com/login', '--permission-mode', 'FULL_ACCESS', '--full-access-session-id', $sessionId, '--no-open', 'true') -AllowFailure
if ($login.ok -or $login.error.code -ne 'USER_TAKEOVER_REQUIRED') { Fail 'Login URL did not stop for user takeover.' }

$loop = Invoke-AgentJson -CmdArgs @('browser-nav', '--url', $loopUrl, '--permission-mode', 'FULL_ACCESS', '--full-access-session-id', $sessionId, '--no-open', 'true') -AllowFailure
if ($loop.ok -or $loop.error.code -ne 'URL_REDIRECT_LOOP') { Fail 'Redirect loop simulated page did not stop.' }

$scroll = Invoke-AgentJson -CmdArgs @('browser-nav', '--url', $localUrl, '--action', 'scroll', '--permission-mode', 'FULL_ACCESS', '--full-access-session-id', $sessionId, '--no-open', 'true')
if (-not $scroll.ok -or $scroll.data.action -ne 'scroll') { Fail 'Simulated scroll action failed.' }

if (-not (Test-Path -LiteralPath $AuditPath)) { Fail 'agent_audit.log was not written.' }
$audit = Get-Content -LiteralPath $AuditPath -Raw
if ($audit -notmatch 'command="browser-nav"') { Fail 'audit did not record browser-nav.' }
if ($audit -notmatch 'https://example.com/' -or $audit -notmatch 'CAPTCHA_DETECTED' -or $audit -notmatch 'URL_REDIRECT_LOOP') { Fail 'audit did not include URL and stop outcomes.' }

[void](Invoke-AgentJson -CmdArgs @('lock-full-access') -AllowFailure)
Write-Host 'External web selftest passed.'
