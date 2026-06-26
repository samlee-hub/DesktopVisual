param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.7.0_explorer_agent_workflows\selftest\compiler'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "winagent.exe not found. Run build.ps1 before explorer_workflow_compiler_selftest.ps1."
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

$baseContext = @{
    expected_process_pattern = 'explorer.exe'
    expected_title_pattern = 'explorer_workflow_v6_7'
    required_markers = @('explorer_workflow_v6_7')
    wrong_page_patterns = @('wrong_folder')
    active_protection_patterns = @('captcha')
    credential_required_patterns = @('password')
    foreground_required = $true
    window_binding_required = $true
}
$baseStop = @{
    stop_on_wrong_context = $true
    stop_on_wrong_field = $true
    stop_on_target_stale = $true
    stop_on_target_not_unique = $true
    stop_on_active_protection = $true
    stop_on_credential_required = $true
    stop_on_unverified_result = $true
    stop_on_runtime_guard_failure = $true
}

$cases = @(
    @{ type = 'explorer_open_path'; source = 'D:\testrepo\testwindow\explorer_workflow_v6_7'; target = ''; dest = ''; risk = 'READ_ONLY'; verify = 'folder_opened'; confirm = $false },
    @{ type = 'explorer_open_file'; source = 'D:\testrepo\testwindow\explorer_workflow_v6_7\open_file_target.txt'; target = ''; dest = ''; risk = 'READ_ONLY'; verify = 'file_opened'; confirm = $false },
    @{ type = 'explorer_rename_file'; source = 'D:\testrepo\testwindow\explorer_workflow_v6_7\rename_source.txt'; target = 'D:\testrepo\testwindow\explorer_workflow_v6_7\renamed_expected.txt'; dest = ''; risk = 'REVERSIBLE_DRAFT'; verify = 'file_renamed'; confirm = $false },
    @{ type = 'explorer_move_file'; source = 'D:\testrepo\testwindow\explorer_workflow_v6_7\move_source.txt'; target = ''; dest = 'D:\testrepo\testwindow\explorer_workflow_v6_7\move_dest\move_source.txt'; risk = 'REVERSIBLE_DRAFT'; verify = 'file_moved'; confirm = $false },
    @{ type = 'explorer_delete_file'; source = 'D:\testrepo\testwindow\explorer_workflow_v6_7\delete_target.txt'; target = ''; dest = ''; risk = 'DESTRUCTIVE'; verify = 'file_deleted'; confirm = $true },
    @{ type = 'explorer_context_menu_action'; source = 'D:\testrepo\testwindow\explorer_workflow_v6_7\context_menu_source.txt'; target = 'D:\testrepo\testwindow\explorer_workflow_v6_7\context_menu_renamed.txt'; dest = ''; risk = 'REVERSIBLE_DRAFT'; verify = 'context_menu_action_result'; confirm = $false },
    @{ type = 'explorer_scroll_and_locate'; source = 'D:\testrepo\testwindow\explorer_workflow_v6_7\long_list'; target = 'D:\testrepo\testwindow\explorer_workflow_v6_7\long_list\item_080_target_visible_after_scroll.txt'; dest = ''; risk = 'LOW_RISK'; verify = 'scroll_target_found'; confirm = $false }
)

foreach ($case in $cases) {
    $workflowPath = Join-Path $OutDir "$($case.type).workflow.json"
    $contractPath = Join-Path $OutDir "$($case.type).step_contract.json"
    $validationPath = Join-Path $OutDir "$($case.type).validation.json"
    $sessionStepsPath = Join-Path $OutDir "$($case.type).session_steps.json"
    Write-JsonFile $workflowPath @{
        workflow_id = "compiler-$($case.type)"
        task_id = 'compiler-task'
        workflow_type = $case.type
        source_path = $case.source
        target_path = $case.target
        destination_path = $case.dest
        expected_folder = 'D:\testrepo\testwindow\explorer_workflow_v6_7'
        expected_filename = if ($case.type -eq 'explorer_rename_file') { 'renamed_expected.txt' } elseif ($case.type -eq 'explorer_context_menu_action') { 'context_menu_renamed.txt' } else { Split-Path -Leaf $case.source }
        risk_level = $case.risk
        confirmation_required = $case.confirm
        confirmation_token = if ($case.confirm) { 'DV67_TEST_DELETE_CONFIRM' } else { '' }
        allowed_root = 'D:\testrepo'
        expected_context = $baseContext
        verification_hint = @{ verify_type = $case.verify; expected_marker = $case.verify }
        stop_policy = $baseStop
    }
    Invoke-WinAgent @('compile-explorer-workflow', '--input', $workflowPath, '--output', $contractPath) | Out-Null
    Invoke-WinAgent @('step-contract-validate', '--input', $contractPath, '--result', $validationPath) | Out-Null
    Invoke-WinAgent @('step-contract-dry-run', '--input', $contractPath, '--session-steps-output', $sessionStepsPath) | Out-Null
    $contract = Get-Content -Raw -LiteralPath $contractPath | ConvertFrom-Json
    if ($contract.contracts[0].runtime_action -ne $case.type) { throw "runtime_action mismatch for $($case.type)" }
    if ($contract.contracts[0].allowed_root -ne 'D:\testrepo') { throw "allowed_root missing for $($case.type)" }
    if ($contract.contracts[0].session_policy.session_required -ne $true) { throw "session_policy missing for $($case.type)" }
}

$planDraft = Join-Path $OutDir 'plan_compiler_explorer_rename.plan.json'
$planContract = Join-Path $OutDir 'plan_compiler_explorer_rename.step_contract.json'
$planDiagnostics = Join-Path $OutDir 'plan_compiler_explorer_rename.diagnostics.json'
Write-JsonFile $planDraft @{
    plan_id = 'compiler-plan-explorer'
    task_id = 'compiler-task-explorer'
    intent = 'explorer_rename_file'
    risk_summary = 'REVERSIBLE_DRAFT'
    allowed_root = 'D:\testrepo'
    expected_context_summary = $baseContext
    steps = @(@{
        draft_step_id = 'rename-step'
        proposed_action = 'explorer_rename_file'
        target_description = 'D:\testrepo\testwindow\explorer_workflow_v6_7\rename_source.txt'
        input_text = 'renamed_expected.txt'
        risk_hint = 'REVERSIBLE_DRAFT'
        verification_hint = 'file renamed'
    })
}
Invoke-WinAgent @('plan-compile', '--input', $planDraft, '--output', $planContract, '--diagnostics', $planDiagnostics) | Out-Null
$plan = Get-Content -Raw -LiteralPath $planContract | ConvertFrom-Json
if ($plan.contracts[0].runtime_action -ne 'explorer_rename_file') { throw 'PlanCompiler did not emit explorer_rename_file.' }
if ($plan.contracts[0].allowed_root -ne 'D:\testrepo') { throw 'PlanCompiler did not emit allowed_root.' }

$report = Join-Path $OutDir 'explorer_workflow_compiler_selftest_report.md'
@(
    '# Explorer Workflow Compiler Selftest'
    ''
    '- Status: PASS'
    '- compile-explorer-workflow cases: 7/7 PASS'
    '- step-contract-validate cases: 7/7 PASS'
    '- step-contract-dry-run RuntimeSession-compatible cases: 7/7 PASS'
    '- PlanCompiler Explorer action extension: PASS'
) | Set-Content -LiteralPath $report -Encoding UTF8

Write-Host "Explorer workflow compiler selftest PASS. Report: $report"
