param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot

$Runner = Join-Path $Root 'v6_1_6_dynamic_app_web_full_access_runner.ps1'
$Verifier = Join-Path $Root 'v6_1_6_dynamic_app_web_full_access_verifier.ps1'
$Gate = Join-Path $Root 'v6_1_6_dynamic_app_web_full_access_acceptance_gate.ps1'

foreach ($path in @($Runner,$Verifier,$Gate)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing required script: $path" }
}

$runnerText = Get-Content -LiteralPath $Runner -Raw
$verifierText = Get-Content -LiteralPath $Verifier -Raw
$gateText = Get-Content -LiteralPath $Gate -Raw

$requiredRunnerTokens = @(
    'STOP_TARGET_SEMANTIC_MISMATCH',
    'FAIL_CLICKED_SENT_FOLDER_NOT_SEND_BUTTON',
    'send_target_verified_before_click',
    'clicked_target_is_compose_send_button',
    'qqmail_sent_folder_false_positive_negative'
)

$requiredVerifierTokens = @(
    'BLOCKED_QQMAIL_WRONG_SEND_TARGET',
    'clicked_target_text',
    'clicked_target_is_compose_send_button',
    'send_target_is_sidebar_or_folder',
    'send_target_verified_before_click'
)

$requiredGateTokens = @(
    'BLOCKED_QQMAIL_WRONG_SEND_TARGET',
    'qqmail_sent_folder_false_positive_negative'
)

$missing = New-Object System.Collections.Generic.List[string]
foreach ($token in $requiredRunnerTokens) {
    if ($runnerText -notmatch [regex]::Escape($token)) { $missing.Add("runner:$token") | Out-Null }
}
foreach ($token in $requiredVerifierTokens) {
    if ($verifierText -notmatch [regex]::Escape($token)) { $missing.Add("verifier:$token") | Out-Null }
}
foreach ($token in $requiredGateTokens) {
    if ($gateText -notmatch [regex]::Escape($token)) { $missing.Add("gate:$token") | Out-Null }
}

if ($missing.Count -gt 0) {
    Write-Host 'QQMAIL_SEND_TARGET_HOTFIX_SELFTEST_FAIL'
    $missing | ForEach-Object { Write-Host $_ }
    exit 1
}

Write-Host 'QQMAIL_SEND_TARGET_HOTFIX_SELFTEST_PASS'
exit 0
