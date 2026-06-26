param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$EvidenceRoot = Join-Path $Root 'artifacts\dev6.5.0_vlm_assisted_observation_contract'
$RunnerResultPath = Join-Path $EvidenceRoot 'v6_5_0_runner_raw_result.json'
if (-not (Test-Path $RunnerResultPath)) {
    throw 'Runner raw result missing.'
}

$runner = Get-Content -Raw $RunnerResultPath | ConvertFrom-Json
$findings = New-Object System.Collections.Generic.List[string]
$positiveRecords = New-Object System.Collections.Generic.List[object]
$negativeRecords = New-Object System.Collections.Generic.List[object]
$dryRunRecords = New-Object System.Collections.Generic.List[object]

function Add-Finding($Message) {
    $findings.Add($Message) | Out-Null
}

function Read-JsonOrNull($Path) {
    if (-not (Test-Path $Path)) { return $null }
    try { return Get-Content -Raw $Path | ConvertFrom-Json } catch { return $null }
}

function ErrorsText($Validation) {
    if (-not $Validation) { return '' }
    return ($Validation.validation_errors | ConvertTo-Json -Depth 20)
}

function WarningsText($Validation) {
    if (-not $Validation) { return '' }
    return ($Validation.validation_warnings | ConvertTo-Json -Depth 20)
}

if ($runner.status -ne 'RAW_COMPLETED_UNVERIFIED') { Add-Finding 'runner status was not RAW_COMPLETED_UNVERIFIED' }
if ($runner.result_is_pass -ne $false) { Add-Finding 'runner attempted to self-certify PASS' }
if ($runner.runtime_executed -ne $false) { Add-Finding 'runner reported runtime_executed=true' }

foreach ($source in @(
    'src\winagent\VLMObservationContract.cpp',
    'src\winagent\VLMProvider.cpp',
    'src\winagent\MockVLMProvider.cpp',
    'src\winagent\VLMObservationValidator.cpp',
    'src\winagent\VLMObservationBoundary.cpp'
)) {
    if (-not (Test-Path (Join-Path $Root $source))) {
        Add-Finding "bottom-layer source missing: $source"
    }
}

$runnerSource = Get-Content -Raw (Join-Path $Root 'v6_5_0_vlm_observation_runner.ps1')
if ($runnerSource -match 'validation_ok\s*=\s*\$true' -and $runnerSource -match 'VLM_DIRECT_ACTION_REJECTED') {
    Add-Finding 'runner appears to contain validator logic'
}

$requestDefault = Read-JsonOrNull $runner.requests.default.request
$requestRoi = Read-JsonOrNull $runner.requests.roi.request
$requestActive = Read-JsonOrNull $runner.requests.active.request
$requestCredential = Read-JsonOrNull $runner.requests.credential.request

if (-not $requestDefault) {
    Add-Finding 'default request missing or invalid'
} else {
    if ($requestDefault.request_created -ne $true) { Add-Finding 'default request_created not true' }
    if ($requestDefault.provider_role -ne 'assistive_only') { Add-Finding 'default provider_role not assistive_only' }
    if (-not $requestDefault.screenshot_path_present) { Add-Finding 'default screenshot_path missing' }
    if (-not $requestDefault.uia_summary_present) { Add-Finding 'default UIA summary missing' }
    if (-not $requestDefault.ocr_summary_present) { Add-Finding 'default OCR summary missing' }
    if (-not $requestDefault.expected_context_present) { Add-Finding 'default expected_context missing' }
    if (-not ($requestDefault.forbidden_outputs -contains 'direct_click')) { Add-Finding 'default forbidden_outputs missing direct_click' }
    if (-not ($requestDefault.allowed_outputs -contains 'possible_targets')) { Add-Finding 'default allowed_outputs missing possible_targets' }
}
if (-not $requestRoi -or $requestRoi.roi_present -ne $true -or $requestRoi.roi_bounds_valid -ne $true) {
    Add-Finding 'ROI request did not contain valid ROI bounds'
}
if (-not $requestActive -or $requestActive.blocked_context -ne $true -or $requestActive.active_protection_detected -ne $true) {
    Add-Finding 'active protection request did not mark blocked_context'
}
if (-not $requestCredential -or $requestCredential.blocked_context -ne $true -or $requestCredential.credential_required_detected -ne $true) {
    Add-Finding 'credential request did not mark blocked_context'
}

