param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.1.4_runtime_guard_browser_normalization'
$VerifiedRoot = Join-Path $ArtifactRoot 'verified'
New-Item -ItemType Directory -Force -Path $VerifiedRoot | Out-Null

$verifierScript = Join-Path $Root 'v6_1_4_runtime_guard_verifier.ps1'
& powershell -NoProfile -ExecutionPolicy Bypass -File $verifierScript -Root $Root > (Join-Path $ArtifactRoot 'runtime_guard_acceptance_verifier.log') 2>&1
$verifierExit = $LASTEXITCODE

function Read-Json([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return $null }
}

$verifier = Read-Json (Join-Path $VerifiedRoot 'runtime_guard_verifier_result.json')
$accepted = ($verifierExit -eq 0 -and $verifier -and $verifier.status -eq 'PASS')
$status = if ($accepted) { 'PASS' } else { 'FAIL' }
$blockedCode = ''
if (-not $accepted -and $verifier -and $verifier.findings -and @($verifier.findings).Count -gt 0) {
    $blockedCode = [string](@($verifier.findings)[0].code)
}

$result = [pscustomobject]@{
    schema_version = 'v6.1.4.runtime_guard_acceptance_gate'
    generated_at = (Get-Date).ToString('o')
    status = $status
    accepted = $accepted
    blocked_code = $blockedCode
    current_trusted_version_allowed = if ($accepted) { '6.1.4' } else { '6.1.3' }
    ready_for_next_version_allowed = [bool]$accepted
    next_planned_version = if ($accepted) { '6.1.5' } else { '6.1.4-rerun' }
    dynamic_app_web_rerun_allowed = [bool]$accepted
    v6_2_allowed = $false
    verifier_exit_code = $verifierExit
    verifier_result = $verifier
}
$result | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $VerifiedRoot 'runtime_guard_acceptance_gate_result.json') -Encoding UTF8

@(
    '# v6.1.4 Runtime Guard Acceptance Gate',
    '',
    "- Result: $status",
    "- Accepted: $accepted",
    "- Blocked code: $blockedCode",
    "- current_trusted_version_allowed: $($result.current_trusted_version_allowed)",
    "- ready_for_next_version_allowed: $($result.ready_for_next_version_allowed)",
    "- dynamic_app_web_rerun_allowed: $($result.dynamic_app_web_rerun_allowed)",
    "- v6.2_allowed: False",
    '',
    'This gate does not treat PyCharm, WeChat, or QQ Mail diagnostics as acceptance blockers.'
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'acceptance_gate_report.md') -Encoding UTF8

if ($accepted) { exit 0 }
exit 1
