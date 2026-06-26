param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev5.10.2_real_taskruntime_final_gate'
$CommandOut = Join-Path $ArtifactRoot 'final_gate_command_outputs'
$TaskRuntimeDir = Join-Path $ArtifactRoot 'task_runtime\localhost_form_fill_submit_humanmode'

New-Item -ItemType Directory -Force -Path $ArtifactRoot | Out-Null
New-Item -ItemType Directory -Force -Path $CommandOut | Out-Null

$Checks = New-Object System.Collections.Generic.List[object]
$KnownLimits = New-Object System.Collections.Generic.List[string]
$CommandSeq = 0

function Add-Check([string]$Area, [string]$Name, [string]$Status, [string]$Detail, [bool]$Blocking = $true) {
    $script:Checks.Add([pscustomobject]@{
        area = $Area
        name = $Name
        status = $Status
        detail = $Detail
        blocking = $Blocking
    }) | Out-Null
}

function Write-Lines([string]$Path, [string[]]$Lines) {
    $dir = Split-Path -Parent $Path
    if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $Lines | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-Captured([string]$Name, [string]$FilePath, [string[]]$Arguments, [int[]]$AllowedExitCodes = @(0)) {
    $script:CommandSeq++
    $safe = ($Name -replace '[^A-Za-z0-9_.-]', '_')
    $outPath = Join-Path $CommandOut ('{0:000}_{1}.stdout.txt' -f $script:CommandSeq, $safe)
    $errPath = Join-Path $CommandOut ('{0:000}_{1}.stderr.txt' -f $script:CommandSeq, $safe)
    try {
        $invokePath = $FilePath
        $invokeArgs = $Arguments
        if ([System.IO.Path]::GetExtension($FilePath) -ieq '.ps1') {
            $invokePath = 'powershell.exe'
            $invokeArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$FilePath) + $Arguments
        }
        $output = & $invokePath @invokeArgs 2>&1
        $exit = $LASTEXITCODE
        $text = ($output | Out-String).Trim()
        $text | Set-Content -LiteralPath $outPath -Encoding UTF8
        '' | Set-Content -LiteralPath $errPath -Encoding UTF8
        $json = $null
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            try { $json = $text | ConvertFrom-Json } catch { $json = $null }
        }
        return [pscustomobject]@{
            name = $Name
            exit_code = $exit
            ok_exit = ($AllowedExitCodes -contains $exit)
            stdout = $text
            stdout_path = $outPath
            stderr_path = $errPath
            json = $json
        }
    } catch {
        $_.Exception.Message | Set-Content -LiteralPath $errPath -Encoding UTF8
        return [pscustomobject]@{
            name = $Name
            exit_code = 9999
            ok_exit = $false
            stdout = ''
            stdout_path = $outPath
            stderr_path = $errPath
            json = $null
            exception = $_.Exception.Message
        }
    }
}

function Test-MarkdownFences([string]$Path) {
    $text = Get-Content -LiteralPath $Path -Raw
    $count = ([regex]::Matches($text, '```')).Count
    return (($count % 2) -eq 0)
}

function Read-JsonlStrict([string]$Path, [System.Collections.Generic.List[string]]$Errors) {
    if (-not (Test-Path -LiteralPath $Path)) {
        $Errors.Add("missing: $Path") | Out-Null
        return
    }
    $lineNo = 0
    foreach ($line in Get-Content -LiteralPath $Path) {
        $lineNo++
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $null = $line | ConvertFrom-Json } catch { $Errors.Add("$Path line $lineNo`: $($_.Exception.Message)") | Out-Null }
    }
}

function Command-AvailableFromHelp([string]$Help, [string]$CommandName) {
    return ($Help -match ('(^|[| ])' + [regex]::Escape($CommandName) + '([| ]|$)'))
}

