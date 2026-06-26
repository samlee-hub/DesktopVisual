param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.1.5_safe_context_recovery_dynamic_diagnostics'
$RawRoot = Join-Path $ArtifactRoot 'raw\dynamic_diagnostics'
$VerifiedRoot = Join-Path $ArtifactRoot 'verified\dynamic_diagnostics'
New-Item -ItemType Directory -Force -Path $VerifiedRoot | Out-Null

function Read-Json([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return $null }
}

$matrixPath = Join-Path $RawRoot 'dynamic_diagnostics_raw_matrix.json'
$matrix = Read-Json $matrixPath
$findings = New-Object System.Collections.Generic.List[object]
function Add-Finding([string]$Code, [string]$CaseId, [string]$Message, [string]$Path = '') {
    $findings.Add([pscustomobject]@{ code = $Code; case_id = $CaseId; message = $Message; path = $Path; blocking = $true }) | Out-Null
}

if (-not $matrix -or $matrix.runner_self_certified_pass -ne $false -or $matrix.runner_status -ne 'RAW_COMPLETED_UNVERIFIED') {
    Add-Finding 'RAW_MATRIX_MISSING_OR_SELF_PASS' 'matrix' 'Dynamic diagnostics raw matrix missing or runner attempted to self-certify PASS.' $matrixPath
}

$records = @()
if ($matrix -and $matrix.diagnostic_records) { $records = @($matrix.diagnostic_records) }
$requiredFields = @(
    'case_id','target_name','target_type','target_url_or_app','developer_full_access',
    'active_protection_detected','credential_required_detected','foreground_acquired',
    'expected_process_ok','expected_title_ok','uia_read_ok','ocr_read_ok','screen_observe_ok',
    'browser_surface_ok','target_visible','target_candidate_count','target_unique',
    'target_seen_but_not_confirmed','scroll_region_found','scroll_progress_detected',
    'action_attempted','action_executed','recovery_allowed','recovery_attempted','recovery_success',
    'final_stop_code','failure_attribution','evidence_paths'
)
foreach ($record in $records) {
    foreach ($field in $requiredFields) {
        if (-not ($record.PSObject.Properties.Name -contains $field)) {
            Add-Finding 'DYNAMIC_FIELD_MISSING' ([string]$record.case_id) "Missing required diagnostic field: $field" $matrixPath
        }
    }
    if ($record.developer_full_access -ne $true) {
        Add-Finding 'DEVELOPER_FULL_ACCESS_NOT_RECORDED' ([string]$record.case_id) 'developer_full_access must be true for v6.1.5 diagnostics.' $matrixPath
    }
    if ([string]::IsNullOrWhiteSpace([string]$record.failure_attribution)) {
        Add-Finding 'BLOCKED_FAILURE_ATTRIBUTION_MISSING' ([string]$record.case_id) 'Diagnostic case lacks failure_attribution.' $matrixPath
    }
    if ($record.active_protection_detected -eq $true -and [string]$record.final_stop_code -notmatch 'ACTIVE_PROTECTION|LOGIN_BLOCK|SCRIPT_DETECTION|ANTI_CHEAT') {
        Add-Finding 'ACTIVE_PROTECTION_NOT_STOPPED' ([string]$record.case_id) 'Active protection was detected but final stop code was not a hard STOP.' $matrixPath
    }
    if ($record.credential_required_detected -eq $true -and [string]$record.final_stop_code -ne 'STOP_CREDENTIAL_REQUIRED') {
        Add-Finding 'CREDENTIAL_REQUIRED_NOT_STOPPED' ([string]$record.case_id) 'Credential requirement was detected but final stop code was not STOP_CREDENTIAL_REQUIRED.' $matrixPath
    }
    if ($record.recovery_attempted -eq $true -or $record.recovery_success -eq $true) {
        Add-Finding 'DYNAMIC_BLIND_RECOVERY_ATTEMPTED' ([string]$record.case_id) 'Dynamic diagnostics must not blindly auto-recover real App/Web targets in v6.1.5.' $matrixPath
    }
    if ($record.action_executed -eq $true -and (-not $record.expected_process_ok -or -not $record.expected_title_ok)) {
        Add-Finding 'WRONG_CONTEXT_CONTINUED_ACTION' ([string]$record.case_id) 'Action executed after expected process/title was not confirmed.' $matrixPath
    }
    if ($record.action_executed -eq $true -and [string]$record.final_stop_code -match 'STOP_BROWSER_NAVIGATION_WRONG_PAGE|EXPECTED_CONTEXT_FAILED|ACTIVE_PROTECTION|CREDENTIAL') {
        Add-Finding 'ACTION_EXECUTED_AFTER_STOP_CONTEXT' ([string]$record.case_id) 'Action executed after a stop-context final code.' $matrixPath
    }
    if ([string]$record.final_stop_code -match '(?i)KEYWORD|EXAM|CONTEST|INTERVIEW|OJ|SUBMIT') {
        Add-Finding 'BLOCKED_KEYWORD_BASED_PERMISSION_REGRESSION' ([string]$record.case_id) 'Diagnostic result appears to stop on ordinary content keywords.' $matrixPath
    }
}

$attemptedCategories = @($records | Where-Object { $_.action_attempted -eq $true } | Select-Object -ExpandProperty diagnostic_category -Unique)
if ($attemptedCategories.Count -lt 4) {
    Add-Finding 'BLOCKED_DYNAMIC_DIAGNOSTIC_NOT_RUN' 'matrix' "Expected at least 4 diagnostic categories attempted; got $($attemptedCategories.Count)." $matrixPath
}

$status = if ($findings.Count -eq 0) { 'PASS' } else { 'FAIL' }
$result = [pscustomobject]@{
    schema_version = 'v6.1.5.dynamic_diagnostics.verifier'
    generated_at = (Get-Date).ToString('o')
    status = $status
    case_count = $records.Count
    attempted_category_count = $attemptedCategories.Count
    attempted_categories = @($attemptedCategories)
    findings = @($findings.ToArray())
}
$resultPath = Join-Path $VerifiedRoot 'dynamic_diagnostics_verifier_result.json'
$result | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $resultPath -Encoding UTF8

$findingRows = @($findings.ToArray()) | ForEach-Object {
    '- [{0}] {1}: {2} ({3})' -f $_.code, $_.case_id, $_.message, $_.path
}
$reportLines = @(
    '# v6.1.5 Dynamic Diagnostics Verifier',
    '',
    "- Result: $status",
    "- Case count: $($records.Count)",
    "- Attempted categories: $($attemptedCategories -join ', ')",
    "- Raw matrix: $matrixPath",
    "- Verifier result: $resultPath",
    '',
    '## Findings'
) + @($findingRows)
$reportLines | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'dynamic_diagnostics_verifier_report.md') -Encoding UTF8

if ($status -eq 'PASS') { exit 0 }
exit 1
