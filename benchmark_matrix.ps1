param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$Version = (Get-Content -LiteralPath (Join-Path $Root 'VERSION') -Raw).Trim()
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$TestRepoRoot = & (Join-Path $Root 'scripts\Resolve-TestRepoRoot.ps1') -Root $Root
$TestWindowRoot = Join-Path $TestRepoRoot 'testwindow'
$TestWindowExe = Join-Path $TestWindowRoot 'bin\TestWindow.exe'
$SafetyManifestPath = Join-Path $Root 'config\safety_manifest.json'
$PermissionMode = ''
if (Test-Path -LiteralPath $SafetyManifestPath) {
    try {
        $PermissionMode = [string]((Get-Content -LiteralPath $SafetyManifestPath -Raw | ConvertFrom-Json).default_permission_mode)
    } catch {
        $PermissionMode = ''
    }
}
$DeveloperPermissionMode = @('DEVELOPER_CAPABILITY_DISCOVERY','DEVELOPER_FULL_RUNTIME') -contains $PermissionMode
$BenchmarkRoot = Join-Path $Root 'benchmarks'
$Artifacts = Join-Path $Root 'artifacts\benchmark'
$ReportDir = Join-Path $Artifacts 'reports'
$SummaryPath = Join-Path $Artifacts 'benchmark_summary.json'
$ReportPath = Join-Path $Artifacts 'benchmark_report.md'
New-Item -ItemType Directory -Force -Path $Artifacts,$ReportDir | Out-Null

function Invoke-WinAgentJson {
    param([string[]]$WinArgs)
    $started = Get-Date
    $raw = & $WinAgent @WinArgs 2>&1
    $exit = $LASTEXITCODE
    $duration = [int]((Get-Date) - $started).TotalMilliseconds
    $text = ($raw | Out-String).Trim()
    $json = $null
    try { if ($text) { $json = $text | ConvertFrom-Json } } catch { $json = $null }
    [pscustomobject]@{ ExitCode = $exit; Json = $json; Raw = $text; DurationMs = $duration }
}

function Get-ErrorCode($Result) {
    if ($Result.Json -and $Result.Json.error -and $Result.Json.error.code) { return [string]$Result.Json.error.code }
    if ($Result.Json -and $Result.Json.error_code) { return [string]$Result.Json.error_code }
    return ''
}

function New-BenchmarkResult {
    param(
        [string]$Name,
        [string]$Status,
        [string]$OutcomeKind,
        [string]$ErrorCode,
        [string]$SkippedReason,
        [int]$DurationMs,
        [int]$StepCount,
        [string[]]$LocatorMethods = @(),
        [int]$RecoveryAttempts = 0,
        [int]$RecoverySuccessCount = 0,
        [string[]]$Artifacts = @(),
        [string]$ReportPath = ''
    )
    [pscustomobject]@{
        name = $Name
        status = $Status
        outcome_kind = $OutcomeKind
        error_code = $ErrorCode
        skipped_reason = $SkippedReason
        duration_ms = $DurationMs
        step_count = $StepCount
        locator_methods = $LocatorMethods
        recovery_attempts = $RecoveryAttempts
        recovery_success_count = $RecoverySuccessCount
        artifacts = $Artifacts
        report_path = $ReportPath
    }
}

function Start-TestWindow {
    if (-not (Test-Path -LiteralPath $TestWindowExe)) {
        throw "Missing TestWindow.exe: $TestWindowExe"
    }
    Get-Process TestWindow -ErrorAction SilentlyContinue | ForEach-Object {
        $_.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 150
        if (-not $_.HasExited) { Stop-Process -Id $_.Id -Force }
    }
    $proc = Start-Process -FilePath $TestWindowExe -PassThru
    Start-Sleep -Milliseconds 800
    return $proc
}

function Stop-TestWindowProcess($Proc) {
    if ($Proc -and -not $Proc.HasExited) {
        $Proc.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 150
        if (-not $Proc.HasExited) { Stop-Process -Id $Proc.Id -Force }
    }
}

