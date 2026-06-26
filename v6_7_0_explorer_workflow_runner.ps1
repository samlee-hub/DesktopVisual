param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.7.0_explorer_agent_workflows_rerun'
$OutDir = Join-Path $ArtifactRoot 'acceptance\runner'
$Fixture = 'D:\testrepo\testwindow\explorer_workflow_v6_7'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
New-Item -ItemType Directory -Force -Path $Fixture | Out-Null

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "winagent.exe not found. Run build.ps1 before v6_7_0_explorer_workflow_runner.ps1."
}

function Write-JsonFile([string]$Path, [object]$Object) {
    $Object | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-WinAgent([string[]]$CommandArgs, [int[]]$AllowedExitCodes = @(0)) {
    $name = ([guid]::NewGuid().ToString('N'))
    $stdout = Join-Path $OutDir "$name.stdout.json"
    $stderr = Join-Path $OutDir "$name.stderr.txt"
    $p = Start-Process -FilePath $WinAgent -ArgumentList $CommandArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $text = if (Test-Path -LiteralPath $stdout) { Get-Content -Raw -LiteralPath $stdout } else { '' }
    $err = if (Test-Path -LiteralPath $stderr) { Get-Content -Raw -LiteralPath $stderr } else { '' }
    if ($AllowedExitCodes -notcontains $p.ExitCode) {
        throw "winagent $($CommandArgs -join ' ') exit $($p.ExitCode). stdout=$text stderr=$err"
    }
    return @{ ExitCode = $p.ExitCode; Stdout = $text; Stderr = $err; StdoutPath = $stdout; StderrPath = $stderr }
}

function Close-FixtureExplorerWindows {
    try {
        $shell = New-Object -ComObject Shell.Application
        foreach ($window in @($shell.Windows())) {
            try {
                $url = [string]$window.LocationURL
                if ($url -like 'file:///D:/testrepo/testwindow*') {
                    $window.Quit()
                }
            } catch {
            }
        }
        Start-Sleep -Milliseconds 700
    } catch {
    }
}

function Reset-Fixture {
    Close-FixtureExplorerWindows
    New-Item -ItemType Directory -Force -Path $Fixture | Out-Null
    Get-ChildItem -LiteralPath $Fixture -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path (Join-Path $Fixture 'move_dest') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Fixture 'long_list') | Out-Null
    'open path marker' | Set-Content -LiteralPath (Join-Path $Fixture 'open_path_marker.txt') -Encoding UTF8
    'open file target' | Set-Content -LiteralPath (Join-Path $Fixture 'open_file_target.txt') -Encoding UTF8
    'rename source' | Set-Content -LiteralPath (Join-Path $Fixture 'rename_source.txt') -Encoding UTF8
    'move source' | Set-Content -LiteralPath (Join-Path $Fixture 'move_source.txt') -Encoding UTF8
    'delete target' | Set-Content -LiteralPath (Join-Path $Fixture 'delete_target.txt') -Encoding UTF8
    'context source' | Set-Content -LiteralPath (Join-Path $Fixture 'context_menu_source.txt') -Encoding UTF8
    'ambiguous a' | Set-Content -LiteralPath (Join-Path $Fixture 'ambiguous_target_a.txt') -Encoding UTF8
    'ambiguous b' | Set-Content -LiteralPath (Join-Path $Fixture 'ambiguous_target_b.txt') -Encoding UTF8
    1..120 | ForEach-Object {
        $name = if ($_ -eq 80) { 'item_080_target_visible_after_scroll.txt' } else { ('item_{0:D3}.txt' -f $_) }
        ('long list item {0}' -f $_) | Set-Content -LiteralPath (Join-Path (Join-Path $Fixture 'long_list') $name) -Encoding UTF8
    }
}

