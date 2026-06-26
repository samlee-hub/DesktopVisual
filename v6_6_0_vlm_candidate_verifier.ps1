param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$EvidenceRoot = Join-Path $Root 'artifacts\dev6.6.0_vlm_assisted_unknown_ui_candidate_handling'
$RunnerPath = Join-Path $EvidenceRoot 'v6_6_0_runner_raw_result.json'

if (-not (Test-Path -LiteralPath $RunnerPath)) { throw 'v6.6.0 runner raw result missing.' }

$runner = Get-Content -LiteralPath $RunnerPath -Raw | ConvertFrom-Json
$findings = New-Object System.Collections.Generic.List[string]
$positiveRecords = New-Object System.Collections.Generic.List[object]
$negativeRecords = New-Object System.Collections.Generic.List[object]

function Add-Finding($Message) { $findings.Add($Message) | Out-Null }

function Read-JsonOrNull($Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return $null }
}

function Read-TextOrEmpty($Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return '' }
    return Get-Content -LiteralPath $Path -Raw
}

function Contains-Code($Values, $Expected) {
    if (-not $Expected) { return $true }
    $text = ($Values | ConvertTo-Json -Depth 20)
    return $text -match [regex]::Escape($Expected)
}

function Case-ByName($Name) {
    @($runner.cases | Where-Object { $_.name -eq $Name }) | Select-Object -First 1
}

if ($runner.status -ne 'RAW_COMPLETED_UNVERIFIED') { Add-Finding 'runner status was not RAW_COMPLETED_UNVERIFIED' }
if ($runner.result_is_pass -ne $false) { Add-Finding 'runner attempted to self-certify PASS' }
if ($runner.runner_only_vlm_candidate_bridge -ne $false) { Add-Finding 'runner reported runner-only candidate bridge' }

foreach ($source in @(
    'src\winagent\VLMCandidateBridge.h',
    'src\winagent\VLMCandidateBridge.cpp',
    'src\winagent\RuntimeCandidateValidator.h',
    'src\winagent\RuntimeCandidateValidator.cpp',
    'src\winagent\LocatorCandidate.h',
    'src\winagent\LocatorCandidate.cpp'
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $source))) {
        Add-Finding "bottom-layer VLM candidate source missing: $source"
    }
}

$bridgeSource = Read-TextOrEmpty (Join-Path $Root 'src\winagent\VLMCandidateBridge.cpp')
$validatorSource = Read-TextOrEmpty (Join-Path $Root 'src\winagent\RuntimeCandidateValidator.cpp')
$locatorSource = Read-TextOrEmpty (Join-Path $Root 'src\winagent\LocatorCandidate.cpp')
if ($bridgeSource -notmatch 'ValidateVLMObservationResultJson') { Add-Finding 'VLMCandidateBridge does not call VLMObservationValidator' }
if ($bridgeSource -notmatch 'ValidateRuntimeCandidatesFromJson') { Add-Finding 'VLMCandidateBridge does not call RuntimeCandidateValidator' }
if ($locatorSource -notmatch 'vlm_assisted_runtime_validated') { Add-Finding 'LocatorCandidate conversion source marker missing' }
if ($validatorSource -notmatch 'CANDIDATE_DIRECT_COORDINATE_FORBIDDEN') { Add-Finding 'RuntimeCandidateValidator direct coordinate rejection missing' }

function Verify-Common-ValidatedCandidate {
    param([object]$Payload, [string]$Name)
    if ($Payload.runtime_locator_failed -ne $true) { Add-Finding "$Name runtime_locator_failed was not true" }
    if ($Payload.vlm_bridge_invoked -ne $true) { Add-Finding "$Name vlm_bridge_invoked was not true" }
    if ($Payload.vlm_result_validated -ne $true) { Add-Finding "$Name vlm_result_validated was not true" }
    if ($Payload.runtime_candidate_validated -ne $true) { Add-Finding "$Name runtime_candidate_validated was not true" }
    if ($Payload.locator_candidate_created -ne $true) { Add-Finding "$Name locator_candidate_created was not true" }
    if ($Payload.locator_candidate.created -ne $true) { Add-Finding "$Name locator_candidate.created was not true" }
    if ($Payload.locator_candidate.coordinate_source_type -ne 'vlm_assisted_runtime_validated') { Add-Finding "$Name coordinate_source_type mismatch" }
    if ($Payload.locator_candidate.requires_final_guard_check -ne $true) { Add-Finding "$Name missing final guard requirement" }
    if ($Payload.locator_candidate.requires_mouse_first_evidence -ne $true) { Add-Finding "$Name missing mouse-first evidence requirement" }
    if ($Payload.locator_candidate.requires_post_action_verification -ne $true) { Add-Finding "$Name missing post-action verification requirement" }
    if ($Payload.bridge_result.candidate_validation_required -ne $true) { Add-Finding "$Name bridge did not require Runtime candidate validation" }
}

