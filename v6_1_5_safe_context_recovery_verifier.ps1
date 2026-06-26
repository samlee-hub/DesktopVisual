param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.1.5_safe_context_recovery_dynamic_diagnostics'
$RawRoot = Join-Path $ArtifactRoot 'raw\safe_context_recovery'
$VerifiedRoot = Join-Path $ArtifactRoot 'verified\safe_context_recovery'
New-Item -ItemType Directory -Force -Path $VerifiedRoot | Out-Null

function Read-Json([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return $null }
}

$matrixPath = Join-Path $RawRoot 'safe_recovery_raw_matrix.json'
$matrix = Read-Json $matrixPath
$findings = New-Object System.Collections.Generic.List[object]
function Add-Finding([string]$Code, [string]$CaseId, [string]$Message, [string]$Path = '') {
    $findings.Add([pscustomobject]@{
        code = $Code
        case_id = $CaseId
        message = $Message
        path = $Path
        blocking = $true
    }) | Out-Null
}

if (-not $matrix -or $matrix.runner_self_certified_pass -ne $false) {
    Add-Finding 'RAW_MATRIX_MISSING_OR_SELF_PASS' 'matrix' 'Safe recovery raw matrix missing or runner attempted to self-certify PASS.' $matrixPath
}

$requiredCases = @(
    'safe_context_recovery_selftest',
    'case_1_local_mock_wrong_page_recovery',
    'case_2_localhost_wrong_page_recovery',
    'case_3_explorer_wrong_folder_recovery',
    'case_4_browser_surface_wrong_page_recovery',
    'case_5_active_protection_hard_stop',
    'case_6_credential_required_hard_stop',
    'case_7_keyword_nonblock_regression'
)

$caseMap = @{}
if ($matrix -and $matrix.cases) {
    foreach ($case in @($matrix.cases)) { $caseMap[[string]$case.case_id] = $case }
}

foreach ($caseId in $requiredCases) {
    if (-not $caseMap.ContainsKey($caseId)) {
        Add-Finding 'CASE_MISSING' $caseId 'Required safe recovery case is missing from raw matrix.'
        continue
    }
    $case = $caseMap[$caseId]
    $primary = Read-Json ([string]$case.primary_result_json)
    if (-not $primary) {
        Add-Finding 'CASE_PRIMARY_RESULT_MISSING' $caseId 'Primary safe-context-recovery JSON is missing or invalid.' ([string]$case.primary_result_json)
        continue
    }
    $rr = $primary.data.recovery_result
    if (-not $rr) {
        Add-Finding 'RECOVERY_RESULT_MISSING' $caseId 'Primary result lacks data.recovery_result.' ([string]$case.primary_result_json)
        continue
    }
    if ($caseId -in @('safe_context_recovery_selftest','case_1_local_mock_wrong_page_recovery','case_2_localhost_wrong_page_recovery','case_3_explorer_wrong_folder_recovery','case_4_browser_surface_wrong_page_recovery','case_7_keyword_nonblock_regression')) {
        if ($primary.ok -ne $true -or $rr.recovery_success -ne $true -or $rr.recovery_allowed -ne $true -or $rr.recovered_markers_ok -ne $true) {
            Add-Finding 'SAFE_RECOVERY_CASE_FAILED' $caseId 'Expected recovery success, allowed=true, and markers_ok=true.' ([string]$case.primary_result_json)
        }
        if ($rr.active_protection_detected -eq $true -or $rr.credential_required_detected -eq $true) {
            Add-Finding 'UNEXPECTED_PROTECTION_OR_CREDENTIAL_STOP' $caseId 'Non-stop case unexpectedly detected active protection or credential requirement.' ([string]$case.primary_result_json)
        }
    }
    if ($caseId -in @('case_1_local_mock_wrong_page_recovery','case_2_localhost_wrong_page_recovery','case_3_explorer_wrong_folder_recovery','case_4_browser_surface_wrong_page_recovery')) {
        if ($rr.recovery_attempted -ne $true) {
            Add-Finding 'RECOVERY_NOT_ATTEMPTED' $caseId 'Wrong-context recovery case did not attempt recovery.' ([string]$case.primary_result_json)
        }
    }
    if ($caseId -eq 'case_5_active_protection_hard_stop') {
        if ($primary.ok -ne $false -or $rr.active_protection_detected -ne $true -or $rr.recovery_attempted -ne $false -or $rr.recovery_stop_code -ne 'STOP_ACTIVE_PROTECTION_OR_LOGIN_BLOCK') {
            Add-Finding 'ACTIVE_PROTECTION_STOP_FAILED' $caseId 'Active protection mock did not hard STOP before recovery/action.' ([string]$case.primary_result_json)
        }
    }
    if ($caseId -eq 'case_6_credential_required_hard_stop') {
        if ($primary.ok -ne $false -or $rr.credential_required_detected -ne $true -or $rr.recovery_attempted -ne $false -or $rr.recovery_stop_code -ne 'STOP_CREDENTIAL_REQUIRED') {
            Add-Finding 'CREDENTIAL_REQUIRED_STOP_FAILED' $caseId 'Credential mock did not hard STOP before recovery/action.' ([string]$case.primary_result_json)
        }
    }
    if ($caseId -eq 'case_7_keyword_nonblock_regression') {
        if ($primary.ok -ne $true -or $rr.recovery_stop_code) {
            Add-Finding 'KEYWORD_BASED_PERMISSION_REGRESSION' $caseId 'Keyword page produced a STOP or failed safe recovery evaluation.' ([string]$case.primary_result_json)
        }
        $badSteps = @($case.steps | Where-Object { $_.exit_code -ne 0 -and $_.step_id -notlike 'keyword_escape_find' })
        if ($badSteps.Count -gt 0) {
            Add-Finding 'KEYWORD_ACTION_FAILED' $caseId 'Keyword non-block low-risk actions failed unexpectedly.' ([string]$case.primary_result_json)
        }
    }
    if ($case.checkpoint_json) {
        $checkpoint = Read-Json ([string]$case.checkpoint_json)
        if (-not $checkpoint -or -not $checkpoint.data.resume_decision) {
            Add-Finding 'CHECKPOINT_RESUME_EVIDENCE_MISSING' $caseId 'Checkpoint/resume evidence missing.' ([string]$case.checkpoint_json)
        } elseif ($checkpoint.data.resume_decision.resume_allowed -ne $true -and $checkpoint.data.resume_decision.replay_required -ne $true) {
            Add-Finding 'CHECKPOINT_RESUME_DECISION_INVALID' $caseId 'Resume decision neither allows resume nor requires replay.' ([string]$case.checkpoint_json)
        }
    }
}