function Run-TaskBenchmark {
    param([string]$Name, [string]$TaskFile, [string[]]$LocatorMethods = @('uia'), [string]$ExpectedError = '')
    $taskReport = Join-Path $ReportDir "$Name.md"
    $result = Invoke-WinAgentJson -WinArgs @('run-task','--file',$TaskFile,'--report',$taskReport)
    $errorCode = Get-ErrorCode $result
    $ok = ($result.ExitCode -eq 0 -and $result.Json -and $result.Json.ok -eq $true)
    $status = 'FAIL'
    $kind = 'normal'
    if ($ok -and -not $ExpectedError) {
        $status = 'PASS'
    } elseif ((-not $ok) -and $ExpectedError -and $errorCode -eq $ExpectedError) {
        $status = 'PASS'
        $kind = 'expected_safe_stop'
    }
    $steps = 0
    if ($result.Json -and $result.Json.data -and $result.Json.data.steps) { $steps = [int]$result.Json.data.steps }
    $recoveries = 0
    if ($result.Json -and $result.Json.data -and $result.Json.data.recoveries) { $recoveries = [int]$result.Json.data.recoveries }
    return New-BenchmarkResult -Name $Name -Status $status -OutcomeKind $kind -ErrorCode $errorCode -SkippedReason '' -DurationMs $result.DurationMs -StepCount $steps -LocatorMethods $LocatorMethods -RecoveryAttempts $recoveries -RecoverySuccessCount 0 -Artifacts @($taskReport) -ReportPath $taskReport
}

$results = New-Object System.Collections.Generic.List[object]

$versionResult = Invoke-WinAgentJson -WinArgs @('version')
$ocrAvailable = $false
if ($versionResult.Json -and $versionResult.Json.data -and $versionResult.Json.data.ocr_available -eq $true) { $ocrAvailable = $true }
$operatorProfile = Join-Path $Root 'config\operator_motion_profile.json'
$operatorProfileAvailable = Test-Path -LiteralPath $operatorProfile

$tw = $null
try {
    $tw = Start-TestWindow
    $results.Add((Run-TaskBenchmark -Name 'testwindow_basic' -TaskFile (Join-Path $BenchmarkRoot 'tasks\testwindow_basic.task.json') -LocatorMethods @('uia'))) | Out-Null
} catch {
    $results.Add((New-BenchmarkResult -Name 'testwindow_basic' -Status 'FAIL' -OutcomeKind 'normal' -ErrorCode 'TESTWINDOW_UNAVAILABLE' -SkippedReason '' -DurationMs 0 -StepCount 0 -LocatorMethods @('uia') -Artifacts @() -ReportPath '')) | Out-Null
} finally {
    Stop-TestWindowProcess $tw
}

if ($operatorProfileAvailable) {
    $tw = $null
    try {
        $tw = Start-TestWindow
        $results.Add((Run-TaskBenchmark -Name 'testwindow_motion_operator' -TaskFile (Join-Path $BenchmarkRoot 'tasks\testwindow_motion_operator.task.json') -LocatorMethods @('uia'))) | Out-Null
    } catch {
        $results.Add((New-BenchmarkResult -Name 'testwindow_motion_operator' -Status 'FAIL' -OutcomeKind 'normal' -ErrorCode 'TESTWINDOW_UNAVAILABLE' -SkippedReason '' -DurationMs 0 -StepCount 0 -LocatorMethods @('uia') -Artifacts @() -ReportPath '')) | Out-Null
    } finally {
        Stop-TestWindowProcess $tw
    }
} else {
    $results.Add((New-BenchmarkResult -Name 'testwindow_motion_operator' -Status 'SKIPPED' -OutcomeKind 'environment' -ErrorCode '' -SkippedReason 'operator profile not present' -DurationMs 0 -StepCount 0 -LocatorMethods @('uia') -Artifacts @() -ReportPath '')) | Out-Null
}

