param(
    [string]$Root = '',
    [switch]$NegativeV610MissingPointerTest
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot

$ArtifactRoot = Join-Path $Root 'artifacts\dev6.1.1_humanmode_regression_triage_and_evidence_gate'
$RawDir = Join-Path $ArtifactRoot 'raw'
$VerifiedDir = Join-Path $ArtifactRoot 'verified'
$ResultPath = Join-Path $VerifiedDir 'acceptance_gate_result.json'
$ReportPath = Join-Path $ArtifactRoot 'acceptance_gate_report.md'

New-Item -ItemType Directory -Force -Path $ArtifactRoot, $RawDir, $VerifiedDir | Out-Null

function RelPath([string]$Path) {
    if ($Path.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $Path.Substring($Root.Length).TrimStart('\')
    }
    return $Path
}

function Add-Finding([System.Collections.Generic.List[object]]$Findings, [string]$Code, [string]$Message, [string]$Path = '', [bool]$Blocking = $true) {
    $Findings.Add([pscustomobject]@{
        code = $Code
        message = $Message
        path = $Path
        blocking = $Blocking
    }) | Out-Null
}

function Read-JsonFile([string]$Path, [string]$Label, [System.Collections.Generic.List[object]]$Findings, [bool]$Required = $true) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Add-Finding $Findings 'MISSING_EVIDENCE' "Missing $Label." (RelPath $Path) $Required
        return $null
    }
    try { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) }
    catch {
        Add-Finding $Findings 'INVALID_JSON' "Invalid JSON in $Label`: $($_.Exception.Message)" (RelPath $Path) $Required
        return $null
    }
}

function Test-JsonlFile([string]$Path, [string]$Label, [System.Collections.Generic.List[object]]$Findings, [bool]$Required = $true) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Add-Finding $Findings 'MISSING_EVIDENCE' "Missing $Label." (RelPath $Path) $Required
        return
    }
    $lineNo = 0
    foreach ($line in Get-Content -LiteralPath $Path) {
        $lineNo++
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $null = $line | ConvertFrom-Json }
        catch { Add-Finding $Findings 'INVALID_JSONL' "Invalid JSONL in $Label at line $lineNo`: $($_.Exception.Message)" (RelPath $Path) $Required }
    }
}

function Analyze-RawLog([string]$Path, [string]$Name, [System.Collections.Generic.List[object]]$Findings, [bool]$Required = $true) {
    $exists = Test-Path -LiteralPath $Path
    if (-not $exists) {
        Add-Finding $Findings 'MISSING_EVIDENCE' "Missing raw log for $Name." (RelPath $Path) $Required
        return [pscustomobject]@{ name=$Name; path=(RelPath $Path); exists=$false; exit_code=$null; status='MISSING'; has_required_header=$false; has_pass=$false; has_fail=$false; has_skip=$false }
    }
    $text = Get-Content -LiteralPath $Path -Raw
    $exit = $null
    if ($text -match '(?m)^EXIT_CODE:\s*(-?\d+)') { $exit = [int]$Matches[1] }
    $hasHeader = ($text -match '(?m)^COMMAND:\s+') -and ($text -match '(?m)^TIMESTAMP_START:\s+') -and ($text -match '(?m)^TIMESTAMP_END:\s+') -and ($text -match '(?m)^EXIT_CODE:\s+')
    if (-not $hasHeader) {
        Add-Finding $Findings 'RAW_LOG_INCOMPLETE' "Raw log lacks command/timestamp/exit-code header for $Name." (RelPath $Path) $Required
    }
    $hasPass = $text -match '(?m)^SCRIPT_STATUS:\s*PASS\b|\bPASS\b'
    $hasFail = $text -match '(?m)^SCRIPT_STATUS:\s*FAIL\b|FAIL_CURSOR_NOT_AT_TARGET|\bFAIL\b|failed'
    $hasSkip = $text -match '(?m)\bSKIP\b|\bSKIPPED\b|SKIP_ENVIRONMENT|NOT_RUN'
    if ($Required -and $exit -ne $null -and $exit -ne 0) {
        Add-Finding $Findings 'REGRESSION_FAILED' "Required raw log $Name has non-zero exit code $exit." (RelPath $Path) $true
    }
    if ($Required -and $hasSkip) {
        Add-Finding $Findings 'REGRESSION_SKIPPED' "Required raw log $Name contains SKIP/NOT_RUN marker." (RelPath $Path) $true
    }
    if ($Required -and $Name -match 'HumanMode pacing' -and $hasFail) {
        Add-Finding $Findings 'REGRESSION_FAILED' "HumanMode pacing raw log contains failure marker." (RelPath $Path) $true
    }
    return [pscustomobject]@{
        name = $Name
        path = (RelPath $Path)
        exists = $true
        exit_code = $exit
        status = if ($hasSkip) { 'SKIP_OR_NOT_RUN' } elseif ($exit -ne $null -and $exit -ne 0) { 'FAIL' } elseif ($hasFail -and $Name -match 'HumanMode pacing') { 'FAIL' } elseif ($hasPass) { 'PASS_MARKER' } else { 'UNVERIFIED' }
        has_required_header = $hasHeader
        has_pass = $hasPass
        has_fail = $hasFail
        has_skip = $hasSkip
    }
}

