param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.1.6_dynamic_app_web_full_access_rc_fresh'
$ClosureRoot = Join-Path $Root 'artifacts\dev6.1.6_scope_reset_step_completion_closure'
$RegistryPath = Join-Path $ArtifactRoot 'case_status_registry.json'
$EvidencePath = Join-Path $ArtifactRoot 'raw\single_cases\case_1_qqmail_send\evidence.json'
$ResultPath = Join-Path $ClosureRoot 'case1_machine_evidence_validation_result.json'
$ValidationReportPath = Join-Path $ClosureRoot 'case1_machine_evidence_validation_report.md'
$RerunReportPath = Join-Path $ClosureRoot 'case1_fresh_rerun_report.md'

function Ensure-Dir([string]$Path) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Save-Json($Object, [string]$Path) {
    $Object | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-Json([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function U([int[]]$Codes) {
    $chars = foreach ($code in $Codes) { [char]$code }
    return -join $chars
}

function Get-Prop($Object, [string]$Name) {
    if ($Object -and $Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
    return $null
}

function Format-MdCell([object]$Value) {
    if ($null -eq $Value) { return '' }
    $text = [string]$Value
    return (($text -replace '\|','/') -replace "`r?`n",' ')
}

Ensure-Dir $ClosureRoot

$ExpectedRecipient = '1581782307@qq.com'
$ExpectedSubject = U @(54,46,49,46,54,27979,35797,37038,20214)
$ExpectedBody = U @(36825,26159,19968,23553,27979,35797,37038,20214)
$ExpectedSend = U @(21457,36865)
$Checks = New-Object System.Collections.Generic.List[object]

function Add-Check([string]$Name, [object]$Expected, [object]$Actual, [bool]$Passed, [string]$Note = '') {
    $script:Checks.Add([ordered]@{
        name = $Name
        expected = if ($null -eq $Expected) { '' } else { [string]$Expected }
        actual = if ($null -eq $Actual) { '' } else { [string]$Actual }
        passed = [bool]$Passed
        note = $Note
    }) | Out-Null
}

$ev = Read-Json $EvidencePath
$registry = Read-Json $RegistryPath
$findings = New-Object System.Collections.Generic.List[object]

if (-not $ev) {
    Add-Check 'evidence_exists' 'true' 'false' $false $EvidencePath
} else {
    $typed = @($ev.typed_text)
    Add-Check 'fresh_run' 'true' (Get-Prop $ev 'fresh_run') ($ev.fresh_run -eq $true)
    Add-Check 'stale_evidence_used' 'false' (Get-Prop $ev 'stale_evidence_used') ($ev.stale_evidence_used -eq $false)
    Add-Check 'fresh_artifact_path' 'rc_fresh case_1 evidence path' $EvidencePath ($EvidencePath -match 'dev6\.1\.6_dynamic_app_web_full_access_rc_fresh' -and $EvidencePath -match 'case_1_qqmail_send' -and $EvidencePath -notmatch 'dev6\.1\.6_dynamic_app_web_full_access_rc\\')
    Add-Check 'raw_status' 'RAW_COMPLETED_UNVERIFIED' (Get-Prop $ev 'raw_status') ([string]$ev.raw_status -eq 'RAW_COMPLETED_UNVERIFIED')
    Add-Check 'final_stop_code' '' (Get-Prop $ev 'final_stop_code') ([string]$ev.final_stop_code -eq '')
    Add-Check 'active_protection_detected' 'false' (Get-Prop $ev 'active_protection_detected') ($ev.active_protection_detected -eq $false)
    Add-Check 'credential_required_detected' 'false' (Get-Prop $ev 'credential_required_detected') ($ev.credential_required_detected -eq $false)
    Add-Check 'qqmail_opened' 'true' (Get-Prop $ev 'qqmail_opened') ($ev.qqmail_opened -eq $true)
    Add-Check 'compose_clicked_by_mouse' 'true' (Get-Prop $ev 'compose_clicked_by_mouse') ($ev.compose_clicked_by_mouse -eq $true)
    Add-Check 'recipient_field_clicked_by_mouse' 'true' (Get-Prop $ev 'recipient_field_clicked_by_mouse') ($ev.recipient_field_clicked_by_mouse -eq $true)
    Add-Check 'subject_field_clicked_by_mouse' 'true' (Get-Prop $ev 'subject_field_clicked_by_mouse') ($ev.subject_field_clicked_by_mouse -eq $true)
    Add-Check 'body_field_clicked_by_mouse' 'true' (Get-Prop $ev 'body_field_clicked_by_mouse') ($ev.body_field_clicked_by_mouse -eq $true)
    Add-Check 'typed_recipient' $ExpectedRecipient ($typed -join ' | ') ($typed -contains $ExpectedRecipient)
    Add-Check 'typed_subject' $ExpectedSubject ($typed -join ' | ') ($typed -contains $ExpectedSubject)
    Add-Check 'typed_body' $ExpectedBody ($typed -join ' | ') ($typed -contains $ExpectedBody)
    Add-Check 'recipient_verified' 'true' (Get-Prop $ev 'recipient_verified') ($ev.recipient_verified -eq $true)
    Add-Check 'subject_verified' 'true' (Get-Prop $ev 'subject_verified') ($ev.subject_verified -eq $true)
    Add-Check 'body_verified' 'true' (Get-Prop $ev 'body_verified') ($ev.body_verified -eq $true)
    Add-Check 'send_target_text' $ExpectedSend (Get-Prop $ev 'send_target_text') ([string]$ev.send_target_text -eq $ExpectedSend)
    Add-Check 'send_target_verified_before_click' 'true' (Get-Prop $ev 'send_target_verified_before_click') ($ev.send_target_verified_before_click -eq $true)
    Add-Check 'send_target_is_compose_action_area' 'true' (Get-Prop $ev 'send_target_is_compose_action_area') ($ev.send_target_is_compose_action_area -eq $true)
    Add-Check 'send_target_is_sidebar_or_folder' 'false' (Get-Prop $ev 'send_target_is_sidebar_or_folder') ($ev.send_target_is_sidebar_or_folder -eq $false)
    Add-Check 'clicked_target_text' $ExpectedSend (Get-Prop $ev 'clicked_target_text') ([string]$ev.clicked_target_text -eq $ExpectedSend)
    Add-Check 'clicked_target_is_compose_send_button' 'true' (Get-Prop $ev 'clicked_target_is_compose_send_button') ($ev.clicked_target_is_compose_send_button -eq $true)
    Add-Check 'clicked_target_is_sidebar_or_folder' 'false' (Get-Prop $ev 'clicked_target_is_sidebar_or_folder') ($ev.clicked_target_is_sidebar_or_folder -eq $false)
    Add-Check 'send_clicked_by_mouse' 'true' (Get-Prop $ev 'send_clicked_by_mouse') ($ev.send_clicked_by_mouse -eq $true)
    Add-Check 'post_send_sent_folder_only' 'false' (Get-Prop $ev 'post_send_sent_folder_only') ($ev.post_send_sent_folder_only -eq $false)
    Add-Check 'post_send_not_sent_folder_navigation' 'true' (Get-Prop $ev 'post_send_not_sent_folder_navigation') ($ev.post_send_not_sent_folder_navigation -eq $true)
    Add-Check 'send_success_verified' 'true' (Get-Prop $ev 'send_success_verified') ($ev.send_success_verified -eq $true)
    Add-Check 'wrong_field_input_count' '0' (Get-Prop $ev 'wrong_field_input_count') ([int]$ev.wrong_field_input_count -eq 0)
    Add-Check 'continued_action_after_wrong_context' 'false' (Get-Prop $ev 'continued_action_after_wrong_context') ($ev.continued_action_after_wrong_context -eq $false)
    Add-Check 'post_action_causal_verified' 'true' (Get-Prop $ev 'post_action_causal_verified') ($ev.post_action_causal_verified -eq $true)

    $sendAction = @($ev.mouse_actions | Where-Object { $_.step -eq 'click_qqmail_send' } | Select-Object -First 1)
    if ($sendAction.Count -eq 0) {
        Add-Check 'click_qqmail_send_mouse_action' 'present' 'missing' $false
    } else {
        $action = $sendAction[0]
        $human = Read-Json ([string]$action.human_action_result_path)
        Add-Check 'click_qqmail_send_action_click_sent' 'true' (Get-Prop $action 'click_sent') ($action.click_sent -eq $true)
        Add-Check 'click_qqmail_send_action_target_text' $ExpectedSend (Get-Prop $action 'clicked_target_text') ([string]$action.clicked_target_text -eq $ExpectedSend)
        Add-Check 'click_qqmail_send_action_region' 'compose_action_area' (Get-Prop $action 'clicked_target_region') ([string]$action.clicked_target_region -eq 'compose_action_area')
        Add-Check 'click_qqmail_send_human_actual_click' 'true' (Get-Prop $human 'actual_click_sent') ($human -and $human.actual_click_sent -eq $true)
        Add-Check 'click_qqmail_send_human_backend_action' 'false' (Get-Prop $human 'backend_action') ($human -and $human.backend_action -eq $false)
        Add-Check 'click_qqmail_send_guard_ok' 'true' (Get-Prop $action.target_semantics_guard 'ok') ($action.target_semantics_guard -and $action.target_semantics_guard.ok -eq $true)
        Add-Check 'click_qqmail_send_guard_forbidden' 'false' (Get-Prop $action.target_semantics_guard 'clicked_target_is_forbidden_similar_target') ($action.target_semantics_guard -and $action.target_semantics_guard.clicked_target_is_forbidden_similar_target -eq $false)
    }

    $stepNames = @($ev.steps | ForEach-Object { [string]$_.step })
    $forbiddenStepHits = @($stepNames | Where-Object { $_ -match 'case_2|case_3|case_4|pycharm|wechat|tiktok' })
    Add-Check 'no_case2_case3_case4_steps' '0 forbidden step hits' ($forbiddenStepHits -join ', ') ($forbiddenStepHits.Count -eq 0)
}

foreach ($check in @($Checks.ToArray())) {
    if ($check.passed -ne $true) {
        $findings.Add([ordered]@{
            code = 'BLOCKED_CASE1_EVIDENCE_NOT_TRUSTWORTHY'
            check = [string]$check.name
            expected = [string]$check.expected
            actual = [string]$check.actual
            note = [string]$check.note
        }) | Out-Null
    }
}

$status = if ($findings.Count -eq 0) { 'PASS' } else { 'BLOCKED' }

if ($registry) {
    $rows = @($registry)
    $case1Rows = @($rows | Where-Object { $_.case_id -eq 'case_1_qqmail_send' } | Select-Object -First 1)
    if ($case1Rows.Count -gt 0) {
        $row = $case1Rows[0]
        if ($status -eq 'PASS') {
            $row.status = 'pass'
            $row.last_pass_evidence_path = $EvidencePath
            $row.last_failure_evidence_path = ''
            $row.frozen_after_pass = $true
            $row.rerun_required = $false
            $row.invalidated = $false
            $row.invalidated_reason = 'previous placeholder superseded; fresh machine evidence verifier PASS'
        } else {
            $row.status = 'blocked'
            $row.last_pass_evidence_path = ''
            $row.last_failure_evidence_path = $EvidencePath
            $row.frozen_after_pass = $false
            $row.rerun_required = $true
        }
        $row.last_run_timestamp = (Get-Date).ToString('o')
        Save-Json @($rows) $RegistryPath
    }
}

$result = [ordered]@{
    schema_version = 'v6.1.6.case1_fresh_evidence_verifier'
    generated_at = (Get-Date).ToString('o')
    status = $status
    stop_code = if ($status -eq 'PASS') { '' } else { 'BLOCKED_CASE1_EVIDENCE_NOT_TRUSTWORTHY' }
    evidence_path = $EvidencePath
    registry_path = $RegistryPath
    checks = @($Checks.ToArray())
    findings = @($findings.ToArray())
    prohibited_cases_not_evaluated = @('case_2_pycharm_run','case_3_wechat_file_transfer','case_4_tiktok_search')
}
Save-Json $result $ResultPath

$table = foreach ($check in @($Checks.ToArray())) {
    "| $(Format-MdCell $check.name) | $(Format-MdCell $check.expected) | $(Format-MdCell $check.actual) | $(if ($check.passed) { 'PASS' } else { 'FAIL' }) |"
}

@(
    '# Case1 Machine Evidence Validation',
    '',
    "- Status: $status",
    "- Stop code: $($result.stop_code)",
    "- Evidence: $EvidencePath",
    "- Registry: $RegistryPath",
    "- Result JSON: $ResultPath",
    "- Scope: Case1 only; Case2/Case3/Case4 not evaluated.",
    '',
    '| Check | Expected | Actual | Result |',
    '|---|---|---|---|'
) + $table | Set-Content -LiteralPath $ValidationReportPath -Encoding UTF8

@(
    '# Case1 Fresh Rerun Report',
    '',
    "- Status: $status",
    "- Runner command: .\v6_1_6_dynamic_app_web_full_access_fresh_runner.ps1 -Root $Root -Case1Only",
    "- Verifier command: .\v6_1_6_case1_fresh_evidence_verifier.ps1 -Root $Root",
    "- Evidence: $EvidencePath",
    "- Recipient: $ExpectedRecipient",
    "- Subject: $ExpectedSubject",
    "- Body: $ExpectedBody",
    "- send_target_text: $([string](Get-Prop $ev 'send_target_text'))",
    "- clicked_target_text: $([string](Get-Prop $ev 'clicked_target_text'))",
    "- clicked_target_is_compose_send_button: $([string](Get-Prop $ev 'clicked_target_is_compose_send_button'))",
    "- clicked_target_is_sidebar_or_folder: $([string](Get-Prop $ev 'clicked_target_is_sidebar_or_folder'))",
    "- post_send_not_sent_folder_navigation: $([string](Get-Prop $ev 'post_send_not_sent_folder_navigation'))",
    "- send_success_verified: $([string](Get-Prop $ev 'send_success_verified'))",
    "- wrong_field_input_count: $([string](Get-Prop $ev 'wrong_field_input_count'))",
    "- continued_action_after_wrong_context: $([string](Get-Prop $ev 'continued_action_after_wrong_context'))",
    "- Case2/Case3/Case4: not run, not evaluated.",
    "- StepCompletionGate: not implemented in this rerun.",
    "- ExecutionOutcomeClassifier: not implemented or run in this rerun."
) | Set-Content -LiteralPath $RerunReportPath -Encoding UTF8

if ($status -eq 'PASS') {
    Write-Host 'CASE1_VERIFIER_PASS'
    exit 0
}

Write-Host 'BLOCKED_CASE1_EVIDENCE_NOT_TRUSTWORTHY'
exit 1
