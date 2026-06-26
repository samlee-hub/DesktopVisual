param(
    [string]$Root = '',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.3.0_plan_draft_to_step_contract_compiler'
$SelftestRoot = Join-Path $ArtifactRoot 'selftest\step_contract_validator'
$ReportPath = Join-Path $ArtifactRoot 'step_contract_validator_selftest_report.md'

New-Item -ItemType Directory -Force -Path $SelftestRoot | Out-Null

if (-not $SkipBuild) {
    & (Join-Path $Root 'build.ps1') -Root $Root
    if ($LASTEXITCODE -ne 0) { throw 'build failed' }
}

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "winagent.exe not found: $WinAgent"
}

function Write-JsonFile {
    param([string]$Path, [object]$Value)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $Value | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding UTF8
    return $Path
}

function Invoke-WinAgentJson {
    param([string[]]$Arguments, [int[]]$AllowedExitCodes = @(0))
    $output = & $WinAgent @Arguments 2>&1
    $exit = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    try { $json = $text | ConvertFrom-Json } catch { throw "Invalid JSON from winagent $($Arguments -join ' '): $text" }
    if ($AllowedExitCodes -notcontains $exit) {
        throw "Unexpected exit $exit from winagent $($Arguments -join ' '): $text"
    }
    [pscustomobject]@{ exit = $exit; json = $json; text = $text; args = $Arguments }
}

function New-ContractStep {
    param([string]$StepId = 'step-001', [int]$Index = 0, [string]$Risk = 'LOW_RISK', [string]$RuntimeAction = 'click', [bool]$Executable = $true)
    [ordered]@{
        contract_id = "contract-$StepId"
        task_id = 'task-validator-selftest'
        plan_id = 'plan-validator-selftest'
        step_id = $StepId
        step_index = $Index
        step_type = 'click'
        runtime_action = $RuntimeAction
        target = 'uia:name=Submit,type=Button'
        input_text = ''
        executable = $Executable
        expected_context = [ordered]@{
            expected_process_pattern = 'msedge.exe'
            expected_title_pattern = 'DesktopVisual Mock'
            required_markers = @('DesktopVisual Mock')
            wrong_page_patterns = @('login', 'captcha')
            active_protection_patterns = @('captcha', 'human verification')
            credential_required_patterns = @('password', 'login required')
            foreground_required = $true
            window_binding_required = $true
        }
        action_precondition = [ordered]@{
            target_required = $true
            target_unique_required = $true
            target_inside_viewport_required = $true
            target_current_observe_required = $true
            focus_required = $true
            mouse_first_required = $true
            text_input_allowed = $false
            scroll_allowed = $false
            stale_target_reject_required = $true
        }
        verification_hint = [ordered]@{
            verify_type = 'marker_visible'
            expected_marker = 'submitted'
            expected_text = ''
            expected_window_title = 'DesktopVisual Mock'
            expected_url_pattern = ''
            expected_output_pattern = ''
            expected_field_value = ''
            post_action_reobserve_required = $true
        }
        risk_level = $Risk
        confirmation_policy = [ordered]@{
            confirmation_required = $false
            confirmation_reason = ''
            developer_full_access_allowed = $false
            public_release_confirmation_required = $false
            manual_handoff_required = $false
        }
        recovery_policy = [ordered]@{
            recovery_allowed = $true
            recovery_scope = 'reobserve_only'
            recovery_target = 'same_context'
            max_recovery_attempts = 1
            resume_from_checkpoint_allowed = $true
            replay_from_checkpoint_allowed = $false
            stop_if_recovery_fails = $true
        }
        stop_policy = [ordered]@{
            stop_on_wrong_context = $true
            stop_on_wrong_field = $true
            stop_on_target_stale = $true
            stop_on_target_not_unique = $true
            stop_on_active_protection = $true
            stop_on_credential_required = $true
            stop_on_unverified_result = $true
            stop_on_runtime_guard_failure = $true
        }
        session_policy = [ordered]@{
            session_required = $true
            session_reuse_allowed = $true
            force_reobserve_before_action = $true
            cache_policy = 'force_reobserve'
            locator_cache_allowed = $false
        }
        evidence_policy = [ordered]@{
            raw_evidence_required = $true
            verifier_required = $true
            gate_required = $true
            mouse_evidence_required = $true
            latency_required = $true
        }
        created_at = '2026-06-14T00:00:00Z'
        compiler_version = '6.3.0'
    }
}

function New-Contract {
    param([object[]]$Steps)
    [ordered]@{
        schema_version = '6.3.0.step_contract'
        compiler_version = '6.3.0'
        task_id = 'task-validator-selftest'
        plan_id = 'plan-validator-selftest'
        contracts = @($Steps)
    }
}

