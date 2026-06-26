param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.7.0_explorer_agent_workflows\selftest\verifier'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "winagent.exe not found. Run build.ps1 before explorer_workflow_verifier_selftest.ps1."
}

function Write-JsonFile([string]$Path, [object]$Object) {
    $Object | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-WinAgent([string[]]$CommandArgs, [int[]]$AllowedExitCodes = @(0)) {
    $name = ([guid]::NewGuid().ToString('N'))
    $stdout = Join-Path $OutDir "$name.stdout.json"
    $stderr = Join-Path $OutDir "$name.stderr.txt"
    $p = Start-Process -FilePath $WinAgent -ArgumentList $CommandArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $text = if (Test-Path -LiteralPath $stdout) { Get-Content -Raw -LiteralPath $stdout } else { '' }
    if ($AllowedExitCodes -notcontains $p.ExitCode) {
        $err = if (Test-Path -LiteralPath $stderr) { Get-Content -Raw -LiteralPath $stderr } else { '' }
        throw "winagent $($CommandArgs -join ' ') exit $($p.ExitCode). stdout=$text stderr=$err"
    }
    return @{ ExitCode = $p.ExitCode; Stdout = $text; StdoutPath = $stdout; StderrPath = $stderr }
}

$valid = Join-Path $OutDir 'valid_open_path.result.json'
Write-JsonFile $valid @{
    schema_version = '6.7.0.explorer_workflow.result'
    workflow_type = 'explorer_open_path'
    execution_mode = 'execute_local_safe'
    final_status = 'PASS'
    workflow_compiled = $true
    compiled_step_contract_used = $true
    step_contract_validator_used = $true
    runtime_session_used = $true
    runtime_context_guard_used = $true
    powershell_file_action_used = $false
    direct_file_api_workflow_action_used = $false
    runner_only_workflow_logic = $false
    folder_opened = $true
    expected_folder_verified = $true
}
Invoke-WinAgent @('verify-explorer-workflow', '--result', $valid, '--output', (Join-Path $OutDir 'valid_open_path.verification.json')) | Out-Null

$fake = Join-Path $OutDir 'powershell_fake.result.json'
Write-JsonFile $fake @{
    schema_version = '6.7.0.explorer_workflow.result'
    workflow_type = 'explorer_rename_file'
    execution_mode = 'execute_local_safe'
    final_status = 'PASS'
    workflow_compiled = $true
    compiled_step_contract_used = $true
    step_contract_validator_used = $true
    runtime_session_used = $true
    runtime_context_guard_used = $true
    powershell_file_action_used = $true
    direct_file_api_workflow_action_used = $false
    runner_only_workflow_logic = $false
    old_name_exists_before = $true
    new_name_exists_after = $true
    old_name_absent_after = $true
    result_verified = $true
}
$fakeResult = Invoke-WinAgent @('verify-explorer-workflow', '--result', $fake, '--output', (Join-Path $OutDir 'powershell_fake.verification.json')) @(1)
if ($fakeResult.Stdout -notmatch 'BLOCKED_FAKE_FILESYSTEM_EXECUTION') {
    throw 'Verifier did not reject PowerShell-only fake execution evidence.'
}

$direct = Join-Path $OutDir 'direct_file_api.result.json'
Write-JsonFile $direct @{
    schema_version = '6.7.0.explorer_workflow.result'
    workflow_type = 'explorer_move_file'
    execution_mode = 'execute_local_safe'
    final_status = 'PASS'
    workflow_compiled = $true
    compiled_step_contract_used = $true
    step_contract_validator_used = $true
    runtime_session_used = $true
    runtime_context_guard_used = $true
    powershell_file_action_used = $false
    direct_file_api_workflow_action_used = $true
    runner_only_workflow_logic = $false
    source_exists_before = $true
    source_absent_after = $true
    destination_exists_after = $true
    result_verified = $true
}
$directResult = Invoke-WinAgent @('verify-explorer-workflow', '--result', $direct, '--output', (Join-Path $OutDir 'direct_file_api.verification.json')) @(1)
if ($directResult.Stdout -notmatch 'BLOCKED_DIRECT_FILE_API_WORKFLOW') {
    throw 'Verifier did not reject direct file API workflow evidence.'
}

$missingRuntime = Join-Path $OutDir 'missing_runtime.result.json'
Write-JsonFile $missingRuntime @{
    schema_version = '6.7.0.explorer_workflow.result'
    workflow_type = 'explorer_open_path'
    execution_mode = 'execute_local_safe'
    final_status = 'PASS'
    workflow_compiled = $true
    compiled_step_contract_used = $true
    step_contract_validator_used = $true
    runtime_session_used = $false
    runtime_context_guard_used = $true
    powershell_file_action_used = $false
    direct_file_api_workflow_action_used = $false
    runner_only_workflow_logic = $false
    folder_opened = $true
    expected_folder_verified = $true
}
$runtimeResult = Invoke-WinAgent @('verify-explorer-workflow', '--result', $missingRuntime, '--output', (Join-Path $OutDir 'missing_runtime.verification.json')) @(1)
if ($runtimeResult.Stdout -notmatch 'BLOCKED_RUNTIME_SESSION_NOT_USED') {
    throw 'Verifier did not reject missing RuntimeSession.'
}

$missingEvidence = Join-Path $OutDir 'missing_specific_evidence.result.json'
Write-JsonFile $missingEvidence @{
    schema_version = '6.7.0.explorer_workflow.result'
    workflow_type = 'explorer_scroll_and_locate'
    execution_mode = 'execute_local_safe'
    final_status = 'PASS'
    workflow_compiled = $true
    compiled_step_contract_used = $true
    step_contract_validator_used = $true
    runtime_session_used = $true
    runtime_context_guard_used = $true
    powershell_file_action_used = $false
    direct_file_api_workflow_action_used = $false
    runner_only_workflow_logic = $false
    scroll_used = $true
    scroll_progress_detected = $false
    target_found = $true
    target_clicked_or_verified = $true
    no_stale_rect = $true
}
$evidenceResult = Invoke-WinAgent @('verify-explorer-workflow', '--result', $missingEvidence, '--output', (Join-Path $OutDir 'missing_specific_evidence.verification.json')) @(1)
if ($evidenceResult.Stdout -notmatch 'BLOCKED_SCROLL_PROGRESS_NOT_PROVEN') {
    throw 'Verifier did not reject missing Explorer-specific evidence.'
}

$missingMoveEvidence = Join-Path $OutDir 'missing_move_staged_evidence.result.json'
Write-JsonFile $missingMoveEvidence @{
    schema_version = '6.7.0.explorer_workflow.result'
    workflow_type = 'explorer_move_file'
    execution_mode = 'execute_local_safe'
    final_status = 'PASS'
    workflow_compiled = $true
    compiled_step_contract_used = $true
    step_contract_validator_used = $true
    runtime_session_used = $true
    runtime_context_guard_used = $true
    powershell_file_action_used = $false
    direct_file_api_workflow_action_used = $false
    runner_only_workflow_logic = $false
    source_exists_before = $true
    source_absent_after = $true
    destination_exists_after = $true
    result_verified = $true
}
$moveEvidenceResult = Invoke-WinAgent @('verify-explorer-workflow', '--result', $missingMoveEvidence, '--output', (Join-Path $OutDir 'missing_move_staged_evidence.verification.json')) @(1)
if ($moveEvidenceResult.Stdout -notmatch 'BLOCKED_EXPLORER_MOVE_EVIDENCE_INCOMPLETE') {
    throw 'Verifier did not reject missing move staged evidence.'
}

$report = Join-Path $OutDir 'explorer_workflow_verifier_selftest_report.md'
@(
    '# Explorer Workflow Verifier Selftest'
    ''
    '- Status: PASS'
    '- valid open_path evidence accepted: PASS'
    '- PowerShell-only fake execution rejected: PASS'
    '- direct file API workflow evidence rejected: PASS'
    '- missing RuntimeSession rejected: PASS'
    '- missing Explorer-specific evidence rejected: PASS'
    '- missing move staged evidence rejected: PASS'
) | Set-Content -LiteralPath $report -Encoding UTF8

Write-Host "Explorer workflow verifier selftest PASS. Report: $report"
