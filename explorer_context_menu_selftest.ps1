param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.7.0_explorer_agent_workflows\selftest\context_menu'
$Fixture = 'D:\testrepo\testwindow\explorer_workflow_v6_7'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
New-Item -ItemType Directory -Force -Path $Fixture | Out-Null

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "winagent.exe not found. Run build.ps1 before explorer_context_menu_selftest.ps1."
}

$Source = Join-Path $Fixture 'context_menu_source.txt'
$Target = Join-Path $Fixture 'context_menu_renamed.txt'
Remove-Item -LiteralPath $Source,$Target -Force -ErrorAction SilentlyContinue
'context menu rename fixture' | Set-Content -LiteralPath $Source -Encoding UTF8

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

$workflow = Join-Path $OutDir 'context_menu_rename.workflow.json'
$result = Join-Path $OutDir 'context_menu_rename.result.json'
$verification = Join-Path $OutDir 'context_menu_rename.verification.json'
Write-JsonFile $workflow @{
    workflow_id = 'context-menu-selftest'
    task_id = 'context-menu-task'
    workflow_type = 'explorer_context_menu_action'
    source_path = $Source
    target_path = $Target
    expected_folder = $Fixture
    expected_filename = 'context_menu_renamed.txt'
    context_menu_action = 'rename'
    risk_level = 'REVERSIBLE_DRAFT'
    allowed_root = 'D:\testrepo'
    expected_context = @{ expected_process_pattern = 'explorer.exe'; expected_title_pattern = 'explorer_workflow_v6_7'; required_markers = @('explorer_workflow_v6_7') }
    verification_hint = @{ verify_type = 'context_menu_action_result'; expected_marker = 'context_menu_renamed.txt' }
    stop_policy = @{ stop_on_wrong_context = $true; stop_on_target_not_unique = $true; stop_on_unverified_result = $true; stop_on_context_menu_not_found = $true }
}

Invoke-WinAgent @('run-explorer-workflow', '--input', $workflow, '--mode', 'execute-local-safe', '--output', $result, '--evidence-dir', (Join-Path $OutDir 'evidence')) | Out-Null
Invoke-WinAgent @('verify-explorer-workflow', '--result', $result, '--output', $verification) | Out-Null
$data = Get-Content -Raw -LiteralPath $result | ConvertFrom-Json
if ($data.right_click_sent -ne $true -or $data.context_menu_visible -ne $true -or $data.menu_item_located -ne $true -or $data.menu_item_clicked -ne $true -or $data.result_verified -ne $true) {
    throw 'Context menu selftest result did not satisfy required evidence fields.'
}

$report = Join-Path $OutDir 'explorer_context_menu_selftest_report.md'
@(
    '# Explorer Context Menu Selftest'
    ''
    '- Status: PASS'
    '- right_click_sent: PASS'
    '- context_menu_visible: PASS'
    '- menu_item_located: PASS'
    '- menu_item_clicked: PASS'
    '- result_verified: PASS'
) | Set-Content -LiteralPath $report -Encoding UTF8

Write-Host "Explorer context menu selftest PASS. Report: $report"
