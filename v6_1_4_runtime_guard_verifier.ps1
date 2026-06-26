param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.1.4_runtime_guard_browser_normalization'
$VerifiedRoot = Join-Path $ArtifactRoot 'verified'
New-Item -ItemType Directory -Force -Path $VerifiedRoot | Out-Null

function Read-Json([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return $null }
}

$findings = New-Object System.Collections.Generic.List[object]
function Add-Finding([string]$Code, [string]$Message, [string]$Path = '') {
    $findings.Add([pscustomobject]@{ code = $Code; message = $Message; path = $Path; blocking = $true }) | Out-Null
}

$runtime = Read-Json (Join-Path $ArtifactRoot 'runtime_context_guard_selftest_summary.json')
if (-not $runtime -or $runtime.status -ne 'PASS') { Add-Finding 'RUNTIME_CONTEXT_GUARD_SELFTEST_FAILED' 'runtime_context_guard_selftest_summary.json is missing or not PASS.' 'runtime_context_guard_selftest_summary.json' }

$browser = Read-Json (Join-Path $ArtifactRoot 'browser_surface_normalization_selftest_summary.json')
if (-not $browser -or $browser.status -ne 'PASS') { Add-Finding 'BROWSER_SURFACE_NORMALIZATION_SELFTEST_FAILED' 'browser_surface_normalization_selftest_summary.json is missing or not PASS.' 'browser_surface_normalization_selftest_summary.json' }

$baselineGate = Read-Json (Join-Path $Root 'artifacts\dev6.1.2_real_ui_baseline_sanity_pre_v6_2_gate\verified\pre_v6_2_acceptance_gate_result.json')
if (-not $baselineGate -or $baselineGate.accepted -ne $true) { Add-Finding 'BLOCKED_BASELINE_WRONG_CONTEXT' 'v6.1.2 baseline acceptance is not accepted=true.' 'artifacts\dev6.1.2_real_ui_baseline_sanity_pre_v6_2_gate\verified\pre_v6_2_acceptance_gate_result.json' }

$scrollGate = Read-Json (Join-Path $Root 'artifacts\dev6.1.3_mouse_wheel_scroll_and_scroll_locate\verified\scroll_acceptance_gate_result.json')
if (-not $scrollGate -or $scrollGate.status -ne 'PASS') {
    $failureType = if ($scrollGate) { [string]$scrollGate.scroll_gate_failure_type } else { 'MISSING' }
    Add-Finding 'BLOCKED_SCROLL_GATE_BASELINE_REPLAY' "v6.1.3 scroll gate is not PASS. failure_type=$failureType" 'artifacts\dev6.1.3_mouse_wheel_scroll_and_scroll_locate\verified\scroll_acceptance_gate_result.json'
}

$rerun = Read-Json (Join-Path $ArtifactRoot 'runtime_guard_rerun_summary.json')
if (-not $rerun) { Add-Finding 'MISSING_RERUN_SUMMARY' 'runtime_guard_rerun_summary.json is missing.' 'runtime_guard_rerun_summary.json' }
elseif ($rerun.status -ne 'PASS') { Add-Finding 'RUNTIME_GUARD_RERUN_FAILED' 'runtime_guard_rerun_summary.json is not PASS.' 'runtime_guard_rerun_summary.json' }

$allPass = $findings.Count -eq 0
$result = [pscustomobject]@{
    schema_version = 'v6.1.4.runtime_guard_verifier'
    generated_at = (Get-Date).ToString('o')
    status = if ($allPass) { 'PASS' } else { 'FAIL' }
    runtime_context_guard_selftest = if ($runtime) { $runtime.status } else { 'MISSING' }
    browser_surface_normalization_selftest = if ($browser) { $browser.status } else { 'MISSING' }
    v6_1_2_baseline_accepted = if ($baselineGate) { [bool]$baselineGate.accepted } else { $false }
    v6_1_3_scroll_gate_status = if ($scrollGate) { [string]$scrollGate.status } else { 'MISSING' }
    runtime_guard_rerun_status = if ($rerun) { [string]$rerun.status } else { 'MISSING' }
    findings = @($findings.ToArray())
}
$resultPath = Join-Path $VerifiedRoot 'runtime_guard_verifier_result.json'
$result | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $resultPath -Encoding UTF8

@(
    '# v6.1.4 Runtime Guard Verifier',
    '',
    "- Result: $($result.status)",
    "- Runtime context guard selftest: $($result.runtime_context_guard_selftest)",
    "- Browser surface normalization selftest: $($result.browser_surface_normalization_selftest)",
    "- v6.1.2 baseline accepted: $($result.v6_1_2_baseline_accepted)",
    "- v6.1.3 scroll gate status: $($result.v6_1_3_scroll_gate_status)",
    "- Runtime guard rerun status: $($result.runtime_guard_rerun_status)",
    '',
    '## Findings'
) + (@($findings.ToArray()) | ForEach-Object { '- [{0}] {1} `{2}`' -f $_.code, $_.message, $_.path }) |
    Set-Content -LiteralPath (Join-Path $ArtifactRoot 'runtime_guard_verifier_report.md') -Encoding UTF8

if ($allPass) { exit 0 }
exit 1
