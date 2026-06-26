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
$SelftestRoot = Join-Path $ArtifactRoot 'selftest\plan_compiler'
$ReportPath = Join-Path $ArtifactRoot 'plan_compiler_selftest_report.md'

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

function New-BasePlan {
    param([string]$CaseId = 'selftest_explorer_open_path')
    [ordered]@{
        schema_version = '6.3.0.agent_plan_draft'
        plan_id = "plan-$CaseId"
        task_id = "task-$CaseId"
        intent = 'explorer_open_path'
        goal = 'open D:\testrepo\testwindow'
        risk_summary = 'LOW_RISK'
        allowed_scope = 'local_test_fixture'
        developer_full_access = $false
        requires_confirmation = $false
        expected_context_summary = [ordered]@{
            expected_process_pattern = 'explorer.exe'
            expected_title_pattern = 'testwindow'
            required_markers = @('testwindow')
            wrong_page_patterns = @('login', 'captcha')
            active_protection_patterns = @('captcha', 'human verification')
            credential_required_patterns = @('password', 'login required')
            foreground_required = $true
            window_binding_required = $true
        }
        verification_summary = 'path visible'
        recovery_summary = 'reobserve_only'
        steps = @(
            [ordered]@{
                draft_step_id = 'draft-open-path'
                natural_language_summary = 'Open the local test folder.'
                proposed_action = 'explorer_open_path'
                target_description = 'D:\testrepo\testwindow'
                input_text = ''
                expected_result = 'D:\testrepo\testwindow is visible'
                risk_hint = 'LOW_RISK'
                confirmation_hint = ''
                recovery_hint = 'reobserve only; do not bypass protection'
                verification_hint = 'path visible'
            }
        )
    }
}