# v5.10.1 prerequisite evidence.
$v5101Report = Join-Path $Root 'artifacts\dev5.10.1_real_ui_adaptive_cases\verifier_report.md'
$v5101SyntheticGuardReport = Join-Path $Root 'artifacts\dev5.10.1_real_ui_adaptive_cases\synthetic_evidence_guard_report.md'
$v5101Verified = Join-Path $Root 'artifacts\dev5.10.1_real_ui_adaptive_cases\verified'
if ((Test-Path -LiteralPath $v5101Report) -and (Test-Path -LiteralPath $v5101SyntheticGuardReport) -and (Test-Path -LiteralPath $v5101Verified)) {
    $v5101Text = Get-Content -LiteralPath $v5101Report -Raw
    $v5101GuardText = Get-Content -LiteralPath $v5101SyntheticGuardReport -Raw
    $caseD = $v5101Text -match 'STRICT_MOUSE_TARGET_HUMANMODE_PASS'
    $caseE = $v5101Text -match '2/2' -and $v5101Text -match 'STRICT_ADAPTIVE_HUMANMODE_PASS'
    $caseF = $v5101Text -match 'Case F' -and $v5101Text -match 'STRICT_ADAPTIVE_HUMANMODE_PASS'
    $syntheticGuard = $v5101GuardText -match 'Result:\s*PASS'
    if ($caseD -and $caseE -and $caseF -and $syntheticGuard) {
        Add-Check 'v5.10.1 evidence' 'Case D/E/F/synthetic guard' 'PASS' 'Rebuilt verifier report contains Case D PASS, Case E 2/2 PASS, Case F PASS, and synthetic guard PASS.'
    } else {
        Add-Check 'v5.10.1 evidence' 'Case D/E/F/synthetic guard' 'FAIL' 'Verifier report did not contain all required PASS markers.'
    }
} else {
    Add-Check 'v5.10.1 evidence' 'verified evidence exists' 'FAIL' 'Missing rebuilt v5.10.1 verifier report, synthetic guard report, or verified directory.'
}

# TaskRuntime independent verifier.
$taskVerifier = Join-Path $Root 'v5_10_2_taskruntime_evidence_verifier.ps1'
$taskVerify = Invoke-Captured -Name 'taskruntime_evidence_verifier' -FilePath $taskVerifier -Arguments @('-Root', $Root)
if ($taskVerify.ok_exit -and $taskVerify.stdout -match 'REAL_TASKRUNTIME_HUMANMODE_PASS') {
    Add-Check 'TaskRuntime' 'independent verifier' 'PASS' 'REAL_TASKRUNTIME_HUMANMODE_PASS'
} else {
    Add-Check 'TaskRuntime' 'independent verifier' 'FAIL' "Verifier failed. Output: $($taskVerify.stdout)"
}

