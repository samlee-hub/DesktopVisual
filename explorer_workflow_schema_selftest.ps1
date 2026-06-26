param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.7.0_explorer_agent_workflows\selftest\schema'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "winagent.exe not found. Run build.ps1 before explorer_workflow_schema_selftest.ps1."
}

function Write-JsonFile([string]$Path, [hashtable]$Object) {
    $Object | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-WinAgent([string[]]$CommandArgs, [int[]]$AllowedExitCodes = @(0)) {
    $stdout = Join-Path $OutDir (([guid]::NewGuid().ToString('N')) + '.stdout.json')
    $stderr = Join-Path $OutDir (([guid]::NewGuid().ToString('N')) + '.stderr.txt')
    $p = Start-Process -FilePath $WinAgent -ArgumentList $CommandArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $text = if (Test-Path -LiteralPath $stdout) { Get-Content -Raw -LiteralPath $stdout } else { '' }
    if ($AllowedExitCodes -notcontains $p.ExitCode) {
        $err = if (Test-Path -LiteralPath $stderr) { Get-Content -Raw -LiteralPath $stderr } else { '' }
        throw "winagent $($CommandArgs -join ' ') exit $($p.ExitCode). stdout=$text stderr=$err"
    }
    return @{ ExitCode = $p.ExitCode; Stdout = $text; StdoutPath = $stdout; StderrPath = $stderr }
}

$validWorkflow = Join-Path $OutDir 'valid_open_path.workflow.json'
$validContract = Join-Path $OutDir 'valid_open_path.step_contract.json'
Write-JsonFile $validWorkflow @{
    workflow_id = 'schema-open-path'
    task_id = 'schema-task'
    workflow_type = 'explorer_open_path'
    source_path = 'D:\testrepo\testwindow\explorer_workflow_v6_7'
    expected_folder = 'D:\testrepo\testwindow\explorer_workflow_v6_7'
    expected_filename = 'open_path_marker.txt'
    risk_level = 'READ_ONLY'
    allowed_root = 'D:\testrepo'
    expected_context = @{ expected_process_pattern = 'explorer.exe'; expected_title_pattern = 'explorer_workflow_v6_7'; required_markers = @('explorer_workflow_v6_7') }
    verification_hint = @{ verify_type = 'folder_opened'; expected_marker = 'open_path_marker.txt' }
    stop_policy = @{ stop_on_wrong_context = $true; stop_on_target_not_unique = $true; stop_on_unverified_result = $true }
}

$valid = Invoke-WinAgent @('compile-explorer-workflow', '--input', $validWorkflow, '--output', $validContract)
if (-not (Test-Path -LiteralPath $validContract)) {
    throw 'compile-explorer-workflow did not write the StepContract.'
}
$contractText = Get-Content -Raw -LiteralPath $validContract
$contract = $contractText | ConvertFrom-Json
if ($contract.compile_ok -ne $true) { throw 'Expected compile_ok=true.' }
if ($contract.contracts[0].allowed_root -ne 'D:\testrepo') { throw 'Expected allowed_root=D:\testrepo.' }
if ($contract.contracts[0].runtime_action -ne 'explorer_open_path') { throw 'Expected explorer_open_path runtime action.' }

$deleteWorkflow = Join-Path $OutDir 'delete_without_confirmation.workflow.json'
Write-JsonFile $deleteWorkflow @{
    workflow_id = 'schema-delete'
    task_id = 'schema-task'
    workflow_type = 'explorer_delete_file'
    source_path = 'D:\testrepo\testwindow\explorer_workflow_v6_7\delete_target.txt'
    expected_folder = 'D:\testrepo\testwindow\explorer_workflow_v6_7'
    expected_filename = 'delete_target.txt'
    risk_level = 'DESTRUCTIVE'
    confirmation_required = $false
    allowed_root = 'D:\testrepo'
    expected_context = @{ expected_process_pattern = 'explorer.exe'; expected_title_pattern = 'explorer_workflow_v6_7'; required_markers = @('delete_target.txt') }
    verification_hint = @{ verify_type = 'file_deleted'; expected_marker = 'delete_target.txt' }
    stop_policy = @{ stop_on_wrong_context = $true; stop_on_target_not_unique = $true; stop_on_unverified_result = $true }
}
$delete = Invoke-WinAgent @('compile-explorer-workflow', '--input', $deleteWorkflow, '--output', (Join-Path $OutDir 'delete.step_contract.json')) @(1)
if ($delete.Stdout -notmatch 'COMPILE_CONFIRMATION_REQUIRED|VALIDATION_REAL_COMMIT_POLICY_MISSING') {
    throw 'delete without confirmation was not rejected by schema/compiler.'
}

$missingHintWorkflow = Join-Path $OutDir 'missing_verification.workflow.json'
Write-JsonFile $missingHintWorkflow @{
    workflow_id = 'schema-missing-verification'
    task_id = 'schema-task'
    workflow_type = 'explorer_open_file'
    source_path = 'D:\testrepo\testwindow\explorer_workflow_v6_7\open_file_target.txt'
    expected_folder = 'D:\testrepo\testwindow\explorer_workflow_v6_7'
    expected_filename = 'open_file_target.txt'
    risk_level = 'READ_ONLY'
    allowed_root = 'D:\testrepo'
    expected_context = @{ expected_process_pattern = 'explorer.exe'; expected_title_pattern = 'explorer_workflow_v6_7'; required_markers = @('open_file_target.txt') }
    stop_policy = @{ stop_on_wrong_context = $true; stop_on_target_not_unique = $true; stop_on_unverified_result = $true }
}
$missing = Invoke-WinAgent @('compile-explorer-workflow', '--input', $missingHintWorkflow, '--output', (Join-Path $OutDir 'missing.step_contract.json')) @(1)
if ($missing.Stdout -notmatch 'COMPILE_MISSING_VERIFICATION_HINT|VALIDATION_VERIFICATION_HINT_INCOMPLETE') {
    throw 'missing verification_hint was not rejected.'
}

$missingRootWorkflow = Join-Path $OutDir 'missing_allowed_root.workflow.json'
Write-JsonFile $missingRootWorkflow @{
    workflow_id = 'schema-missing-allowed-root'
    task_id = 'schema-task'
    workflow_type = 'explorer_open_path'
    source_path = 'D:\testrepo\testwindow\explorer_workflow_v6_7'
    expected_folder = 'D:\testrepo\testwindow\explorer_workflow_v6_7'
    expected_filename = 'open_path_marker.txt'
    risk_level = 'READ_ONLY'
    expected_context = @{ expected_process_pattern = 'explorer.exe'; expected_title_pattern = 'explorer_workflow_v6_7'; required_markers = @('explorer_workflow_v6_7') }
    verification_hint = @{ verify_type = 'folder_opened'; expected_marker = 'open_path_marker.txt' }
    stop_policy = @{ stop_on_wrong_context = $true; stop_on_target_not_unique = $true; stop_on_unverified_result = $true }
}
$missingRoot = Invoke-WinAgent @('compile-explorer-workflow', '--input', $missingRootWorkflow, '--output', (Join-Path $OutDir 'missing_allowed_root.step_contract.json')) @(1)
if ($missingRoot.Stdout -notmatch 'COMPILE_ALLOWED_ROOT_MISSING') {
    throw 'missing allowed_root was not rejected.'
}

$report = Join-Path $OutDir 'explorer_workflow_schema_selftest_report.md'
@(
    '# Explorer Workflow Schema Selftest'
    ''
    '- Status: PASS'
    '- compile-explorer-workflow valid schema: PASS'
    '- explicit allowed_root D:\testrepo: PASS'
    '- delete without confirmation rejected: PASS'
    '- missing verification_hint rejected: PASS'
    '- missing allowed_root rejected: PASS'
) | Set-Content -LiteralPath $report -Encoding UTF8

Write-Host "Explorer workflow schema selftest PASS. Report: $report"
