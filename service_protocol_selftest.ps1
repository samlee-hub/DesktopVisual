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
$Artifacts = Join-Path $Root 'artifacts\service_protocol'
$AuditLog = Join-Path $Root 'artifacts\service_audit.log'
$PidFile = Join-Path $Artifacts 'service_protocol_pid.txt'
$PipeName = 'DesktopVisualService'
New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null

function Fail($Message) { throw "FAIL: $Message" }

if (-not $SkipBuild) {
    & (Join-Path $Root 'build.ps1') -Root $Root
    if ($LASTEXITCODE -ne 0) { Fail "build.ps1 failed with exit code $LASTEXITCODE" }
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

function Assert-ServiceEnvelope($Response, [string]$Endpoint) {
    foreach ($field in @('ok','error_code','message','data','artifacts','report_path','duration_ms','service_protocol_version')) {
        if (-not ($Response.PSObject.Properties.Name -contains $field)) {
            Fail "$Endpoint missing envelope field '$field'"
        }
    }
    if ($Response.service_protocol_version -ne '1.0') { Fail "$Endpoint protocol version was $($Response.service_protocol_version)" }
    if ($null -eq $Response.artifacts) { Fail "$Endpoint artifacts must be an array" }
    if ($null -eq $Response.duration_ms -or [int]$Response.duration_ms -lt 0) { Fail "$Endpoint duration_ms invalid" }
}

function Invoke-Checked($Endpoint, $Body) {
    $response = Send-ServiceRequest $Endpoint $Body
    Assert-ServiceEnvelope $response $Endpoint
    return $response
}

Get-Process winagent -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Process TestWindow -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item -LiteralPath $AuditLog -ErrorAction SilentlyContinue

$service = $null
$testWindow = $null
try {
    if (-not (Test-Path -LiteralPath $TestWindowExe)) { Fail "Missing TestWindow.exe: $TestWindowExe" }
    $testWindow = Start-Process -FilePath $TestWindowExe -PassThru
    Start-Sleep -Milliseconds 800

    $service = Start-Process -FilePath $WinAgent -ArgumentList @('serve','--max-session-ms','300000') -NoNewWindow -PassThru
    $service.Id | Set-Content -LiteralPath $PidFile -Encoding ASCII
    Start-Sleep -Milliseconds 1000
    if ($service.HasExited) { Fail "service exited early with code $($service.ExitCode)" }

    $expectedVersion = (Get-Content -LiteralPath (Join-Path $Root 'VERSION') -Raw).Trim()
    $version = Invoke-Checked '/version' @{}
    if (-not $version.ok -or $version.data.version -ne $expectedVersion) { Fail "/version did not return $expectedVersion" }
    if ($version.data.service_protocol_version -ne '1.0') { Fail "/version data missing service protocol version" }

    $health = Invoke-Checked '/health-check' @{}
    if (-not $health.ok -or $health.data.status -ne 'ok') { Fail "/health-check failed" }

    $safety = Invoke-Checked '/safety-report' @{}
    if (-not $safety.ok) { Fail "/safety-report failed: $($safety.message)" }

    $policy = Invoke-Checked '/policy-check' @{ title='Agent Test Window'; process='TestWindow.exe'; action='observe' }
    if (-not $policy.ok) { Fail "/policy-check failed: $($policy.message)" }

    $consent = Invoke-Checked '/consent-check' @{ title='Agent Test Window' }
    if (-not $consent.ok) { Fail "/consent-check failed: $($consent.message)" }

    $observe = Invoke-Checked '/observe' @{ title='Agent Test Window'; screenshot='false'; uia='true' }
    if (-not $observe.ok) { Fail "/observe failed: $($observe.message)" }

    $locate = Invoke-Checked '/locate' @{ title='Agent Test Window'; selector='uia:name=Click Me' }
    if (-not $locate.ok) { Fail "/locate failed: $($locate.message)" }

    $act = Invoke-Checked '/act' @{ title='Agent Test Window'; selector='uia:name=Click Me'; action='click' }
    if (-not $act.ok) { Fail "/act failed: $($act.message)" }

    $taskFile = Join-Path $Root 'tasks\testwindow_basic.task.json'
    $taskReport = Join-Path $Artifacts 'service_protocol_task_report.md'
    $task = Invoke-Checked '/run-task' @{ file=$taskFile; report=$taskReport }
    if (-not $task.ok -or $task.report_path -ne $taskReport -or -not (Test-Path -LiteralPath $taskReport)) {
        Fail "/run-task did not return report_path or generate report"
    }

    $readReport = Invoke-Checked '/read-report' @{ path=$taskReport }
    if (-not $readReport.ok -or [int]$readReport.data.content_length -le 0) { Fail "/read-report failed" }

    $denied = Invoke-Checked '/policy-check' @{ title='captcha human verification'; process='TestWindow.exe'; action='click'; permission_mode='DEVELOPER_CAPABILITY_DISCOVERY' }
    if ($denied.ok -or $denied.error_code -ne 'STOP_ACTIVE_PROTECTION') { Fail "/policy-check active protection path did not use unified error_code" }

    $shutdown = Invoke-Checked '/shutdown' @{}
    if (-not $shutdown.ok) { Fail "/shutdown failed" }
    Start-Sleep -Milliseconds 800

    if (-not (Test-Path -LiteralPath $AuditLog)) { Fail "service audit log was not created" }
    $audit = Get-Content -LiteralPath $AuditLog
    foreach ($endpoint in @('/version','/health-check','/safety-report','/policy-check','/consent-check','/observe','/locate','/act','/run-task','/read-report','/shutdown')) {
        $endpointNeedle = 'endpoint="' + $endpoint + '"'
        if (-not ($audit | Select-String -SimpleMatch $endpointNeedle -Quiet)) {
            Fail "service audit missing $endpoint"
        }
    }
    if (-not ($audit | Select-String -Pattern 'service_protocol_version="1\.0"' -Quiet)) {
        Fail "service audit missing protocol version"
    }

    Write-Host "Service protocol selftest passed. Report: $taskReport"
} finally {
    Get-Process winagent -ErrorAction SilentlyContinue | Stop-Process -Force
    Get-Process TestWindow -ErrorAction SilentlyContinue | Stop-Process -Force
    Remove-Item -LiteralPath $PidFile -ErrorAction SilentlyContinue
}
