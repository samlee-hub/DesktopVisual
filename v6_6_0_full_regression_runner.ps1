param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$EvidenceRoot = Join-Path $Root 'artifacts\dev6.6.0_vlm_assisted_unknown_ui_candidate_handling'
$RegressionRoot = Join-Path $EvidenceRoot 'full_regression'
New-Item -ItemType Directory -Force -Path $RegressionRoot | Out-Null

$ResultPath = Join-Path $EvidenceRoot 'full_regression_result.json'
$ReportPath = Join-Path $EvidenceRoot 'full_regression_report.md'
$ProgressPath = Join-Path $EvidenceRoot 'full_regression_progress.json'

$commands = @(
    @{ name='build'; path='build.ps1'; args=@('-Root',$Root); required=$true },
    @{ name='selftest'; path='selftest.ps1'; args=@(); required=$true },
    @{ name='runtime_context_guard_selftest'; path='runtime_context_guard_selftest.ps1'; args=@(); required=$true },
    @{ name='browser_surface_normalization_selftest'; path='browser_surface_normalization_selftest.ps1'; args=@(); required=$true },
    @{ name='runtime_session_selftest'; path='runtime_session_selftest.ps1'; args=@(); required=$true },
    @{ name='runtime_session_cache_selftest'; path='runtime_session_cache_selftest.ps1'; args=@(); required=$true },
    @{ name='runtime_session_latency_benchmark'; path='runtime_session_latency_benchmark.ps1'; args=@(); required=$true },
    @{ name='plan_compiler_selftest'; path='plan_compiler_selftest.ps1'; args=@('-Root',$Root); required=$true },
    @{ name='step_contract_validator_selftest'; path='step_contract_validator_selftest.ps1'; args=@('-Root',$Root); required=$true },
    @{ name='compiled_plan_executor_selftest'; path='compiled_plan_executor_selftest.ps1'; args=@('-Root',$Root); required=$true },
    @{ name='step_execution_verifier_selftest'; path='step_execution_verifier_selftest.ps1'; args=@('-Root',$Root); required=$true },
    @{ name='execution_evidence_pack_selftest'; path='execution_evidence_pack_selftest.ps1'; args=@('-Root',$Root); required=$true },
    @{ name='vlm_observation_contract_selftest'; path='vlm_observation_contract_selftest.ps1'; args=@('-Root',$Root,'-SkipBuild'); required=$true },
    @{ name='mock_vlm_provider_selftest'; path='mock_vlm_provider_selftest.ps1'; args=@('-Root',$Root,'-SkipBuild'); required=$true },
    @{ name='vlm_observation_validator_selftest'; path='vlm_observation_validator_selftest.ps1'; args=@('-Root',$Root,'-SkipBuild'); required=$true },
    @{ name='vlm_observation_boundary_selftest'; path='vlm_observation_boundary_selftest.ps1'; args=@('-Root',$Root,'-SkipBuild'); required=$true },
    @{ name='vlm_candidate_bridge_selftest'; path='vlm_candidate_bridge_selftest.ps1'; args=@('-Root',$Root,'-SkipBuild'); required=$true },
    @{ name='runtime_candidate_validator_selftest'; path='runtime_candidate_validator_selftest.ps1'; args=@('-Root',$Root,'-SkipBuild'); required=$true },
    @{ name='vlm_locator_candidate_selftest'; path='vlm_locator_candidate_selftest.ps1'; args=@('-Root',$Root,'-SkipBuild'); required=$true },
    @{ name='vlm_assisted_local_safe_action_selftest'; path='vlm_assisted_local_safe_action_selftest.ps1'; args=@('-Root',$Root,'-SkipBuild'); required=$true },
    @{ name='v6_1_2_pre_v6_2_acceptance_gate'; path='v6_1_2_pre_v6_2_acceptance_gate.ps1'; args=@(); required=$true },
    @{ name='v6_1_3_scroll_acceptance_gate'; path='v6_1_3_scroll_acceptance_gate.ps1'; args=@(); required=$true },
    @{ name='v6_1_4_runtime_guard_acceptance_gate'; path='v6_1_4_runtime_guard_acceptance_gate.ps1'; args=@(); required=$true },
    @{ name='v6_1_5_safe_context_recovery_acceptance_gate'; path='v6_1_5_safe_context_recovery_acceptance_gate.ps1'; args=@(); required=$true },
    @{ name='v6_1_5a_mouse_first_interaction_acceptance_gate'; path='v6_1_5a_mouse_first_interaction_acceptance_gate.ps1'; args=@(); required=$true },
    @{ name='v6_1_6_scope_reset_step_completion_acceptance_gate'; path='v6_1_6_scope_reset_step_completion_acceptance_gate.ps1'; args=@(); required=$true },
    @{ name='v6_2_0_persistent_runtime_acceptance_gate'; path='v6_2_0_persistent_runtime_acceptance_gate.ps1'; args=@(); required=$true },
    @{ name='v6_3_0_plan_compiler_acceptance_gate'; path='v6_3_0_plan_compiler_acceptance_gate.ps1'; args=@(); required=$true },
    @{ name='v6_4_0_runtime_task_execution_acceptance_gate'; path='v6_4_0_runtime_task_execution_acceptance_gate.ps1'; args=@(); required=$true },
    @{ name='v6_5_0_vlm_observation_acceptance_gate'; path='v6_5_0_vlm_observation_acceptance_gate.ps1'; args=@('-Root',$Root); required=$true },
    @{ name='v6_6_0_vlm_candidate_runner'; path='v6_6_0_vlm_candidate_runner.ps1'; args=@('-Root',$Root); required=$true },
    @{ name='v6_6_0_vlm_candidate_verifier'; path='v6_6_0_vlm_candidate_verifier.ps1'; args=@('-Root',$Root); required=$true }
)

