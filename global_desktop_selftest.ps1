param(
    [string]$Root = '',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$TestWindowExe = 'D:\testrepo\testwindow\bin\TestWindow.exe'
$AuditPath = Join-Path $Root 'artifacts\agent_audit.log'
$PermissionDir = Join-Path $Root 'artifacts\permission'
$SessionPath = Join-Path $PermissionDir 'full_access_session.json'

function Fail($Message) { throw $Message }

function Invoke-AgentJson([string[]]$CmdArgs, [switch]$AllowFailure) {
    $output = & $WinAgent @CmdArgs 2>&1
    $exit = $LASTEXITCODE
    if ($exit -ne 0 -and -not $AllowFailure) {
        Fail "winagent $($CmdArgs -join ' ') exited $exit with output: $output"
    }
    try {
        return ($output | ConvertFrom-Json)
    } catch {
        Fail "Invalid JSON from winagent $($CmdArgs -join ' '): $output"
    }
}

function New-TestFullAccessSession {
    New-Item -ItemType Directory -Force -Path $PermissionDir | Out-Null
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $session = [pscustomobject]@{
        session_id = 'global-desktop-selftest-session'
        permission_mode = 'FULL_ACCESS'
        scope = 'session-only'
        ttl_seconds = 600
        created_at_unix_ms = $now
        expires_at_unix_ms = $now + 600000
    }
    $session | ConvertTo-Json | Set-Content -LiteralPath $SessionPath -Encoding UTF8
    return $session.session_id
}

function Stop-TestWindows {
    Get-Process TestWindow -ErrorAction SilentlyContinue | Stop-Process -Force
}

if (-not $SkipBuild) {
    & "$Root\build.ps1" -Root $Root
    if ($LASTEXITCODE -ne 0) { Fail 'Build failed.' }
}

if (-not (Test-Path -LiteralPath $TestWindowExe)) { Fail "Missing TestWindow.exe: $TestWindowExe" }

Stop-TestWindows
Remove-Item -LiteralPath $AuditPath -ErrorAction SilentlyContinue
[void](Invoke-AgentJson -CmdArgs @('lock-full-access') -AllowFailure)

$defaultDenied = Invoke-AgentJson -CmdArgs @(
    'launch-app',
    '--kind', 'exe',
    '--path', $TestWindowExe,
    '--target-title', 'Agent Test Window',
    '--process', 'TestWindow.exe',
    '--permission-mode', 'DEFAULT'
) -AllowFailure
if ($defaultDenied.ok -or $defaultDenied.error.code -ne 'SAFETY_POLICY_DENIED') {
    Fail 'DEFAULT did not deny global desktop app launch.'
}

$noSession = Invoke-AgentJson -CmdArgs @(
    'launch-app',
    '--kind', 'exe',
    '--path', $TestWindowExe,
    '--target-title', 'Agent Test Window',
    '--process', 'TestWindow.exe',
    '--permission-mode', 'FULL_ACCESS',
    '--full-access-session-id', 'missing'
) -AllowFailure
if ($noSession.ok -or $noSession.error.code -ne 'FULL_ACCESS_SESSION_REQUIRED') {
    Fail 'FULL_ACCESS launch without a valid session was not denied.'
}

$sessionId = New-TestFullAccessSession

$protected = Invoke-AgentJson -CmdArgs @(
    'launch-app',
    '--kind', 'exe',
    '--path', 'C:\Windows\System32\CredentialUIBroker.exe',
    '--target-title', 'Credential',
    '--process', 'CredentialUIBroker.exe',
    '--permission-mode', 'FULL_ACCESS',
    '--full-access-session-id', $sessionId
) -AllowFailure
if ($protected.ok -or $protected.error.code -ne 'CREDENTIAL_INPUT_DETECTED') {
    Fail 'CredentialUIBroker launch did not trigger credential stop.'
}

$login = Invoke-AgentJson -CmdArgs @(
    'launch-app',
    '--kind', 'exe',
    '--path', $TestWindowExe,
    '--target-title', 'Login Required',
    '--process', 'TestWindow.exe',
    '--permission-mode', 'FULL_ACCESS',
    '--full-access-session-id', $sessionId
) -AllowFailure
if ($login.ok -or $login.error.code -ne 'USER_TAKEOVER_REQUIRED') {
    Fail 'Login/credential target title did not trigger user takeover.'
}

$launch = Invoke-AgentJson -CmdArgs @(
    'launch-app',
    '--kind', 'exe',
    '--path', $TestWindowExe,
    '--target-title', 'Agent Test Window',
    '--process', 'TestWindow.exe',
    '--permission-mode', 'FULL_ACCESS',
    '--full-access-session-id', $sessionId,
    '--loop-threshold', '10'
)
if (-not $launch.ok) { Fail 'FULL_ACCESS launch of TestWindow failed.' }
if ($launch.data.target_window.title -ne 'Agent Test Window') { Fail 'launch-app did not record target window title.' }
if ($launch.data.target_window.process -ne 'TestWindow.exe') { Fail 'launch-app did not record target process.' }
if (-not $launch.data.target_window.hwnd) { Fail 'launch-app did not record target hwnd.' }
if (-not $launch.data.target_window.rect) { Fail 'launch-app did not record target rect.' }

$loop = Invoke-AgentJson -CmdArgs @(
    'launch-app',
    '--kind', 'exe',
    '--path', $TestWindowExe,
    '--target-title', 'Agent Test Window',
    '--process', 'TestWindow.exe',
    '--permission-mode', 'FULL_ACCESS',
    '--full-access-session-id', $sessionId,
    '--loop-threshold', '1'
) -AllowFailure
if ($loop.ok -or $loop.error.code -ne 'WINDOW_SPAWN_LOOP') {
    Fail 'Repeated launch did not trigger WINDOW_SPAWN_LOOP.'
}

if (-not (Test-Path -LiteralPath $AuditPath)) { Fail 'agent_audit.log was not written.' }
$audit = Get-Content -LiteralPath $AuditPath -Raw
if ($audit -notmatch 'command="launch-app"') { Fail 'audit did not record launch-app.' }
if ($audit -notmatch 'result="ok"' -or $audit -notmatch 'WINDOW_SPAWN_LOOP') { Fail 'audit did not record success and loop guard failure.' }

Stop-TestWindows
[void](Invoke-AgentJson -CmdArgs @('lock-full-access') -AllowFailure)
Write-Host 'Global desktop selftest passed.'
