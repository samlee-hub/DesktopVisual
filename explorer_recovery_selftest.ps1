param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.7.0_explorer_agent_workflows\selftest\recovery'
$Fixture = 'D:\testrepo\testwindow\explorer_workflow_v6_7'
$WrongTitle = 'explorer_wrong_folder_v6_7_' + ([guid]::NewGuid().ToString('N').Substring(0, 8))
$WrongFolder = Join-Path 'D:\testrepo\testwindow' $WrongTitle
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
New-Item -ItemType Directory -Force -Path $Fixture | Out-Null
New-Item -ItemType Directory -Force -Path $WrongFolder | Out-Null

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "winagent.exe not found. Run build.ps1 before explorer_recovery_selftest.ps1."
}

$Target = Join-Path $Fixture 'recovery_open_file_target.txt'
'recovery fixture' | Set-Content -LiteralPath $Target -Encoding UTF8
Start-Process explorer.exe -ArgumentList $WrongFolder | Out-Null
Start-Sleep -Seconds 1

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

Invoke-WinAgent @('focus', '--title', $WrongTitle) | Out-Null
Start-Sleep -Milliseconds 300

$workflow = Join-Path $OutDir 'wrong_folder_recovery.workflow.json'
$result = Join-Path $OutDir 'wrong_folder_recovery.result.json'
$verification = Join-Path $OutDir 'wrong_folder_recovery.verification.json'
Write-JsonFile $workflow @{
    workflow_id = 'recovery-selftest'
    task_id = 'recovery-task'
    workflow_type = 'explorer_open_file'
    source_path = $Target
    expected_folder = $Fixture
    expected_filename = 'recovery_open_file_target.txt'
    risk_level = 'READ_ONLY'
    allowed_root = 'D:\testrepo'
    expected_context = @{ expected_process_pattern = 'explorer.exe'; expected_title_pattern = 'explorer_workflow_v6_7'; required_markers = @('explorer_workflow_v6_7') }
    verification_hint = @{ verify_type = 'file_opened'; expected_marker = 'recovery_open_file_target.txt' }
    recovery_policy = @{ recovery_allowed = $true; recovery_scope = 'explorer_allowed_root'; recovery_target = 'expected_folder'; max_recovery_attempts = 1; resume_from_checkpoint_allowed = $true }
    stop_policy = @{ stop_on_wrong_context = $true; stop_on_target_not_unique = $true; stop_on_unverified_result = $true; stop_if_recovery_fails = $true }
}

Invoke-WinAgent @('run-explorer-workflow', '--input', $workflow, '--mode', 'execute-local-safe', '--output', $result, '--evidence-dir', (Join-Path $OutDir 'evidence')) | Out-Null
Invoke-WinAgent @('verify-explorer-workflow', '--result', $result, '--output', $verification) | Out-Null
$data = Get-Content -Raw -LiteralPath $result | ConvertFrom-Json
if ($data.wrong_folder_detected -ne $true -or $data.recovery_attempted -ne $true -or $data.recovery_success -ne $true -or $data.file_open_verified -ne $true) {
    throw 'Recovery selftest result did not satisfy wrong-folder recovery evidence fields.'
}

$report = Join-Path $OutDir 'explorer_recovery_selftest_report.md'
@(
    '# Explorer Recovery Selftest'
    ''
    '- Status: PASS'
    '- wrong_folder_detected: PASS'
    '- recovery_attempted: PASS'
    '- recovery_success: PASS'
    '- final_verification_ok: PASS'
) | Set-Content -LiteralPath $report -Encoding UTF8

Write-Host "Explorer recovery selftest PASS. Report: $report"
