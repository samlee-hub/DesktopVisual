param(
    [string]$Root = '',
    [string]$TestRepoRoot = '',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$Artifacts = Join-Path $Root 'artifacts'
$SafetyArtifacts = Join-Path $Artifacts 'safety'
if (-not $TestRepoRoot) { $TestRepoRoot = $env:DESKTOPVISUAL_TESTREPO_ROOT }
if (-not $TestRepoRoot) {
    $sibling = Join-Path (Split-Path -Parent $Root) 'testrepo'
    if (Test-Path -LiteralPath $sibling) { $TestRepoRoot = $sibling }
}
if (-not $TestRepoRoot) { $TestRepoRoot = 'D:\testrepo' }
$TestRepoRoot = [System.IO.Path]::GetFullPath($TestRepoRoot)
$TestWindowExe = Join-Path $TestRepoRoot 'testwindow\bin\TestWindow.exe'
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
    & "$Root\build.ps1" -Root $Root -TestRepoRoot $TestRepoRoot
    if ($LASTEXITCODE -ne 0) { Fail 'Build failed.' }
}

New-Item -ItemType Directory -Force -Path $SafetyArtifacts | Out-Null

$tw = $null
$svc = $null
try {
    Get-Process TestWindow -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 200
    $tw = Start-Process -FilePath $TestWindowExe -PassThru
    Start-Sleep -Milliseconds 800

    $report = Invoke-AgentJson -CmdArgs @('safety-report')
    if (-not $report.ok) { Fail 'safety-report returned ok=false.' }
    if (-not $report.data.manifest_loaded) { Fail 'safety-report did not load safety_manifest.json.' }
    if (-not (Test-Path (Join-Path $SafetyArtifacts 'safety_report.md'))) { Fail 'safety_report.md was not generated.' }
    if (-not (Test-Path (Join-Path $SafetyArtifacts 'safety_report.json'))) { Fail 'safety_report.json was not generated.' }

    $allow = Invoke-AgentJson -CmdArgs @('policy-check', '--title', 'Agent Test Window', '--process', 'TestWindow.exe', '--action', 'click')
    if (-not $allow.ok -or -not $allow.data.allow) { Fail 'policy-check did not allow TestWindow click.' }

    $developerProc = Invoke-AgentJson -CmdArgs @('policy-check', '--title', 'Agent Test Window', '--process', 'explorer.exe', '--action', 'click', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY')
    if (-not $developerProc.ok -or -not $developerProc.data.allow) { Fail 'developer policy-check did not allow ordinary non-whitelisted process.' }

    $ordinaryContentTitle = Invoke-AgentJson -CmdArgs @('policy-check', '--title', 'Password Credential test exam challenge Window', '--process', 'TestWindow.exe', '--action', 'click', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY')
    if (-not $ordinaryContentTitle.ok -or -not $ordinaryContentTitle.data.allow) { Fail 'developer policy-check blocked ordinary content/title keywords.' }

    $activeProtectionTitle = Invoke-AgentJson -CmdArgs @('policy-check', '--title', 'captcha human verification', '--process', 'TestWindow.exe', '--action', 'click', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY') -AllowFailure
    if ($activeProtectionTitle.ok -or $activeProtectionTitle.error.code -ne 'STOP_ACTIVE_PROTECTION') { Fail 'policy-check did not stop active protection title.' }

    $missingConsent = Invoke-AgentJson -CmdArgs @('consent-check', '--title', 'Definitely Missing DesktopVisual Window') -AllowFailure
    if ($missingConsent.ok -or $missingConsent.error.code -ne 'WINDOW_NOT_FOUND') { Fail 'consent-check did not return WINDOW_NOT_FOUND for missing window.' }

    $taskPath = Join-Path $Artifacts 'safety_manifest_active_protection_task.json'
    $taskReport = Join-Path $Artifacts 'safety_manifest_active_protection_task_report.md'
    @'
{
  "version": 1,
  "name": "safety_manifest_active_protection_task",
  "target": { "title": "captcha human verification", "process": "TestWindow.exe" },
  "permission_mode": "DEVELOPER_CAPABILITY_DISCOVERY",
  "allow_unrestricted_desktop": true,
  "steps": [
    { "name": "must_stop_before_action", "type": "act", "selector": "uia:name=Click Me", "action": "click" }
  ]
}
'@ | Set-Content -Path $taskPath -Encoding UTF8
    $task = Invoke-AgentJson -CmdArgs @('run-task', '--file', $taskPath, '--report', $taskReport) -AllowFailure
    if ($task.ok -or $task.error.code -ne 'SAFETY_POLICY_DENIED') { Fail 'run-task did not stop unrestricted desktop task with SAFETY_POLICY_DENIED.' }
    $taskReportText = Get-Content -Path $taskReport -Raw
    if ($taskReportText -notmatch 'Safety Manifest') { Fail 'run-task report does not include Safety Manifest summary.' }

    Get-Process winagent -ErrorAction SilentlyContinue | Stop-Process -Force
    Remove-Item $ServiceAudit -ErrorAction SilentlyContinue
    $svc = Start-Process -FilePath $WinAgent -ArgumentList @('serve', '--max-session-ms', '120000') -NoNewWindow -PassThru
    Start-Sleep -Milliseconds 1000
    if ($svc.HasExited) { Fail "Service exited early with code $($svc.ExitCode)." }
    $svcReport = Send-ServiceRequest '/safety-report' @{}
    if (-not $svcReport.ok -or -not $svcReport.data.manifest_loaded) { Fail 'service /safety-report failed.' }
    [void](Send-ServiceRequest '/shutdown' @{})
    Start-Sleep -Milliseconds 500
    if (-not (Test-Path $ServiceAudit)) { Fail 'service_audit.log was not written.' }
    $auditText = Get-Content -Path $ServiceAudit -Raw
    if ($auditText -notmatch '/safety-report') { Fail 'service_audit.log does not include /safety-report.' }
    if ($auditText -match 'secret clipboard password') { Fail 'service_audit.log included sensitive clipboard text.' }

    $version = Invoke-AgentJson -CmdArgs @('version')
    if ($null -eq $version.data.manifest_loaded) { Fail 'version output does not include manifest_loaded.' }

    Write-Host 'Safety manifest selftest passed.'
    Write-Host "Report: $(Join-Path $SafetyArtifacts 'safety_report.md')"
} finally {
    if ($svc -and -not $svc.HasExited) { Stop-Process -Id $svc.Id -Force }
    if ($tw -and -not $tw.HasExited) { Stop-Process -Id $tw.Id -Force }
}
