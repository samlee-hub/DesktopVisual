param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\task_service_protocol_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates v5.7 task CLI commands and service task API.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.7.2'
$Report = Join-Path $ArtifactDir 'task_service_protocol_selftest_report.md'
$PipeName = 'DesktopVisualService'
$TaskFile = Join-Path $Root 'tasks\session_schema\local_form_fill_submit_mock_audit.task-session.json'

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

function Fail($Message) { throw "FAIL: $Message" }

function Invoke-JsonCommand([string[]]$CommandArgs) {
    $output = & $WinAgent @CommandArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        Fail "Command failed ($($CommandArgs -join ' ')): $output"
    }
    try { return ($output | Out-String) | ConvertFrom-Json } catch { Fail "Invalid JSON from $($CommandArgs -join ' '): $output" }
}

function Send-ServiceRequest($Endpoint, $Body) {
    $request = @{ endpoint = $Endpoint; body = $Body } | ConvertTo-Json -Compress
    $pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', $PipeName, [System.IO.Pipes.PipeDirection]::InOut)
    $pipe.Connect(5000)
    $writer = New-Object System.IO.StreamWriter($pipe)
    $writer.AutoFlush = $true
    $writer.WriteLine($request)
    $reader = New-Object System.IO.StreamReader($pipe)
    $response = $reader.ReadLine()
    $pipe.Close()
    if ([string]::IsNullOrWhiteSpace($response)) { Fail "Empty service response for $Endpoint" }
    try { return $response | ConvertFrom-Json } catch { Fail "Invalid JSON for $Endpoint`: $response" }
}

function Assert-Envelope($Response, [string]$Endpoint) {
    foreach ($field in @('ok','error_code','message','data','artifacts','report_path','duration_ms','service_protocol_version')) {
        if (-not ($Response.PSObject.Properties.Name -contains $field)) { Fail "$Endpoint missing envelope field $field" }
    }
    if ($Response.service_protocol_version -ne '1.0') { Fail "$Endpoint unexpected service protocol version $($Response.service_protocol_version)" }
}

$helpText = (& $WinAgent help 2>&1 | Out-String)
foreach ($command in @('run-task','task-status','task-report','task-cancel','task-confirm','task-events')) {
    if ($helpText -notmatch [regex]::Escape($command)) { Fail "help output missing $command" }
}

foreach ($invalidCommand in @(
    @('run-task'),
    @('task-status'),
    @('task-events'),
    @('task-report'),
    @('task-confirm'),
    @('task-cancel')
)) {
    $bad = & $WinAgent @invalidCommand 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -or $bad -notmatch 'INVALID_ARGUMENT') {
        Fail "$($invalidCommand[0]) invalid args did not fail with INVALID_ARGUMENT"
    }
}

$run = Invoke-JsonCommand -CommandArgs @('run-task','--file',$TaskFile)
if (-not $run.ok -or -not $run.data.task_id -or $run.data.current_state -ne 'completed') { Fail 'CLI run-task did not complete TaskSession' }
$taskId = [string]$run.data.task_id

$status = Invoke-JsonCommand -CommandArgs @('task-status','--task-id',$taskId)
if (-not $status.ok -or $status.data.current_state -ne 'completed' -or -not $status.data.machine_readable_status) { Fail 'task-status did not return completed machine-readable status' }

$events = Invoke-JsonCommand -CommandArgs @('task-events','--task-id',$taskId)
if (-not $events.ok -or [int]$events.data.event_count -lt 1) { Fail 'task-events did not return event_count' }

$taskReport = Invoke-JsonCommand -CommandArgs @('task-report','--task-id',$taskId)
if (-not $taskReport.ok -or -not (Test-Path -LiteralPath $taskReport.data.report_path)) { Fail 'task-report did not return report path' }

$confirm = Invoke-JsonCommand -CommandArgs @('task-confirm','--task-id',$taskId,'--response','confirm')
if (-not $confirm.ok -or $confirm.data.response -ne 'confirm') { Fail 'task-confirm did not record confirm response' }

$cancel = Invoke-JsonCommand -CommandArgs @('task-cancel','--task-id',$taskId,'--reason','selftest cancel after completion')
if (-not $cancel.ok -or $cancel.data.cancelled -ne $false) { Fail 'task-cancel should be stable no-op for completed task' }

Get-Process winagent -ErrorAction SilentlyContinue | Stop-Process -Force
$service = $null
try {
    $service = Start-Process -FilePath $WinAgent -ArgumentList @('serve','--max-session-ms','300000') -NoNewWindow -PassThru
    Start-Sleep -Milliseconds 1000
    if ($service.HasExited) { Fail "service exited early with code $($service.ExitCode)" }

    foreach ($healthEndpoint in @('/health','/health-check')) {
        $health = Send-ServiceRequest $healthEndpoint @{}
        Assert-Envelope $health $healthEndpoint
        if (-not $health.ok -or $health.data.service_protocol_version -ne '1.0') { Fail "$healthEndpoint failed" }
    }

    $capabilities = Send-ServiceRequest '/capabilities' @{}
    Assert-Envelope $capabilities '/capabilities'
    if ($capabilities.data.service_protocol_version -ne '1.0') { Fail '/capabilities missing service_protocol_version' }
    if ($capabilities.data.safety_bypass -ne $false) { Fail '/capabilities must report safety_bypass=false' }
    if (-not $capabilities.ok -or -not ($capabilities.data.available -contains 'task_service_protocol')) { Fail '/capabilities missing task_service_protocol' }

    $invalidSvcRun = Send-ServiceRequest '/run_task' @{}
    Assert-Envelope $invalidSvcRun '/run_task invalid'
    if ($invalidSvcRun.ok -ne $false -or $invalidSvcRun.error_code -ne 'INVALID_ARGUMENT') { Fail '/run_task invalid args did not fail with INVALID_ARGUMENT' }

    $svcRun = Send-ServiceRequest '/run_task' @{ file = $TaskFile }
    Assert-Envelope $svcRun '/run_task'
    if (-not $svcRun.ok -or $svcRun.data.current_state -ne 'completed') { Fail '/run_task did not complete TaskSession' }
    $svcTaskId = [string]$svcRun.data.task_id

    foreach ($pair in @(
        @('/get_task_status', @{ task_id = $svcTaskId }),
        @('/get_task_events', @{ task_id = $svcTaskId }),
        @('/read_task_report', @{ task_id = $svcTaskId }),
        @('/confirm_task_action', @{ task_id = $svcTaskId; response = 'confirm' }),
        @('/cancel_task', @{ task_id = $svcTaskId; reason = 'selftest cancel after completion' })
    )) {
        $resp = Send-ServiceRequest $pair[0] $pair[1]
        Assert-Envelope $resp $pair[0]
        if (-not $resp.ok) { Fail "$($pair[0]) failed: $($resp.message)" }
    }

    $shutdown = Send-ServiceRequest '/shutdown' @{}
    Assert-Envelope $shutdown '/shutdown'
} finally {
    Get-Process winagent -ErrorAction SilentlyContinue | Stop-Process -Force
}

$lines = @(
    '# v5.7.2 Task Service Protocol Selftest',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "- CLI task_id: $taskId",
    '- CLI commands: run-task, task-status, task-report, task-events, task-confirm, task-cancel',
    '- Service endpoints: health, capabilities, run_task, get_task_status, get_task_events, confirm_task_action, cancel_task, read_task_report'
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.7 task service protocol selftest'
Write-Host "Report: $Report"