$casesByName = @{}
foreach ($case in $runner.cases) {
    $casesByName[$case.name] = $case
}

function Verify-ValidationCase {
    param(
        [string]$Name,
        [bool]$ExpectedOk,
        [string[]]$ExpectedErrors = @(),
        [string[]]$ExpectedWarnings = @(),
        [Nullable[bool]]$ExpectCandidatePipeline = $null
    )
    if (-not $casesByName.ContainsKey($Name)) {
        Add-Finding "missing case $Name"
        return $null
    }
    $case = $casesByName[$Name]
    $validation = Read-JsonOrNull $case.validation
    $result = Read-JsonOrNull $case.result
    $request = Read-JsonOrNull $case.request
    $record = [ordered]@{
        name = $Name
        scenario = $case.scenario
        expected_validation_ok = $ExpectedOk
        validation_ok = if ($validation) { $validation.validation_ok } else { $null }
        safe_for_direct_execution = if ($validation) { $validation.safe_for_direct_execution } else { $null }
        validation_errors = if ($validation) { @($validation.validation_errors) } else { @('missing_validation') }
        validation_warnings = if ($validation) { @($validation.validation_warnings) } else { @() }
        request = $case.request
        result = $case.result
        validation = $case.validation
    }
    if ($case.group -eq 'positive') { $positiveRecords.Add($record) | Out-Null }
    elseif ($case.group -eq 'dry_run') { $dryRunRecords.Add($record) | Out-Null }
    else { $negativeRecords.Add($record) | Out-Null }
    if (-not $validation) { Add-Finding "$Name validation missing or invalid"; return $record }
    if ($validation.validation_ok -ne $ExpectedOk) { Add-Finding "$Name validation_ok was $($validation.validation_ok), expected $ExpectedOk" }
    if ($validation.safe_for_direct_execution -ne $false) { Add-Finding "$Name safe_for_direct_execution was not false" }
    foreach ($code in $ExpectedErrors) {
        if ((ErrorsText $validation) -notmatch [regex]::Escape($code)) { Add-Finding "$Name missing expected error $code" }
    }
    foreach ($code in $ExpectedWarnings) {
        if ((WarningsText $validation) -notmatch [regex]::Escape($code)) { Add-Finding "$Name missing expected warning $code" }
    }
    if ($null -ne $ExpectCandidatePipeline -and $validation.safe_for_runtime_candidate_pipeline -ne $ExpectCandidatePipeline) {
        Add-Finding "$Name safe_for_runtime_candidate_pipeline was $($validation.safe_for_runtime_candidate_pipeline), expected $ExpectCandidatePipeline"
    }
    if ($ExpectedOk -and $result -and $result.possible_targets) {
        foreach ($target in $result.possible_targets) {
            if ($target.observation_only -ne $true) { Add-Finding "$Name possible target observation_only not true" }
            if ($target.requires_runtime_validation -ne $true) { Add-Finding "$Name possible target requires_runtime_validation not true" }
        }
    }
    return $record
}

Verify-ValidationCase -Name 'build_observation_request_from_runtime_observe' -ExpectedOk $true -ExpectCandidatePipeline $true | Out-Null
Verify-ValidationCase -Name 'valid_mock_vlm_observation_result' -ExpectedOk $true -ExpectCandidatePipeline $true | Out-Null
Verify-ValidationCase -Name 'roi_observation_request' -ExpectedOk $true -ExpectCandidatePipeline $true | Out-Null
Verify-ValidationCase -Name 'active_protection_context_summary_only' -ExpectedOk $true -ExpectCandidatePipeline $false | Out-Null
Verify-ValidationCase -Name 'credential_required_context_summary_only' -ExpectedOk $true -ExpectCandidatePipeline $false | Out-Null