function New-BaseContext([string[]]$Markers = @('explorer_workflow_v6_7')) {
    return @{
        expected_process_pattern = 'explorer.exe'
        expected_title_pattern = 'explorer_workflow_v6_7'
        required_markers = $Markers
        foreground_required = $true
        window_binding_required = $true
    }
}

function New-BaseStop {
    return @{
        stop_on_wrong_context = $true
        stop_on_target_not_unique = $true
        stop_on_target_stale = $true
        stop_on_unverified_result = $true
        stop_on_runtime_guard_failure = $true
    }
}

function New-Workflow([string]$Id, [string]$Type, [string]$Source, [string]$Target = '', [string]$Destination = '', [string]$ExpectedFolder = $Fixture, [string]$ExpectedFilename = '', [string]$Risk = 'READ_ONLY', [bool]$ConfirmationRequired = $false, [string]$ConfirmationToken = '', [string]$VerifyType = 'folder_opened', [hashtable]$RecoveryPolicy = $null, [string]$ContextMenuAction = 'rename', [bool]$IncludeAllowedRoot = $true, [bool]$IncludeVerificationHint = $true) {
    $workflow = @{
        workflow_id = $Id
        task_id = "task-$Id"
        workflow_type = $Type
        source_path = $Source
        target_path = $Target
        destination_path = $Destination
        expected_folder = $ExpectedFolder
        expected_filename = $ExpectedFilename
        risk_level = $Risk
        confirmation_required = $ConfirmationRequired
        confirmation_token = $ConfirmationToken
        context_menu_action = $ContextMenuAction
        expected_context = New-BaseContext
        stop_policy = New-BaseStop
    }
    if ($IncludeAllowedRoot) { $workflow.allowed_root = 'D:\testrepo' }
    if ($IncludeVerificationHint) { $workflow.verification_hint = @{ verify_type = $VerifyType; expected_marker = $ExpectedFilename } }
    if ($RecoveryPolicy) { $workflow.recovery_policy = $RecoveryPolicy }
    return $workflow
}

function Run-WorkflowCase([string]$Name, [hashtable]$Workflow, [int[]]$AllowedExitCodes = @(0), [string]$ExpectedStatus = 'PASS', [string]$ExpectedError = '') {
    $caseDir = Join-Path $OutDir $Name
    New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
    $workflowPath = Join-Path $caseDir 'workflow.json'
    $resultPath = Join-Path $caseDir 'result.json'
    Write-JsonFile $workflowPath $Workflow
    $run = Invoke-WinAgent @('run-explorer-workflow', '--input', $workflowPath, '--mode', 'execute-local-safe', '--output', $resultPath, '--evidence-dir', (Join-Path $caseDir 'evidence')) @(0, 1)
    $result = if (Test-Path -LiteralPath $resultPath) { Get-Content -Raw -LiteralPath $resultPath | ConvertFrom-Json } else { (($run.Stdout | ConvertFrom-Json).data) }
    $statusOk = [string]$result.final_status -eq $ExpectedStatus
    $errorOk = ($ExpectedError -eq '') -or ([string]$result.error_code -eq $ExpectedError) -or ($run.Stdout -match [regex]::Escape($ExpectedError))
    return [pscustomobject]@{
        name = $Name
        category = if ($ExpectedStatus -eq 'PASS') { 'positive' } else { 'negative' }
        ok = ($statusOk -and $errorOk)
        exit_code = $run.ExitCode
        expected_status = $ExpectedStatus
        final_status = [string]$result.final_status
        expected_error = $ExpectedError
        error_code = [string]$result.error_code
        result_path = $resultPath
        stdout_path = $run.StdoutPath
    }
}

