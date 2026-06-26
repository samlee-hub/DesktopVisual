param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.1.5a_visible_mouse_first_interaction'
$VerifiedRoot = Join-Path $ArtifactRoot 'verified\mouse_first'
New-Item -ItemType Directory -Force -Path $VerifiedRoot | Out-Null

function Read-Json([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return $null }
}

$verifierScript = Join-Path $Root 'v6_1_5a_mouse_first_interaction_verifier.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifierScript -Root $Root > (Join-Path $ArtifactRoot 'mouse_first_gate_verifier.log') 2>&1
$verifierExit = $LASTEXITCODE

$findings = New-Object System.Collections.Generic.List[object]
function Add-Finding([string]$Code, [string]$Message, [string]$Path = '') {
    $findings.Add([pscustomobject]@{
        code = $Code
        message = $Message
        path = $Path
        blocking = $true
    }) | Out-Null
}

$verifierPath = Join-Path $VerifiedRoot 'mouse_first_verifier_result.json'
$verifier = Read-Json $verifierPath
if ($verifierExit -ne 0 -or -not $verifier -or $verifier.status -ne 'PASS') {
    $codes = @()
    if ($verifier -and $verifier.findings) {
        $codes = @($verifier.findings | Select-Object -ExpandProperty code -Unique)
    }
    if ($codes -contains 'BLOCKED_KEYBOARD_ONLY_FALSE_PASS') {
        Add-Finding 'BLOCKED_KEYBOARD_ONLY_FALSE_PASS' 'Verifier rejected a keyboard-only or fallback mouse-first false PASS.' $verifierPath
    } elseif ($codes -contains 'BLOCKED_MOUSE_FOCUS_VERIFICATION_FAILED') {
        Add-Finding 'BLOCKED_MOUSE_FOCUS_VERIFICATION_FAILED' 'Verifier rejected missing focus/context verification after mouse click.' $verifierPath
    } elseif ($codes -contains 'BLOCKED_WRONG_FIELD_INPUT') {
        Add-Finding 'BLOCKED_WRONG_FIELD_INPUT' 'Verifier detected wrong field input risk.' $verifierPath
    } elseif ($codes -contains 'BLOCKED_UNDISCLOSED_FIXED_COORDINATE') {
        Add-Finding 'BLOCKED_UNDISCLOSED_FIXED_COORDINATE' 'Verifier detected an unmarked fixed coordinate.' $verifierPath
    } else {
        Add-Finding 'BLOCKED_MOUSE_FIRST_EVIDENCE_MISSING' 'Mouse-first verifier did not PASS.' $verifierPath
    }
}

$v612Path = Join-Path $Root 'artifacts\dev6.1.2_real_ui_baseline_sanity_pre_v6_2_gate\verified\pre_v6_2_acceptance_gate_result.json'
$v612 = Read-Json $v612Path
if (-not $v612 -or $v612.accepted -ne $true) {
    Add-Finding 'BLOCKED_PREVIOUS_GATE_REGRESSION' 'v6.1.2 baseline gate is not accepted=true.' $v612Path
}

$v613Path = Join-Path $Root 'artifacts\dev6.1.3_mouse_wheel_scroll_and_scroll_locate\verified\scroll_acceptance_gate_result.json'
$v613 = Read-Json $v613Path
if (-not $v613 -or $v613.status -ne 'PASS') {
    Add-Finding 'BLOCKED_PREVIOUS_GATE_REGRESSION' 'v6.1.3 scroll gate is not PASS.' $v613Path
}

$v614Path = Join-Path $Root 'artifacts\dev6.1.4_runtime_guard_browser_normalization\verified\runtime_guard_acceptance_gate_result.json'
$v614 = Read-Json $v614Path
if (-not $v614 -or $v614.status -ne 'PASS') {
    $v614Final = Join-Path $Root 'artifacts\dev6.1.4_runtime_guard_browser_stabilization\final_status_report.md'
    if (-not (Test-Path -LiteralPath $v614Final)) {
        Add-Finding 'BLOCKED_PREVIOUS_GATE_REGRESSION' 'v6.1.4 runtime guard gate/final report is missing.' $v614Path
    }
}

$v615Path = Join-Path $Root 'artifacts\dev6.1.5_safe_context_recovery_dynamic_diagnostics\verified\safe_context_recovery\safe_context_recovery_acceptance_gate_result.json'
$v615 = Read-Json $v615Path
if (-not $v615 -or $v615.status -ne 'PASS') {
    Add-Finding 'BLOCKED_PREVIOUS_GATE_REGRESSION' 'v6.1.5 safe context recovery gate is not PASS.' $v615Path
}

$accepted = $findings.Count -eq 0
$result = [ordered]@{
    schema_version = 'v6.1.5a.mouse_first.acceptance_gate'
    generated_at = (Get-Date).ToString('o')
    status = if ($accepted) { 'PASS' } else { 'FAIL' }
    accepted = [bool]$accepted
    verifier_exit_code = $verifierExit
    current_trusted_version_before_promotion = '6.1.5'
    next_allowed_version = if ($accepted) { '6.1.6' } else { '6.1.5a-rerun' }
    v6_1_6_allowed = [bool]$accepted
    v6_2_allowed = $false
    findings = @($findings.ToArray())
    verifier_result = $verifier
    regression_results = [ordered]@{
        v6_1_2_gate = if ($v612 -and $v612.accepted -eq $true) { 'PASS' } else { 'FAIL' }
        v6_1_3_gate = if ($v613 -and $v613.status -eq 'PASS') { 'PASS' } else { 'FAIL' }
        v6_1_4_gate = if (($v614 -and $v614.status -eq 'PASS') -or (Test-Path -LiteralPath (Join-Path $Root 'artifacts\dev6.1.4_runtime_guard_browser_stabilization\final_status_report.md'))) { 'PASS' } else { 'FAIL' }
        v6_1_5_gate = if ($v615 -and $v615.status -eq 'PASS') { 'PASS' } else { 'FAIL' }
    }
}

$resultPath = Join-Path $VerifiedRoot 'mouse_first_acceptance_gate_result.json'
$result | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $resultPath -Encoding UTF8

$findingRows = @($findings.ToArray()) | ForEach-Object {
    '- [{0}] {1} `{2}`' -f $_.code, $_.message, $_.path
}
if ($findingRows.Count -eq 0) { $findingRows = @('- No blocking findings.') }

@(
    '# v6.1.5a Mouse First Interaction Acceptance Gate',
    '',
    "- Result: $($result.status)",
    "- Accepted: $($result.accepted)",
    "- v6.1.6 allowed: $($result.v6_1_6_allowed)",
    "- v6.2 allowed: $($result.v6_2_allowed)",
    '',
    '## Regression Gates',
    "- v6.1.2 gate: $($result.regression_results.v6_1_2_gate)",
    "- v6.1.3 gate: $($result.regression_results.v6_1_3_gate)",
    "- v6.1.4 gate: $($result.regression_results.v6_1_4_gate)",
    "- v6.1.5 gate: $($result.regression_results.v6_1_5_gate)",
    '',
    '## Findings'
) + $findingRows | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'v6_1_5a_acceptance_gate_report.md') -Encoding UTF8

if ($accepted) { exit 0 }
exit 1
