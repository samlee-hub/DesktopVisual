param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\recovery_safe_stop_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates v5.2.4 SafeStop and blocked handling.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.2.4'
$Report = Join-Path $ArtifactDir 'recovery_safe_stop_selftest_report.md'
$Blocked = Join-Path $Root 'tasks\recovery_policy\blocked_scene_captcha.json'
$Policy = Join-Path $Root 'tasks\recovery_policy\valid_standard_recovery_policy.json'

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null
Get-Content -LiteralPath $Blocked -Raw | ConvertFrom-Json | Out-Null

$outputs = New-Object System.Collections.Generic.List[string]
foreach ($reason in @('captcha', 'anti_cheat', 'proctoring', 'payment', 'credential_security_challenge', 'game_automation', 'real_exam_public_profile', 'SAFETY_DENIED')) {
    $output = & $WinAgent safe-stop-check --reason $reason --context $Blocked
    if ($LASTEXITCODE -ne 0) {
        throw "safe-stop-check failed for $reason. Output: $output"
    }
    $json = $output | ConvertFrom-Json
    if (-not $json.ok) { throw "safe-stop-check returned ok=false for $reason" }
    if (-not $json.data.safe_stop) { throw "Expected safe_stop=true for $reason" }
    if ($json.data.recovery_allowed) { throw "Expected recovery_allowed=false for $reason" }
    if ($json.data.escalation_allowed) { throw "Expected escalation_allowed=false for $reason" }
    if ($json.data.recommended_action -ne 'stop') { throw "Expected recommended_action=stop for $reason" }
    $outputs.Add($output) | Out-Null
}

$recoveryOutput = & $WinAgent recovery-evaluate --policy $Policy --failure-reason SAFETY_DENIED --context $Blocked --attempt 1
if ($LASTEXITCODE -eq 0) {
    throw "SAFETY_DENIED must not be recoverable. Output: $recoveryOutput"
}
$recoveryJson = $recoveryOutput | ConvertFrom-Json
if ($recoveryJson.error.code -ne 'RECOVERY_REQUIRES_ESCALATION_OR_STOP') {
    throw "Unexpected SAFETY_DENIED recovery error: $($recoveryJson.error.code)"
}
if ($recoveryJson.data.next_action -ne 'stop') {
    throw 'SAFETY_DENIED recovery must recommend stop.'
}

$escalationOutput = & $WinAgent escalation-request-create --reason safety_denied --task local_form_fill_submit_mock --step click_submit_and_verify --context $Blocked
if ($LASTEXITCODE -ne 0) {
    throw "safety_denied escalation request failed. Output: $escalationOutput"
}
$escalationJson = $escalationOutput | ConvertFrom-Json
if ($escalationJson.data.recommended_action -ne 'stop') { throw 'safety_denied escalation must recommend stop.' }
if ($escalationJson.data.allowed_routes -contains 'escalate_to_agent') { throw 'safety_denied must not allow escalate_to_agent.' }
if ($escalationJson.data.allowed_routes -contains 'ask_user') { throw 'safety_denied must not ask user as bypass route.' }

$lines = @(
    '# v5.2.4 SafeStop Selftest Report',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    '- blocked scene mock: PASS',
    '- SAFETY_DENIED no recovery: PASS',
    '- no escalation bypass: PASS',
    '',
    '## Outputs',
    '',
    '```json'
) + $outputs + @(
    $recoveryOutput,
    $escalationOutput,
    '```'
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.2.4 SafeStop selftest'
Write-Host "Report: $Report"
