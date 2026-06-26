param(
    [string]$Root = '',
    [switch]$SkipRegressionCommands
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.1.6_dynamic_app_web_full_access_rc_fresh'
$VerifiedRoot = Join-Path $ArtifactRoot 'verified'
$CommandLogRoot = Join-Path $ArtifactRoot 'required_command_logs'
$RegistryPath = Join-Path $ArtifactRoot 'case_status_registry.json'
$VerifierResultPath = Join-Path $VerifiedRoot 'v6_1_6_verifier_result.json'
$GateResultPath = Join-Path $VerifiedRoot 'v6_1_6_acceptance_gate_result.json'
$CommandMatrixPath = Join-Path $VerifiedRoot 'required_command_results.json'
$ExecutionClassifierSelftestPath = Join-Path $ArtifactRoot 'execution_outcome_classifier_selftest\execution_outcome_classifier_selftest_result.json'

function Ensure-Dir([string]$Path) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Save-Json($Value, [string]$Path) {
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { Ensure-Dir $dir }
    $Value | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-Json([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return $null }
}

function ConvertTo-Arg([string]$Arg) {
    if ($null -eq $Arg) { return '""' }
    $s = [string]$Arg
    if ($s.Length -eq 0) { return '""' }
    if ($s -notmatch '[\s"]') { return $s }
    $result = '"'
    $slashes = 0
    foreach ($ch in $s.ToCharArray()) {
        if ($ch -eq '\') {
            $slashes++
        } elseif ($ch -eq '"') {
            if ($slashes -gt 0) { $result += ('\' * ($slashes * 2)) }
            $result += '\"'
            $slashes = 0
        } else {
            if ($slashes -gt 0) { $result += ('\' * $slashes) }
            $slashes = 0
            $result += $ch
        }
    }
    if ($slashes -gt 0) { $result += ('\' * ($slashes * 2)) }
    $result += '"'
    return $result
}

function ConvertTo-ArgLine([string[]]$ArgList) {
    (($ArgList | ForEach-Object { ConvertTo-Arg $_ }) -join ' ')
}

function Invoke-ProcessCapture {
param(
        [string]$Exe,
        [string[]]$ProcArgs,
        [string]$StdoutPath,
        [string]$StderrPath,
        [int]$TimeoutSec = 900
    )
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $Exe
    $psi.Arguments = ConvertTo-ArgLine $ProcArgs
    $psi.WorkingDirectory = $Root
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    $started = Get-Date
    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit($TimeoutSec * 1000)
    if ($timedOut) {
        try { $process.Kill($true) } catch { try { $process.Kill() } catch {} }
        try { $process.WaitForExit(3000) | Out-Null } catch {}
    }
    try { $stdoutTask.Wait(5000) | Out-Null } catch {}
    try { $stderrTask.Wait(5000) | Out-Null } catch {}
    $stdout = if ($stdoutTask.IsCompleted) { $stdoutTask.Result } else { '' }
    $stderr = if ($stderrTask.IsCompleted) { $stderrTask.Result } else { '' }
    $ended = Get-Date
    $stdout | Set-Content -LiteralPath $StdoutPath -Encoding UTF8
    $stderr | Set-Content -LiteralPath $StderrPath -Encoding UTF8
    [pscustomobject]@{
        started = $started
        ended = $ended
        exit_code = if ($timedOut) { 124 } else { $process.ExitCode }
        timed_out = $timedOut
        duration_ms = [int](($ended - $started).TotalMilliseconds)
        stdout_path = $StdoutPath
        stderr_path = $StderrPath
    }
}

function Invoke-RequiredCommand {
    param(
        [string]$Name,
        [string]$ScriptName,
        [string[]]$ScriptArgs = @(),
        [int]$TimeoutSec = 900,
        [bool]$Required = $true
    )
    $script = Join-Path $Root $ScriptName
    $stdout = Join-Path $CommandLogRoot "$Name.stdout.log"
    $stderr = Join-Path $CommandLogRoot "$Name.stderr.log"
    $meta = Join-Path $CommandLogRoot "$Name.meta.json"
    if (-not (Test-Path -LiteralPath $script)) {
        $row = [ordered]@{
            name = $Name
            script = $script
            args = $ScriptArgs
            required = $Required
            status = 'NOT_FOUND'
            exit_code = $null
            timed_out = $false
            stdout = ''
            stderr = ''
            meta = $meta
        }
        Save-Json $row $meta
        return $row
    }
    $commandArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$script) + $ScriptArgs
    $result = Invoke-ProcessCapture -Exe (Get-Command powershell.exe).Source -ProcArgs $commandArgs -StdoutPath $stdout -StderrPath $stderr -TimeoutSec $TimeoutSec
    $status = if ($result.timed_out) { 'TIMEOUT' } elseif ($result.exit_code -eq 0) { 'PASS' } else { 'FAIL' }
    $row = [ordered]@{
        name = $Name
        script = $script
        args = $ScriptArgs
        required = $Required
        status = $status
        exit_code = $result.exit_code
        timed_out = $result.timed_out
        started_at = $result.started.ToString('o')
        ended_at = $result.ended.ToString('o')
        duration_ms = $result.duration_ms
        stdout = $stdout
        stderr = $stderr
        meta = $meta
    }
    Save-Json $row $meta
    return $row
}

function Add-Finding {
    param(
        [System.Collections.Generic.List[object]]$Findings,
        [string]$Code,
        [string]$Message,
        [string]$Path = ''
    )
    $Findings.Add([pscustomobject]@{
        code = $Code
        message = $Message
        path = $Path
        blocking = $true
    }) | Out-Null
}

function Test-RequiredCommandPass($CommandResults, [string]$Name) {
    $rows = @($CommandResults | Where-Object { $_.name -eq $Name } | Select-Object -First 1)
    $row = if ($rows.Count -gt 0) { $rows[0] } else { $null }
    if (-not $row) { return $false }
    return ($row.status -eq 'PASS')
}

function Get-FirstVerifierCode($Verifier) {
    if ($Verifier -and $Verifier.findings) {
        $priority = @(
            'BLOCKED_RUNNER_ONLY_TARGET_SEMANTICS',
            'BLOCKED_RUNNER_ONLY_EXECUTION_CLASSIFIER',
            'BLOCKED_EXECUTION_OUTCOME_MISSING',
            'BLOCKED_CODE_INPUT_INDENTATION_ERROR',
            'BLOCKED_PYCHARM_EXECUTION_OUTCOME_UNVERIFIED',
            'BLOCKED_STALE_EVIDENCE_USED',
            'BLOCKED_MISSING_CLICKED_TARGET_EVIDENCE',
            'BLOCKED_MISSING_POST_ACTION_CAUSAL_VERIFICATION',
            'BLOCKED_QQMAIL_WRONG_SEND_TARGET',
            'BLOCKED_KEYBOARD_ONLY_FALSE_PASS',
            'BLOCKED_WRONG_FIELD_INPUT',
            'BLOCKED_MOUSE_MISCLICK',
            'BLOCKED_MOUSE_EVIDENCE_MISSING',
            'BLOCKED_INTEGRATED_SEQUENCE_FAILED',
            'BLOCKED_QQMAIL_FULL_ACCESS_CASE_FAILED',
            'BLOCKED_PYCHARM_FULL_ACCESS_CASE_FAILED',
            'BLOCKED_WECHAT_FULL_ACCESS_CASE_FAILED',
            'BLOCKED_TIKTOK_FULL_ACCESS_CASE_FAILED'
        )
        foreach ($code in $priority) {
            if (@($Verifier.findings | Where-Object { $_.code -eq $code }).Count -gt 0) { return $code }
        }
        $firstRows = @($Verifier.findings | Select-Object -First 1)
        $first = if ($firstRows.Count -gt 0) { $firstRows[0] } else { $null }
        if ($first) { return [string]$first.code }
    }
    return ''
}

function Test-StatusFilesPassAligned {
    $agentsPath = Join-Path $Root 'AGENTS.md'
    $versionPath = Join-Path $Root 'VERSION'
    $changelogPath = Join-Path $Root 'CHANGELOG.md'
    $statusPath = Join-Path $Root 'docs\DEVELOPMENT_STATUS.md'
    $version = if (Test-Path -LiteralPath $versionPath) { (Get-Content -LiteralPath $versionPath -Raw).Trim() } else { '' }
    $agents = if (Test-Path -LiteralPath $agentsPath) { Get-Content -LiteralPath $agentsPath -Raw } else { '' }
    $changelog = if (Test-Path -LiteralPath $changelogPath) { Get-Content -LiteralPath $changelogPath -Raw } else { '' }
    $status = if (Test-Path -LiteralPath $statusPath) { Get-Content -LiteralPath $statusPath -Raw } else { '' }
    return [ordered]@{
        version = $version
        pass_aligned = ($version -eq '6.1.6' -and $agents -match 'current_trusted_version:\s*6\.1\.6' -and $agents -match 'last_completed_status:\s*pass' -and $changelog -match '6\.1\.6' -and $status -match '6\.1\.6')
        blocked_aligned = ($version -eq '6.1.5a' -and $agents -match 'current_trusted_version:\s*6\.1\.5a' -and $agents -match 'last_completed_status:\s*blocked' -and $agents -match 'next_planned_version:\s*6\.1\.6-rerun' -and $changelog -match '6\.1\.6' -and $status -match '6\.1\.6')
    }
}

Ensure-Dir $ArtifactRoot
Ensure-Dir $VerifiedRoot
Ensure-Dir $CommandLogRoot

$commandResults = New-Object System.Collections.Generic.List[object]
if (-not $SkipRegressionCommands) {
    $required = @(
        @{ name = '01_build'; script = 'build.ps1'; args = @(); timeout = 1200 },
        @{ name = '02_selftest'; script = 'selftest.ps1'; args = @(); timeout = 1200 },
        @{ name = '03_runtime_context_guard_selftest'; script = 'runtime_context_guard_selftest.ps1'; args = @(); timeout = 900 },
        @{ name = '04_browser_surface_normalization_selftest'; script = 'browser_surface_normalization_selftest.ps1'; args = @(); timeout = 900 },
        @{ name = '05_v6_1_2_pre_v6_2_acceptance_gate'; script = 'v6_1_2_pre_v6_2_acceptance_gate.ps1'; args = @('-Root',$Root); timeout = 1200 },
        @{ name = '06_v6_1_3_scroll_acceptance_gate'; script = 'v6_1_3_scroll_acceptance_gate.ps1'; args = @('-Root',$Root); timeout = 1200 },
        @{ name = '07_v6_1_4_runtime_guard_acceptance_gate'; script = 'v6_1_4_runtime_guard_acceptance_gate.ps1'; args = @('-Root',$Root); timeout = 1200 },
        @{ name = '08_v6_1_5_safe_context_recovery_acceptance_gate'; script = 'v6_1_5_safe_context_recovery_acceptance_gate.ps1'; args = @('-Root',$Root); timeout = 1200 },
        @{ name = '09_v6_1_5a_mouse_first_interaction_acceptance_gate'; script = 'v6_1_5a_mouse_first_interaction_acceptance_gate.ps1'; args = @('-Root',$Root); timeout = 1200 },
        @{ name = '10_v6_1_6_target_semantics_selftest'; script = 'v6_1_6_target_semantics_selftest.ps1'; args = @('-Root',$Root); timeout = 900 },
        @{ name = '10a_execution_outcome_classifier_selftest'; script = 'execution_outcome_classifier_selftest.ps1'; args = @('-Root',$Root); timeout = 900 }
    )
    foreach ($cmd in $required) {
        $commandResults.Add((Invoke-RequiredCommand -Name $cmd.name -ScriptName $cmd.script -ScriptArgs $cmd.args -TimeoutSec $cmd.timeout -Required $true)) | Out-Null
    }
    $optional = @(
        @{ name = 'optional_adapter_selftest'; script = 'adapter_selftest.ps1'; args = @(); timeout = 900 },
        @{ name = 'optional_app_profile_selftest'; script = 'app_profile_selftest.ps1'; args = @(); timeout = 900 },
        @{ name = 'optional_case_v2_selftest'; script = 'case_v2_selftest.ps1'; args = @(); timeout = 900 },
        @{ name = 'optional_selector_selftest'; script = 'selector_selftest.ps1'; args = @(); timeout = 900 },
        @{ name = 'optional_serve_selftest'; script = 'serve_selftest.ps1'; args = @(); timeout = 900 },
        @{ name = 'optional_rc_check'; script = 'rc_check.ps1'; args = @(); timeout = 900 }
    )
    foreach ($cmd in $optional) {
        $commandResults.Add((Invoke-RequiredCommand -Name $cmd.name -ScriptName $cmd.script -ScriptArgs $cmd.args -TimeoutSec $cmd.timeout -Required $false)) | Out-Null
    }
}

$verifierScript = Join-Path $Root 'v6_1_6_dynamic_app_web_full_access_fresh_verifier.ps1'
$verifierStdout = Join-Path $CommandLogRoot '11_v6_1_6_verifier.stdout.log'
$verifierStderr = Join-Path $CommandLogRoot '11_v6_1_6_verifier.stderr.log'
$verifierRun = Invoke-ProcessCapture -Exe (Get-Command powershell.exe).Source -ProcArgs @('-NoProfile','-ExecutionPolicy','Bypass','-File',$verifierScript,'-Root',$Root) -StdoutPath $verifierStdout -StderrPath $verifierStderr -TimeoutSec 1200
$commandResults.Add([ordered]@{
    name = '11_v6_1_6_dynamic_app_web_full_access_verifier'
    script = $verifierScript
    args = @('-Root',$Root)
    required = $true
    status = if ($verifierRun.timed_out) { 'TIMEOUT' } elseif ($verifierRun.exit_code -eq 0) { 'PASS' } else { 'FAIL' }
    exit_code = $verifierRun.exit_code
    timed_out = $verifierRun.timed_out
    started_at = $verifierRun.started.ToString('o')
    ended_at = $verifierRun.ended.ToString('o')
    duration_ms = $verifierRun.duration_ms
    stdout = $verifierStdout
    stderr = $verifierStderr
}) | Out-Null

Save-Json @($commandResults.ToArray()) $CommandMatrixPath

$findings = New-Object System.Collections.Generic.List[object]
$verifier = Read-Json $VerifierResultPath
$rawRegistry = Read-Json $RegistryPath
$registry = @()
foreach ($item in @($rawRegistry)) {
    if ($item -is [System.Array]) { $registry += @($item) } else { $registry += $item }
}
$statusFiles = Test-StatusFilesPassAligned

foreach ($row in @($commandResults.ToArray())) {
    if ($row.required -eq $true -and $row.status -ne 'PASS') {
        if ($row.name -eq '11_v6_1_6_dynamic_app_web_full_access_verifier') {
            $code = Get-FirstVerifierCode $verifier
            if ([string]::IsNullOrWhiteSpace($code)) { $code = 'BLOCKED_MOUSE_EVIDENCE_MISSING' }
            Add-Finding $findings $code "v6.1.6 verifier did not PASS." $VerifierResultPath
        } elseif ($row.name -eq '10a_execution_outcome_classifier_selftest') {
            Add-Finding $findings 'BLOCKED_PYCHARM_EXECUTION_OUTCOME_UNVERIFIED' "Execution outcome classifier selftest did not PASS: $($row.status)." ([string]$row.meta)
        } else {
            Add-Finding $findings 'BLOCKED_PREVIOUS_GATE_REGRESSION' "Required regression command $($row.name) did not PASS: $($row.status)." ([string]$row.meta)
        }
    }
    if ($row.required -eq $false -and $row.status -eq 'TIMEOUT' -and $row.name -eq 'optional_rc_check') {
        Add-Finding $findings 'BLOCKED_PREVIOUS_GATE_REGRESSION' 'rc_check.ps1 timed out and was recorded as TIMEOUT.' ([string]$row.meta)
    }
}

if (-not $verifier) {
    Add-Finding $findings 'BLOCKED_MOUSE_EVIDENCE_MISSING' 'Verifier result JSON is missing.' $VerifierResultPath
} elseif ($verifier.status -ne 'PASS') {
    $code = Get-FirstVerifierCode $verifier
    if ([string]::IsNullOrWhiteSpace($code)) { $code = 'BLOCKED_MOUSE_EVIDENCE_MISSING' }
    Add-Finding $findings $code "Verifier status is $($verifier.status)." $VerifierResultPath
}

$executionSelftest = Read-Json $ExecutionClassifierSelftestPath
if (-not $executionSelftest -or [string]$executionSelftest.status -ne 'PASS') {
    Add-Finding $findings 'BLOCKED_PYCHARM_EXECUTION_OUTCOME_UNVERIFIED' 'execution_outcome_classifier_selftest did not produce PASS.' $ExecutionClassifierSelftestPath
}

$case2Result = $null
if ($verifier -and $verifier.case_results) {
    $case2Rows = @($verifier.case_results | Where-Object { $_.case_id -eq 'case_2_pycharm_run' } | Select-Object -First 1)
    if ($case2Rows.Count -gt 0) { $case2Result = $case2Rows[0] }
}
if (-not $case2Result -or [string]$case2Result.status -ne 'PASS') {
    Add-Finding $findings 'BLOCKED_PYCHARM_EXECUTION_OUTCOME_UNVERIFIED' 'Case 2 did not verifier PASS with execution outcome evidence.' $VerifierResultPath
} else {
    $case2Evidence = Read-Json ([string]$case2Result.evidence_path)
    if (-not $case2Evidence -or -not $case2Evidence.execution_outcome) {
        Add-Finding $findings 'BLOCKED_EXECUTION_OUTCOME_MISSING' 'Case 2 evidence does not contain execution_outcome.' ([string]$case2Result.evidence_path)
    } elseif (
        $case2Evidence.run_triggered -ne $true -or
        $case2Evidence.execution_success -ne $true -or
        $case2Evidence.exit_code_present -ne $true -or
        [int]$case2Evidence.exit_code -ne 0 -or
        $case2Evidence.current_run_verified -ne $true -or
        $case2Evidence.output_sequence_verified -ne $true
    ) {
        Add-Finding $findings 'BLOCKED_PYCHARM_EXECUTION_OUTCOME_UNVERIFIED' 'Case 2 execution outcome fields do not meet hotfix gate requirements.' ([string]$case2Result.evidence_path)
    }
}

$negativeOk = $false
if ($verifier -and $verifier.negative_cases) {
    $negativeRows = @($verifier.negative_cases | Where-Object { $_.case_id -eq 'qqmail_sent_folder_false_positive_negative' } | Select-Object -First 1)
    if ($negativeRows.Count -gt 0 -and $negativeRows[0].status -eq 'PASS') { $negativeOk = $true }
}
if (-not $negativeOk) {
    Add-Finding $findings 'BLOCKED_QQMAIL_WRONG_SEND_TARGET' 'qqmail_sent_folder_false_positive_negative did not PASS.' $VerifierResultPath
}

$caseFreezeOk = $true
if (-not $registry) {
    $caseFreezeOk = $false
} else {
    foreach ($caseId in @('case_1_qqmail_send','case_2_pycharm_run','case_3_wechat_file_transfer','case_4_tiktok_search')) {
        $rows = @($registry | Where-Object { $_.case_id -eq $caseId } | Select-Object -First 1)
        $row = if ($rows.Count -gt 0) { $rows[0] } else { $null }
        if (-not $row -or $row.status -ne 'pass' -or $row.frozen_after_pass -ne $true) { $caseFreezeOk = $false }
    }
}
if (-not $caseFreezeOk) {
    Add-Finding $findings 'BLOCKED_MOUSE_EVIDENCE_MISSING' 'Four single cases are not all pass and frozen_after_pass=true.' $RegistryPath
}

if ($verifier -and $verifier.integrated_sequence_status -ne 'PASS') {
    Add-Finding $findings 'BLOCKED_INTEGRATED_SEQUENCE_FAILED' "Integrated sequence status is $($verifier.integrated_sequence_status)." $VerifierResultPath
}

$accepted = ($findings.Count -eq 0)
if ($accepted -and -not $statusFiles.pass_aligned) {
    Add-Finding $findings 'BLOCKED_STATUS_FILE_MISMATCH' 'AGENTS/VERSION/CHANGELOG/DEVELOPMENT_STATUS are not aligned for v6.1.6 PASS.' $Root
    $accepted = $false
}

$stopCode = ''
if (-not $accepted) {
    $firstRows = @($findings.ToArray() | Select-Object -First 1)
    $first = if ($firstRows.Count -gt 0) { $firstRows[0] } else { $null }
    if ($first) { $stopCode = [string]$first.code } else { $stopCode = 'BLOCKED_MOUSE_EVIDENCE_MISSING' }
}

$result = [ordered]@{
    schema_version = 'v6.1.6.dynamic_app_web_full_access.acceptance_gate'
    generated_at = (Get-Date).ToString('o')
    status = if ($accepted) { 'PASS' } else { 'BLOCKED' }
    accepted = [bool]$accepted
    stop_code = $stopCode
    current_trusted_version_before_gate = $statusFiles.version
    v6_2_allowed = [bool]$accepted
    v6_1_series_closed = [bool]$accepted
    verifier_result_path = $VerifierResultPath
    registry_path = $RegistryPath
    command_matrix_path = $CommandMatrixPath
    execution_outcome_classifier_selftest_path = $ExecutionClassifierSelftestPath
    execution_outcome_classifier_selftest_status = if ($executionSelftest) { [string]$executionSelftest.status } else { 'MISSING' }
    command_results = @($commandResults.ToArray())
    qqmail_sent_folder_false_positive_negative = [bool]$negativeOk
    case_freeze_ok = [bool]$caseFreezeOk
    integrated_sequence_status = if ($verifier) { [string]$verifier.integrated_sequence_status } else { 'MISSING' }
    findings = @($findings.ToArray())
}
Save-Json $result $GateResultPath

$findingRows = @($findings.ToArray()) | ForEach-Object {
    '- [{0}] {1} `{2}`' -f $_.code, $_.message, $_.path
}
if ($findingRows.Count -eq 0) { $findingRows = @('- No blocking findings.') }

$commandRows = @($commandResults.ToArray()) | ForEach-Object {
    '- {0}: {1} exit={2} timeout={3}' -f $_.name, $_.status, $_.exit_code, $_.timed_out
}

@(
    '# v6.1.6 Dynamic App/Web Full Access Acceptance Gate',
    '',
    "- Result: $($result.status)",
    "- Accepted: $($result.accepted)",
    "- Stop code: $($result.stop_code)",
    "- v6.2 allowed: $($result.v6_2_allowed)",
    "- v6.1 series closed: $($result.v6_1_series_closed)",
    "- Verifier result: $VerifierResultPath",
    "- Command matrix: $CommandMatrixPath",
    '',
    '## Required Commands'
) + $commandRows + @(
    '',
    '## Findings'
) + $findingRows | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'v6_1_6_acceptance_gate_report.md') -Encoding UTF8

@(
    '# v6.1.6 Final Status Report',
    '',
    "- Result: $($result.status)",
    "- Accepted: $($result.accepted)",
    "- Stop code: $($result.stop_code)",
    "- Current trusted version before gate: $($result.current_trusted_version_before_gate)",
    "- v6.2 allowed: $($result.v6_2_allowed)",
    "- v6.1 series closed: $($result.v6_1_series_closed)",
    "- Gate result: $GateResultPath",
    "- Verifier result: $VerifierResultPath",
    "- Registry: $RegistryPath"
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'final_status_report.md') -Encoding UTF8

if ($accepted) {
    Write-Host 'v6.1.6 accepted'
    exit 0
}
Write-Host $stopCode
exit 1