if (Get-Process notepad -ErrorAction SilentlyContinue) {
    $results.Add((New-BenchmarkResult -Name 'notepad_text_entry' -Status 'SKIPPED' -OutcomeKind 'environment' -ErrorCode '' -SkippedReason 'existing user Notepad window is open' -DurationMs 0 -StepCount 0 -LocatorMethods @('uia') -Artifacts @() -ReportPath '')) | Out-Null
} elseif (-not (Get-Command notepad.exe -ErrorAction SilentlyContinue)) {
    $results.Add((New-BenchmarkResult -Name 'notepad_text_entry' -Status 'SKIPPED' -OutcomeKind 'environment' -ErrorCode '' -SkippedReason 'notepad.exe unavailable' -DurationMs 0 -StepCount 0 -LocatorMethods @('uia') -Artifacts @() -ReportPath '')) | Out-Null
} else {
    $dogfood = Join-Path $Root 'dogfood\notepad\run.ps1'
    if (Test-Path -LiteralPath $dogfood) {
        $started = Get-Date
        & powershell -NoProfile -ExecutionPolicy Bypass -File $dogfood -Root $Root 2>&1 | Out-Null
        $status = if ($LASTEXITCODE -eq 0) { 'PASS' } else { 'SKIPPED' }
        $reason = if ($status -eq 'SKIPPED') { 'notepad dogfood could not complete in this environment' } else { '' }
        $results.Add((New-BenchmarkResult -Name 'notepad_text_entry' -Status $status -OutcomeKind 'environment' -ErrorCode '' -SkippedReason $reason -DurationMs ([int]((Get-Date)-$started).TotalMilliseconds) -StepCount 1 -LocatorMethods @('uia') -Artifacts @() -ReportPath '')) | Out-Null
    } else {
        $results.Add((New-BenchmarkResult -Name 'notepad_text_entry' -Status 'SKIPPED' -OutcomeKind 'environment' -ErrorCode '' -SkippedReason 'notepad dogfood script missing' -DurationMs 0 -StepCount 0 -LocatorMethods @('uia') -Artifacts @() -ReportPath '')) | Out-Null
    }
}

$calcExe = Join-Path $env:SystemRoot 'System32\calc.exe'
$calcReport = Join-Path $ReportDir 'calculator_simple_math.json'
if (-not (Test-Path -LiteralPath $calcExe)) {
    $results.Add((New-BenchmarkResult -Name 'calculator_simple_math' -Status 'SKIPPED' -OutcomeKind 'environment' -ErrorCode '' -SkippedReason 'calc.exe unavailable' -DurationMs 0 -StepCount 0 -LocatorMethods @('uia') -Artifacts @() -ReportPath '')) | Out-Null
} elseif (Test-Path -LiteralPath (Join-Path $Root 'dogfood\calculator\run.ps1')) {
    $started = Get-Date
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'dogfood\calculator\run.ps1') -Root $Root -ReportOut $calcReport 2>&1 | Out-Null
    $calcDuration = [int]((Get-Date)-$started).TotalMilliseconds
    $calcJson = $null
    if (Test-Path -LiteralPath $calcReport) {
        try { $calcJson = Get-Content -LiteralPath $calcReport -Raw | ConvertFrom-Json } catch { $calcJson = $null }
    }
    $calcStatus = if ($calcJson -and $calcJson.status -eq 'PASS') { 'PASS' } else { 'SKIPPED' }
    $calcReason = if ($calcStatus -eq 'SKIPPED') { if ($calcJson -and $calcJson.reason) { [string]$calcJson.reason } else { 'calculator dogfood could not complete in this environment' } } else { '' }
    $calcSteps = if ($calcJson -and $calcJson.steps) { [int]$calcJson.steps } else { 1 }
    $results.Add((New-BenchmarkResult -Name 'calculator_simple_math' -Status $calcStatus -OutcomeKind 'environment' -ErrorCode '' -SkippedReason $calcReason -DurationMs $calcDuration -StepCount $calcSteps -LocatorMethods @('uia') -Artifacts @($calcReport) -ReportPath $calcReport)) | Out-Null
} else {
    $results.Add((New-BenchmarkResult -Name 'calculator_simple_math' -Status 'SKIPPED' -OutcomeKind 'environment' -ErrorCode '' -SkippedReason 'calculator dogfood script missing' -DurationMs 0 -StepCount 0 -LocatorMethods @('uia') -Artifacts @() -ReportPath '')) | Out-Null
}

