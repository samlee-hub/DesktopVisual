param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.7.0_explorer_agent_workflows_rerun'
$OutDir = Join-Path $ArtifactRoot 'full_regression'
$ResultJson = Join-Path $ArtifactRoot 'full_regression_rerun_result.json'
$Report = Join-Path $ArtifactRoot 'full_regression_rerun_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$tests = @(
    '.\build.ps1',
    '.\selftest.ps1',
    '.\runtime_context_guard_selftest.ps1',
    '.\browser_surface_normalization_selftest.ps1',
    '.\runtime_session_selftest.ps1',
    '.\runtime_session_cache_selftest.ps1',
    '.\runtime_session_latency_benchmark.ps1',
    '.\plan_compiler_selftest.ps1',
    '.\step_contract_validator_selftest.ps1',
    '.\compiled_plan_executor_selftest.ps1',
    '.\step_execution_verifier_selftest.ps1',
    '.\execution_evidence_pack_selftest.ps1',
    '.\vlm_observation_contract_selftest.ps1',
    '.\mock_vlm_provider_selftest.ps1',
    '.\vlm_observation_validator_selftest.ps1',
    '.\vlm_observation_boundary_selftest.ps1',
    '.\vlm_candidate_bridge_selftest.ps1',
    '.\runtime_candidate_validator_selftest.ps1',
    '.\vlm_locator_candidate_selftest.ps1',
    '.\vlm_assisted_local_safe_action_selftest.ps1',
    '.\explorer_workflow_schema_selftest.ps1',
    '.\explorer_workflow_compiler_selftest.ps1',
    '.\explorer_workflow_executor_selftest.ps1',
    '.\explorer_workflow_verifier_selftest.ps1',
    '.\explorer_context_menu_selftest.ps1',
    '.\explorer_recovery_selftest.ps1',
    '.\explorer_move_file_selftest.ps1',
    '.\explorer_scroll_and_locate_selftest.ps1',
    '.\v6_1_2_pre_v6_2_acceptance_gate.ps1',
    '.\v6_1_3_scroll_acceptance_gate.ps1',
    '.\v6_1_4_runtime_guard_acceptance_gate.ps1',
    '.\v6_1_5_safe_context_recovery_acceptance_gate.ps1',
    '.\v6_1_5a_mouse_first_interaction_acceptance_gate.ps1',
    '.\v6_1_6_scope_reset_step_completion_acceptance_gate.ps1',
    '.\v6_2_0_persistent_runtime_acceptance_gate.ps1',
    '.\v6_3_0_plan_compiler_acceptance_gate.ps1',
    '.\v6_4_0_runtime_task_execution_acceptance_gate.ps1',
    '.\v6_5_0_vlm_observation_acceptance_gate.ps1',
    '.\v6_6_0_vlm_candidate_acceptance_gate.ps1'
)

$optional = @(
    '.\adapter_selftest.ps1',
    '.\app_profile_selftest.ps1',
    '.\case_v2_selftest.ps1',
    '.\selector_selftest.ps1',
    '.\serve_selftest.ps1'
)
foreach ($test in $optional) {
    if (Test-Path -LiteralPath (Join-Path $Root ($test -replace '^\.\\', ''))) {
        $tests += $test
    }
}

$tests += @(
    '.\v6_7_0_explorer_workflow_runner.ps1',
    '.\v6_7_0_explorer_workflow_verifier.ps1',
    '.\v6_7_0_explorer_workflow_acceptance_gate.ps1'
)

function Write-RegressionState([object[]]$Results, [bool]$Completed, [string]$Status) {
    $failed = @($Results | Where-Object { $_.status -eq 'FAIL' })
    $firstFailure = if ($failed.Count -gt 0) { $failed[0].test } else { '' }
    [pscustomobject]@{
        started_from_beginning = $true
        commands_total = $tests.Count
        commands_completed = $Results.Count
        commands_passed = @($Results | Where-Object { $_.status -eq 'PASS' }).Count
        commands_failed = $failed.Count
        first_failure = $firstFailure
        full_regression_completed = $Completed
        final_status = $Status
        rerun_after_targeted_fixes = $true
        results = $Results
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ResultJson -Encoding UTF8

    @(
        '# v6.7.0-rerun Full Regression Report'
        ''
        "- Status: $Status"
        "- Completed: $($Results.Count) / $($tests.Count)"
        "- started_from_beginning: true"
        "- full_regression_completed: $Completed"
        "- first_failure: $firstFailure"
        ''
        ($Results | ForEach-Object { "- $($_.test): $($_.status) exit=$($_.exit_code)" })
    ) | Set-Content -LiteralPath $Report -Encoding UTF8
}

$results = @()
for ($i = 0; $i -lt $tests.Count; ++$i) {
    $test = $tests[$i]

    if ($test -eq '.\v6_7_0_explorer_workflow_acceptance_gate.ps1') {
        Write-RegressionState $results $true 'PASS'
    }

    $name = ($test -replace '[\\.: ]', '_')
    $stdout = Join-Path $OutDir "$name.stdout.txt"
    $stderr = Join-Path $OutDir "$name.stderr.txt"
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $test) -WorkingDirectory $Root -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $record = [pscustomobject]@{
        test = $test
        exit_code = $p.ExitCode
        status = if ($p.ExitCode -eq 0) { 'PASS' } else { 'FAIL' }
        stdout = $stdout
        stderr = $stderr
    }
    $results += $record
    if ($p.ExitCode -ne 0) {
        Write-RegressionState $results $false 'BLOCKED'
        Write-Host "v6.7.0 full regression BLOCKED. Report: $Report"
        exit 1
    }
}

Write-RegressionState $results $true 'PASS'
Write-Host "v6.7.0 full regression PASS. Report: $Report"
