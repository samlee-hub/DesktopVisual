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
$SelftestRoot = Join-Path $ArtifactRoot 'selftest\locator_candidate'
$ReportPath = Join-Path $ArtifactRoot 'locator_candidate_conversion_report.md'
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

$positivePath = Join-Path $SelftestRoot 'positive_locator_candidate.json'
$positive = Invoke-WinAgentJson @(
    'vlm-assisted-locate-dry-run',
    '--allow-legacy-mock-vlm', 'true',
    '--target', 'Submit',
    '--provider', 'mock',
    '--scenario', 'valid',
    '--result', $positivePath,
    '--evidence-dir', (Join-Path $SelftestRoot 'positive')
)
$positivePayload = Get-Content -LiteralPath $positivePath -Raw | ConvertFrom-Json
$candidate = $positivePayload.locator_candidate

$negativePath = Join-Path $SelftestRoot 'negative_no_conversion.json'
$negative = Invoke-WinAgentJson -Arguments @(
    'vlm-assisted-locate-dry-run',
    '--allow-legacy-mock-vlm', 'true',
    '--target', 'Warp Drive',
    '--provider', 'mock',
    '--scenario', 'hallucinated_target',
    '--result', $negativePath,
    '--evidence-dir', (Join-Path $SelftestRoot 'negative')
) -AllowedExitCodes @(1)
$negativePayload = Get-Content -LiteralPath $negativePath -Raw | ConvertFrom-Json

$failures = [System.Collections.Generic.List[string]]::new()
if ($positive.exit -ne 0) { $failures.Add('positive conversion command did not exit 0') | Out-Null }
if ($positivePayload.runtime_candidate_validated -ne $true) { $failures.Add('positive runtime_candidate_validated not true') | Out-Null }
if ($positivePayload.locator_candidate_created -ne $true) { $failures.Add('positive locator_candidate_created not true') | Out-Null }
if ($candidate.created -ne $true) { $failures.Add('locator candidate created flag not true') | Out-Null }
if ($candidate.candidate_source -ne 'vlm_assisted_runtime_validated') { $failures.Add('candidate_source mismatch') | Out-Null }
if (-not $candidate.source_request_id) { $failures.Add('source_request_id missing') | Out-Null }
if (-not $candidate.source_result_id) { $failures.Add('source_result_id missing') | Out-Null }
if (-not $candidate.source_candidate_id) { $failures.Add('source_candidate_id missing') | Out-Null }
if ($candidate.runtime_validation_ok -ne $true) { $failures.Add('runtime_validation_ok not true') | Out-Null }
if (-not $candidate.runtime_validation_method) { $failures.Add('runtime_validation_method missing') | Out-Null }
if ($candidate.requires_final_guard_check -ne $true) { $failures.Add('requires_final_guard_check not true') | Out-Null }
if ($candidate.requires_mouse_first_evidence -ne $true) { $failures.Add('requires_mouse_first_evidence not true') | Out-Null }
if ($candidate.requires_post_action_verification -ne $true) { $failures.Add('requires_post_action_verification not true') | Out-Null }
if ($candidate.coordinate_source_type -ne 'vlm_assisted_runtime_validated') { $failures.Add('coordinate_source_type mismatch') | Out-Null }
if ($candidate.target_center.x -le 0 -or $candidate.target_center.y -le 0) { $failures.Add('target center was not recomputed') | Out-Null }
if ($candidate.selector -notmatch '^coord:x=\d+,y=\d+$') { $failures.Add('locator selector was not a runtime-computed coord selector') | Out-Null }

if ($negative.exit -ne 1) { $failures.Add('negative conversion command did not exit 1') | Out-Null }
if ($negativePayload.runtime_candidate_validated -ne $false) { $failures.Add('negative runtime_candidate_validated not false') | Out-Null }
if ($negativePayload.locator_candidate.created -ne $false) { $failures.Add('invalid candidate converted to LocatorCandidate') | Out-Null }
if ($negativePayload.locator_candidate_created -ne $false) { $failures.Add('negative locator_candidate_created not false') | Out-Null }

$status = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
@(
    '# v6.6.0 LocatorCandidate Conversion Report',
    '',
    "- Result: $status",
    "- Positive result: $positivePath",
    "- Negative result: $negativePath",
    '',
    '## Positive LocatorCandidate',
    '',
    '```json',
    ($candidate | ConvertTo-Json -Depth 60),
    '```'
) | Set-Content -LiteralPath $ReportPath -Encoding UTF8

if ($failures.Count -ne 0) {
    throw "VLM LocatorCandidate conversion selftest failed: $($failures -join '; ')"
}

Write-Output 'PASS: v6.6.0 VLM LocatorCandidate conversion selftest'
Write-Output "Report: $ReportPath"