function Get-MarkdownPointerCandidates([string]$Text) {
    $items = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($Text)) { return $items.ToArray() }
    foreach ($m in [regex]::Matches($Text, '`([^`]+)`')) {
        $value = $m.Groups[1].Value
        if ($value -match '\.(md|json|jsonl|log|txt|ps1|exe|bmp|png)$' -or $value -match 'artifacts[\\/]') {
            $items.Add($value) | Out-Null
        }
    }
    foreach ($line in ($Text -split "`r?`n")) {
        $trim = $line.Trim()
        if ($trim -match '^-+\s+([A-Za-z0-9_./\\ -]+\.(md|json|jsonl|log|txt|ps1|bmp|png))$') {
            $items.Add($Matches[1].Trim()) | Out-Null
        }
    }
    return @($items | Select-Object -Unique)
}

function Resolve-PointerPath([string]$BaseDir, [string]$Pointer) {
    $normalized = $Pointer -replace '/', '\'
    if ([System.IO.Path]::IsPathRooted($normalized)) { return $normalized }
    if ($normalized.StartsWith('artifacts\', [System.StringComparison]::OrdinalIgnoreCase) -or
        $normalized.StartsWith('docs\', [System.StringComparison]::OrdinalIgnoreCase) -or
        $normalized.StartsWith('config\', [System.StringComparison]::OrdinalIgnoreCase) -or
        $normalized.StartsWith('src\', [System.StringComparison]::OrdinalIgnoreCase)) {
        return Join-Path $Root $normalized
    }
    return Join-Path $BaseDir $normalized
}

function Audit-EvidenceIndex([string]$Path, [System.Collections.Generic.List[object]]$Findings, [bool]$Required = $true) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Add-Finding $Findings 'MISSING_EVIDENCE_INDEX' 'Missing evidence_index.md.' (RelPath $Path) $Required
        return @()
    }
    $text = Get-Content -LiteralPath $Path -Raw
    $base = Split-Path -Parent $Path
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($ptr in (Get-MarkdownPointerCandidates $text)) {
        $resolved = Resolve-PointerPath $base $ptr
        $exists = Test-Path -LiteralPath $resolved
        $items.Add([pscustomobject]@{ pointer=$ptr; resolved=(RelPath $resolved); exists=$exists }) | Out-Null
        if (-not $exists -and $text -notmatch ('(?is)Missing Evidence.*' + [regex]::Escape($ptr))) {
            Add-Finding $Findings 'MISSING_EVIDENCE_POINTER' "evidence_index.md points to missing file: $ptr" (RelPath $Path) $Required
        }
    }
    return $items.ToArray()
}

function Get-StateField([string]$Text, [string]$Field) {
    if ($Text -match ('(?m)^' + [regex]::Escape($Field) + ':\s*(.+)$')) { return $Matches[1].Trim() }
    return ''
}

$findings = New-Object System.Collections.Generic.List[object]

$v610EvidenceIndex = Join-Path $Root 'artifacts\dev6.1.0_task_intent_planner\evidence_index.md'
$v610PacingLog = Join-Path $Root 'artifacts\dev6.1.0_task_intent_planner\v5_9_0_e_humanmode_motion_pacing_test.log'
$v610IndexText = if (Test-Path -LiteralPath $v610EvidenceIndex) { Get-Content -LiteralPath $v610EvidenceIndex -Raw } else { '' }
$v610ReferencesMissingPacingLog = $v610IndexText -match 'v5_9_0_e_humanmode_motion_pacing_test\.log' -and -not (Test-Path -LiteralPath $v610PacingLog)

if ($NegativeV610MissingPointerTest) {
    if ($v610ReferencesMissingPacingLog) {
        Add-Finding $findings 'MISSING_REQUIRED_EVIDENCE_POINTER' 'v6.1.0 evidence_index.md references a missing HumanMode pacing log.' (RelPath $v610PacingLog) $true
    }
    $status = if ($findings.Count -eq 0) { 'PASS' } else { 'FAIL_EVIDENCE_MISSING' }
    $result = [ordered]@{
        schema_version = 'v6.1.1.evidence_acceptance_gate'
        generated_at = (Get-Date).ToString('o')
        mode = 'negative_v6_1_0_missing_pointer'
        status = $status
        accepted = $false
        trusted_version_allowed = '6.0.0'
        ready_for_next_version_allowed = $false
        findings = [object[]]$findings.ToArray()
    }
    $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $ResultPath -Encoding UTF8
    $negativeReport = New-Object System.Collections.Generic.List[string]
    $negativeReport.Add('# v6.1.1 Evidence Acceptance Gate Report') | Out-Null
    $negativeReport.Add('') | Out-Null
    $negativeReport.Add('- Mode: `negative_v6_1_0_missing_pointer`') | Out-Null
    $negativeReport.Add(('- Status: `{0}`' -f $status)) | Out-Null
    $negativeReport.Add('') | Out-Null
    $negativeReport.Add('## Findings') | Out-Null
    if ($findings.Count -eq 0) {
        $negativeReport.Add('- None') | Out-Null
    } else {
        foreach ($finding in $findings) {
            $negativeReport.Add(('- [{0}] {1} `{2}`' -f $finding.code, $finding.message, $finding.path)) | Out-Null
        }
    }
    $negativeReport | Set-Content -LiteralPath $ReportPath -Encoding UTF8
    Write-Host "ACCEPTANCE_GATE_RESULT: $status"
    Write-Host "Result: $ResultPath"
    Write-Host "Report: $ReportPath"
    if ($status -eq 'PASS') { exit 0 } else { exit 1 }
}

if (-not (Test-Path -LiteralPath $RawDir)) {
    Add-Finding $findings 'MISSING_EVIDENCE' 'Missing raw evidence directory.' (RelPath $RawDir) $true
}
if (-not (Test-Path -LiteralPath $VerifiedDir)) {
    Add-Finding $findings 'MISSING_EVIDENCE' 'Missing verified evidence directory.' (RelPath $VerifiedDir) $true
}

$rawLogs = @(
    @{ name='build'; file='build.log'; required=$true },
    @{ name='version'; file='version.log'; required=$true },
    @{ name='v6.1 planner selftest'; file='v6_1_0_task_intent_planner_selftest.log'; required=$true },
    @{ name='v6.0 boundary regression'; file='v6_0_0_agent_boundary_selftest.log'; required=$true },
    @{ name='permission regression'; file='v5_9_permission_reset_selftest.log'; required=$true },
    @{ name='HumanMode pacing run1'; file='v5_9_0_e_humanmode_motion_pacing_test_run1.log'; required=$true },
    @{ name='HumanMode pacing run2'; file='v5_9_0_e_humanmode_motion_pacing_test_run2.log'; required=$true },
    @{ name='adaptive loop regression'; file='v5_10_0_adaptive_humanmode_loop_test.log'; required=$true },
    @{ name='HumanMode triage'; file='v6_1_1_humanmode_regression_triage.log'; required=$true },
    @{ name='JSON parse'; file='json_parse.log'; required=$true },
    @{ name='Markdown fence validation'; file='markdown_fence_validation.log'; required=$true },
    @{ name='encoding mojibake scan'; file='encoding_mojibake_scan.log'; required=$true },
    @{ name='COMMAND_PROTOCOL consistency'; file='command_protocol_consistency.log'; required=$true }
)
$rawResults = New-Object System.Collections.Generic.List[object]
foreach ($item in $rawLogs) {
    $rawResults.Add((Analyze-RawLog (Join-Path $RawDir $item.file) $item.name $findings ([bool]$item.required))) | Out-Null
}

$humanTriage = Read-JsonFile (Join-Path $VerifiedDir 'humanmode_triage_result.json') 'humanmode_triage_result.json' $findings $true
$plannerAcceptance = Read-JsonFile (Join-Path $VerifiedDir 'planner_acceptance_result.json') 'planner_acceptance_result.json' $findings $true
$regressionResult = Read-JsonFile (Join-Path $VerifiedDir 'regression_result.json') 'regression_result.json' $findings $true
$evidenceIntegrity = Read-JsonFile (Join-Path $VerifiedDir 'evidence_integrity_result.json') 'evidence_integrity_result.json' $findings $true

if ($humanTriage -and $humanTriage.required_rerun_needed -eq $true) {
    Add-Finding $findings 'INCONCLUSIVE' 'HumanMode triage still requires rerun.' (RelPath (Join-Path $VerifiedDir 'humanmode_triage_result.json')) $true
}
if ($plannerAcceptance -and $plannerAcceptance.ok -ne $true) {
    Add-Finding $findings 'REGRESSION_FAILED' 'Planner acceptance result is not ok.' (RelPath (Join-Path $VerifiedDir 'planner_acceptance_result.json')) $true
}
if ($regressionResult -and $regressionResult.ok -ne $true) {
    Add-Finding $findings 'REGRESSION_FAILED' 'Regression result is not ok.' (RelPath (Join-Path $VerifiedDir 'regression_result.json')) $true
}
if ($evidenceIntegrity -and $evidenceIntegrity.ok -ne $true) {
    Add-Finding $findings 'EVIDENCE_INTEGRITY_FAILED' 'Evidence integrity result is not ok.' (RelPath (Join-Path $VerifiedDir 'evidence_integrity_result.json')) $true
}

$currentEvidenceIndex = Join-Path $ArtifactRoot 'evidence_index.md'
$currentPointers = Audit-EvidenceIndex $currentEvidenceIndex $findings $true
$v610Pointers = Audit-EvidenceIndex $v610EvidenceIndex $findings $false
if ($v610ReferencesMissingPacingLog) {
    Add-Finding $findings 'MISSING_REQUIRED_EVIDENCE_POINTER' 'Legacy v6.1.0 blocked evidence pointer is missing and must not be used as v6.1.1 PASS.' (RelPath $v610PacingLog) $false
}

$indexText = if (Test-Path -LiteralPath $currentEvidenceIndex) { Get-Content -LiteralPath $currentEvidenceIndex -Raw } else { '' }
$passSection = ''
if ($indexText -match '(?is)##\s+PASS Evidence(.*?)(##\s+|$)') { $passSection = $Matches[1] }
if ($passSection -match 'artifacts[\\/]invalidated|INVALIDATED|synthetic|placeholder|diagnostic-only|mock') {
    Add-Finding $findings 'SYNTHETIC_EVIDENCE_DETECTED' 'PASS Evidence section references invalidated/synthetic/placeholder/diagnostic-only evidence.' (RelPath $currentEvidenceIndex) $true
}

$legacyMissingUsedAsPass = $passSection -match 'dev6\.1\.0_task_intent_planner[\\/]v5_9_0_e_humanmode_motion_pacing_test\.log'
if ($legacyMissingUsedAsPass) {
    Add-Finding $findings 'MISSING_EVIDENCE_POINTER' 'Missing v6.1.0 pacing log is referenced as current PASS evidence.' (RelPath $currentEvidenceIndex) $true
}

$agentsPath = Join-Path $Root 'AGENTS.md'
$agents = if (Test-Path -LiteralPath $agentsPath) { Get-Content -LiteralPath $agentsPath -Raw } else { '' }
$state = [ordered]@{
    version_file = ((Get-Content -LiteralPath (Join-Path $Root 'VERSION') -Raw).Trim())
    current_trusted_version = Get-StateField $agents 'current_trusted_version'
    last_completed_version = Get-StateField $agents 'last_completed_version'
    last_completed_status = Get-StateField $agents 'last_completed_status'
    ready_for_next_version = Get-StateField $agents 'ready_for_next_version'
    next_planned_version = Get-StateField $agents 'next_planned_version'
    current_stage = Get-StateField $agents 'current_stage'
}
$regressionMode = $state.version_file -ne '6.1.1'

$blockingFindings = @($findings | Where-Object { $_.blocking })
$preStateStatus = if ($blockingFindings.Count -eq 0) { 'candidate_accept' } else { 'candidate_blocked' }
if (-not $regressionMode) {
    if ($preStateStatus -eq 'candidate_blocked') {
        if ($state.current_trusted_version -ne '6.0.0') { Add-Finding $findings 'STATE_INCONSISTENT' 'current_trusted_version advanced despite gate blockers.' 'AGENTS.md' $true }
        if ($state.ready_for_next_version -eq 'true') { Add-Finding $findings 'STATE_INCONSISTENT' 'ready_for_next_version is true despite gate blockers.' 'AGENTS.md' $true }
        if ($state.next_planned_version -ne '6.1.2' -and $state.last_completed_version -eq '6.1.1') { Add-Finding $findings 'STATE_INCONSISTENT' 'blocked v6.1.1 must set next_planned_version to 6.1.2.' 'AGENTS.md' $true }
    } else {
        if ($state.current_trusted_version -ne '6.1.1') { Add-Finding $findings 'STATE_INCONSISTENT' 'accepted gate requires current_trusted_version 6.1.1.' 'AGENTS.md' $true }
        if ($state.ready_for_next_version -ne 'true') { Add-Finding $findings 'STATE_INCONSISTENT' 'accepted gate requires ready_for_next_version true.' 'AGENTS.md' $true }
        if ($state.next_planned_version -ne '6.2.0') { Add-Finding $findings 'STATE_INCONSISTENT' 'accepted gate requires next_planned_version 6.2.0.' 'AGENTS.md' $true }
    }
}

$blockingFindings = @($findings | Where-Object { $_.blocking })
$status = 'PASS'
if (@($findings | Where-Object { $_.blocking -and $_.code -match 'SYNTHETIC' }).Count -gt 0) { $status = 'FAIL_SYNTHETIC_EVIDENCE_DETECTED' }
elseif (@($findings | Where-Object { $_.blocking -and $_.code -match 'STATE' }).Count -gt 0) { $status = 'FAIL_STATE_INCONSISTENT' }
elseif (@($findings | Where-Object { $_.blocking -and $_.code -match 'REGRESSION' }).Count -gt 0) { $status = 'FAIL_REGRESSION' }
elseif (@($findings | Where-Object { $_.blocking -and $_.code -match 'MISSING|RAW_LOG_INCOMPLETE|INVALID_JSON|INVALID_JSONL' }).Count -gt 0) { $status = 'FAIL_EVIDENCE_MISSING' }
elseif (@($findings | Where-Object { $_.blocking -and $_.code -match 'INCONCLUSIVE' }).Count -gt 0) { $status = 'FAIL_INCONCLUSIVE' }
elseif ($blockingFindings.Count -gt 0) { $status = 'FAIL_INCONCLUSIVE' }
if ($status -eq 'PASS' -and $regressionMode) { $status = 'PASS_REGRESSION' }

$accepted = ($status -eq 'PASS' -or $status -eq 'PASS_REGRESSION')
$result = [ordered]@{
    schema_version = 'v6.1.1.evidence_acceptance_gate'
    generated_at = (Get-Date).ToString('o')
    mode = 'final'
    status = $status
    regression_mode = [bool]$regressionMode
    accepted = [bool]$accepted
    current_trusted_version_allowed = if ($accepted) { '6.1.1' } else { '6.0.0' }
    ready_for_next_version_allowed = [bool]$accepted
    next_planned_version_required = if ($accepted) { '6.2.0' } else { '6.1.2' }
    raw_log_results = [object[]]$rawResults.ToArray()
    current_evidence_pointers = [object[]]$currentPointers
    legacy_v6_1_0_evidence_pointers = [object[]]$v610Pointers
    legacy_v6_1_0_missing_pacing_log = [bool]$v610ReferencesMissingPacingLog
    agents_state = $state
    findings = [object[]]$findings.ToArray()
}
$result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ResultPath -Encoding UTF8

$report = New-Object System.Collections.Generic.List[string]
$report.Add('# v6.1.1 Evidence Acceptance Gate Report') | Out-Null
$report.Add('') | Out-Null
$report.Add(('- Status: `{0}`' -f $status)) | Out-Null
$report.Add(('- Accepted: `{0}`' -f $accepted)) | Out-Null
$report.Add(('- Legacy v6.1.0 missing pacing log: `{0}`' -f $v610ReferencesMissingPacingLog)) | Out-Null
$report.Add('') | Out-Null
$report.Add('## Raw Logs') | Out-Null
foreach ($row in $rawResults) {
    $report.Add(('- {0}: {1}, exit={2}, path=`{3}`' -f $row.name, $row.status, $row.exit_code, $row.path)) | Out-Null
}
$report.Add('') | Out-Null
$report.Add('## Findings') | Out-Null
if ($findings.Count -eq 0) {
    $report.Add('- None') | Out-Null
} else {
    foreach ($finding in $findings) {
        $report.Add(('- [{0}] blocking={1}: {2} `{3}`' -f $finding.code, $finding.blocking, $finding.message, $finding.path)) | Out-Null
    }
}
$report.Add('') | Out-Null
$report.Add('## Result JSON') | Out-Null
$report.Add('') | Out-Null
$report.Add('```json') | Out-Null
$report.Add(($result | ConvertTo-Json -Depth 20)) | Out-Null
$report.Add('```') | Out-Null
$report | Set-Content -LiteralPath $ReportPath -Encoding UTF8

Write-Host "ACCEPTANCE_GATE_RESULT: $status"
Write-Host "Result: $ResultPath"
Write-Host "Report: $ReportPath"
if ($accepted) { exit 0 } else { exit 1 }