function Verify-PositiveCase {
    param(
        [string]$Name,
        [bool]$ExpectRuntimeExecution = $false,
        [scriptblock]$ExtraCheck = $null
    )
    $case = Case-ByName $Name
    if (-not $case) { Add-Finding "missing positive case $Name"; return }
    $payload = Read-JsonOrNull $case.result
    $record = [ordered]@{
        name = $Name
        command = $case.command
        scenario = $case.scenario
        exit_code = $case.exit_code
        result = $case.result
    }
    $positiveRecords.Add($record) | Out-Null
    if ($case.exit_code -ne 0) { Add-Finding "$Name exit_code was $($case.exit_code), expected 0" }
    if (-not $payload) { Add-Finding "$Name result JSON missing or invalid"; return }
    Verify-Common-ValidatedCandidate -Payload $payload -Name $Name
    if ($payload.runtime_executed -ne $ExpectRuntimeExecution) { Add-Finding "$Name runtime_executed was $($payload.runtime_executed), expected $ExpectRuntimeExecution" }
    if (-not $ExpectRuntimeExecution -and $payload.mouse_click_sent -ne $false) { Add-Finding "$Name dry/locate case sent mouse click" }
    if ($ExpectRuntimeExecution) {
        if ($payload.runtime_context_guard_used -ne $true) { Add-Finding "$Name did not use RuntimeContextGuard" }
        if ($payload.mouse_click_sent -ne $true) { Add-Finding "$Name did not send mouse click" }
        if ($payload.action_evidence.human_action_result.actual_click_sent -ne $true) { Add-Finding "$Name actual_click_sent not true" }
        if ($payload.post_action_verified -ne $true) { Add-Finding "$Name post_action_verified not true" }
    }
    if ($ExtraCheck) { & $ExtraCheck $case $payload }
}

Verify-PositiveCase -Name 'runtime_locate_failed_to_vlm_candidate' -ExpectRuntimeExecution $false
Verify-PositiveCase -Name 'locate_only_api' -ExpectRuntimeExecution $false
Verify-PositiveCase -Name 'approx_region_candidate' -ExpectRuntimeExecution $false -ExtraCheck {
    param($case, $payload)
    $vlmResultText = Read-TextOrEmpty (Join-Path $case.evidence_dir 'vlm_candidate_result.json')
    if ($vlmResultText -match '"click_point"|direct_click|coordinate_action_detail') { Add-Finding 'approx_region_candidate contained direct coordinate action output' }
    if ($payload.locator_candidate_created -ne $true) { Add-Finding 'approx_region_candidate did not create locator candidate' }
}
Verify-PositiveCase -Name 'roi_candidate' -ExpectRuntimeExecution $false -ExtraCheck {
    param($case, $payload)
    if ($payload.runtime_candidate_validation.selected_candidate.validation_method -notmatch 'roi_check') { Add-Finding 'roi_candidate validation_method missing roi_check' }
}
Verify-PositiveCase -Name 'multiple_candidates_one_unique_valid' -ExpectRuntimeExecution $false -ExtraCheck {
    param($case, $payload)
    if ($payload.runtime_candidate_validation.candidate_count -le 1) { Add-Finding 'multiple_candidates_one_unique_valid candidate_count was not > 1' }
    if ($payload.runtime_candidate_validation.validated_candidate_count -ne 1) { Add-Finding 'multiple_candidates_one_unique_valid validated count was not 1' }
    if ($payload.runtime_candidate_validation.rejected_candidate_count -lt 1) { Add-Finding 'multiple_candidates_one_unique_valid rejected count was not >= 1' }
    if ($payload.runtime_candidate_validation.selected_candidate_unique -ne $true) { Add-Finding 'multiple_candidates_one_unique_valid selected target was not unique' }
}
Verify-PositiveCase -Name 'local_safe_click' -ExpectRuntimeExecution $true -ExtraCheck {
    param($case, $payload)
    $stateText = Read-TextOrEmpty $case.state_snapshot
    if ($stateText -notmatch 'clicks=1') { Add-Finding 'local_safe_click state snapshot missing clicks=1' }
}

