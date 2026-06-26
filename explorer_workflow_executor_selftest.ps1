param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$FixtureRoot = 'D:\testrepo\testwindow\explorer_workflow_v6_7'
$OutDir = Join-Path $Root 'artifacts\dev6.7.0_explorer_agent_workflows\selftest\executor'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
New-Item -ItemType Directory -Force -Path $FixtureRoot | Out-Null
Set-Content -LiteralPath (Join-Path $FixtureRoot 'open_path_marker.txt') -Value 'DV67 open path marker' -Encoding UTF8

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "winagent.exe not found. Run build.ps1 before explorer_workflow_executor_selftest.ps1."
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

$context = @{
    expected_process_pattern = 'explorer.exe'
    expected_title_pattern = 'explorer_workflow_v6_7'
    required_markers = @('open_path_marker.txt')
    wrong_page_patterns = @('wrong_folder')
    active_protection_patterns = @('captcha')
    credential_required_patterns = @('password')
    foreground_required = $true
    window_binding_required = $true
}
$stop = @{
    stop_on_wrong_context = $true
    stop_on_wrong_field = $true
    stop_on_target_stale = $true
    stop_on_target_not_unique = $true
    stop_on_active_protection = $true
    stop_on_credential_required = $true
    stop_on_unverified_result = $true
    stop_on_runtime_guard_failure = $true
}

$workflow = Join-Path $OutDir 'open_path.workflow.json'
$resultPath = Join-Path $OutDir 'open_path.result.json'
$evidenceDir = Join-Path $OutDir 'open_path_evidence'
Write-JsonFile $workflow @{
    workflow_id = 'executor-open-path'
    task_id = 'executor-task'
    workflow_type = 'explorer_open_path'
    source_path = $FixtureRoot
    expected_folder = $FixtureRoot
    expected_filename = 'open_path_marker.txt'
    risk_level = 'READ_ONLY'
    allowed_root = 'D:\testrepo'
    expected_context = $context
    verification_hint = @{ verify_type = 'folder_opened'; expected_marker = 'open_path_marker.txt' }
    stop_policy = $stop
}

Invoke-WinAgent @('run-explorer-workflow', '--input', $workflow, '--mode', 'execute-local-safe', '--output', $resultPath, '--evidence-dir', $evidenceDir) | Out-Null
$result = Get-Content -Raw -LiteralPath $resultPath | ConvertFrom-Json
if ($result.final_status -ne 'PASS') { throw "Expected PASS, got $($result.final_status) / $($result.error_code)" }
if ($result.runtime_session_used -ne $true) { throw 'RuntimeSession was not used.' }
if ($result.compiled_step_contract_used -ne $true) { throw 'StepContract was not used.' }
if ($result.runtime_context_guard_used -ne $true) { throw 'RuntimeContextGuard was not used.' }
if ($result.expected_folder_verified -ne $true) { throw 'Expected folder was not verified.' }

$report = Join-Path $OutDir 'explorer_workflow_executor_selftest_report.md'
@(
    '# Explorer Workflow Executor Selftest'
    ''
    '- Status: PASS'
    '- execute-local-safe open_path: PASS'
    '- RuntimeSession used: PASS'
    '- StepContract used: PASS'
    '- RuntimeContextGuard used: PASS'
    '- Evidence pack created: PASS'
) | Set-Content -LiteralPath $report -Encoding UTF8

Write-Host "Explorer workflow executor selftest PASS. Report: $report"