function Compile-RejectCase([string]$Name, [hashtable]$Workflow, [string]$ExpectedError) {
    $caseDir = Join-Path $OutDir $Name
    New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
    $workflowPath = Join-Path $caseDir 'workflow.json'
    Write-JsonFile $workflowPath $Workflow
    $run = Invoke-WinAgent @('compile-explorer-workflow', '--input', $workflowPath, '--output', (Join-Path $caseDir 'step_contract.json')) @(1)
    return [pscustomObject]@{
        name = $Name
        category = 'negative'
        ok = ($run.Stdout -match [regex]::Escape($ExpectedError))
        exit_code = $run.ExitCode
        expected_status = 'REJECTED'
        final_status = 'REJECTED'
        expected_error = $ExpectedError
        error_code = $ExpectedError
        result_path = $workflowPath
        stdout_path = $run.StdoutPath
    }
}

function Verify-RejectCase([string]$Name, [hashtable]$ResultEvidence, [string]$ExpectedError) {
    $caseDir = Join-Path $OutDir $Name
    New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
    $resultPath = Join-Path $caseDir 'result.json'
    Write-JsonFile $resultPath $ResultEvidence
    $run = Invoke-WinAgent @('verify-explorer-workflow', '--result', $resultPath, '--output', (Join-Path $caseDir 'verification.json')) @(1)
    return [pscustomObject]@{
        name = $Name
        category = 'negative'
        ok = ($run.Stdout -match [regex]::Escape($ExpectedError))
        exit_code = $run.ExitCode
        expected_status = 'REJECTED'
        final_status = 'REJECTED'
        expected_error = $ExpectedError
        error_code = $ExpectedError
        result_path = $resultPath
        stdout_path = $run.StdoutPath
    }
}

Reset-Fixture
$results = @()

$results += Run-WorkflowCase 'case_01_open_path' (New-Workflow 'case-01-open-path' 'explorer_open_path' $Fixture -ExpectedFilename 'open_path_marker.txt' -Risk 'READ_ONLY' -VerifyType 'folder_opened')
$results += Run-WorkflowCase 'case_02_open_file' (New-Workflow 'case-02-open-file' 'explorer_open_file' (Join-Path $Fixture 'open_file_target.txt') -ExpectedFilename 'open_file_target.txt' -Risk 'READ_ONLY' -VerifyType 'file_opened')
$results += Run-WorkflowCase 'case_03_rename_file' (New-Workflow 'case-03-rename-file' 'explorer_rename_file' (Join-Path $Fixture 'rename_source.txt') -Target (Join-Path $Fixture 'renamed_expected.txt') -ExpectedFilename 'renamed_expected.txt' -Risk 'REVERSIBLE_DRAFT' -VerifyType 'file_renamed')
$results += Run-WorkflowCase 'case_04_move_file' (New-Workflow 'case-04-move-file' 'explorer_move_file' (Join-Path $Fixture 'move_source.txt') -Destination (Join-Path (Join-Path $Fixture 'move_dest') 'move_source.txt') -ExpectedFilename 'move_source.txt' -Risk 'REVERSIBLE_DRAFT' -VerifyType 'file_moved')
$results += Run-WorkflowCase 'case_05_delete_without_confirmation' (New-Workflow 'case-05-delete-without-confirmation' 'explorer_delete_file' (Join-Path $Fixture 'delete_target.txt') -ExpectedFilename 'delete_target.txt' -Risk 'DESTRUCTIVE' -ConfirmationRequired $true -VerifyType 'file_deleted') @(1) 'BLOCKED' 'BLOCKED_UNCONFIRMED_DESTRUCTIVE_ACTION'
$results += Run-WorkflowCase 'case_05_delete_with_confirmation' (New-Workflow 'case-05-delete-with-confirmation' 'explorer_delete_file' (Join-Path $Fixture 'delete_target.txt') -ExpectedFilename 'delete_target.txt' -Risk 'DESTRUCTIVE' -ConfirmationRequired $true -ConfirmationToken 'DV67_TEST_DELETE_CONFIRM' -VerifyType 'file_deleted')
Close-FixtureExplorerWindows
$scrollWorkflow = New-Workflow 'case-06-scroll-and-locate' 'explorer_scroll_and_locate' (Join-Path $Fixture 'long_list') -Target (Join-Path (Join-Path $Fixture 'long_list') 'item_080_target_visible_after_scroll.txt') -ExpectedFolder (Join-Path $Fixture 'long_list') -ExpectedFilename 'item_080_target_visible_after_scroll.txt' -Risk 'LOW_RISK' -VerifyType 'scroll_target_found'
$scrollWorkflow.expected_context = @{ expected_process_pattern = 'explorer.exe'; required_markers = @('long_list'); foreground_required = $true; window_binding_required = $true }
$results += Run-WorkflowCase 'case_06_scroll_and_locate' $scrollWorkflow
Close-FixtureExplorerWindows
$results += Run-WorkflowCase 'case_07_context_menu_rename' (New-Workflow 'case-07-context-menu-rename' 'explorer_context_menu_action' (Join-Path $Fixture 'context_menu_source.txt') -Target (Join-Path $Fixture 'context_menu_renamed.txt') -ExpectedFilename 'context_menu_renamed.txt' -Risk 'REVERSIBLE_DRAFT' -VerifyType 'context_menu_action_result' -ContextMenuAction 'rename')