function Verify-NegativeCase {
    param([string]$Name, [string]$ExpectedRejection)
    $case = Case-ByName $Name
    if (-not $case) { Add-Finding "missing negative case $Name"; return }
    $payload = Read-JsonOrNull $case.result
    $record = [ordered]@{
        name = $Name
        scenario = $case.scenario
        exit_code = $case.exit_code
        expected_rejection = $ExpectedRejection
        result = $case.result
    }
    $negativeRecords.Add($record) | Out-Null
    if ($case.exit_code -eq 0) { Add-Finding "$Name unexpectedly exited 0" }
    if (-not $payload) { Add-Finding "$Name result JSON missing or invalid"; return }
    if ($payload.runtime_executed -ne $false) { Add-Finding "$Name runtime_executed was not false" }
    if ($payload.mouse_click_sent -ne $false) { Add-Finding "$Name mouse_click_sent was not false" }
    if ($payload.locator_candidate.created -ne $false) { Add-Finding "$Name invalid candidate converted to LocatorCandidate" }
    if ($payload.locator_candidate_created -ne $false) { Add-Finding "$Name locator_candidate_created was not false" }
    if ($payload.bridge_result.candidate_validation_required -ne $true) { Add-Finding "$Name bridge did not require candidate validation" }
    $allReasons = @()
    if ($payload.bridge_result.rejection_reasons) { $allReasons += @($payload.bridge_result.rejection_reasons) }
    if ($payload.runtime_candidate_validation -and $payload.runtime_candidate_validation.rejection_reasons) { $allReasons += @($payload.runtime_candidate_validation.rejection_reasons) }
    if ($payload.bridge_result.runtime_execution_reason) { $allReasons += $payload.bridge_result.runtime_execution_reason }
    if (-not (Contains-Code $allReasons $ExpectedRejection)) { Add-Finding "$Name missing expected rejection $ExpectedRejection" }
}

foreach ($case in @($runner.cases | Where-Object { $_.group -eq 'negative' })) {
    Verify-NegativeCase -Name $case.name -ExpectedRejection $case.expected_rejection
}

foreach ($case in @($runner.cases)) {
    $payload = Read-JsonOrNull $case.result
    if (-not $payload) { continue }
    if ($payload.locator_candidate_created -eq $true -and $payload.runtime_candidate_validated -ne $true) {
        Add-Finding "$($case.name) converted candidate without RuntimeCandidateValidator"
    }
    if ($payload.runtime_executed -eq $true -and $payload.runtime_context_guard_used -ne $true) {
        Add-Finding "$($case.name) executed without RuntimeContextGuard"
    }
}

$status = if ($findings.Count -eq 0) { 'PASS' } else { 'FAIL' }
$report = [ordered]@{
    schema_version = '6.6.0.vlm_candidate.verifier'
    generated_at = (Get-Date).ToString('o')
    status = $status
    verifier_pass = ($status -eq 'PASS')
    findings = @($findings)
    positive_case_count = $positiveRecords.Count
    negative_case_count = $negativeRecords.Count
    local_safe_runtime_executed = (@($positiveRecords | Where-Object { $_.name -eq 'local_safe_click' }).Count -eq 1)
    direct_action_allowed = $false
    coordinate_action_allowed = $false
    runner_only_vlm_candidate_bridge = $false
    raw_completed_unverified_counted_as_pass = $false
}
$report | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath (Join-Path $EvidenceRoot 'v6_6_0_verifier_report.json') -Encoding UTF8

[System.IO.File]::WriteAllLines(
    (Join-Path $EvidenceRoot 'positive_candidate_cases_report.md'),
    [string[]]@(
        '# v6.6.0 Positive Candidate Cases Report',
        '',
        "- Status: $status",
        "- Positive cases: $($positiveRecords.Count)",
        "- Local-safe runtime executed: $($report.local_safe_runtime_executed)",
        '',
        ($positiveRecords | ConvertTo-Json -Depth 20)
    ),
    [System.Text.UTF8Encoding]::new($false))

[System.IO.File]::WriteAllLines(
    (Join-Path $EvidenceRoot 'negative_candidate_cases_report.md'),
    [string[]]@(
        '# v6.6.0 Negative Candidate Cases Report',
        '',
        "- Status: $status",
        "- Negative cases: $($negativeRecords.Count)",
        "- Direct action allowed: false",
        "- Coordinate action allowed: false",
        '',
        ($negativeRecords | ConvertTo-Json -Depth 20)
    ),
    [System.Text.UTF8Encoding]::new($false))

$lines = @('# v6.6.0 VLM Candidate Verifier Report','')
$lines += "- Status: $status"
$lines += "- Positive cases: $($positiveRecords.Count)"
$lines += "- Negative cases: $($negativeRecords.Count)"
$lines += "- Local-safe runtime executed: $($report.local_safe_runtime_executed)"
$lines += "- Direct action allowed: false"
$lines += "- Coordinate action allowed: false"
$lines += "- Runner-only candidate bridge: false"
if ($findings.Count -gt 0) {
    $lines += ''
    $lines += '## Findings'
    foreach ($finding in $findings) { $lines += "- $finding" }
}
[System.IO.File]::WriteAllLines((Join-Path $EvidenceRoot 'v6_6_0_verifier_report.md'), [string[]]$lines, [System.Text.UTF8Encoding]::new($false))

if ($status -ne 'PASS') {
    'V6_6_0_VLM_CANDIDATE_VERIFIER_FAIL'
    $findings
    exit 1
}

'V6_6_0_VLM_CANDIDATE_VERIFIER_PASS'
