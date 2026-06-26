param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\recovery_retry_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates v5.2.2 low-risk retry/wait recovery decisions.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.2.2'
$Report = Join-Path $ArtifactDir 'recovery_retry_selftest_report.md'
$Policy = Join-Path $Root 'tasks\recovery_policy\valid_standard_recovery_policy.json'
$DelayedButton = Join-Path $Root 'tasks\recovery_policy\delayed_button_not_ready.json'
$DelayedText = Join-Path $Root 'tasks\recovery_policy\delayed_text_missing.json'
$StaleCandidate = Join-Path $Root 'tasks\recovery_policy\stale_candidate_context.json'

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

foreach ($path in @($Policy, $DelayedButton, $DelayedText, $StaleCandidate)) {
    Get-Content -LiteralPath $path -Raw | ConvertFrom-Json | Out-Null
}

function Invoke-Recovery {
    param(
        [string]$FailureReason,
        [string]$Context,
        [string]$ExpectedStrategy,
        [string]$ExpectedAction
    )
    $output = & $WinAgent recovery-evaluate --policy $Policy --failure-reason $FailureReason --context $Context --attempt 1
    if ($LASTEXITCODE -ne 0) {
        throw "recovery-evaluate failed for $FailureReason. Output: $output"
    }
    $json = $output | ConvertFrom-Json
    if (-not $json.ok) { throw "recovery-evaluate returned ok=false for $FailureReason" }
    if ($json.data.strategy -ne $ExpectedStrategy) { throw "Expected $ExpectedStrategy for $FailureReason, got $($json.data.strategy)" }
    if ($json.data.next_action -ne $ExpectedAction) { throw "Expected $ExpectedAction for $FailureReason, got $($json.data.next_action)" }
    if (-not $json.data.audit_record.recovery_attempt_id) { throw "Missing audit recovery_attempt_id for $FailureReason" }
    if (-not $json.data.safe_to_retry) { throw "Expected safe_to_retry=true for $FailureReason" }
    return $output
}

$buttonOutput = Invoke-Recovery -FailureReason 'TARGET_NOT_READY' -Context $DelayedButton -ExpectedStrategy 'wait_and_retry' -ExpectedAction 'wait'
$textOutput = Invoke-Recovery -FailureReason 'TEXT_NOT_FOUND' -Context $DelayedText -ExpectedStrategy 're_observe' -ExpectedAction 're_observe'
$locatorOutput = Invoke-Recovery -FailureReason 'LOCATOR_NOT_FOUND' -Context $DelayedText -ExpectedStrategy 're_locate' -ExpectedAction 're_locate'
$cacheOutput = Invoke-Recovery -FailureReason 'STALE_CANDIDATE' -Context $StaleCandidate -ExpectedStrategy 'invalidate_cache' -ExpectedAction 'invalidate_cache'
$cacheJson = $cacheOutput | ConvertFrom-Json
if (-not $cacheJson.data.cache_invalidated) { throw 'Expected cache_invalidated=true for STALE_CANDIDATE.' }

$lines = @(
    '# v5.2.2 Recovery Retry Selftest Report',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    '- TARGET_NOT_READY -> wait_and_retry: PASS',
    '- TEXT_NOT_FOUND -> re_observe: PASS',
    '- LOCATOR_NOT_FOUND -> re_locate: PASS',
    '- STALE_CANDIDATE -> invalidate_cache: PASS',
    '',
    '## Outputs',
    '',
    '```json',
    $buttonOutput,
    $textOutput,
    $locatorOutput,
    $cacheOutput,
    '```'
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.2.2 Recovery retry selftest'
Write-Host "Report: $Report"