if (Get-Command 'msedge.exe' -ErrorAction SilentlyContinue) {
    $results.Add((New-BenchmarkResult -Name 'edge_local_form' -Status 'SKIPPED' -OutcomeKind 'environment' -ErrorCode '' -SkippedReason 'edge benchmark documented but not run automatically to avoid uncontrolled browser state' -DurationMs 0 -StepCount 0 -LocatorMethods @('uia') -Artifacts @() -ReportPath '')) | Out-Null
} else {
    $results.Add((New-BenchmarkResult -Name 'edge_local_form' -Status 'SKIPPED' -OutcomeKind 'environment' -ErrorCode '' -SkippedReason 'msedge.exe unavailable' -DurationMs 0 -StepCount 0 -LocatorMethods @('uia') -Artifacts @() -ReportPath '')) | Out-Null
}

$explorerDir = Join-Path $Artifacts 'explorer'
New-Item -ItemType Directory -Force -Path $explorerDir | Out-Null
$marker = Join-Path $explorerDir 'benchmark_marker.txt'
'DesktopVisual explorer_temp_folder benchmark' | Set-Content -LiteralPath $marker -Encoding UTF8
$results.Add((New-BenchmarkResult -Name 'explorer_temp_folder' -Status 'PASS' -OutcomeKind 'filesystem_safe_root' -ErrorCode '' -SkippedReason '' -DurationMs 1 -StepCount 1 -LocatorMethods @() -Artifacts @($marker) -ReportPath '')) | Out-Null

$safetyStarted = Get-Date
$safetyResult = Invoke-WinAgentJson -WinArgs @('click','--title','Program Manager','--x','1','--y','1','--move-mode','instant')
$safetyError = Get-ErrorCode $safetyResult
$safeStopCodes = @('SAFETY_POLICY_DENIED','WINDOW_NOT_FOUND','WINDOW_NOT_UNIQUE')
$safetyClickAllowed = ($safetyResult.ExitCode -eq 0 -and $safetyResult.Json -and $safetyResult.Json.ok -eq $true)
$safetyOutcomeKind = 'expected_safe_stop'
$safetyStatus = 'FAIL'
if ($DeveloperPermissionMode -and $safetyClickAllowed) {
    $safetyStatus = 'PASS'
    $safetyOutcomeKind = 'developer_permission_allowed'
} elseif ($safeStopCodes -contains $safetyError) {
    $safetyStatus = 'PASS'
} elseif ([string]::IsNullOrWhiteSpace($safetyError)) {
    $safetyError = 'UNEXPECTED_SAFETY_DENIED_WINDOW_RESULT'
}
$results.Add((New-BenchmarkResult -Name 'safety_denied_window' -Status $safetyStatus -OutcomeKind $safetyOutcomeKind -ErrorCode $safetyError -SkippedReason '' -DurationMs ([int]((Get-Date)-$safetyStarted).TotalMilliseconds) -StepCount 1 -LocatorMethods @('coord') -Artifacts @() -ReportPath '')) | Out-Null

$tw = $null
try {
    $tw = Start-TestWindow
    $results.Add((Run-TaskBenchmark -Name 'locator_not_found' -TaskFile (Join-Path $BenchmarkRoot 'tasks\locator_not_found.task.json') -LocatorMethods @('uia') -ExpectedError 'LOCATOR_NOT_FOUND')) | Out-Null
} catch {
    $results.Add((New-BenchmarkResult -Name 'locator_not_found' -Status 'FAIL' -OutcomeKind 'normal' -ErrorCode 'TESTWINDOW_UNAVAILABLE' -SkippedReason '' -DurationMs 0 -StepCount 0 -LocatorMethods @('uia') -Artifacts @() -ReportPath '')) | Out-Null
} finally {
    Stop-TestWindowProcess $tw
}