$status = if ($findings.Count -eq 0) { 'PASS' } else { 'FAIL' }
$result = [pscustomobject]@{
    schema_version = 'v6.1.5.safe_context_recovery.verifier'
    generated_at = (Get-Date).ToString('o')
    status = $status
    case_count = if ($matrix -and $matrix.cases) { @($matrix.cases).Count } else { 0 }
    findings = @($findings.ToArray())
}
$resultPath = Join-Path $VerifiedRoot 'safe_context_recovery_verifier_result.json'
$result | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $resultPath -Encoding UTF8

$findingRows = @($findings.ToArray()) | ForEach-Object {
    '- [{0}] {1}: {2} `{3}`' -f $_.code, $_.case_id, $_.message, $_.path
}
$verifierReportLines = @(
    '# v6.1.5 Safe Context Recovery Verifier',
    '',
    "- Result: $status",
    ('- Raw matrix: {0}' -f $matrixPath),
    ('- Verifier result: {0}' -f $resultPath),
    '',
    '## Findings'
) + @($findingRows)
$verifierReportLines | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'safe_context_recovery_verifier_report.md') -Encoding UTF8

@(
    '# v6.1.5 Checkpoint Resume Report',
    '',
    "- Result: $status",
    '- Recovery cases with checkpoint evidence require either explicit resume_allowed or replay_required; blind mid-step continuation is not accepted.'
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'checkpoint_resume_report.md') -Encoding UTF8

@(
    '# v6.1.5 Active Protection STOP Report',
    '',
    "- Result: $(if (($findings | Where-Object code -eq 'ACTIVE_PROTECTION_STOP_FAILED').Count -eq 0) { 'PASS' } else { 'FAIL' })",
    '- Required stop code: STOP_ACTIVE_PROTECTION_OR_LOGIN_BLOCK'
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'active_protection_stop_report.md') -Encoding UTF8

@(
    '# v6.1.5 Credential Required STOP Report',
    '',
    "- Result: $(if (($findings | Where-Object code -eq 'CREDENTIAL_REQUIRED_STOP_FAILED').Count -eq 0) { 'PASS' } else { 'FAIL' })",
    '- Required stop code: STOP_CREDENTIAL_REQUIRED'
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'credential_required_stop_report.md') -Encoding UTF8

@(
    '# v6.1.5 Keyword Nonblock Regression Report',
    '',
    "- Result: $(if (($findings | Where-Object code -like '*KEYWORD*').Count -eq 0) { 'PASS' } else { 'FAIL' })",
    '- Covered words: test, exam, contest, interview, challenge, assessment, OJ, submit, code, race.',
    '- These words are not active protection signals by themselves.'
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'keyword_nonblock_regression_report.md') -Encoding UTF8

if ($status -eq 'PASS') { exit 0 }
exit 1