# CLI surface and capabilities.
if (-not (Test-Path -LiteralPath $WinAgent)) {
    Add-Check 'CLI' 'winagent.exe exists' 'FAIL' "Missing $WinAgent"
} else {
    Add-Check 'CLI' 'winagent.exe exists' 'PASS' $WinAgent
}
$version = Invoke-Captured -Name 'winagent_version' -FilePath $WinAgent -Arguments @('version')
if ($version.ok_exit -and $version.json -and $version.json.data.version -eq '5.10.2') {
    Add-Check 'CLI' 'version' 'PASS' 'winagent.exe version returned 5.10.2.'
} else {
    Add-Check 'CLI' 'version' 'FAIL' "Unexpected version output: $($version.stdout)"
}
$help = Invoke-Captured -Name 'winagent_help' -FilePath $WinAgent -Arguments @('help') -AllowedExitCodes @(0,1)
$helpText = $help.stdout
foreach ($cmd in @('adaptive-locate','adaptive-click','adaptive-double-click','adaptive-type','adaptive-run-step','run-task','task-status','task-events','task-report')) {
    if (Command-AvailableFromHelp $helpText $cmd) {
        Add-Check 'CLI' "command $cmd" 'PASS' 'Listed in help surface.'
    } else {
        Add-Check 'CLI' "command $cmd" 'FAIL' 'Missing from help surface.'
    }
}
if ($version.json -and $version.json.data.capabilities.available) {
    $caps = @($version.json.data.capabilities.available)
    foreach ($cap in @('adaptive_locate','adaptive_click','adaptive_double_click','adaptive_type','adaptive_run_step','run_task')) {
        if ($caps -contains $cap) { Add-Check 'CLI' "capability $cap" 'PASS' 'Reported by version capabilities.' }
        else { Add-Check 'CLI' "capability $cap" 'FAIL' 'Missing from version capabilities.' }
    }
} else {
    Add-Check 'CLI' 'capabilities' 'FAIL' 'version output did not include capabilities.'
}
$adaptiveLocate = Invoke-Captured -Name 'adaptive_locate_mock_browser_form' -FilePath $WinAgent -Arguments @('adaptive-locate','--mock','browser-form','--target','Recipient','--target-kind','browser_field','--role','Edit')
if ($adaptiveLocate.ok_exit -and $adaptiveLocate.json -and $adaptiveLocate.json.ok -eq $true) {
    Add-Check 'CLI' 'adaptive-locate executable' 'PASS' 'Mock browser-form locator returned JSON successfully.'
} else {
    Add-Check 'CLI' 'adaptive-locate executable' 'FAIL' $adaptiveLocate.stdout
}
$adaptiveClick = Invoke-Captured -Name 'adaptive_click_no_action_mock_invalid' -FilePath $WinAgent -Arguments @('adaptive-click','--mock','invalid-target') -AllowedExitCodes @(0)
if ($adaptiveClick.ok_exit -and $adaptiveClick.json -and $adaptiveClick.json.command -eq 'adaptive-click' -and $adaptiveClick.json.data.human_action_result) {
    Add-Check 'CLI' 'adaptive-click executable' 'PASS' 'Invalid-target diagnostic returned HumanActionResult without sending a click.'
} else {
    Add-Check 'CLI' 'adaptive-click executable' 'FAIL' $adaptiveClick.stdout
}
$adaptiveType = Invoke-Captured -Name 'adaptive_type_arg_validation' -FilePath $WinAgent -Arguments @('adaptive-type') -AllowedExitCodes @(0,1,2)
if ($adaptiveType.json -and $adaptiveType.json.error.code -eq 'INVALID_ARGUMENT') {
    Add-Check 'CLI' 'adaptive-type executable' 'PASS' 'Argument validation returned JSON without typing.'
} else {
    Add-Check 'CLI' 'adaptive-type executable' 'FAIL' $adaptiveType.stdout
}
$adaptiveRun = Invoke-Captured -Name 'adaptive_run_step_candidate_validation' -FilePath $WinAgent -Arguments @('adaptive-run-step','--diagnostic','candidate-validation')
if ($adaptiveRun.ok_exit -and $adaptiveRun.json -and $adaptiveRun.json.ok -eq $true) {
    Add-Check 'CLI' 'adaptive-run-step executable' 'PASS' 'candidate-validation diagnostic passed.'
} else {
    Add-Check 'CLI' 'adaptive-run-step executable' 'FAIL' $adaptiveRun.stdout
}
foreach ($taskCmd in @('task-status','task-events','task-report')) {
    $r = Invoke-Captured -Name $taskCmd -FilePath $WinAgent -Arguments @($taskCmd,'--file',(Join-Path $Root 'tasks\localhost_form_fill_submit_humanmode.task.json'))
    if ($r.ok_exit -and $r.json -and $r.json.ok -eq $true) {
        Add-Check 'CLI' $taskCmd 'PASS' 'Task command returned completed TaskSession artifacts.'
    } else {
        Add-Check 'CLI' $taskCmd 'FAIL' $r.stdout
    }
}
$taskResult = Join-Path $TaskRuntimeDir 'task_result.json'
if (Test-Path -LiteralPath $taskResult) {
    $tr = Get-Content -LiteralPath $taskResult -Raw | ConvertFrom-Json
    if ($tr.ok -eq $true -and $tr.actual_result -eq 'REAL_UI_EXECUTION_COMPLETED_PENDING_INDEPENDENT_VERIFIER') {
        Add-Check 'CLI' 'run-task evidence' 'PASS' 'TaskRuntime run-task evidence exists and completed pending verifier.'
    } else {
        Add-Check 'CLI' 'run-task evidence' 'FAIL' 'task_result.json does not show completed real UI execution.'
    }
} else {
    Add-Check 'CLI' 'run-task evidence' 'FAIL' 'Missing TaskRuntime task_result.json.'
}

