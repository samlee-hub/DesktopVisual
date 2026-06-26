param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.10.0_experience_memory_failure_attribution\selftests\failure_attribution_normalizer'
$ReportPath = Join-Path $OutDir 'failure_attribution_normalizer_selftest_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$cases = @(
    @{ name='browser_missing_field'; code='FAIL_FIELD_NOT_FOUND'; result='failed'; category='LOCATOR_FAILURE' },
    @{ name='target_not_unique'; code='STOP_TARGET_NOT_UNIQUE'; result='blocked'; category='LOCATOR_FAILURE' },
    @{ name='active_protection'; code='STOP_ACTIVE_PROTECTION_OR_LOGIN_BLOCK'; result='stopped'; category='ACTIVE_PROTECTION' },
    @{ name='credential_required'; code='STOP_CREDENTIAL_REQUIRED'; result='stopped'; category='CREDENTIAL_REQUIRED' },
    @{ name='verify_move_failed'; code='VERIFY_MOVE_FAILED'; result='failed'; category='EXECUTION_VERIFICATION_FAILED' },
    @{ name='surface_blocked'; code='environment/surface-blocked'; result='blocked'; category='ENVIRONMENT_BLOCKED' },
    @{ name='raw_completed_unverified'; code='RAW_COMPLETED_UNVERIFIED'; result='raw_completed_unverified'; category='EVIDENCE_MISSING' },
    @{ name='unknown_failure'; code='UNSEEN_NEW_FAILURE_CODE'; result='failed'; category='UNKNOWN_FAILURE' }
)

$rows = @()
foreach ($case in $cases) {
    $out = Join-Path $OutDir "$($case.name).json"
    $cmd = & $WinAgent failure-attribution-normalize --workflow-type browser_form --execution-result $case.result --failure-code $case.code --output $out 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "failure-attribution-normalize failed for $($case.name): $($cmd | Out-String)"
    }
    $json = Get-Content -Raw -LiteralPath $out | ConvertFrom-Json
    if ($json.normalized_failure_category -ne $case.category) {
        throw "$($case.name) expected $($case.category), got $($json.normalized_failure_category)"
    }
    if ($case.name -eq 'unknown_failure' -and $json.safe_for_success -ne $false) {
        throw 'Unknown failure must not be safe_for_success'
    }
    $rows += "- $($case.name): $($json.normalized_failure_category)"
}

Set-Content -LiteralPath $ReportPath -Encoding UTF8 -Value @"
# Failure Attribution Normalizer Selftest

- status: PASS
- ui_workflow_executed: false
- unknown_failure_maps_to_success: false

## Cases

$($rows -join "`n")
"@
Write-Host 'failure_attribution_normalizer_selftest PASS'