$RecoveryTarget = Join-Path $Fixture 'recovery_case_target.txt'
'recovery case target' | Set-Content -LiteralPath $RecoveryTarget -Encoding UTF8
$WrongTitle = 'explorer_wrong_folder_runner_' + ([guid]::NewGuid().ToString('N').Substring(0, 8))
$WrongFolder = Join-Path 'D:\testrepo\testwindow' $WrongTitle
New-Item -ItemType Directory -Force -Path $WrongFolder | Out-Null
Start-Process explorer.exe -ArgumentList $WrongFolder | Out-Null
Start-Sleep -Seconds 1
Invoke-WinAgent @('focus', '--title', $WrongTitle) | Out-Null
Start-Sleep -Milliseconds 300
$results += Run-WorkflowCase 'case_08_wrong_folder_recovery' (New-Workflow 'case-08-wrong-folder-recovery' 'explorer_open_file' $RecoveryTarget -ExpectedFilename 'recovery_case_target.txt' -Risk 'READ_ONLY' -VerifyType 'file_opened' -RecoveryPolicy @{ recovery_allowed = $true; recovery_scope = 'explorer_allowed_root'; recovery_target = 'expected_folder'; max_recovery_attempts = 1 })

$outside = New-Workflow 'negative-outside-root' 'explorer_delete_file' 'C:\Windows\Temp\dv67_outside.txt' -ExpectedFolder 'C:\Windows\Temp' -ExpectedFilename 'dv67_outside.txt' -Risk 'DESTRUCTIVE' -ConfirmationRequired $true -ConfirmationToken 'DV67_TEST_DELETE_CONFIRM' -VerifyType 'file_deleted'
$results += Compile-RejectCase 'negative_scope_violation' $outside 'STOP_EXPLORER_SCOPE_VIOLATION'
$results += Run-WorkflowCase 'negative_target_missing' (New-Workflow 'negative-target-missing' 'explorer_open_file' (Join-Path $Fixture 'missing_target.txt') -ExpectedFilename 'missing_target.txt' -Risk 'READ_ONLY' -VerifyType 'file_opened') @(1) 'BLOCKED' 'FAIL_TARGET_NOT_FOUND'
$results += Run-WorkflowCase 'negative_ambiguous_target' (New-Workflow 'negative-ambiguous-target' 'explorer_open_file' (Join-Path $Fixture 'ambiguous_target_a.txt') -ExpectedFilename 'ambiguous_target' -Risk 'READ_ONLY' -VerifyType 'file_opened') @(1) 'BLOCKED' 'STOP_TARGET_NOT_UNIQUE'
$WrongNoRecoveryTitle = 'explorer_wrong_folder_no_recovery_' + ([guid]::NewGuid().ToString('N').Substring(0, 8))
$WrongNoRecoveryFolder = Join-Path 'D:\testrepo\testwindow' $WrongNoRecoveryTitle
New-Item -ItemType Directory -Force -Path $WrongNoRecoveryFolder | Out-Null
Start-Process explorer.exe -ArgumentList $WrongNoRecoveryFolder | Out-Null
Start-Sleep -Seconds 1
Invoke-WinAgent @('focus', '--title', $WrongNoRecoveryTitle) | Out-Null
Start-Sleep -Milliseconds 300
$results += Run-WorkflowCase 'negative_wrong_folder_without_recovery' (New-Workflow 'negative-wrong-folder-no-recovery' 'explorer_open_file' (Join-Path $Fixture 'open_file_target.txt') -ExpectedFilename 'open_file_target.txt' -Risk 'READ_ONLY' -VerifyType 'file_opened' -RecoveryPolicy @{ recovery_allowed = $false; recovery_scope = 'explorer_allowed_root'; recovery_target = 'expected_folder' }) @(1) 'BLOCKED' 'STOP_WRONG_CONTEXT'
$results += Run-WorkflowCase 'negative_context_menu_item_missing' (New-Workflow 'negative-context-menu-item-missing' 'explorer_context_menu_action' (Join-Path $Fixture 'open_file_target.txt') -Target (Join-Path $Fixture 'unused_context_target.txt') -ExpectedFilename 'unused_context_target.txt' -Risk 'REVERSIBLE_DRAFT' -VerifyType 'context_menu_action_result' -ContextMenuAction 'definitely_missing_menu_item') @(1) 'BLOCKED' 'STOP_CONTEXT_MENU_NOT_FOUND'
$results += Run-WorkflowCase 'negative_stale_locator_force_reobserve' (New-Workflow 'negative-stale-locator' 'explorer_open_file' (Join-Path $Fixture 'rename_source.txt') -ExpectedFilename 'rename_source.txt' -Risk 'READ_ONLY' -VerifyType 'file_opened') @(1) 'BLOCKED' 'FAIL_TARGET_NOT_FOUND'
$results += Run-WorkflowCase 'negative_move_destination_missing' (New-Workflow 'negative-move-destination-missing' 'explorer_move_file' (Join-Path $Fixture 'open_file_target.txt') -Destination (Join-Path $Fixture 'missing_dest\open_file_target.txt') -ExpectedFilename 'open_file_target.txt' -Risk 'REVERSIBLE_DRAFT' -VerifyType 'file_moved') @(1) 'BLOCKED' 'FAIL_DESTINATION_NOT_FOUND'
$invalid = New-Workflow 'negative-invalid-schema' 'explorer_browser_form' $Fixture -ExpectedFilename 'open_path_marker.txt' -Risk 'READ_ONLY' -VerifyType 'folder_opened'
$results += Compile-RejectCase 'negative_invalid_schema' $invalid 'COMPILE_SCHEMA_INVALID'
$missingHint = New-Workflow 'negative-missing-verification-hint' 'explorer_open_path' $Fixture -ExpectedFilename 'open_path_marker.txt' -Risk 'READ_ONLY' -IncludeVerificationHint $false
$results += Compile-RejectCase 'negative_missing_verification_hint' $missingHint 'COMPILE_MISSING_VERIFICATION_HINT'
$missingRoot = New-Workflow 'negative-missing-allowed-root' 'explorer_open_path' $Fixture -ExpectedFilename 'open_path_marker.txt' -Risk 'READ_ONLY' -IncludeAllowedRoot $false
$results += Compile-RejectCase 'negative_missing_allowed_root' $missingRoot 'COMPILE_ALLOWED_ROOT_MISSING'

