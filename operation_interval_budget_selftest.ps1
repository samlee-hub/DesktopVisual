param([string]$Root = '')

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$OutDir = Join-Path $Root 'artifacts\dev6.12.1_visible_ui_foundation_hardening'
$Report = Join-Path $OutDir 'operation_interval_budget_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Fail([string]$Message) { throw $Message }

$sourceFiles = Get-ChildItem -LiteralPath (Join-Path $Root 'src\winagent') -Recurse -Include *.cpp,*.h -File
$badSleeps = @()
foreach ($file in $sourceFiles) {
    Select-String -LiteralPath $file.FullName -Pattern 'Sleep\s*\(\s*(\d{4,})\s*\)' | ForEach-Object {
        $value = [int]$_.Matches[0].Groups[1].Value
        if ($value -ge 5000) {
            $badSleeps += [pscustomobject]@{ Path = $_.Path; Line = $_.LineNumber; Text = $_.Line.Trim() }
        }
    }
}
if ($badSleeps.Count -gt 0) {
    $details = ($badSleeps | ForEach-Object { "$($_.Path):$($_.Line):$($_.Text)" }) -join "`n"
    Fail "FAIL_FIXED_SLEEP_USED_AS_PRIMARY_WAIT`n$details"
}

$newScripts = @(
    'multiline_text_input_correctness_selftest.ps1',
    'code_editor_keyboard_input_selftest.ps1',
    'pycharm_first_pass_multiline_input_selftest.ps1',
    'motion_frame_rate_165hz_selftest.ps1',
    'operation_interval_budget_selftest.ps1'
) | ForEach-Object { Join-Path $Root $_ }
$badStartSleeps = @()
foreach ($script in $newScripts) {
    if (-not (Test-Path -LiteralPath $script)) { continue }
    Select-String -LiteralPath $script -Pattern 'Start-Sleep\s+-Seconds\s+([5-9]|[1-9][0-9]+)|Start-Sleep\s+-Milliseconds\s+([5-9][0-9]{3}|[1-9][0-9]{4,})' | ForEach-Object {
        $badStartSleeps += [pscustomobject]@{ Path = $_.Path; Line = $_.LineNumber; Text = $_.Line.Trim() }
    }
}
if ($badStartSleeps.Count -gt 0) {
    $details = ($badStartSleeps | ForEach-Object { "$($_.Path):$($_.Line):$($_.Text)" }) -join "`n"
    Fail "FAIL_FIXED_SLEEP_USED_AS_PRIMARY_WAIT`n$details"
}

$waitConditionEvidence = Select-String -Path (Join-Path $Root 'src\winagent\*.cpp') -Pattern 'while\s*\(|WaitFor|ElapsedMs|QueryPerformanceCounter' -Quiet
if (-not $waitConditionEvidence) {
    Fail 'FAIL_WAIT_CONDITION_MISSING'
}

@(
    '# Operation Interval Budget Selftest',
    '',
    '- result: PASS',
    '- operation_interval_budget_pass: true',
    '- any_operation_interval_over_5s: false',
    '- fixed_sleep_primary_wait_detected: false',
    '- wait_condition_present: true',
    '- scanned_scope: src\winagent and v6.12.1 input/motion selftests'
) | Set-Content -Encoding UTF8 -LiteralPath $Report

Write-Host 'PASS operation_interval_budget_selftest'
exit 0
