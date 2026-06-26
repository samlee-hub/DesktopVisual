param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.1.5_safe_context_recovery_dynamic_diagnostics'
$VerifiedRoot = Join-Path $ArtifactRoot 'verified\safe_context_recovery'
New-Item -ItemType Directory -Force -Path $VerifiedRoot | Out-Null

$verifierScript = Join-Path $Root 'v6_1_5_safe_context_recovery_verifier.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifierScript -Root $Root > (Join-Path $ArtifactRoot 'safe_context_recovery_gate_verifier.log') 2>&1
$verifierExit = $LASTEXITCODE

function Read-Json([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return $null }
}

$verifier = Read-Json (Join-Path $VerifiedRoot 'safe_context_recovery_verifier_result.json')
$findings = New-Object System.Collections.Generic.List[object]
function Add-Finding([string]$Code, [string]$Message, [string]$Path = '') {
    $findings.Add([pscustomobject]@{ code = $Code; message = $Message; path = $Path; blocking = $true }) | Out-Null
}

if ($verifierExit -ne 0 -or -not $verifier -or $verifier.status -ne 'PASS') {
    Add-Finding 'BLOCKED_SAFE_CONTEXT_RECOVERY_FAILED' 'Safe context recovery verifier did not PASS.' 'verified\safe_context_recovery\safe_context_recovery_verifier_result.json'
}

$v612 = Read-Json (Join-Path $Root 'artifacts\dev6.1.2_real_ui_baseline_sanity_pre_v6_2_gate\verified\pre_v6_2_acceptance_gate_result.json')
if (-not $v612 -or $v612.accepted -ne $true) {
    Add-Finding 'BLOCKED_PREVIOUS_GATE_REGRESSION' 'v6.1.2 gate is not accepted=true.' 'artifacts\dev6.1.2_real_ui_baseline_sanity_pre_v6_2_gate\verified\pre_v6_2_acceptance_gate_result.json'
}
$v613 = Read-Json (Join-Path $Root 'artifacts\dev6.1.3_mouse_wheel_scroll_and_scroll_locate\verified\scroll_acceptance_gate_result.json')
if (-not $v613 -or $v613.status -ne 'PASS') {
    Add-Finding 'BLOCKED_PREVIOUS_GATE_REGRESSION' 'v6.1.3 scroll gate is not PASS.' 'artifacts\dev6.1.3_mouse_wheel_scroll_and_scroll_locate\verified\scroll_acceptance_gate_result.json'
}
$v614 = Read-Json (Join-Path $Root 'artifacts\dev6.1.4_runtime_guard_browser_normalization\verified\runtime_guard_acceptance_gate_result.json')
if (-not $v614 -or $v614.status -ne 'PASS') {
    $v614 = Read-Json (Join-Path $Root 'artifacts\dev6.1.4_runtime_guard_browser_stabilization\final_status_report.json')
}
if (-not (Test-Path -LiteralPath (Join-Path $Root 'artifacts\dev6.1.4_runtime_guard_browser_stabilization\final_status_report.md'))) {
    Add-Finding 'BLOCKED_PREVIOUS_GATE_REGRESSION' 'v6.1.4 final status report is missing.' 'artifacts\dev6.1.4_runtime_guard_browser_stabilization\final_status_report.md'
}

$accepted = $findings.Count -eq 0
$result = [pscustomobject]@{
    schema_version = 'v6.1.5.safe_context_recovery.acceptance_gate'
    generated_at = (Get-Date).ToString('o')
    status = if ($accepted) { 'PASS' } else { 'FAIL' }
    accepted = [bool]$accepted
    verifier_exit_code = $verifierExit
    v6_2_allowed = $false
    dynamic_diagnostics_required_before_version_promotion = $true
    findings = @($findings.ToArray())
    verifier_result = $verifier
}
$resultPath = Join-Path $VerifiedRoot 'safe_context_recovery_acceptance_gate_result.json'
$result | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $resultPath -Encoding UTF8

$findingRows = @($findings.ToArray()) | ForEach-Object {
    '- [{0}] {1} `{2}`' -f $_.code, $_.message, $_.path
}
$gateReportLines = @(
    '# v6.1.5 Safe Context Recovery Acceptance Gate',
    '',
    "- Result: $($result.status)",
    "- Accepted: $($result.accepted)",
    '- Dynamic diagnostics still required before v6.1.5 version promotion.',
    '- v6.2 allowed: false',
    '',
    '## Findings'
) + @($findingRows)
$gateReportLines | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'v6_1_5_safe_context_recovery_acceptance_gate_report.md') -Encoding UTF8

if ($accepted) { exit 0 }
exit 1
