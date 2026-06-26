param(
    [string]$Root = '',
    [switch]$IncludeAcceptanceGate
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$EvidenceRoot = Join-Path $Root 'artifacts\dev6.5.0_vlm_assisted_observation_contract'
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null

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
    @{ name='v6_1_2_pre_v6_2_acceptance_gate'; path='v6_1_2_pre_v6_2_acceptance_gate.ps1'; args=@(); required=$true },
    @{ name='v6_1_3_scroll_acceptance_gate'; path='v6_1_3_scroll_acceptance_gate.ps1'; args=@(); required=$true },
    @{ name='v6_1_4_runtime_guard_acceptance_gate'; path='v6_1_4_runtime_guard_acceptance_gate.ps1'; args=@(); required=$true },
    @{ name='v6_1_5_safe_context_recovery_acceptance_gate'; path='v6_1_5_safe_context_recovery_acceptance_gate.ps1'; args=@(); required=$true },
    @{ name='v6_1_5a_mouse_first_interaction_acceptance_gate'; path='v6_1_5a_mouse_first_interaction_acceptance_gate.ps1'; args=@(); required=$true },
    @{ name='v6_1_6_scope_reset_step_completion_acceptance_gate'; path='v6_1_6_scope_reset_step_completion_acceptance_gate.ps1'; args=@(); required=$true },
    @{ name='v6_2_0_persistent_runtime_acceptance_gate'; path='v6_2_0_persistent_runtime_acceptance_gate.ps1'; args=@(); required=$true },
    @{ name='v6_3_0_plan_compiler_acceptance_gate'; path='v6_3_0_plan_compiler_acceptance_gate.ps1'; args=@(); required=$true },
    @{ name='v6_4_0_runtime_task_execution_acceptance_gate'; path='v6_4_0_runtime_task_execution_acceptance_gate.ps1'; args=@(); required=$true },
    @{ name='v6_5_0_vlm_observation_runner'; path='v6_5_0_vlm_observation_runner.ps1'; args=@('-Root',$Root); required=$true },
    @{ name='v6_5_0_vlm_observation_verifier'; path='v6_5_0_vlm_observation_verifier.ps1'; args=@('-Root',$Root); required=$true }
)

foreach ($optional in @('adapter_selftest.ps1','app_profile_selftest.ps1','case_v2_selftest.ps1','selector_selftest.ps1','serve_selftest.ps1')) {
    if (Test-Path (Join-Path $Root $optional)) {
        $commands += @{ name=($optional -replace '\.ps1$',''); path=$optional; args=@(); required=$false }
    }
}

if ($IncludeAcceptanceGate) {
    $commands += @{ name='v6_5_0_vlm_observation_acceptance_gate'; path='v6_5_0_vlm_observation_acceptance_gate.ps1'; args=@('-Root',$Root); required=$true }
}

$results = New-Object System.Collections.Generic.List[object]
foreach ($cmd in $commands) {
    $script = Join-Path $Root $cmd.path
    $stdout = Join-Path $EvidenceRoot ("regression_{0}.stdout.txt" -f $cmd.name)
    $stderr = Join-Path $EvidenceRoot ("regression_{0}.stderr.txt" -f $cmd.name)
    $started = Get-Date
    if (-not (Test-Path $script)) {
        $results.Add([ordered]@{ name=$cmd.name; required=$cmd.required; status='MISSING'; exit_code=$null; duration_ms=0; stdout=$stdout; stderr=$stderr }) | Out-Null
        Write-Output "$($cmd.name): MISSING"
        continue
    }
    if ($IncludeAcceptanceGate -and $cmd.name -eq 'v6_5_0_vlm_observation_acceptance_gate') {
        $preGateStatus = 'PASS'
        foreach ($existing in $results) {
            if ($existing.required -and $existing.status -ne 'PASS') { $preGateStatus = 'FAIL' }
        }
        $preGateRcCheck = [ordered]@{ status='not_run'; required=$false }
        $preGateRcCheckResultPath = Join-Path $EvidenceRoot 'rc_check_result.json'
        if (Test-Path -LiteralPath $preGateRcCheckResultPath) {
            try { $preGateRcCheck = Get-Content -LiteralPath $preGateRcCheckResultPath -Raw | ConvertFrom-Json } catch { $preGateRcCheck = [ordered]@{ status='unreadable'; required=$false; path=$preGateRcCheckResultPath } }
        }
        [pscustomobject]@{
            schema_version = '6.5.0.full_regression'
            generated_at = (Get-Date).ToString('o')
            status = $preGateStatus
            acceptance_gate_included = $false
            commands = $results.ToArray()
            rc_check = $preGateRcCheck
        } | ConvertTo-Json -Depth 30 | Set-Content -Encoding UTF8 (Join-Path $EvidenceRoot 'full_regression_result.json')
    }
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $script @($cmd.args) 2>&1
        $exit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    $output | Out-File -Encoding utf8 $stdout
    '' | Out-File -Encoding utf8 $stderr
    $duration = [int]((Get-Date) - $started).TotalMilliseconds
    $status = if ($exit -eq 0) { 'PASS' } else { 'FAIL' }
    $results.Add([ordered]@{ name=$cmd.name; required=$cmd.required; status=$status; exit_code=$exit; duration_ms=$duration; stdout=$stdout; stderr=$stderr }) | Out-Null
    Write-Output "$($cmd.name): $status exit=$exit duration_ms=$duration"
}

$status = 'PASS'
foreach ($result in $results) {
    if ($result.required -and $result.status -ne 'PASS') { $status = 'FAIL' }
}

$rcCheck = [ordered]@{ status='not_run'; required=$false }
$rcCheckResultPath = Join-Path $EvidenceRoot 'rc_check_result.json'
if (Test-Path -LiteralPath $rcCheckResultPath) {
    try { $rcCheck = Get-Content -LiteralPath $rcCheckResultPath -Raw | ConvertFrom-Json } catch { $rcCheck = [ordered]@{ status='unreadable'; required=$false; path=$rcCheckResultPath } }
}

$resultObject = [pscustomobject]@{
    schema_version = '6.5.0.full_regression'
    generated_at = (Get-Date).ToString('o')
    status = $status
    acceptance_gate_included = [bool]$IncludeAcceptanceGate
    commands = $results.ToArray()
    rc_check = $rcCheck
}
$resultObject | ConvertTo-Json -Depth 30 | Set-Content -Encoding UTF8 (Join-Path $EvidenceRoot 'full_regression_result.json')

$lines = @('# v6.5.0 Full Regression Result','')
$lines += "- Status: $status"
$lines += "- v6.5.0 acceptance gate included: $([bool]$IncludeAcceptanceGate)"
$lines += ''
foreach ($result in $results) {
    $lines += "- $($result.name): $($result.status) exit=$($result.exit_code) duration_ms=$($result.duration_ms)"
}
$lines | Set-Content -Encoding UTF8 (Join-Path $EvidenceRoot 'full_regression_result.md')

if ($status -ne 'PASS') {
    'V6_5_0_FULL_REGRESSION_FAIL'
    exit 1
}

'V6_5_0_FULL_REGRESSION_PASS'