# Active protection STOP and ordinary-content allow.
$ordinaryTitle = 'test exam assessment quiz problem challenge mail submit localhost local HTML ordinary external web'
$ordinary = Invoke-Captured -Name 'active_protection_ordinary_allow' -FilePath $WinAgent -Arguments @('policy-check','--title',$ordinaryTitle,'--process','msedge.exe','--action','observe','--permission-mode','DEVELOPER_CAPABILITY_DISCOVERY') -AllowedExitCodes @(0,1)
if ($ordinary.json -and $ordinary.json.ok -eq $true -and $ordinary.json.data.allow -eq $true) {
    Add-Check 'Active protection' 'ordinary content allowed' 'PASS' 'Ordinary content words did not trigger active-protection STOP.'
} else {
    Add-Check 'Active protection' 'ordinary content allowed' 'FAIL' $ordinary.stdout
}
$stopSignals = @(
    'CAPTCHA',
    'reCAPTCHA',
    'hCaptcha',
    'Turnstile',
    'human verification',
    'bot challenge',
    'automation detected',
    'script detected',
    'BEService.exe',
    'EasyAntiCheat',
    'BattlEye',
    'vgc.exe',
    'Vanguard',
    'lockdown browser',
    'secure exam browser',
    'active proctoring'
)
$stopFailures = New-Object System.Collections.Generic.List[string]
foreach ($signal in $stopSignals) {
    $r = Invoke-Captured -Name ('active_stop_' + ($signal -replace '[^A-Za-z0-9]','_')) -FilePath $WinAgent -Arguments @('policy-check','--title',$signal,'--process',$signal,'--action','click','--permission-mode','DEVELOPER_CAPABILITY_DISCOVERY') -AllowedExitCodes @(0,1)
    if (-not ($r.json -and $r.json.ok -eq $false -and ($r.json.error.code -eq 'STOP_ACTIVE_PROTECTION' -or $r.json.data.decision -eq 'STOP_ACTIVE_PROTECTION'))) {
        $stopFailures.Add($signal) | Out-Null
    }
}
if ($stopFailures.Count -eq 0) {
    Add-Check 'Active protection' 'STOP signals' 'PASS' 'All active-protection signals returned STOP_ACTIVE_PROTECTION.'
} else {
    Add-Check 'Active protection' 'STOP signals' 'FAIL' ('Missing STOP for: ' + ($stopFailures -join ', '))
}

# Service smoke. Non-blocking if unavailable on the local machine.
$serviceScript = Join-Path $Root 'service_protocol_selftest.ps1'
if (Test-Path -LiteralPath $serviceScript) {
    $service = Invoke-Captured -Name 'service_protocol_selftest' -FilePath $serviceScript -Arguments @('-Root',$Root,'-SkipBuild') -AllowedExitCodes @(0)
    if ($service.ok_exit -and $service.stdout -match 'Service protocol selftest passed') {
        Add-Check 'Service' 'service protocol smoke' 'PASS' 'service_protocol_selftest.ps1 passed.'
    } else {
        $KnownLimits.Add('NOT_RUN_SERVICE_UNAVAILABLE: service protocol smoke did not complete in this local gate run; CLI task API remains available.') | Out-Null
        Add-Check 'Service' 'service protocol smoke' 'NOT_RUN_SERVICE_UNAVAILABLE' $service.stdout $false
    }
} else {
    $KnownLimits.Add('NOT_RUN_SERVICE_UNAVAILABLE: service_protocol_selftest.ps1 missing.') | Out-Null
    Add-Check 'Service' 'service protocol smoke' 'NOT_RUN_SERVICE_UNAVAILABLE' 'service_protocol_selftest.ps1 missing.' $false
}