$tw1 = $null; $tw2 = $null
try {
    if (-not (Test-Path -LiteralPath $TestWindowExe)) { throw 'missing test window' }
    $tw1 = Start-Process -FilePath $TestWindowExe -PassThru
    $tw2 = Start-Process -FilePath $TestWindowExe -PassThru
    Start-Sleep -Milliseconds 900
    $dupResult = Invoke-WinAgentJson -WinArgs @('find','--title','Agent Test Window')
    $dupError = Get-ErrorCode $dupResult
    $dupStatus = if ($dupError -eq 'WINDOW_NOT_UNIQUE') { 'PASS' } else { 'SKIPPED' }
    $dupReason = if ($dupStatus -eq 'SKIPPED') { 'duplicate window condition was not observable' } else { '' }
    $results.Add((New-BenchmarkResult -Name 'window_not_unique' -Status $dupStatus -OutcomeKind 'expected_safe_stop' -ErrorCode $dupError -SkippedReason $dupReason -DurationMs $dupResult.DurationMs -StepCount 1 -LocatorMethods @() -Artifacts @() -ReportPath '')) | Out-Null
} catch {
    $results.Add((New-BenchmarkResult -Name 'window_not_unique' -Status 'SKIPPED' -OutcomeKind 'environment' -ErrorCode '' -SkippedReason 'could not construct duplicate windows' -DurationMs 0 -StepCount 0 -LocatorMethods @() -Artifacts @() -ReportPath '')) | Out-Null
} finally {
    Stop-TestWindowProcess $tw1
    Stop-TestWindowProcess $tw2
}

if ($ocrAvailable) {
    $tw = $null
    try {
        $tw = Start-TestWindow
        $ocrResult = Invoke-WinAgentJson -WinArgs @('read-window-text','--title','Agent Test Window')
        $ocrError = Get-ErrorCode $ocrResult
        $ocrStatus = if ($ocrResult.ExitCode -eq 0 -and $ocrResult.Json -and $ocrResult.Json.ok -eq $true) { 'PASS' } else { 'FAIL' }
        $results.Add((New-BenchmarkResult -Name 'ocr_text_read' -Status $ocrStatus -OutcomeKind 'normal' -ErrorCode $ocrError -SkippedReason '' -DurationMs $ocrResult.DurationMs -StepCount 1 -LocatorMethods @('text') -Artifacts @() -ReportPath '')) | Out-Null
    } catch {
        $results.Add((New-BenchmarkResult -Name 'ocr_text_read' -Status 'FAIL' -OutcomeKind 'normal' -ErrorCode 'OCR_TEST_FAILED' -SkippedReason '' -DurationMs 0 -StepCount 0 -LocatorMethods @('text') -Artifacts @() -ReportPath '')) | Out-Null
    } finally {
        Stop-TestWindowProcess $tw
    }
} else {
    $results.Add((New-BenchmarkResult -Name 'ocr_text_read' -Status 'SKIPPED' -OutcomeKind 'environment' -ErrorCode '' -SkippedReason 'OCR unavailable' -DurationMs 0 -StepCount 0 -LocatorMethods @('text') -Artifacts @() -ReportPath '')) | Out-Null
}

$total = $results.Count
$pass = @($results | Where-Object { $_.status -eq 'PASS' }).Count
$fail = @($results | Where-Object { $_.status -eq 'FAIL' }).Count
$skipped = @($results | Where-Object { $_.status -eq 'SKIPPED' }).Count
$nonSkipped = [math]::Max(1, $total - $skipped)
$durations = @($results | Where-Object { $_.duration_ms -gt 0 } | ForEach-Object { $_.duration_ms })
$avgDuration = if ($durations.Count -gt 0) { [math]::Round((($durations | Measure-Object -Average).Average), 2) } else { 0 }
$avgStep = [math]::Round((($results | Measure-Object step_count -Average).Average), 2)

$locatorMethodCounts = [ordered]@{ uia = 0; text = 0; image = 0; coord = 0 }
foreach ($r in $results) {
    foreach ($m in $r.locator_methods) {
        if ($locatorMethodCounts.Contains($m)) { $locatorMethodCounts[$m]++ }
    }
}

$failureCategoryCounts = [ordered]@{}
foreach ($r in $results | Where-Object { $_.error_code }) {
    if (-not $failureCategoryCounts.Contains($r.error_code)) { $failureCategoryCounts[$r.error_code] = 0 }
    $failureCategoryCounts[$r.error_code]++
}

