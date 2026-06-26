param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.1.6_dynamic_app_web_full_access_rc_fresh'
$ReportPath = Join-Path $ArtifactRoot 'target_semantics_selftest_report.md'
$ResultPath = Join-Path $ArtifactRoot 'target_semantics_selftest_result.json'
$WinAgent = Join-Path $Root 'bin\winagent.exe'

function Ensure-Dir([string]$Path) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Save-Json($Value, [string]$Path) {
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { Ensure-Dir $dir }
    $Value | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-WinAgentJson([string[]]$WinArgs) {
    $output = & $WinAgent @WinArgs 2>&1
    $exit = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    $json = $null
    try { $json = $text | ConvertFrom-Json } catch { $json = $null }
    [pscustomobject]@{
        exit_code = $exit
        stdout = $text
        json = $json
    }
}

function U([int[]]$Codes) {
    $chars = foreach ($code in $Codes) { [char]$code }
    return -join $chars
}

$SendText = U @(21457,36865)
$SentText = U @(24050,21457,36865)

Ensure-Dir $ArtifactRoot

$checks = New-Object System.Collections.Generic.List[object]
function Add-Check([string]$Name, [bool]$Pass, [string]$Detail) {
    $script:checks.Add([ordered]@{
        name = $Name
        pass = [bool]$Pass
        detail = $Detail
    }) | Out-Null
}

$guardHeader = Join-Path $Root 'src\winagent\TargetSemanticsGuard.h'
$guardCpp = Join-Path $Root 'src\winagent\TargetSemanticsGuard.cpp'
$winAgentCpp = Join-Path $Root 'src\winagent\WinAgent.cpp'
$build = Join-Path $Root 'build.ps1'
$runner = Join-Path $Root 'v6_1_6_dynamic_app_web_full_access_fresh_runner.ps1'
$verifier = Join-Path $Root 'v6_1_6_dynamic_app_web_full_access_fresh_verifier.ps1'
$gate = Join-Path $Root 'v6_1_6_dynamic_app_web_full_access_fresh_acceptance_gate.ps1'

Add-Check 'guard_header_exists' (Test-Path -LiteralPath $guardHeader) $guardHeader
Add-Check 'guard_cpp_exists' (Test-Path -LiteralPath $guardCpp) $guardCpp

$buildText = if (Test-Path -LiteralPath $build) { Get-Content -LiteralPath $build -Raw } else { '' }
Add-Check 'build_includes_guard_cpp' ($buildText -match 'TargetSemanticsGuard\.cpp') $build

$winAgentText = if (Test-Path -LiteralPath $winAgentCpp) { Get-Content -LiteralPath $winAgentCpp -Raw } else { '' }
$guardCppText = if (Test-Path -LiteralPath $guardCpp) { Get-Content -LiteralPath $guardCpp -Raw } else { '' }
Add-Check 'winagent_includes_guard' ($winAgentText -match '#include "TargetSemanticsGuard\.h"') $winAgentCpp
Add-Check 'desktop_click_uses_guard' ($winAgentText -match 'EvaluateTargetSemanticsGuard' -and $winAgentText -match 'CommandDesktopMouseVariant') $winAgentCpp
Add-Check 'act_uses_guard' ($winAgentText -match 'EvaluateTargetSemanticsGuard' -and $winAgentText -match 'CommandAct') $winAgentCpp
Add-Check 'stop_codes_present' ($guardCppText -match 'STOP_TARGET_SEMANTIC_MISMATCH' -and $guardCppText -match 'STOP_FORBIDDEN_SIMILAR_TARGET' -and $guardCppText -match 'STOP_TARGET_REGION_MISMATCH' -and $guardCppText -match 'STOP_CLICKED_TARGET_NOT_EXPECTED' -and $guardCppText -match 'STOP_POST_ACTION_CAUSAL_VERIFICATION_FAILED') $guardCpp

$runnerText = if (Test-Path -LiteralPath $runner) { Get-Content -LiteralPath $runner -Raw } else { '' }
Add-Check 'fresh_runner_passes_guard_profile' ($runnerText -match '--expected-text-exact' -and $runnerText -match '--negative-text-pattern' -and $runnerText -match '--candidate-semantic-type') $runner
Add-Check 'fresh_runner_records_guard_evidence' ($runnerText -match 'target_semantics_guard') $runner
Add-Check 'fresh_runner_preserves_actual_candidate_region' ($runnerText -match '\$region\s*=\s*if \(-not \[string\]::IsNullOrWhiteSpace\(\$CandidateRegion\)\) \{ \$CandidateRegion \}' -and $runnerText -notmatch '\$region\s*=\s*if .*\$profileObject\.expected_region.*\{ \[string\]\$profileObject\.expected_region \}') $runner
Add-Check 'pycharm_runner_records_keyboard_run_exception' ($runnerText -match 'run_icon_visual_target_limitation' -and $runnerText -match 'run_via_keyboard_shortcut' -and $runnerText -match 'vlm_or_visual_template_future_work' -and $runnerText -match 'SHIFT\+F10' -and $runnerText -notmatch 'click_pycharm_run') $runner

$verifierText = if (Test-Path -LiteralPath $verifier) { Get-Content -LiteralPath $verifier -Raw } else { '' }
Add-Check 'fresh_verifier_requires_guard_evidence' ($verifierText -match 'target_semantics_guard' -and $verifierText -match 'BLOCKED_RUNNER_ONLY_TARGET_SEMANTICS') $verifier
Add-Check 'fresh_verifier_accepts_pycharm_keyboard_run_exception' ($verifierText -match 'Validate-PyCharmRunShortcutException' -and $verifierText -match 'run_via_keyboard_shortcut' -and $verifierText -match 'run_icon_visual_target_limitation' -and $verifierText -match 'SHIFT\+F10') $verifier

$gateText = if (Test-Path -LiteralPath $gate) { Get-Content -LiteralPath $gate -Raw } else { '' }
Add-Check 'fresh_gate_runs_selftest' ($gateText -match 'v6_1_6_target_semantics_selftest\.ps1') $gate

if (Test-Path -LiteralPath $WinAgent) {
    $positive = Invoke-WinAgentJson @(
        'target-semantics-guard-check',
        '--expected-text-exact', $SendText,
        '--expected-role-pattern', 'Button',
        '--expected-region', 'compose_action_area',
        '--negative-text-pattern', ('^' + $SentText + '$'),
        '--candidate-text', $SendText,
        '--candidate-role', 'Button',
        '--candidate-region', 'compose_action_area',
        '--candidate-semantic-type', 'compose_send_button',
        '--target-unique', 'true',
        '--target-actionable', 'true',
        '--target-inside-viewport', 'true',
        '--target-rect-left', '300',
        '--target-rect-top', '200',
        '--target-rect-right', '360',
        '--target-rect-bottom', '236',
        '--require-unique-candidate', 'true',
        '--require-actionable-control', 'true',
        '--require-nonzero-rect', 'true',
        '--require-inside-viewport', 'true'
    )
    Add-Check 'guard_positive_behavior' ($positive.exit_code -eq 0 -and $positive.json.ok -eq $true -and $positive.json.data.target_semantics_guard.clicked_target_text -eq $SendText -and $positive.json.data.target_semantics_guard.clicked_target_is_expected_target -eq $true) $positive.stdout

    $negative = Invoke-WinAgentJson @(
        'target-semantics-guard-check',
        '--expected-text-exact', $SendText,
        '--negative-text-pattern', ('^' + $SentText + '$'),
        '--expected-region', 'compose_action_area',
        '--forbidden-region', 'sidebar_or_folder',
        '--candidate-text', $SentText,
        '--candidate-role', 'Button',
        '--candidate-region', 'sidebar_or_folder',
        '--candidate-semantic-type', 'mail_folder_nav',
        '--target-unique', 'true',
        '--target-actionable', 'true',
        '--target-inside-viewport', 'true',
        '--target-rect-left', '100',
        '--target-rect-top', '200',
        '--target-rect-right', '180',
        '--target-rect-bottom', '236',
        '--require-unique-candidate', 'true',
        '--require-nonzero-rect', 'true',
        '--require-inside-viewport', 'true'
    )
    Add-Check 'guard_negative_sent_folder_behavior' ($negative.exit_code -ne 0 -and $negative.json.ok -eq $false -and $negative.json.error.code -eq 'STOP_FORBIDDEN_SIMILAR_TARGET') $negative.stdout

    $post = Invoke-WinAgentJson @(
        'target-semantics-guard-check',
        '--post-action-causal-requirement', 'compose_send_completed',
        '--post-action-causal-verified', 'false'
    )
    Add-Check 'guard_post_action_causal_behavior' ($post.exit_code -ne 0 -and $post.json.ok -eq $false -and $post.json.error.code -eq 'STOP_POST_ACTION_CAUSAL_VERIFICATION_FAILED') $post.stdout

    $pycharmClose = Invoke-WinAgentJson @(
        'target-semantics-guard-check',
        '--expected-text-pattern', 'right arrow Run',
        '--expected-role-pattern', 'Button',
        '--expected-region', 'pycharm_run_right_arrow_button',
        '--forbidden-region', 'window_control_or_tab_close',
        '--negative-text-pattern', 'Close',
        '--negative-text-pattern', (U @(20851,38381)),
        '--candidate-text', 'Close',
        '--candidate-role', 'Button',
        '--candidate-region', 'window_control_or_tab_close',
        '--candidate-semantic-type', 'close_button',
        '--target-unique', 'true',
        '--target-actionable', 'true',
        '--target-inside-viewport', 'true',
        '--target-rect-left', '1500',
        '--target-rect-top', '20',
        '--target-rect-right', '1532',
        '--target-rect-bottom', '52',
        '--require-unique-candidate', 'true',
        '--require-actionable-control', 'true',
        '--require-nonzero-rect', 'true',
        '--require-inside-viewport', 'true'
    )
    Add-Check 'guard_negative_pycharm_close_not_run_behavior' ($pycharmClose.exit_code -ne 0 -and $pycharmClose.json.ok -eq $false -and $pycharmClose.json.error.code -eq 'STOP_FORBIDDEN_SIMILAR_TARGET') $pycharmClose.stdout
} else {
    Add-Check 'guard_positive_behavior' $false "Missing $WinAgent"
    Add-Check 'guard_negative_sent_folder_behavior' $false "Missing $WinAgent"
    Add-Check 'guard_post_action_causal_behavior' $false "Missing $WinAgent"
    Add-Check 'guard_negative_pycharm_close_not_run_behavior' $false "Missing $WinAgent"
}

$failed = @($checks.ToArray() | Where-Object { $_.pass -ne $true })
$status = if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }

Save-Json ([ordered]@{
    schema_version = 'v6.1.6.target_semantics_selftest'
    generated_at = (Get-Date).ToString('o')
    status = $status
    checks = @($checks.ToArray())
}) $ResultPath

$rows = @($checks.ToArray()) | ForEach-Object {
    '- {0}: {1} - {2}' -f $_.name, $(if ($_.pass) { 'PASS' } else { 'FAIL' }), $_.detail
}
@(
    '# v6.1.6 Target Semantics Selftest',
    '',
    "- Status: $status",
    "- Result JSON: $ResultPath",
    '',
    '## Checks'
) + $rows | Set-Content -LiteralPath $ReportPath -Encoding UTF8

if ($status -eq 'PASS') {
    Write-Host 'TARGET_SEMANTICS_SELFTEST_PASS'
    exit 0
}

Write-Host 'TARGET_SEMANTICS_SELFTEST_FAIL'
exit 1
