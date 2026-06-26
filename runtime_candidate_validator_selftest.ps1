param(
    [string]$Root = '',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.6.0_vlm_assisted_unknown_ui_candidate_handling'
$SelftestRoot = Join-Path $ArtifactRoot 'selftest\runtime_candidate_validator'
$ReportPath = Join-Path $ArtifactRoot 'runtime_candidate_validator_report.md'
New-Item -ItemType Directory -Force -Path $SelftestRoot | Out-Null

if (-not $SkipBuild) {
    & (Join-Path $Root 'build.ps1') -Root $Root
    if ($LASTEXITCODE -ne 0) { throw 'build failed' }
}
if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "winagent.exe not found: $WinAgent"
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

$cases = @(
    @{ name='valid_candidate'; scenario='valid'; target='Submit'; exit=0; ok=$true; expectedReason='' },
    @{ name='approx_region_candidate'; scenario='approximate_region_only'; target='Submit'; exit=0; ok=$true; expectedReason='' },
    @{ name='roi_candidate'; scenario='roi_candidate'; target='Submit'; exit=0; ok=$true; expectedReason=''; extra=@('--roi','true') },
    @{ name='multiple_candidates_one_unique'; scenario='multiple_one_unique'; target='Submit'; exit=0; ok=$true; expectedReason='' },
    @{ name='ambiguous_candidates'; scenario='ambiguous_candidates'; target='Submit'; exit=1; ok=$false; expectedReason='CANDIDATE_NOT_UNIQUE' },
    @{ name='offscreen_candidate'; scenario='offscreen_candidate'; target='Submit'; exit=1; ok=$false; expectedReason='CANDIDATE_OFFSCREEN' },
    @{ name='outside_viewport_candidate'; scenario='outside_viewport_candidate'; target='Submit'; exit=1; ok=$false; expectedReason='CANDIDATE_OUTSIDE_VIEWPORT' },
    @{ name='active_protection_region'; scenario='protection_region_candidate'; target='CAPTCHA Continue'; exit=1; ok=$false; expectedReason='CANDIDATE_ACTIVE_PROTECTION_REGION' },
    @{ name='credential_region'; scenario='credential_region_candidate'; target='Password'; exit=1; ok=$false; expectedReason='CANDIDATE_CREDENTIAL_REGION' },
    @{ name='hallucinated_target'; scenario='hallucinated_target'; target='Warp Drive'; exit=1; ok=$false; expectedReason='CANDIDATE_NO_RUNTIME_CORROBORATION' },
    @{ name='low_confidence_no_corroboration'; scenario='low_confidence_no_corroboration'; target='Ghost Action'; exit=1; ok=$false; expectedReason='CANDIDATE_LOW_CONFIDENCE' },
    @{ name='stale_observe_candidate'; scenario='valid'; target='Submit'; exit=1; ok=$false; expectedReason='CANDIDATE_STALE_OBSERVE'; extra=@('--stale-observe','true') }
)

$records = [System.Collections.Generic.List[object]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

foreach ($case in $cases) {
    $resultPath = Join-Path $SelftestRoot "$($case.name).json"
    $args = @(
        'vlm-assisted-locate-dry-run',
        '--allow-legacy-mock-vlm', 'true',
        '--target', $case.target,
        '--provider', 'mock',
        '--scenario', $case.scenario,
        '--result', $resultPath,
        '--evidence-dir', (Join-Path $SelftestRoot $case.name)
    )
    if ($case.extra) { $args += $case.extra }
    $run = Invoke-WinAgentJson -Arguments $args -AllowedExitCodes @(0,1)
    $payload = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    $validation = $payload.runtime_candidate_validation
    $reasons = @($validation.rejection_reasons)
    $record = [ordered]@{
        name = $case.name
        scenario = $case.scenario
        exit = $run.exit
        expected_exit = $case.exit
        candidate_validation_ok = $validation.candidate_validation_ok
        expected_ok = $case.ok
        candidate_count = $validation.candidate_count
        validated_candidate_count = $validation.validated_candidate_count
        rejected_candidate_count = $validation.rejected_candidate_count
        selected_candidate_unique = $validation.selected_candidate_unique
        rejection_reasons = $reasons
        result = $resultPath
    }
    $records.Add([pscustomobject]$record) | Out-Null
    if ($run.exit -ne $case.exit) { $failures.Add("$($case.name): exit $($run.exit), expected $($case.exit)") | Out-Null }
    if ($validation.candidate_validation_ok -ne $case.ok) { $failures.Add("$($case.name): candidate_validation_ok mismatch") | Out-Null }
    if ($case.expectedReason -and ($reasons -notcontains $case.expectedReason)) {
        $failures.Add("$($case.name): missing rejection $($case.expectedReason)") | Out-Null
    }
    if ($case.ok -and -not $payload.locator_candidate.created) {
        $failures.Add("$($case.name): locator candidate was not created after validation") | Out-Null
    }
    if ($case.ok -and $payload.locator_candidate.coordinate_source_type -ne 'vlm_assisted_runtime_validated') {
        $failures.Add("$($case.name): coordinate_source_type mismatch") | Out-Null
    }
}

$status = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
@(
    '# v6.6.0 RuntimeCandidateValidator Report',
    '',
    "- Result: $status",
    "- Cases: $($records.Count)",
    '',
    '```json',
    ($records | ConvertTo-Json -Depth 80),
    '```'
) | Set-Content -LiteralPath $ReportPath -Encoding UTF8

if ($failures.Count -ne 0) {
    throw "RuntimeCandidateValidator selftest failed: $($failures -join '; ')"
}

Write-Output 'PASS: v6.6.0 RuntimeCandidateValidator selftest'
Write-Output "Report: $ReportPath"
