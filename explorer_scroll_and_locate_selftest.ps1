param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.7.0_explorer_agent_workflows_rerun'
$OutDir = Join-Path $ArtifactRoot 'selftest\scroll_and_locate'
$Fixture = 'D:\testrepo\testwindow\explorer_workflow_v6_7_scroll_selftest'
$LongList = Join-Path $Fixture 'long_list'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
New-Item -ItemType Directory -Force -Path $LongList | Out-Null

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "winagent.exe not found. Run build.ps1 before explorer_scroll_and_locate_selftest.ps1."
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
New-Item -ItemType Directory -Force -Path $LongList | Out-Null
1..120 | ForEach-Object {
    $name = if ($_ -eq 80) { 'item_080_target_visible_after_scroll.txt' } else { ('item_{0:D3}.txt' -f $_) }
    ('long list item {0}' -f $_) | Set-Content -LiteralPath (Join-Path $LongList $name) -Encoding UTF8
}

$Target = Join-Path $LongList 'item_080_target_visible_after_scroll.txt'
$workflowPath = Join-Path $OutDir 'scroll_and_locate.workflow.json'
$resultPath = Join-Path $OutDir 'scroll_and_locate.result.json'
$verificationPath = Join-Path $OutDir 'scroll_and_locate.verification.json'
$workflow = @{
    workflow_id = 'scroll-and-locate-selftest'
    task_id = 'scroll-and-locate-selftest-task'
    workflow_type = 'explorer_scroll_and_locate'
    source_path = $LongList
    target_path = $Target
    expected_folder = $LongList
    expected_filename = 'item_080_target_visible_after_scroll.txt'
    risk_level = 'LOW_RISK'
    allowed_root = 'D:\testrepo'
    expected_context = @{
        expected_process_pattern = 'explorer.exe'
        expected_title_pattern = 'long_list'
        required_markers = @('long_list')
        foreground_required = $true
        window_binding_required = $true
    }
    verification_hint = @{ verify_type = 'scroll_target_found'; expected_marker = 'item_080_target_visible_after_scroll.txt' }
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
    'list_area_located',
    'list_area_clicked',
    'list_area_focus_verified',
    'target_exists_in_fixture',
    'scroll_used',
    'scroll_progress_detected',
    'scroll_position_changed',
    'target_found',
    'target_clicked_or_verified',
    'runtime_context_guard_each_iteration'
)
foreach ($field in $requiredTrue) {
    if ($result.$field -ne $true) {
        throw "Scroll selftest missing true field: $field"
    }
}
if ([int]$result.scroll_iteration_count -lt 1) { throw 'scroll_iteration_count was less than 1.' }
if ($result.stale_rect_used -ne $false) { throw 'stale_rect_used was not false.' }
if ($result.power_shell_file_operation_used -ne $false) { throw 'PowerShell file operation flag was not false.' }
if ($result.direct_file_api_used -ne $false) { throw 'Direct file API flag was not false.' }

$report = Join-Path $OutDir 'explorer_scroll_and_locate_selftest_report.md'
@(
    '# Explorer Scroll And Locate Selftest'
    ''
    '- Status: PASS'
    "- Result: $resultPath"
    "- Verification: $verificationPath"
    "- scroll_iteration_count: $($result.scroll_iteration_count)"
    "- wheel_event_count: $($result.wheel_event_count)"
    "- visible_first_item_before: $($result.visible_first_item_before)"
    "- visible_first_item_after: $($result.visible_first_item_after)"
    "- visible_last_item_after: $($result.visible_last_item_after)"
) | Set-Content -LiteralPath $report -Encoding UTF8

Write-Host "Explorer scroll and locate selftest PASS. Report: $report"
