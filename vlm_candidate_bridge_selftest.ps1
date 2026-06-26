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
$SelftestRoot = Join-Path $ArtifactRoot 'selftest\bridge'
$ReportPath = Join-Path $ArtifactRoot 'vlm_candidate_bridge_design.md'
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

$resultPath = Join-Path $SelftestRoot 'bridge_dry_run_result.json'
$run = Invoke-WinAgentJson @(
    'vlm-assisted-locate-dry-run',
    '--allow-legacy-mock-vlm', 'true',
    '--target', 'Submit',
    '--provider', 'mock',
    '--scenario', 'valid',
    '--result', $resultPath
)

$payload = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
$data = $run.json.data
$bridge = $payload.bridge_result
$candidate = $payload.locator_candidate

$failures = [System.Collections.Generic.List[string]]::new()
if ($data.runtime_locator_failed -ne $true) { $failures.Add('runtime_locator_failed was not true') | Out-Null }
if ($data.vlm_bridge_invoked -ne $true) { $failures.Add('vlm_bridge_invoked was not true') | Out-Null }
if ($data.vlm_result_validated -ne $true) { $failures.Add('vlm_result_validated was not true') | Out-Null }
if ($data.runtime_candidate_validated -ne $true) { $failures.Add('runtime_candidate_validated was not true') | Out-Null }
if ($data.locator_candidate_created -ne $true) { $failures.Add('locator_candidate_created was not true') | Out-Null }
if ($data.runtime_executed -ne $false) { $failures.Add('runtime_executed was not false for dry-run') | Out-Null }
if ($bridge.bridge_invoked -ne $true) { $failures.Add('bridge_result.bridge_invoked was not true') | Out-Null }
if ($bridge.runtime_execution_allowed -ne $true) { $failures.Add('bridge_result.runtime_execution_allowed was not true') | Out-Null }
if ($bridge.candidate_validation_required -ne $true) { $failures.Add('candidate_validation_required was not true') | Out-Null }
if ($candidate.candidate_source -ne 'vlm_assisted_runtime_validated') { $failures.Add('locator candidate source was not vlm_assisted_runtime_validated') | Out-Null }
if ($candidate.requires_final_guard_check -ne $true) { $failures.Add('requires_final_guard_check was not true') | Out-Null }
if ($candidate.requires_mouse_first_evidence -ne $true) { $failures.Add('requires_mouse_first_evidence was not true') | Out-Null }
if ($candidate.coordinate_source_type -ne 'vlm_assisted_runtime_validated') { $failures.Add('coordinate_source_type mismatch') | Out-Null }

$status = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
@(
    '# v6.6.0 VLM Candidate Bridge Design And Selftest Report',
    '',
    "- Result: $status",
    "- Runtime locator failed before bridge: $($data.runtime_locator_failed)",
    "- VLM bridge invoked: $($data.vlm_bridge_invoked)",
    "- VLM result validated: $($data.vlm_result_validated)",
    "- Runtime candidate validated: $($data.runtime_candidate_validated)",
    "- LocatorCandidate created: $($data.locator_candidate_created)",
    "- Runtime executed: $($data.runtime_executed)",
    "- Result path: $resultPath",
    ''
) | Set-Content -LiteralPath $ReportPath -Encoding UTF8

if ($failures.Count -ne 0) {
    throw "VLM candidate bridge selftest failed: $($failures -join '; ')"
}

Write-Output 'PASS: v6.6.0 VLM candidate bridge selftest'
Write-Output "Report: $ReportPath"