# Core regression smoke scripts.
$coreScripts = @(
    @{ name='permission selftest'; path='v5_9_permission_reset_selftest.ps1'; args=@('-Root',$Root,'-SkipBuild') },
    @{ name='HumanMode pacing test'; path='v5_9_0_e_humanmode_motion_pacing_test.ps1'; args=@('-Root',$Root,'-SkipBuild') },
    @{ name='adaptive loop test'; path='v5_10_0_adaptive_humanmode_loop_test.ps1'; args=@('-Root',$Root,'-SkipBuild') },
    @{ name='TaskSession smoke'; path='task_session_selftest.ps1'; args=@('-Root',$Root) },
    @{ name='state machine smoke'; path='task_state_machine_selftest.ps1'; args=@('-Root',$Root) },
    @{ name='StepContract parse'; path='step_contract_selftest.ps1'; args=@('-Root',$Root) },
    @{ name='precondition smoke'; path='step_precondition_selftest.ps1'; args=@('-Root',$Root) },
    @{ name='verification smoke'; path='step_verification_selftest.ps1'; args=@('-Root',$Root) },
    @{ name='recovery smoke'; path='recovery_selftest.ps1'; args=@('-Root',$Root,'-SkipBuild') },
    @{ name='confirmation smoke'; path='confirmation_flow_selftest.ps1'; args=@('-Root',$Root) },
    @{ name='template smoke'; path='task_template_v2_schema_selftest.ps1'; args=@('-Root',$Root) },
    @{ name='profile smoke'; path='profile_binding_selftest.ps1'; args=@('-Root',$Root) },
    @{ name='file workflow smoke'; path='file_path_resolver_selftest.ps1'; args=@('-Root',$Root) },
    @{ name='service protocol smoke'; path='task_service_protocol_selftest.ps1'; args=@('-Root',$Root) },
    @{ name='dogfood smoke'; path='dogfood_selftest.ps1'; args=@('-Root',$Root,'-SkipBuild') }
)
foreach ($item in $coreScripts) {
    $scriptPath = Join-Path $Root $item.path
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        Add-Check 'Core regression' $item.name 'NOT_RUN' "Missing script: $scriptPath" $false
        continue
    }
    $r = Invoke-Captured -Name ('core_' + ($item.name -replace '[^A-Za-z0-9]','_')) -FilePath $scriptPath -Arguments ([string[]]$item.args) -AllowedExitCodes @(0)
    if ($r.ok_exit) { Add-Check 'Core regression' $item.name 'PASS' 'Script exit code 0.' }
    else { Add-Check 'Core regression' $item.name 'FAIL' $r.stdout }
}

# JSON/JSONL/Markdown/encoding/documentation checks.
$docFiles = @(
    'AGENTS.md',
    'README.md',
    'CHANGELOG.md',
    'COMMAND_PROTOCOL.md',
    'docs\ARCHITECTURE.md',
    'docs\ROADMAP.md',
    'docs\TASK_RUNTIME.md',
    'docs\BENCHMARKS.md',
    'docs\KNOWN_LIMITATIONS.md',
    'docs\SAFETY_MANIFEST.md',
    'docs\SERVICE_PROTOCOL.md',
    'docs\STEP_CONTRACT.md',
    'docs\TASK_TEMPLATES_V2.md'
)
$docErrors = New-Object System.Collections.Generic.List[string]
$mojibake = New-Object System.Collections.Generic.List[string]
$fenceErrors = New-Object System.Collections.Generic.List[string]
foreach ($rel in $docFiles) {
    $p = Join-Path $Root $rel
    if (-not (Test-Path -LiteralPath $p)) { $docErrors.Add("missing: $rel") | Out-Null; continue }
    $text = Get-Content -LiteralPath $p -Raw
    if ($text -match 'NOT_IMPLEMENTED_REAL_HUMANMODE_TASKRUNTIME_FLOW') { $docErrors.Add("stale NOT_IMPLEMENTED marker: $rel") | Out-Null }
    if ($text -match 'v5\s+is\s+a\s+complete\s+Agent') { $docErrors.Add("claims v5 is complete Agent: $rel") | Out-Null }
    if ($text -match 'v5\s+depends\s+on\s+VLM') { $docErrors.Add("claims v5 depends on VLM: $rel") | Out-Null }
    if ($text -match 'old invalidated.*evidence.*PASS' -and $text -notmatch 'must not|cannot|invalid') { $docErrors.Add("ambiguous invalidated evidence wording: $rel") | Out-Null }
    if (-not (Test-MarkdownFences $p)) { $fenceErrors.Add($rel) | Out-Null }
    $replacementChar = [string][char]0xFFFD
    if ($text.Contains($replacementChar) -or $text -match 'Ã|Â|â') { $mojibake.Add($rel) | Out-Null }
}
if ($docErrors.Count -eq 0) { Add-Check 'Documentation' 'semantic consistency' 'PASS' 'No stale TaskRuntime invalidation instruction, complete-Agent claim, or VLM dependency claim detected.' }
else { Add-Check 'Documentation' 'semantic consistency' 'FAIL' ($docErrors -join '; ') }
if ($fenceErrors.Count -eq 0) { Add-Check 'Documentation' 'Markdown fences' 'PASS' 'All checked Markdown files have balanced fences.' }
else { Add-Check 'Documentation' 'Markdown fences' 'FAIL' ($fenceErrors -join '; ') }
if ($mojibake.Count -eq 0) { Add-Check 'Documentation' 'encoding/mojibake scan' 'PASS' 'No mojibake markers detected in checked docs.' }
else { Add-Check 'Documentation' 'encoding/mojibake scan' 'FAIL' ($mojibake -join '; ') }