Verify-ValidationCase -Name 'direct_click_output' -ExpectedOk $false -ExpectedErrors @('VLM_DIRECT_ACTION_REJECTED') | Out-Null
Verify-ValidationCase -Name 'coordinates_only_action' -ExpectedOk $false -ExpectedErrors @('VLM_COORDINATE_ACTION_REJECTED') | Out-Null
Verify-ValidationCase -Name 'executable_action_output' -ExpectedOk $false -ExpectedErrors @('VLM_DIRECT_ACTION_REJECTED') | Out-Null
Verify-ValidationCase -Name 'runtime_command_output' -ExpectedOk $false -ExpectedErrors @('VLM_RUNTIME_COMMAND_REJECTED') | Out-Null
Verify-ValidationCase -Name 'provider_role_not_assistive_only' -ExpectedOk $false -ExpectedErrors @('VLM_PROVIDER_ROLE_INVALID') | Out-Null
Verify-ValidationCase -Name 'malformed_json' -ExpectedOk $false -ExpectedErrors @('VLM_MALFORMED_JSON') | Out-Null
Verify-ValidationCase -Name 'possible_targets_missing_observation_only' -ExpectedOk $false -ExpectedErrors @('VLM_DIRECT_ACTION_REJECTED') | Out-Null
Verify-ValidationCase -Name 'possible_targets_missing_requires_runtime_validation' -ExpectedOk $false -ExpectedErrors @('VLM_CANDIDATE_REQUIRES_RUNTIME_VALIDATION') | Out-Null
Verify-ValidationCase -Name 'prompt_injection_classified_non_executable' -ExpectedOk $true -ExpectedWarnings @('VLM_PROMPT_INJECTION_CLASSIFIED') -ExpectCandidatePipeline $true | Out-Null
Verify-ValidationCase -Name 'captcha_bypass_suggestion' -ExpectedOk $false -ExpectedErrors @('VLM_BYPASS_INSTRUCTION_REJECTED') | Out-Null
Verify-ValidationCase -Name 'credential_handling_suggestion' -ExpectedOk $false -ExpectedErrors @('VLM_CREDENTIAL_INSTRUCTION_REJECTED') | Out-Null
Verify-ValidationCase -Name 'anti_cheat_script_detection_bypass_suggestion' -ExpectedOk $false -ExpectedErrors @('VLM_ACTIVE_PROTECTION_BYPASS_REJECTED') | Out-Null
Verify-ValidationCase -Name 'active_protection_executable_candidate' -ExpectedOk $false -ExpectedErrors @('VLM_DIRECT_ACTION_REJECTED') | Out-Null
Verify-ValidationCase -Name 'direct_coordinate_click_point' -ExpectedOk $false -ExpectedErrors @('VLM_COORDINATE_ACTION_REJECTED') | Out-Null
Verify-ValidationCase -Name 'approximate_region_only_non_executable' -ExpectedOk $true -ExpectCandidatePipeline $true | Out-Null