$results = [System.Collections.Generic.List[object]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Result {
    param([string]$Name, [string]$Status, [string]$Detail = '')
    $results.Add([pscustomobject]@{ name = $Name; status = $Status; detail = $Detail }) | Out-Null
    if ($Status -ne 'PASS') { $failures.Add("${Name}: $Detail") | Out-Null }
}

$validPlan = Write-JsonFile (Join-Path $SelftestRoot 'valid_explorer_plan.json') (New-BasePlan)
$contractPath = Join-Path $SelftestRoot 'valid_explorer_contract.json'
$diagnosticsPath = Join-Path $SelftestRoot 'valid_explorer_diagnostics.json'
$compile = Invoke-WinAgentJson @('plan-compile', '--input', $validPlan, '--output', $contractPath, '--diagnostics', $diagnosticsPath)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$diag = Get-Content -LiteralPath $diagnosticsPath -Raw | ConvertFrom-Json
if ($compile.json.ok -and $diag.compile_ok -and $contract.contracts[0].runtime_action -eq 'explorer_open_path' -and
    $contract.contracts[0].expected_context -and $contract.contracts[0].verification_hint -and
    $contract.contracts[0].risk_level -eq 'LOW_RISK' -and $contract.contracts[0].stop_policy -and
    $contract.contracts[0].session_policy -and $contract.contracts[0].evidence_policy) {
    Add-Result 'compile valid explorer_open_path' 'PASS'
} else {
    Add-Result 'compile valid explorer_open_path' 'FAIL' $compile.text
}

$sessionStepsPath = Join-Path $SelftestRoot 'valid_explorer_session_steps.json'
$dryRun = Invoke-WinAgentJson @('step-contract-dry-run', '--input', $contractPath, '--session-steps-output', $sessionStepsPath)
$sessionSteps = Get-Content -LiteralPath $sessionStepsPath -Raw | ConvertFrom-Json
if ($dryRun.json.ok -and $sessionSteps.runtime_executed -eq $false -and $sessionSteps.session_steps[0].step_id -eq 'draft-open-path') {
    Add-Result 'dry-run emits session steps without runtime execution' 'PASS'
} else {
    Add-Result 'dry-run emits session steps without runtime execution' 'FAIL' $dryRun.text
}

$missingContext = New-BasePlan 'missing_context'
$missingContext.Remove('expected_context_summary')
$missingContextPath = Write-JsonFile (Join-Path $SelftestRoot 'missing_context_plan.json') $missingContext
$missingContextOut = Join-Path $SelftestRoot 'missing_context_contract.json'
$missingContextDiag = Join-Path $SelftestRoot 'missing_context_diagnostics.json'
$badContext = Invoke-WinAgentJson @('plan-compile', '--input', $missingContextPath, '--output', $missingContextOut, '--diagnostics', $missingContextDiag) @(1)
$badContextDiag = Get-Content -LiteralPath $missingContextDiag -Raw | ConvertFrom-Json
if (-not $badContext.json.ok -and $badContextDiag.compile_ok -eq $false -and $badContextDiag.error_code -eq 'COMPILE_MISSING_EXPECTED_CONTEXT') {
    Add-Result 'compile rejects missing expected_context' 'PASS'
} else {
    Add-Result 'compile rejects missing expected_context' 'FAIL' $badContext.text
}

$missingVerify = New-BasePlan 'missing_verification'
$missingVerify.steps[0].Remove('verification_hint')
$missingVerifyPath = Write-JsonFile (Join-Path $SelftestRoot 'missing_verification_plan.json') $missingVerify
$missingVerifyOut = Join-Path $SelftestRoot 'missing_verification_contract.json'
$missingVerifyDiag = Join-Path $SelftestRoot 'missing_verification_diagnostics.json'
$badVerify = Invoke-WinAgentJson @('plan-compile', '--input', $missingVerifyPath, '--output', $missingVerifyOut, '--diagnostics', $missingVerifyDiag) @(1)
$badVerifyDiag = Get-Content -LiteralPath $missingVerifyDiag -Raw | ConvertFrom-Json
if (-not $badVerify.json.ok -and $badVerifyDiag.compile_ok -eq $false -and $badVerifyDiag.error_code -eq 'COMPILE_MISSING_VERIFICATION_HINT') {
    Add-Result 'compile rejects missing verification_hint' 'PASS'
} else {
    Add-Result 'compile rejects missing verification_hint' 'FAIL' $badVerify.text
}

$directCoord = New-BasePlan 'unsafe_direct_coordinate'
$directCoord.steps[0].proposed_action = 'direct_coordinate_click'
$directCoord.steps[0].target_description = 'x=100,y=200'
$directCoord.steps[0].verification_hint = 'button clicked'
$directCoordPath = Write-JsonFile (Join-Path $SelftestRoot 'direct_coordinate_plan.json') $directCoord
$directCoordOut = Join-Path $SelftestRoot 'direct_coordinate_contract.json'
$directCoordDiag = Join-Path $SelftestRoot 'direct_coordinate_diagnostics.json'
$badCoord = Invoke-WinAgentJson @('plan-compile', '--input', $directCoordPath, '--output', $directCoordOut, '--diagnostics', $directCoordDiag) @(1)
$badCoordDiag = Get-Content -LiteralPath $directCoordDiag -Raw | ConvertFrom-Json
if (-not $badCoord.json.ok -and $badCoordDiag.compile_ok -eq $false -and $badCoordDiag.error_code -eq 'COMPILE_UNSAFE_DIRECT_COORDINATE') {
    Add-Result 'compile rejects unsafe direct coordinate' 'PASS'
} else {
    Add-Result 'compile rejects unsafe direct coordinate' 'FAIL' $badCoord.text
}

$status = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
@(
    '# v6.3.0 PlanCompiler Selftest Report',
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
    throw "plan compiler selftest failed: $($failures -join '; ')"
}

Write-Output 'PASS: v6.3.0 PlanCompiler selftest'
Write-Output "Report: $ReportPath"