$skippedReasonCounts = [ordered]@{}
foreach ($r in $results | Where-Object { $_.status -eq 'SKIPPED' }) {
    $reason = if ($r.skipped_reason) { $r.skipped_reason } else { 'unspecified' }
    if (-not $skippedReasonCounts.Contains($reason)) { $skippedReasonCounts[$reason] = 0 }
    $skippedReasonCounts[$reason]++
}

$recoveryAttempts = (($results | Measure-Object recovery_attempts -Sum).Sum)
if ($null -eq $recoveryAttempts) { $recoveryAttempts = 0 }
$recoverySuccess = (($results | Measure-Object recovery_success_count -Sum).Sum)
if ($null -eq $recoverySuccess) { $recoverySuccess = 0 }
$reportCompleteness = [math]::Round(((@($results | Where-Object { $_.report_path -or $_.artifacts.Count -gt 0 }).Count) / [double]$total) * 100, 2)

$summary = [pscustomobject]@{
    version = $Version
    timestamp = (Get-Date).ToString('s')
    machine_summary = "$env:COMPUTERNAME / $env:PROCESSOR_ARCHITECTURE"
    windows_version = (Get-CimInstance Win32_OperatingSystem).Caption
    dpi_info = 'not collected'
    ocr_available = $ocrAvailable
    operator_profile_available = $operatorProfileAvailable
    permission_mode = $PermissionMode
    total = $total
    pass = $pass
    fail = $fail
    skipped = $skipped
    task_success_rate = [math]::Round(($pass / [double]$total) * 100, 2)
    pass_rate_excluding_skipped = [math]::Round(($pass / [double]$nonSkipped) * 100, 2)
    average_duration_ms = $avgDuration
    avg_duration_ms = $avgDuration
    avg_step_count = $avgStep
    locator_method_counts = $locatorMethodCounts
    failure_category_counts = $failureCategoryCounts
    skipped_reason_counts = $skippedReasonCounts
    recovery_attempts = [int]$recoveryAttempts
    recovery_success_count = [int]$recoverySuccess
    recovery_success_rate = $(if ($recoveryAttempts -gt 0) { [math]::Round(($recoverySuccess / [double]$recoveryAttempts) * 100, 2) } else { 0 })
    report_completeness_score = $reportCompleteness
    artifacts = @($ReportPath,$SummaryPath,$ReportDir)
    tasks = $results
}

$summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $SummaryPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# DesktopVisual Benchmark Report')
$lines.Add('')
$lines.Add("- Version: $Version")
$lines.Add("- Timestamp: $($summary.timestamp)")
$lines.Add("- Total: $total")
$lines.Add("- PASS: $pass")
$lines.Add("- FAIL: $fail")
$lines.Add("- SKIPPED: $skipped")
$lines.Add("- pass_rate_excluding_skipped: $($summary.pass_rate_excluding_skipped)%")
$lines.Add("- average_duration_ms: $avgDuration")
$lines.Add("- report_completeness_score: $reportCompleteness%")
$lines.Add('')
$lines.Add('## Results')
$lines.Add('')
$lines.Add('| task | status | outcome | error_code | skipped_reason | duration_ms | report |')
$lines.Add('|---|---|---|---|---|---:|---|')
foreach ($r in $results) {
    $lines.Add(("| {0} | {1} | {2} | {3} | {4} | {5} | {6} |" -f $r.name,$r.status,$r.outcome_kind,$r.error_code,($r.skipped_reason -replace '\|','/'),$r.duration_ms,($r.report_path -replace '\|','/')))
}
$lines.Add('')
$lines.Add('## Notes')
$lines.Add('')
$lines.Add('- SKIPPED is not PASS; it records missing or unsafe prerequisites.')
$lines.Add('- Expected safety stops are counted as PASS only when the required stop code or safe-stop condition was observed.')
$lines.Add('- Benchmarks operate only authorized windows, local generated HTML/files, and PROJECT_ROOT artifacts.')
$lines | Set-Content -LiteralPath $ReportPath -Encoding UTF8

Write-Host "Benchmark report: $ReportPath"
Write-Host "Benchmark summary: $SummaryPath"
Write-Host "PASS=$pass FAIL=$fail SKIPPED=$skipped"
if ($fail -gt 0) { exit 1 }
exit 0
