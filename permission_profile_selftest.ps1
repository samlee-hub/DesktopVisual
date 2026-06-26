param(
    [string]$Root = '',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$Artifacts = Join-Path $Root 'artifacts'
$PermissionArtifacts = Join-Path $Artifacts 'permission'
$ServiceAudit = Join-Path $Artifacts 'service_audit.log'
$SafetyManifestPath = Join-Path $Root 'config\safety_manifest.json'

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

function Send-ServiceRequest($endpoint, $body) {
    $request = @{ endpoint = $endpoint; body = $body } | ConvertTo-Json -Compress
    $pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', 'DesktopVisualService', [System.IO.Pipes.PipeDirection]::InOut)
    $pipe.Connect(5000)
    $writer = New-Object System.IO.StreamWriter($pipe)
    $writer.AutoFlush = $true
    $writer.WriteLine($request)
    $reader = New-Object System.IO.StreamReader($pipe)
    $response = $reader.ReadLine()
    $pipe.Close()
    return $response | ConvertFrom-Json
}

try {
    Get-Content -LiteralPath $SafetyManifestPath -Raw | ConvertFrom-Json | Out-Null
} catch {
    Fail "safety_manifest.json is not strict JSON: $($_.Exception.Message)"
}

if (-not $SkipBuild) {
    & "$Root\build.ps1" -Root $Root
    if ($LASTEXITCODE -ne 0) { Fail 'Build failed.' }
}

New-Item -ItemType Directory -Force -Path $PermissionArtifacts | Out-Null

$svc = $null
try {
    [void](Invoke-AgentJson -CmdArgs @('lock-full-access') -AllowFailure)

    $status = Invoke-AgentJson -CmdArgs @('permission-status')
    if ($status.data.permission_mode -ne 'DEVELOPER_CAPABILITY_DISCOVERY') { Fail 'permission-status did not default to DEVELOPER_CAPABILITY_DISCOVERY.' }
    if ($status.data.full_access.active) { Fail 'FULL_ACCESS should not be active after lock-full-access.' }

    $defaultExternal = Invoke-AgentJson -CmdArgs @('policy-check', '--title', 'External Browser', '--process', 'msedge.exe', '--action', 'external_web', '--permission-mode', 'DEFAULT') -AllowFailure
    if ($defaultExternal.ok -or $defaultExternal.error.code -ne 'SAFETY_POLICY_DENIED') { Fail 'DEFAULT allowed external_web.' }

    $defaultApp = Invoke-AgentJson -CmdArgs @('policy-check', '--title', 'Third Party App', '--process', 'ThirdParty.exe', '--action', 'third_party_apps', '--permission-mode', 'DEFAULT') -AllowFailure
    if ($defaultApp.ok -or $defaultApp.error.code -ne 'SAFETY_POLICY_DENIED') { Fail 'DEFAULT allowed third_party_apps.' }

    $defaultComm = Invoke-AgentJson -CmdArgs @('policy-check', '--title', 'Chat Window', '--process', 'Chat.exe', '--action', 'communication', '--permission-mode', 'DEFAULT') -AllowFailure
    if ($defaultComm.ok -or $defaultComm.error.code -ne 'SAFETY_POLICY_DENIED') { Fail 'DEFAULT allowed communication.' }

    $developerExternal = Invoke-AgentJson -CmdArgs @('policy-check', '--title', 'External Browser test page', '--process', 'chrome.exe', '--action', 'external_web', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY')
    if (-not $developerExternal.ok -or -not $developerExternal.data.allow) { Fail 'DEVELOPER_CAPABILITY_DISCOVERY did not allow external_web.' }

    $developerApp = Invoke-AgentJson -CmdArgs @('policy-check', '--title', 'Third Party App', '--process', 'ThirdParty.exe', '--action', 'third_party_apps', '--permission-mode', 'developer_full_runtime')
    if (-not $developerApp.ok -or -not $developerApp.data.allow) { Fail 'developer_full_runtime alias did not allow third_party_apps.' }

    $developerPrimitive = Invoke-AgentJson -CmdArgs @('policy-check', '--title', 'Exam test challenge fixture', '--process', 'chrome.exe', '--action', 'mouse.double_click', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY')
    if (-not $developerPrimitive.ok -or -not $developerPrimitive.data.allow) { Fail 'Developer mode required FULL_ACCESS for low-level UI primitive or blocked ordinary content keywords.' }

    $activeProtection = Invoke-AgentJson -CmdArgs @('policy-check', '--title', 'captcha human verification', '--process', 'chrome.exe', '--action', 'mouse.click', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY') -AllowFailure
    if ($activeProtection.ok -or $activeProtection.error.code -ne 'STOP_ACTIVE_PROTECTION') { Fail 'Developer mode did not stop active protection.' }

    $fullNoSession = Invoke-AgentJson -CmdArgs @('policy-check', '--title', 'External Browser', '--process', 'msedge.exe', '--action', 'external_web', '--permission-mode', 'FULL_ACCESS') -AllowFailure
    if ($fullNoSession.ok -or $fullNoSession.error.code -ne 'FULL_ACCESS_SESSION_REQUIRED') { Fail 'FULL_ACCESS without session was not denied.' }

    $nonInteractiveUnlock = Invoke-AgentJson -CmdArgs @('unlock-full-access', '--ttl', '30', '--scope', 'session-only') -AllowFailure
    if ($nonInteractiveUnlock.ok -or $nonInteractiveUnlock.error.code -ne 'FULL_ACCESS_REQUIRES_INTERACTIVE_CONFIRMATION') {
        Fail 'Non-interactive unlock-full-access should require local interactive confirmation.'
    }

    $status = Invoke-AgentJson -CmdArgs @('permission-status')
    if ($status.data.full_access.active) { Fail 'Non-interactive unlock-full-access should not create an active session.' }

    $taskPath = Join-Path $Artifacts 'permission_full_access_without_session.task.json'
    $taskReport = Join-Path $Artifacts 'permission_full_access_without_session_report.md'
    @'
{
  "version": 1,
  "name": "permission_full_access_without_session",
  "permission_mode": "FULL_ACCESS",
  "target": { "title": "External Browser", "process": "msedge.exe" },
  "steps": [
    { "name": "observe target", "type": "observe" }
  ]
}
'@ | Set-Content -LiteralPath $taskPath -Encoding UTF8
    $taskDenied = Invoke-AgentJson -CmdArgs @('run-task', '--file', $taskPath, '--report', $taskReport) -AllowFailure
    if ($taskDenied.ok -or $taskDenied.error.code -ne 'FULL_ACCESS_SESSION_REQUIRED') { Fail 'run-task FULL_ACCESS without session was not denied.' }

    Get-Process winagent -ErrorAction SilentlyContinue | Stop-Process -Force
    Remove-Item -LiteralPath $ServiceAudit -ErrorAction SilentlyContinue
    $svc = Start-Process -FilePath $WinAgent -ArgumentList @('serve', '--max-session-ms', '120000') -NoNewWindow -PassThru
    Start-Sleep -Milliseconds 1000
    if ($svc.HasExited) { Fail "Service exited early with code $($svc.ExitCode)." }

    $svcNoSession = Send-ServiceRequest '/policy-check' @{ title = 'External Browser'; process = 'msedge.exe'; action = 'external_web'; permission_mode = 'FULL_ACCESS' }
    if ($svcNoSession.ok -or $svcNoSession.error.code -ne 'FULL_ACCESS_SESSION_REQUIRED') { Fail 'Service FULL_ACCESS without session was not denied.' }

    $svcUnlock = Send-ServiceRequest '/unlock-full-access' @{ ttl = 30; scope = 'session-only' }
    if ($svcUnlock.ok -or $svcUnlock.error.code -ne 'INVALID_ARGUMENT') { Fail 'Service should not expose unlock-full-access.' }

    [void](Send-ServiceRequest '/shutdown' @{})
    Start-Sleep -Milliseconds 500
    if (-not (Test-Path -LiteralPath $ServiceAudit)) { Fail 'service_audit.log was not written.' }
    $auditText = Get-Content -LiteralPath $ServiceAudit -Raw
    if ($auditText -notmatch 'permission_mode="FULL_ACCESS"') { Fail 'service audit did not record permission_mode.' }

    [void](Invoke-AgentJson -CmdArgs @('lock-full-access'))
    Write-Host 'Permission profile selftest passed.'
} finally {
    if ($svc -and -not $svc.HasExited) { Stop-Process -Id $svc.Id -Force }
}