$optionalCommands = @()
foreach ($optional in @('adapter_selftest.ps1','app_profile_selftest.ps1','case_v2_selftest.ps1','selector_selftest.ps1','serve_selftest.ps1')) {
    if (Test-Path -LiteralPath (Join-Path $Root $optional)) {
        $optionalCommands += @{ name=($optional -replace '\.ps1$',''); path=$optional; args=@(); required=$false }
    }
}

function Get-RequiredStatus($Items) {
    foreach ($item in $Items) {
        if ($item.required -and $item.status -ne 'PASS') { return 'FAIL' }
    }
    return 'PASS'
}

function Write-FullRegressionResult($Status, $CommandResults, $OptionalResults, $RcCheck) {
    $commandArray = @()
    foreach ($item in $CommandResults) { $commandArray += $item }
    $optionalArray = @()
    foreach ($item in $OptionalResults) { $optionalArray += $item }

    $result = [ordered]@{
        schema_version = '6.6.0.full_regression'
        generated_at = (Get-Date).ToString('o')
        status = $Status
        commands = $commandArray
        optional_commands = $optionalArray
        rc_check = $RcCheck
    }
    $result | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $ResultPath -Encoding UTF8

    $lines = @('# v6.6.0 Full Regression Result','')
    $lines += "- Status: $Status"
    $lines += "- Required commands: $(@($commandArray | Where-Object { $_.required }).Count)"
    $lines += "- Optional commands: $(@($optionalArray).Count)"
    $lines += "- rc_check: $($RcCheck.status)"
    $lines += "- Result JSON: $ResultPath"
    $lines += ''
    $lines += '## Required Commands'
    foreach ($item in $commandArray) {
        $lines += "- $($item.name): $($item.status) exit=$($item.exit_code) duration_ms=$($item.duration_ms)"
    }
    if (@($optionalArray).Count -gt 0) {
        $lines += ''
        $lines += '## Optional Commands'
        foreach ($item in $optionalArray) {
            $lines += "- $($item.name): $($item.status) exit=$($item.exit_code) duration_ms=$($item.duration_ms)"
        }
    }
    $lines += ''
    $lines += '## rc_check'
    $lines += "- Status: $($RcCheck.status)"
    $lines += "- Exit code: $($RcCheck.exit_code)"
    $lines += "- Stdout: $($RcCheck.stdout)"
    $lines += "- Stderr: $($RcCheck.stderr)"
    [System.IO.File]::WriteAllLines($ReportPath, [string[]]$lines, [System.Text.UTF8Encoding]::new($false))
}