foreach ($name in @('dry_run_no_runtime_execution','vlm_action_runtime_boundary_attempt')) {
    if (-not $casesByName.ContainsKey($name)) {
        Add-Finding "missing dry-run case $name"
        continue
    }
    $case = $casesByName[$name]
    $validation = Read-JsonOrNull $case.validation
    $boundary = Read-JsonOrNull $case.boundary
    $record = [ordered]@{
        name = $name
        scenario = $case.scenario
        validation_ok = if ($validation) { $validation.validation_ok } else { $null }
        boundary_enforced = if ($boundary) { $boundary.boundary_enforced } else { $null }
        runtime_executed = if ($boundary) { $boundary.runtime_executed } else { $null }
        mouse_click_sent = if ($boundary) { $boundary.mouse_click_sent } else { $null }
        keyboard_type_sent = if ($boundary) { $boundary.keyboard_type_sent } else { $null }
        safe_for_direct_execution = if ($boundary) { $boundary.safe_for_direct_execution } else { $null }
        step_contract_accepts_vlm_action = if ($boundary) { $boundary.step_contract_accepts_vlm_action } else { $null }
    }
    $dryRunRecords.Add($record) | Out-Null
    if (-not $boundary) { Add-Finding "$name boundary missing"; continue }
    if ($boundary.boundary_enforced -ne $true) { Add-Finding "$name boundary_enforced not true" }
    if ($boundary.runtime_executed -ne $false) { Add-Finding "$name runtime_executed not false" }
    if ($boundary.mouse_click_sent -ne $false) { Add-Finding "$name mouse_click_sent not false" }
    if ($boundary.keyboard_type_sent -ne $false) { Add-Finding "$name keyboard_type_sent not false" }
    if ($boundary.safe_for_direct_execution -ne $false) { Add-Finding "$name safe_for_direct_execution not false" }
    if ($boundary.vlm_result_entered_runtime_action_path -ne $false) { Add-Finding "$name entered runtime action path" }
    if ($boundary.step_contract_accepts_vlm_action -ne $false) { Add-Finding "$name StepContract accepted VLM action" }
}

$status = if ($findings.Count -eq 0) { 'PASS' } else { 'FAIL' }
$report = [ordered]@{
    schema_version = '6.5.0.vlm_observation.verifier'
    generated_at = (Get-Date).ToString('o')
    status = $status
    verifier_pass = ($status -eq 'PASS')
    findings = @($findings)
    positive_case_count = $positiveRecords.Count
    negative_case_count = $negativeRecords.Count
    dry_run_case_count = $dryRunRecords.Count
    runtime_executed = $false
    direct_action_allowed = $false
    coordinate_action_allowed = $false
    runner_only_vlm_contract = $false
    safe_for_direct_execution_any = $false
}
$report | ConvertTo-Json -Depth 40 | Set-Content -Encoding UTF8 (Join-Path $EvidenceRoot 'v6_5_0_verifier_report.json')

@(
    '# v6.5.0 Positive Observation Cases Report',
    '',
    "- Status: $status",
    '',
    '```json',
    ($positiveRecords | ConvertTo-Json -Depth 40),
    '```'
) | Set-Content -Encoding UTF8 (Join-Path $EvidenceRoot 'positive_observation_cases_report.md')

@(
    '# v6.5.0 Negative Observation Cases Report',
    '',
    "- Status: $status",
    '',
    '```json',
    ($negativeRecords | ConvertTo-Json -Depth 40),
    '```'
) | Set-Content -Encoding UTF8 (Join-Path $EvidenceRoot 'negative_observation_cases_report.md')

@(
    '# v6.5.0 Dry-Run Report',
    '',
    "- Status: $status",
    "- Runtime executed: false",
    '',
    '```json',
    ($dryRunRecords | ConvertTo-Json -Depth 40),
    '```'
) | Set-Content -Encoding UTF8 (Join-Path $EvidenceRoot 'dry_run_report.md')

$lines = @('# v6.5.0 VLM Observation Verifier Report','')
$lines += "- Status: $status"
$lines += "- Positive cases: $($positiveRecords.Count)"
$lines += "- Negative cases: $($negativeRecords.Count)"
$lines += "- Dry-run cases: $($dryRunRecords.Count)"
$lines += "- Runtime executed: false"
if ($findings.Count -gt 0) {
    $lines += ''
    $lines += '## Findings'
    foreach ($f in $findings) { $lines += "- $f" }
}
$lines | Set-Content -Encoding UTF8 (Join-Path $EvidenceRoot 'v6_5_0_verifier_report.md')

if ($status -ne 'PASS') {
    'V6_5_0_VLM_OBSERVATION_VERIFIER_FAIL'
    $findings
    exit 1
}

'V6_5_0_VLM_OBSERVATION_VERIFIER_PASS'