$results = [System.Collections.Generic.List[object]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Result {
    param([string]$Name, [string]$Status, [string]$Detail = '')
    $results.Add([pscustomobject]@{ name = $Name; status = $Status; detail = $Detail }) | Out-Null
    if ($Status -ne 'PASS') { $failures.Add("${Name}: $Detail") | Out-Null }
}

$validPath = Write-JsonFile (Join-Path $SelftestRoot 'valid_contract.json') (New-Contract @((New-ContractStep)))
$validResultPath = Join-Path $SelftestRoot 'valid_result.json'
$valid = Invoke-WinAgentJson @('step-contract-validate', '--input', $validPath, '--result', $validResultPath)
$validResult = Get-Content -LiteralPath $validResultPath -Raw | ConvertFrom-Json
if ($valid.json.ok -and $validResult.validation_ok -and $validResult.executable -and $validResult.runtime_session_compatible -and $validResult.safe_for_developer_full_access) {
    Add-Result 'validator accepts complete contract' 'PASS'
} else {
    Add-Result 'validator accepts complete contract' 'FAIL' $valid.text
}

$duplicatePath = Write-JsonFile (Join-Path $SelftestRoot 'duplicate_step_id_contract.json') (New-Contract @((New-ContractStep 'dup' 0), (New-ContractStep 'dup' 1)))
$duplicateResultPath = Join-Path $SelftestRoot 'duplicate_result.json'
$duplicate = Invoke-WinAgentJson @('step-contract-validate', '--input', $duplicatePath, '--result', $duplicateResultPath) @(1)
$duplicateResult = Get-Content -LiteralPath $duplicateResultPath -Raw | ConvertFrom-Json
if (-not $duplicate.json.ok -and -not $duplicateResult.validation_ok -and (($duplicateResult.validation_errors | ConvertTo-Json -Depth 10) -match 'duplicate')) {
    Add-Result 'validator rejects duplicate step_id' 'PASS'
} else {
    Add-Result 'validator rejects duplicate step_id' 'FAIL' $duplicate.text
}

$gapPath = Write-JsonFile (Join-Path $SelftestRoot 'step_index_gap_contract.json') (New-Contract @((New-ContractStep 's0' 0), (New-ContractStep 's2' 2)))
$gapResultPath = Join-Path $SelftestRoot 'gap_result.json'
$gap = Invoke-WinAgentJson @('step-contract-validate', '--input', $gapPath, '--result', $gapResultPath) @(1)
$gapResult = Get-Content -LiteralPath $gapResultPath -Raw | ConvertFrom-Json
if (-not $gap.json.ok -and -not $gapResult.validation_ok -and (($gapResult.validation_errors | ConvertTo-Json -Depth 10) -match 'continuous')) {
    Add-Result 'validator rejects non-continuous step_index' 'PASS'
} else {
    Add-Result 'validator rejects non-continuous step_index' 'FAIL' $gap.text
}

$blockedExecutable = New-ContractStep 'blocked' 0 'ACTIVE_PROTECTION_BLOCKED' 'click' $true
$blockedPath = Write-JsonFile (Join-Path $SelftestRoot 'active_protection_executable_contract.json') (New-Contract @($blockedExecutable))
$blockedResultPath = Join-Path $SelftestRoot 'blocked_result.json'
$blocked = Invoke-WinAgentJson @('step-contract-validate', '--input', $blockedPath, '--result', $blockedResultPath) @(1)
$blockedResult = Get-Content -LiteralPath $blockedResultPath -Raw | ConvertFrom-Json
if (-not $blocked.json.ok -and -not $blockedResult.validation_ok -and (($blockedResult.validation_errors | ConvertTo-Json -Depth 10) -match 'ACTIVE_PROTECTION_BLOCKED')) {
    Add-Result 'validator rejects executable active protection blocked step' 'PASS'
} else {
    Add-Result 'validator rejects executable active protection blocked step' 'FAIL' $blocked.text
}

$status = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
@(
    '# v6.3.0 StepContract Validator Selftest Report',
    '',
    "- Result: $status",
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "- WinAgent: $WinAgent",
    '',
    '## Results',
    '',
    '```json',
    ($results | ConvertTo-Json -Depth 100),
    '```'
) | Set-Content -LiteralPath $ReportPath -Encoding UTF8

if ($failures.Count -ne 0) {
    throw "step contract validator selftest failed: $($failures -join '; ')"
}

Write-Output 'PASS: v6.3.0 StepContract validator selftest'
Write-Output "Report: $ReportPath"