$baseFake = @{
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
$fakePs = $baseFake.Clone(); $fakePs.powershell_file_action_used = $true
$fakeApi = $baseFake.Clone(); $fakeApi.direct_file_api_workflow_action_used = $true
$fakeRunner = $baseFake.Clone(); $fakeRunner.runner_only_workflow_logic = $true
$fakeSession = $baseFake.Clone(); $fakeSession.runtime_session_used = $false
$fakeValidator = $baseFake.Clone(); $fakeValidator.step_contract_validator_used = $false
$fakeGuard = $baseFake.Clone(); $fakeGuard.runtime_context_guard_used = $false
$results += Verify-RejectCase 'negative_powershell_fake_execution' $fakePs 'BLOCKED_FAKE_FILESYSTEM_EXECUTION'
$results += Verify-RejectCase 'negative_direct_file_api_execution' $fakeApi 'BLOCKED_DIRECT_FILE_API_WORKFLOW'
$results += Verify-RejectCase 'negative_runner_only_logic' $fakeRunner 'BLOCKED_RUNNER_ONLY_EXPLORER_WORKFLOW'
$results += Verify-RejectCase 'negative_runtime_session_missing' $fakeSession 'BLOCKED_RUNTIME_SESSION_NOT_USED'
$results += Verify-RejectCase 'negative_step_contract_validator_missing' $fakeValidator 'VERIFY_STEP_CONTRACT_VALIDATOR_NOT_USED'
$results += Verify-RejectCase 'negative_runtime_context_guard_missing' $fakeGuard 'BLOCKED_RUNTIME_GUARD_BYPASSED'

$rawPath = Join-Path $OutDir 'runner_results.json'
$results | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $rawPath -Encoding UTF8

$positive = $results | Where-Object { $_.category -eq 'positive' }
$negative = $results | Where-Object { $_.category -eq 'negative' }
$positiveReport = Join-Path $ArtifactRoot 'positive_explorer_cases_report.md'
$negativeReport = Join-Path $ArtifactRoot 'negative_explorer_cases_report.md'
@(
    '# Positive Explorer Cases Report'
    ''
    "- Status: $(if (($positive | Where-Object { -not $_.ok }).Count -eq 0) { 'PASS' } else { 'FAIL' })"
    "- Cases: $($positive.Count)"
    ''
    ($positive | ForEach-Object { "- $($_.name): $(if ($_.ok) { 'PASS' } else { 'FAIL' }) final_status=$($_.final_status) error=$($_.error_code)" })
) | Set-Content -LiteralPath $positiveReport -Encoding UTF8
@(
    '# Negative Explorer Cases Report'
    ''
    "- Status: $(if (($negative | Where-Object { -not $_.ok }).Count -eq 0) { 'PASS' } else { 'FAIL' })"
    "- Cases: $($negative.Count)"
    ''
    ($negative | ForEach-Object { "- $($_.name): $(if ($_.ok) { 'PASS' } else { 'FAIL' }) expected=$($_.expected_error) actual=$($_.error_code)" })
) | Set-Content -LiteralPath $negativeReport -Encoding UTF8

$cleanupOk = $true
$cleanupError = ''
try {
    Get-ChildItem -LiteralPath $Fixture -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction Stop
} catch {
    $cleanupOk = $false
    $cleanupError = $_.Exception.Message
}

$cleanupReport = Join-Path $OutDir 'fixture_cleanup_report.md'
@(
    '# Explorer Fixture Cleanup Report'
    ''
    "- Fixture: $Fixture"
    "- Cleanup attempted: true"
    "- Cleanup ok: $cleanupOk"
    "- Cleanup error: $cleanupError"
) | Set-Content -LiteralPath $cleanupReport -Encoding UTF8

$failed = $results | Where-Object { -not $_.ok }
if ($failed.Count -gt 0) {
    Write-Host "v6.7.0 Explorer workflow runner FAIL. Results: $rawPath"
    $failed | Format-Table name, expected_error, error_code, final_status -AutoSize | Out-String | Write-Host
    exit 1
}

Write-Host "v6.7.0 Explorer workflow runner PASS. Results: $rawPath"
