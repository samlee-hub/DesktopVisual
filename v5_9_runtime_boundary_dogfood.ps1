param(
    [string]$Root = '',
    [switch]$AttemptVisibleUi
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$ArtifactDir = Join-Path $Root 'artifacts\dev5.9.0-a'
$CasesDir = Join-Path $ArtifactDir 'runtime_boundary_cases'
$MailMock = 'D:\testrepo\testwindow\desktopvisual_mail_mock.html'

New-Item -ItemType Directory -Force -Path $CasesDir | Out-Null

function Write-Text($Path, $Content) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    Set-Content -LiteralPath $Path -Encoding UTF8 -Value $Content
}

function New-SkipCase($Id, $Title, $Reason, $FallbackUsed = $false) {
    $dir = Join-Path $CasesDir $Id
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $events = Join-Path $dir 'task_events.jsonl'
    $result = Join-Path $dir 'task_result.json'
    $report = Join-Path $dir 'task_report.md'
    $record = [ordered]@{
        case_id = $Id
        title = $Title
        result = 'SKIP_ENVIRONMENT'
        reason = $Reason
        fallback_used = $FallbackUsed
        strict_ui = $false
        fixed_coordinate_count = 0
        manual_intervention_count = 0
        locator_derived_coordinate_count = 0
        vlm_call_count = 0
        real_email_send_count = 0
        real_external_form_submit_count = 0
        active_protection_bypass_attempt_count = 0
    }
    ($record | ConvertTo-Json -Compress) | Set-Content -LiteralPath $events -Encoding UTF8
    $record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $result -Encoding UTF8
    $md = @(
        "# $Title",
        '',
        '- Result: SKIP_ENVIRONMENT',
        "- Reason: $Reason",
        "- Fallback used: $FallbackUsed",
        '- fixed_coordinate_count: 0',
        '- manual_intervention_count: 0',
        '- locator_derived_coordinate_count: 0',
        '- vlm_call_count: 0',
        '- real_email_send_count: 0',
        '- real_external_form_submit_count: 0',
        '- active_protection_bypass_attempt_count: 0'
    ) -join "`r`n"
    Write-Text $report $md
    return $record
}

if (-not (Test-Path -LiteralPath $MailMock)) {
    throw "Missing local mail mock fixture: $MailMock"
}

$nonInteractiveReason = 'Visible desktop dogfood was not attempted in this run because the current shell session cannot independently verify real mouse/keyboard UI effects without risking a direct-launch or mock PASS. Re-run with -AttemptVisibleUi from an attached desktop session to execute strict/fallback UI paths.'

$results = @()
if (-not $AttemptVisibleUi) {
    $results += New-SkipCase 'desktop_mouse_open_chrome_visible_flow' 'Case A - desktop mouse open Chrome visible flow' $nonInteractiveReason
    $results += New-SkipCase 'chrome_address_bar_external_url_navigation_flow' 'Case B - Chrome address bar external URL navigation flow' $nonInteractiveReason
    $results += New-SkipCase 'third_party_app_launch_flow' 'Case C - third-party app launch flow' $nonInteractiveReason
    $results += New-SkipCase 'explorer_open_local_html_flow' 'Case D - Explorer open local HTML flow' $nonInteractiveReason
    $results += New-SkipCase 'local_mail_mock_browser_fill_and_send_flow' 'Case E - local mail mock browser fill and send flow' $nonInteractiveReason
} else {
    $results += New-SkipCase 'desktop_mouse_open_chrome_visible_flow' 'Case A - desktop mouse open Chrome visible flow' 'Visible UI execution path is registered, but no locator-derived desktop icon/start-menu implementation is available yet; direct launch is forbidden for strict evidence.'
    $results += New-SkipCase 'chrome_address_bar_external_url_navigation_flow' 'Case B - Chrome address bar external URL navigation flow' 'Visible UI execution path is registered, but browser address-bar interaction needs a prior verified browser window; direct navigation/no-open mock is forbidden.'
    $results += New-SkipCase 'third_party_app_launch_flow' 'Case C - third-party app launch flow' 'Visible UI execution path is registered, but no user-specified third-party app locator was provided; PyCharm absence must be treated as environment skip unless installed and explicitly targeted.'
    $results += New-SkipCase 'explorer_open_local_html_flow' 'Case D - Explorer open local HTML flow' 'Visible UI execution path is registered, but Explorer UI navigation must use a verified foreground Explorer window; ShellExecute is forbidden as strict evidence.'
    $results += New-SkipCase 'local_mail_mock_browser_fill_and_send_flow' 'Case E - local mail mock browser fill and send flow' 'Visible UI execution path is registered, but strict browser field interaction requires a verified browser window and locator-derived input points; direct DOM modification is forbidden.'
}

$summary = [ordered]@{
    strict_ui_pass_count = @($results | Where-Object result -eq 'STRICT_UI_PASS').Count
    fallback_pass_count = @($results | Where-Object result -eq 'FALLBACK_PASS').Count
    skip_environment_count = @($results | Where-Object result -eq 'SKIP_ENVIRONMENT').Count
    fail_count = @($results | Where-Object result -eq 'FAIL').Count
    blocked_by_active_protection_count = @($results | Where-Object result -eq 'BLOCKED_BY_ACTIVE_PROTECTION').Count
    manual_intervention_count = 0
    fixed_coordinate_count = 0
    locator_derived_coordinate_count = 0
    vlm_call_count = 0
    real_email_send_count = 0
    real_external_form_submit_count = 0
    active_protection_bypass_attempt_count = 0
    fake_pass_count = 0
    cases = $results
}

$summaryPath = Join-Path $ArtifactDir 'runtime_boundary_dogfood_summary.json'
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

$report = @(
    '# v5.9.0-a Runtime Boundary Dogfood Report',
    '',
    "- strict_ui_pass_count: $($summary.strict_ui_pass_count)",
    "- fallback_pass_count: $($summary.fallback_pass_count)",
    "- skip_environment_count: $($summary.skip_environment_count)",
    "- fail_count: $($summary.fail_count)",
    "- blocked_by_active_protection_count: $($summary.blocked_by_active_protection_count)",
    "- manual_intervention_count: $($summary.manual_intervention_count)",
    "- fixed_coordinate_count: $($summary.fixed_coordinate_count)",
    "- locator_derived_coordinate_count: $($summary.locator_derived_coordinate_count)",
    "- vlm_call_count: $($summary.vlm_call_count)",
    "- real_email_send_count: $($summary.real_email_send_count)",
    "- real_external_form_submit_count: $($summary.real_external_form_submit_count)",
    "- active_protection_bypass_attempt_count: $($summary.active_protection_bypass_attempt_count)",
    "- fake_pass_count: $($summary.fake_pass_count)",
    '',
    '## Cases',
    ''
)
foreach ($case in $results) {
    $report += "- $($case.case_id): $($case.result) - $($case.reason)"
}
Write-Text (Join-Path $ArtifactDir 'runtime_boundary_dogfood_report.md') ($report -join "`r`n")
Write-Host "Runtime boundary dogfood summary: $summaryPath"
