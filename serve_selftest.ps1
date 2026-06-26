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
$Artifacts = Join-Path $Root 'artifacts'
$PipeName = '\\.\pipe\DesktopVisualService'
$AuditLog = Join-Path $Artifacts 'service_audit.log'
$PidFile = Join-Path $Artifacts 'service_pid.txt'

function Fail($msg) { throw "FAIL: $msg" }
function Pass($msg) { Write-Host "  PASS: $msg" -ForegroundColor Green }

if (-not $SkipBuild) {
    Write-Host "Building..."
    & "$Root\build.ps1" -Root $Root
    if ($LASTEXITCODE -ne 0) { Fail "Build failed" }
}

$passed = 0; $failed = 0

function Check($name, [scriptblock]$test) {
    Write-Host "=== $name ===" -ForegroundColor Cyan
    try { & $test; $script:passed++ } catch { Write-Host "  $_" -ForegroundColor Red; $script:failed++ }
}

# Kill any existing service
Get-Process winagent -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500

# Start TestWindow
Get-Process TestWindow -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 200
$tw = Start-Process -FilePath $TestWindowExe -PassThru
Start-Sleep -Milliseconds 800

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

# 1. Start service
Check "Start winagent serve" {
    $args = @('serve', '--port', '17873', '--max-session-ms', '300000')
    $proc = Start-Process -FilePath $WinAgent -ArgumentList $args -NoNewWindow -PassThru
    $proc.Id | Out-File $PidFile
    Start-Sleep -Milliseconds 1000

    if ($proc.HasExited) { Fail "Service process exited immediately (code $($proc.ExitCode))" }
    Pass "Service started (PID $($proc.Id))"
}

# 2. /version
Check "GET /version" {
    $resp = Send-ServiceRequest '/version' @{}
    if (-not $resp.ok) { Fail "/version failed: $($resp.error.message)" }
    if ($resp.data.version -ne '3.5.0') { Write-Host "  WARNING: version string is $($resp.data.version), expected 3.5.0" -ForegroundColor Yellow }
    if ($resp.service_protocol_version -ne '1.0') { Fail "service protocol version is $($resp.service_protocol_version)" }
    Pass "/version ok: v$($resp.data.version)"
}

# 3. /observe
Check "POST /observe" {
    $resp = Send-ServiceRequest '/observe' @{title='Agent Test Window';screenshot='false';uia='true'}
    if (-not $resp.ok) { Fail "/observe failed: $($resp.error.message)" }
    Pass "/observe ok"
}

# 4. /locate
Check "POST /locate" {
    $resp = Send-ServiceRequest '/locate' @{title='Agent Test Window';selector='uia:name=Click Me'}
    if (-not $resp.ok) { Fail "/locate failed: $($resp.error.message)" }
    Pass "/locate ok: method=$($resp.data.locate_method)"
}

# 5. /act
Check "POST /act click" {
    $resp = Send-ServiceRequest '/act' @{title='Agent Test Window';selector='uia:name=Click Me';action='click';text=''}
    if (-not $resp.ok) { Fail "/act failed: $($resp.error.message)" }
    Pass "/act click ok: method=$($resp.data.action_method)"
}

# 6. /run-case
Check "POST /run-case" {
    $caseFile = Join-Path $Root 'cases\case_v2_basic.case'
    $reportFile = Join-Path $Artifacts 'serve_selftest_case_v2_report.md'
    $resp = Send-ServiceRequest '/run-case' @{file=$caseFile;report=$reportFile}
    if (-not $resp.ok) { Fail "/run-case failed: $($resp.error.message)" }
    Pass "/run-case ok: $($resp.data.step_count) steps, $($resp.data.passed_step_count) passed"
}

# 7. /report
Check "GET /report" {
    $reportFile = Join-Path $Artifacts 'serve_selftest_case_v2_report.md'
    if (Test-Path $reportFile) {
        $resp = Send-ServiceRequest '/report' @{path=$reportFile}
        if (-not $resp.ok) { Fail "/report failed: $($resp.error.message)" }
        Pass "/report ok: content_length=$($resp.data.content_length)"
    } else {
        Pass "/report skipped (no report to read)"
    }
}

# 8. /shutdown
Check "POST /shutdown" {
    $resp = Send-ServiceRequest '/shutdown' @{}
    Start-Sleep -Milliseconds 1000
    Pass "/shutdown ok"
}

# 9. Verify service_audit.log
Check "service_audit.log exists" {
    if (Test-Path $AuditLog) {
        $lines = Get-Content $AuditLog
        if ($lines.Count -gt 0) {
            Pass "service_audit.log has $($lines.Count) entries"
        } else {
            Fail "service_audit.log is empty"
        }
    } else {
        Fail "service_audit.log not found at $AuditLog"
    }
}

# Cleanup
Get-Process winagent -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Process TestWindow -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item $PidFile -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "===================================" -ForegroundColor Cyan
Write-Host "Serve Selftest v3.5" -ForegroundColor Cyan
Write-Host "Passed: $passed / $($passed + $failed)" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Green' })
if ($failed -gt 0) { exit 1 }
exit 0