function Write-Progress($Phase, $CurrentName, $Completed, $Total) {
    [ordered]@{
        schema_version = '6.6.0.full_regression.progress'
        generated_at = (Get-Date).ToString('o')
        phase = $Phase
        current = $CurrentName
        completed = $Completed
        total = $Total
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ProgressPath -Encoding UTF8
}

function Invoke-RegressionCommand($Command, $Kind) {
    $script = Join-Path $Root $Command.path
    $commandDir = Join-Path $RegressionRoot $Command.name
    New-Item -ItemType Directory -Force -Path $commandDir | Out-Null
    $stdout = Join-Path $commandDir 'stdout.txt'
    $stderr = Join-Path $commandDir 'stderr.txt'
    $started = Get-Date

    if (-not (Test-Path -LiteralPath $script)) {
        '' | Set-Content -LiteralPath $stdout -Encoding UTF8
        "Missing script: $script" | Set-Content -LiteralPath $stderr -Encoding UTF8
        return [ordered]@{
            name = $Command.name
            command = $Command.path
            kind = $Kind
            required = [bool]$Command.required
            status = 'MISSING'
            exit_code = $null
            duration_ms = 0
            stdout = $stdout
            stderr = $stderr
        }
    }

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script @($Command.args) 2>&1
        $exit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    $output | Out-File -LiteralPath $stdout -Encoding utf8
    '' | Out-File -LiteralPath $stderr -Encoding utf8
    $duration = [int]((Get-Date) - $started).TotalMilliseconds
    $status = if ($exit -eq 0) { 'PASS' } else { 'FAIL' }
    [ordered]@{
        name = $Command.name
        command = $Command.path
        kind = $Kind
        required = [bool]$Command.required
        status = $status
        exit_code = $exit
        duration_ms = $duration
        stdout = $stdout
        stderr = $stderr
    }
}

$commandResults = New-Object System.Collections.Generic.List[object]
$optionalResults = New-Object System.Collections.Generic.List[object]
$rcCheck = [ordered]@{ name='rc_check'; command='rc_check.ps1'; kind='rc_check'; required=$false; status='not_run'; exit_code=$null; duration_ms=0; stdout=''; stderr='' }

$total = @($commands).Count + @($optionalCommands).Count + 2
$completed = 0
foreach ($cmd in $commands) {
    Write-Progress 'required' $cmd.name $completed $total
    $result = Invoke-RegressionCommand $cmd 'required'
    $commandResults.Add($result) | Out-Null
    $completed += 1
    Write-Output "$($result.name): $($result.status) exit=$($result.exit_code) duration_ms=$($result.duration_ms)"
    Write-FullRegressionResult (Get-RequiredStatus $commandResults) $commandResults $optionalResults $rcCheck
}

foreach ($cmd in $optionalCommands) {
    Write-Progress 'optional' $cmd.name $completed $total
    $result = Invoke-RegressionCommand $cmd 'optional'
    $optionalResults.Add($result) | Out-Null
    $completed += 1
    Write-Output "$($result.name): $($result.status) exit=$($result.exit_code) duration_ms=$($result.duration_ms)"
    Write-FullRegressionResult (Get-RequiredStatus $commandResults) $commandResults $optionalResults $rcCheck
}

$rcScript = Join-Path $Root 'rc_check.ps1'
if (Test-Path -LiteralPath $rcScript) {
    Write-Progress 'rc_check' 'rc_check' $completed $total
    $rcResult = Invoke-RegressionCommand @{ name='rc_check'; path='rc_check.ps1'; args=@('-Root',$Root); required=$false } 'rc_check'
    $rcCheck = [ordered]@{
        name = 'rc_check'
        command = 'rc_check.ps1'
        kind = 'rc_check'
        required = $false
        status = $rcResult.status
        exit_code = $rcResult.exit_code
        duration_ms = $rcResult.duration_ms
        stdout = $rcResult.stdout
        stderr = $rcResult.stderr
    }
    $completed += 1
    Write-Output "rc_check: $($rcCheck.status) exit=$($rcCheck.exit_code) duration_ms=$($rcCheck.duration_ms)"
} else {
    $rcCheck = [ordered]@{ name='rc_check'; command='rc_check.ps1'; kind='rc_check'; required=$false; status='not_run'; exit_code=$null; duration_ms=0; stdout=''; stderr='missing' }
}

$preGateStatus = if ((Get-RequiredStatus $commandResults) -eq 'PASS') { 'PASS_PENDING_GATE' } else { 'FAIL' }
Write-FullRegressionResult $preGateStatus $commandResults $optionalResults $rcCheck

$gateCommand = @{ name='v6_6_0_vlm_candidate_acceptance_gate'; path='v6_6_0_vlm_candidate_acceptance_gate.ps1'; args=@('-Root',$Root); required=$true }
Write-Progress 'acceptance_gate' $gateCommand.name $completed $total
$gateResult = Invoke-RegressionCommand $gateCommand 'required'
$commandResults.Add($gateResult) | Out-Null
$completed += 1
Write-Output "$($gateResult.name): $($gateResult.status) exit=$($gateResult.exit_code) duration_ms=$($gateResult.duration_ms)"

$finalStatus = if ($preGateStatus -eq 'PASS_PENDING_GATE' -and $gateResult.status -eq 'PASS') { 'PASS' } else { 'FAIL' }
Write-FullRegressionResult $finalStatus $commandResults $optionalResults $rcCheck
Write-Progress 'complete' $finalStatus $completed $total

if ($finalStatus -ne 'PASS') {
    'V6_6_0_FULL_REGRESSION_FAIL'
    exit 1
}

'V6_6_0_FULL_REGRESSION_PASS'