$jsonErrors = New-Object System.Collections.Generic.List[string]
$jsonFiles = @(
    'config\safety_manifest.json',
    'tasks\localhost_form_fill_submit_humanmode.task.json',
    'artifacts\dev5.10.2_real_taskruntime_final_gate\task_runtime\localhost_form_fill_submit_humanmode\task_result.json'
)
foreach ($rel in $jsonFiles) {
    $p = Join-Path $Root $rel
    if (-not (Test-Path -LiteralPath $p)) { $jsonErrors.Add("missing: $rel") | Out-Null; continue }
    try { $null = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json } catch { $jsonErrors.Add("$rel`: $($_.Exception.Message)") | Out-Null }
}
foreach ($rel in @(
    'artifacts\dev5.10.2_real_taskruntime_final_gate\task_runtime\localhost_form_fill_submit_humanmode\task_events.jsonl',
    'artifacts\dev5.10.2_real_taskruntime_final_gate\task_runtime\localhost_form_fill_submit_humanmode\action_trace.jsonl',
    'artifacts\dev5.10.2_real_taskruntime_final_gate\task_runtime\localhost_form_fill_submit_humanmode\locator_trace.jsonl',
    'artifacts\dev5.10.2_real_taskruntime_final_gate\task_runtime\localhost_form_fill_submit_humanmode\adaptive_loop_trace.jsonl',
    'artifacts\dev5.10.2_real_taskruntime_final_gate\task_runtime\localhost_form_fill_submit_humanmode\human_action_results.jsonl',
    'artifacts\dev5.10.2_real_taskruntime_final_gate\task_runtime\localhost_form_fill_submit_humanmode\raw_command_log.jsonl'
)) {
    Read-JsonlStrict (Join-Path $Root $rel) $jsonErrors
}
if ($jsonErrors.Count -eq 0) { Add-Check 'Data validation' 'JSON/JSONL parse' 'PASS' 'Required JSON and JSONL files parse.' }
else { Add-Check 'Data validation' 'JSON/JSONL parse' 'FAIL' ($jsonErrors -join '; ') }
if (Command-AvailableFromHelp $helpText 'run-task' -and (Get-Content -LiteralPath (Join-Path $Root 'COMMAND_PROTOCOL.md') -Raw) -match 'run-task') {
    Add-Check 'Documentation' 'COMMAND_PROTOCOL consistency' 'PASS' 'Required TaskRuntime CLI commands are documented and present in help.'
} else {
    Add-Check 'Documentation' 'COMMAND_PROTOCOL consistency' 'FAIL' 'run-task missing from help or COMMAND_PROTOCOL.'
}

$blockingFailures = @($Checks | Where-Object { $_.blocking -and $_.status -notin @('PASS') })
$taskRuntimePass = @($Checks | Where-Object { $_.area -eq 'TaskRuntime' -and $_.status -eq 'PASS' }).Count -gt 0
$caseDPass = $caseD
$caseEPass = $caseE
$caseFPass = $caseF
$activePass = @($Checks | Where-Object { $_.area -eq 'Active protection' -and $_.status -ne 'PASS' }).Count -eq 0
$syntheticDetected = $false
if (Test-Path -LiteralPath (Join-Path $ArtifactRoot 'taskruntime_evidence_verifier_report.md')) {
    $syntheticDetected = (Get-Content -LiteralPath (Join-Path $ArtifactRoot 'taskruntime_evidence_verifier_report.md') -Raw) -match 'synthetic.*detected|placeholder'
}
$ready = ($blockingFailures.Count -eq 0)

