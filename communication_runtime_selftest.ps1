param(
    [string]$Root = '',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$BuildScript = Join-Path $Root 'build.ps1'
$Artifacts = Join-Path $Root 'artifacts\communication_runtime'
$TestWindowExe = 'D:\testrepo\testwindow\bin\TestWindow.exe'
$PermissionDir = Join-Path $Root 'artifacts\permission'
$SessionPath = Join-Path $PermissionDir 'full_access_session.json'
$AuditPath = Join-Path $Root 'artifacts\agent_audit.log'

function Fail($Message) { throw $Message }

function Invoke-AgentJson {
    param([string[]]$CmdArgs, [switch]$AllowFailure)
    $output = & $WinAgent @CmdArgs 2>&1
    $exit = $LASTEXITCODE
    if ($exit -ne 0 -and -not $AllowFailure) {
        Fail "winagent $($CmdArgs -join ' ') exited $exit with output: $output"
    }
    try {
        return @{ exit = $exit; text = [string]$output; json = ($output | ConvertFrom-Json) }
    } catch {
        Fail "Invalid JSON from winagent $($CmdArgs -join ' '): $output"
    }
}

function New-TestFullAccessSession {
    New-Item -ItemType Directory -Force -Path $PermissionDir | Out-Null
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $session = [pscustomobject]@{
        session_id = 'communication-runtime-selftest-session'
        permission_mode = 'FULL_ACCESS'
        scope = 'session-only'
        ttl_seconds = 600
        created_at_unix_ms = $now
        expires_at_unix_ms = $now + 600000
    }
    $session | ConvertTo-Json | Set-Content -LiteralPath $SessionPath -Encoding UTF8
    return $session.session_id
}

function Write-Task {
    param([string]$Name, [string]$Json)
    $path = Join-Path $Artifacts "$Name.task.json"
    Set-Content -LiteralPath $path -Value $Json -Encoding UTF8
    return $path
}

function Run-Task {
    param([string]$Name, [string]$Json, [switch]$AllowFailure)
    $taskPath = Write-Task -Name $Name -Json $Json
    $report = Join-Path $Artifacts "$Name.report.md"
    $result = Invoke-AgentJson -CmdArgs @('run-task', '--file', $taskPath, '--report', $report) -AllowFailure:$AllowFailure
    if (!(Test-Path -LiteralPath $report)) { Fail "Missing report: $report" }
    return @{ result = $result; report = $report; text = Get-Content -LiteralPath $report -Raw }
}

function Assert-Contains([string]$Text, [string]$Needle) {
    if ($Text -notlike "*$Needle*") { Fail "Missing expected text: $Needle" }
}

if (-not $SkipBuild) {
    & $BuildScript -Root $Root
    if ($LASTEXITCODE -ne 0) { Fail 'Build failed.' }
}

New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null
Remove-Item -LiteralPath $AuditPath -ErrorAction SilentlyContinue
[void](Invoke-AgentJson -CmdArgs @('lock-full-access') -AllowFailure)

Get-Process TestWindow -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
$proc = $null

try {
    $proc = Start-Process -FilePath $TestWindowExe -PassThru
    Start-Sleep -Milliseconds 500

    $defaultDenied = Run-Task -Name 'default_denied' -AllowFailure -Json @'
{
  "version": 1,
  "name": "default_denied",
  "permission_mode": "DEFAULT",
  "target": { "title": "Agent Test Window", "process": "TestWindow.exe" },
  "steps": [
    {
      "name": "send",
      "type": "communication_step",
      "operation": "send_message",
      "channel": "local-chat-sim",
      "target": "alice@example.test",
      "subject": "Status",
      "content": "hello from default",
      "user_requested_send": true
    }
  ]
}
'@
    if ($defaultDenied.result.json.error.code -ne 'SAFETY_POLICY_DENIED') { Fail "Expected SAFETY_POLICY_DENIED, got $($defaultDenied.result.json.error.code)" }

    $sessionId = New-TestFullAccessSession
    $allowed = Run-Task -Name 'full_access_allowed' -Json @"
{
  "version": 1,
  "name": "full_access_allowed",
  "permission_mode": "FULL_ACCESS",
  "full_access_session_id": "$sessionId",
  "target": { "title": "Agent Test Window", "process": "TestWindow.exe" },
  "steps": [
    {
      "name": "send",
      "type": "communication_step",
      "operation": "send_message",
      "channel": "local-email-sim",
      "target": "alice@example.test",
      "subject": "Status",
      "content": "SECRET_FULL_CONTENT_123",
      "content_summary": "short status update",
      "user_requested_send": true
    }
  ]
}
"@
    if (-not $allowed.result.json.ok) { Fail "FULL_ACCESS simulated send failed: $($allowed.result.text)" }
    Assert-Contains $allowed.text 'CommunicationAction'
    Assert-Contains $allowed.text 'alice@example.test'
    Assert-Contains $allowed.text 'content_hash'
    Assert-Contains $allowed.text 'send_action_performed'
    if ($allowed.text -like '*SECRET_FULL_CONTENT_123*') { Fail 'Report leaked full communication content.' }

    $missingTarget = Run-Task -Name 'missing_target' -AllowFailure -Json @"
{
  "version": 1,
  "name": "missing_target",
  "permission_mode": "FULL_ACCESS",
  "full_access_session_id": "$sessionId",
  "target": { "title": "Agent Test Window", "process": "TestWindow.exe" },
  "steps": [
    {
      "name": "send",
      "type": "communication_step",
      "operation": "send_message",
      "channel": "local-chat-sim",
      "content": "hello",
      "user_requested_send": true
    }
  ]
}
"@
    if ($missingTarget.result.json.error.code -ne 'USER_TAKEOVER_REQUIRED') { Fail "Expected USER_TAKEOVER_REQUIRED for missing target, got $($missingTarget.result.json.error.code)" }

    $notRequested = Run-Task -Name 'not_requested' -AllowFailure -Json @"
{
  "version": 1,
  "name": "not_requested",
  "permission_mode": "FULL_ACCESS",
  "full_access_session_id": "$sessionId",
  "target": { "title": "Agent Test Window", "process": "TestWindow.exe" },
  "steps": [
    {
      "name": "send",
      "type": "communication_step",
      "operation": "send_message",
      "channel": "local-chat-sim",
      "target": "alice@example.test",
      "content": "hello",
      "user_requested_send": false
    }
  ]
}
"@
    if ($notRequested.result.json.error.code -ne 'USER_TAKEOVER_REQUIRED') { Fail "Expected USER_TAKEOVER_REQUIRED for missing user request, got $($notRequested.result.json.error.code)" }

    $captcha = Run-Task -Name 'captcha_stop' -AllowFailure -Json @"
{
  "version": 1,
  "name": "captcha_stop",
  "permission_mode": "FULL_ACCESS",
  "full_access_session_id": "$sessionId",
  "target": { "title": "Agent Test Window", "process": "TestWindow.exe" },
  "steps": [
    {
      "name": "send",
      "type": "communication_step",
      "operation": "send_message",
      "channel": "local-chat-sim",
      "target": "alice@example.test",
      "content": "hello",
      "observed_summary": "captcha required",
      "user_requested_send": true
    }
  ]
}
"@
    if ($captcha.result.json.error.code -ne 'CAPTCHA_DETECTED') { Fail "Expected CAPTCHA_DETECTED, got $($captcha.result.json.error.code)" }

    $login = Run-Task -Name 'login_stop' -AllowFailure -Json @"
{
  "version": 1,
  "name": "login_stop",
  "permission_mode": "FULL_ACCESS",
  "full_access_session_id": "$sessionId",
  "target": { "title": "Agent Test Window", "process": "TestWindow.exe" },
  "steps": [
    {
      "name": "send",
      "type": "communication_step",
      "operation": "send_message",
      "channel": "local-email-sim",
      "target": "alice@example.test",
      "content": "hello",
      "observed_summary": "login required",
      "user_requested_send": true
    }
  ]
}
"@
    if ($login.result.json.error.code -ne 'USER_TAKEOVER_REQUIRED') { Fail "Expected USER_TAKEOVER_REQUIRED for login, got $($login.result.json.error.code)" }

    $audit = Get-Content -LiteralPath $AuditPath -Raw
    Assert-Contains $audit 'command="communication_step"'
    Assert-Contains $audit 'target_title="Agent Test Window"'
    Assert-Contains $audit 'local-email-sim'
    Assert-Contains $audit 'alice@example.test'

    Write-Host 'communication_runtime_selftest passed.'
} finally {
    if ($proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
}
