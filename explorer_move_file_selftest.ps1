param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.7.0_explorer_agent_workflows_rerun'
$OutDir = Join-Path $ArtifactRoot 'selftest\move_file'
$Fixture = 'D:\testrepo\testwindow\explorer_workflow_v6_7_move_selftest'
$DestDir = Join-Path $Fixture 'move_dest'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
New-Item -ItemType Directory -Force -Path $DestDir | Out-Null

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "winagent.exe not found. Run build.ps1 before explorer_move_file_selftest.ps1."
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
    if ($AllowedExitCodes -notcontains $p.ExitCode) {
        $err = if (Test-Path -LiteralPath $stderr) { Get-Content -Raw -LiteralPath $stderr } else { '' }
        throw "winagent $($CommandArgs -join ' ') exit $($p.ExitCode). stdout=$text stderr=$err"
    }
    return @{ ExitCode = $p.ExitCode; Stdout = $text; StdoutPath = $stdout; StderrPath = $stderr }
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
        Start-Sleep -Milliseconds 500
    } catch {
    }
}

Close-FixtureExplorerWindows
if (Test-Path -LiteralPath $Fixture) {
    Get-ChildItem -LiteralPath $Fixture -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
$Source = Join-Path $Fixture 'move_source.txt'
$Destination = Join-Path $DestDir 'move_source.txt'
'move source' | Set-Content -LiteralPath $Source -Encoding UTF8

$workflowPath = Join-Path $OutDir 'move_file.workflow.json'
$resultPath = Join-Path $OutDir 'move_file.result.json'
$verificationPath = Join-Path $OutDir 'move_file.verification.json'
$workflow = @{
    workflow_id = 'move-file-selftest'
    task_id = 'move-file-selftest-task'
    workflow_type = 'explorer_move_file'
    source_path = $Source
    destination_path = $Destination
    expected_folder = $Fixture
    expected_filename = 'move_source.txt'
    risk_level = 'REVERSIBLE_DRAFT'
    allowed_root = 'D:\testrepo'
    expected_context = @{
        expected_process_pattern = 'explorer.exe'
        expected_title_pattern = 'explorer_workflow_v6_7_move_selftest'
        required_markers = @('move_source.txt')
        foreground_required = $true
        window_binding_required = $true
    }
    verification_hint = @{ verify_type = 'file_moved'; expected_marker = 'move_source.txt' }
    stop_policy = @{
        stop_on_wrong_context = $true
        stop_on_target_not_unique = $true
        stop_on_target_stale = $true
        stop_on_unverified_result = $true
        stop_on_runtime_guard_failure = $true
    }
}
Write-JsonFile $workflowPath $workflow

Invoke-WinAgent @('run-explorer-workflow', '--input', $workflowPath, '--mode', 'execute-local-safe', '--output', $resultPath, '--evidence-dir', (Join-Path $OutDir 'evidence')) | Out-Null
Invoke-WinAgent @('verify-explorer-workflow', '--result', $resultPath, '--output', $verificationPath) | Out-Null
$result = Get-Content -Raw -LiteralPath $resultPath | ConvertFrom-Json

$requiredTrue = @(
    'source_exists_before',
    'source_selected_by_mouse',
    'source_selection_verified',
    'cut_attempted',
    'cut_sent',
    'destination_folder_opened',
    'destination_folder_focused',
    'paste_attempted',
    'paste_sent',
    'move_action_attempted',
    'move_action_executed',
    'source_absent_after',
    'destination_exists_after',
    'move_result_verified',
    'step_level_verification_complete',
    'runtime_session_used',
    'runtime_context_guard_used',
    'step_contract_validated'
)
foreach ($field in $requiredTrue) {
    if ($result.$field -ne $true) {
        throw "Move file selftest missing true field: $field"
    }
}
if ($result.power_shell_file_operation_used -ne $false) { throw 'PowerShell file operation flag was not false.' }
if ($result.direct_file_api_used -ne $false) { throw 'Direct file API flag was not false.' }

$report = Join-Path $OutDir 'explorer_move_file_selftest_report.md'
@(
    '# Explorer Move File Selftest'
    ''
    '- Status: PASS'
    "- Result: $resultPath"
    "- Verification: $verificationPath"
    "- cut_method: $($result.cut_method)"
    "- paste_method: $($result.paste_method)"
    "- fallback_used: $($result.fallback_used)"
    "- move_verification_retry_count: $($result.move_verification_retry_count)"
) | Set-Content -LiteralPath $report -Encoding UTF8

Write-Host "Explorer move file selftest PASS. Report: $report"