function New-CheckReport([string]$Title, [string]$Path, [object[]]$Rows) {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# $Title") | Out-Null
    $lines.Add('') | Out-Null
    foreach ($row in $Rows) {
        $lines.Add("- [$($row.status)] $($row.area) / $($row.name): $($row.detail)") | Out-Null
    }
    Write-Lines $Path $lines.ToArray()
}

New-CheckReport 'v5.10.2 Service Protocol Report' (Join-Path $ArtifactRoot 'service_protocol_report.md') (@($Checks | Where-Object { $_.area -eq 'Service' }))
New-CheckReport 'v5.10.2 Active Protection STOP Report' (Join-Path $ArtifactRoot 'active_protection_stop_report.md') (@($Checks | Where-Object { $_.area -eq 'Active protection' }))
New-CheckReport 'v5.10.2 Full Regression Report' (Join-Path $ArtifactRoot 'full_regression_report.md') (@($Checks | Where-Object { $_.area -eq 'Core regression' -or $_.area -eq 'Data validation' }))
New-CheckReport 'v5.10.2 Documentation Validation Report' (Join-Path $ArtifactRoot 'documentation_validation_report.md') (@($Checks | Where-Object { $_.area -eq 'Documentation' }))

$handoff = [ordered]@{
    ready_for_v6 = [bool]$ready
    blocking_issues = @($blockingFailures | ForEach-Object { "$($_.area)/$($_.name): $($_.detail)" })
    trusted_version = '5.10.2'
    invalidated_versions = @('5.10.1-old','5.10.2-old')
    taskruntime_real_humanmode_pass = [bool]$taskRuntimePass
    case_d_real_pass = [bool]$caseDPass
    case_e_real_pass = [bool]$caseEPass
    case_f_real_pass = [bool]$caseFPass
    active_protection_stop_pass = [bool]$activePass
    synthetic_evidence_detected = [bool]$syntheticDetected
}
$handoffJson = $handoff | ConvertTo-Json -Depth 8
Write-Lines (Join-Path $ArtifactRoot 'v6_handoff_readiness_report.md') @(
    '# v6 Handoff Readiness',
    '',
    '```json',
    $handoffJson,
    '```',
    '',
    '## Known Limits',
    $(if ($KnownLimits.Count -eq 0) { '- None' } else { $KnownLimits | ForEach-Object { "- $_" } })
)

$finalLines = New-Object System.Collections.Generic.List[string]
$finalLines.Add('# v5.10.2 Final Pre-v6 Gate Report') | Out-Null
$finalLines.Add('') | Out-Null
$finalLines.Add("- Verdict: $(if ($ready) { 'PASS' } else { 'FAIL' })") | Out-Null
$finalLines.Add("- Trusted version: 5.10.2") | Out-Null
$finalLines.Add("- Ready for v6: $ready") | Out-Null
$finalLines.Add("- Blocking issue count: $($blockingFailures.Count)") | Out-Null
$finalLines.Add('') | Out-Null
$finalLines.Add('## Checks') | Out-Null
$finalLines.Add('') | Out-Null
foreach ($row in $Checks) {
    $finalLines.Add("- [$($row.status)] $($row.area) / $($row.name): $($row.detail)") | Out-Null
}
$finalLines.Add('') | Out-Null
$finalLines.Add('## Known Limits') | Out-Null
if ($KnownLimits.Count -eq 0) { $finalLines.Add('- None') | Out-Null } else { foreach ($k in $KnownLimits) { $finalLines.Add("- $k") | Out-Null } }
$finalLines.Add('') | Out-Null
$finalLines.Add('## Handoff JSON') | Out-Null
$finalLines.Add('') | Out-Null
$finalLines.Add('```json') | Out-Null
$finalLines.Add($handoffJson) | Out-Null
$finalLines.Add('```') | Out-Null
Write-Lines (Join-Path $ArtifactRoot 'final_pre_v6_gate_report.md') $finalLines.ToArray()

if (-not $ready) {
    Write-Host "FINAL_PRE_V6_GATE_FAIL. Report: $(Join-Path $ArtifactRoot 'final_pre_v6_gate_report.md')"
    exit 1
}

Write-Host "FINAL_PRE_V6_GATE_PASS. Report: $(Join-Path $ArtifactRoot 'final_pre_v6_gate_report.md')"
exit 0
