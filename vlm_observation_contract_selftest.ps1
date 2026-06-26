param(
    [string]$Root = '',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.5.0_vlm_assisted_observation_contract'
$SelftestRoot = Join-Path $ArtifactRoot 'selftest\contract'
$ReportPath = Join-Path $ArtifactRoot 'vlm_observation_contract_schema.md'
New-Item -ItemType Directory -Force -Path $SelftestRoot | Out-Null

if (-not $SkipBuild) {
    & (Join-Path $Root 'build.ps1') -Root $Root
    if ($LASTEXITCODE -ne 0) { throw 'build failed' }
}

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "winagent.exe not found: $WinAgent"
}

function Write-JsonFile {
    param([string]$Path, [object]$Value)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $Value | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding UTF8
    return $Path
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

function New-ObserveFixture {
    param([bool]$ActiveProtection = $false, [bool]$CredentialRequired = $false, [object]$Region = $null)
    $fixture = [ordered]@{
        ok = $true
        command = 'observe'
        data = [ordered]@{
            target_window = [ordered]@{
                hwnd = '0x0000000000012345'
                title = 'DesktopVisual Mock Window'
                process_name = 'mock.exe'
                rect = [ordered]@{ left = 100; top = 120; right = 900; bottom = 720 }
            }
            screen_bounds = [ordered]@{ left = 0; top = 0; right = 1920; bottom = 1080 }
            screenshot = [ordered]@{
                path = Join-Path $SelftestRoot 'mock_screen.bmp'
                method = 'mock'
            }
            uia_text_summary = 'Submit button, Email field, Result area'
            ocr_text_summary = 'DesktopVisual Mock Submit Email Result'
            visible_text_hash = 'hash-contract-selftest'
            element_summary = @(
                [ordered]@{ element_id = 'uia-1'; label = 'Email'; role = 'Edit'; text = ''; bounds = [ordered]@{ left = 130; top = 180; right = 500; bottom = 220 } },
                [ordered]@{ element_id = 'uia-2'; label = 'Submit'; role = 'Button'; text = 'Submit'; bounds = [ordered]@{ left = 130; top = 240; right = 230; bottom = 280 } }
            )
            active_protection_detected = $ActiveProtection
            credential_required_detected = $CredentialRequired
        }
    }
    if ($Region) {
        $fixture.data.screenshot_region = $Region
    }
    return $fixture
}

$results = [System.Collections.Generic.List[object]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Result {
    param([string]$Name, [string]$Status, [string]$Detail = '')
    $results.Add([pscustomobject]@{ name = $Name; status = $Status; detail = $Detail }) | Out-Null
    if ($Status -ne 'PASS') { $failures.Add("${Name}: $Detail") | Out-Null }
}

$screenshot = Join-Path $SelftestRoot 'mock_screen.bmp'
Set-Content -LiteralPath $screenshot -Encoding Byte -Value @()

$observePath = Write-JsonFile (Join-Path $SelftestRoot 'observe_fixture.json') (New-ObserveFixture)
$requestPath = Join-Path $SelftestRoot 'request.json'
$build = Invoke-WinAgentJson @(
    'vlm-observation-build-request',
    '--observe-json', $observePath,
    '--screenshot', $screenshot,
    '--task-hint', 'find the submit button',
    '--expected-context', 'DesktopVisual Mock Window',
    '--observation-purpose', 'target_candidates_observation_only',
    '--output', $requestPath
)
$request = Get-Content -LiteralPath $requestPath -Raw | ConvertFrom-Json
if ($build.json.ok -and
    $request.request_created -eq $true -and
    $request.provider_role -eq 'assistive_only' -and
    $request.screenshot_path -eq $screenshot -and
    $request.uia_text_summary -and
    $request.ocr_text_summary -and
    $request.expected_context -and
    ($request.forbidden_outputs -contains 'direct_click') -and
    ($request.allowed_outputs -contains 'possible_targets') -and
    $request.blocked_context -eq $false) {
    Add-Result 'build observation request from observe JSON' 'PASS'
} else {
    Add-Result 'build observation request from observe JSON' 'FAIL' $build.text
}

$roiObservePath = Write-JsonFile (Join-Path $SelftestRoot 'observe_roi_fixture.json') (New-ObserveFixture -Region ([ordered]@{ left = 120; top = 150; right = 520; bottom = 360 }))
$roiRequestPath = Join-Path $SelftestRoot 'request_roi.json'
$roiBuild = Invoke-WinAgentJson @(
    'vlm-observation-build-request',
    '--observe-json', $roiObservePath,
    '--screenshot', $screenshot,
    '--task-hint', 'describe region',
    '--expected-context', 'DesktopVisual Mock Window',
    '--observation-purpose', 'layout_understanding',
    '--output', $roiRequestPath
)
$roiRequest = Get-Content -LiteralPath $roiRequestPath -Raw | ConvertFrom-Json
if ($roiBuild.json.ok -and
    $roiRequest.screenshot_region -and
    $roiRequest.screenshot_region.left -eq 120 -and
    $roiRequest.screenshot_region.right -eq 520 -and
    $roiRequest.roi_present -eq $true -and
    $roiRequest.roi_bounds_valid -eq $true) {
    Add-Result 'build ROI observation request' 'PASS'
} else {
    Add-Result 'build ROI observation request' 'FAIL' $roiBuild.text
}

$blockedObservePath = Write-JsonFile (Join-Path $SelftestRoot 'observe_active_protection_fixture.json') (New-ObserveFixture -ActiveProtection $true)
$blockedRequestPath = Join-Path $SelftestRoot 'request_active_protection.json'
$blockedBuild = Invoke-WinAgentJson @(
    'vlm-observation-build-request',
    '--observe-json', $blockedObservePath,
    '--screenshot', $screenshot,
    '--task-hint', 'summarize visible scene only',
    '--expected-context', 'active protection present',
    '--observation-purpose', 'scene_summary',
    '--output', $blockedRequestPath
)
$blockedRequest = Get-Content -LiteralPath $blockedRequestPath -Raw | ConvertFrom-Json
if ($blockedBuild.json.ok -and
    $blockedRequest.request_created -eq $true -and
    $blockedRequest.active_protection_detected -eq $true -and
    $blockedRequest.blocked_context -eq $true -and
    ($blockedRequest.forbidden_outputs -contains 'anti_cheat_evasion') -and
    ($blockedRequest.forbidden_outputs -contains 'captcha_solving')) {
    Add-Result 'build active-protection observation request' 'PASS'
} else {
    Add-Result 'build active-protection observation request' 'FAIL' $blockedBuild.text
}

$resultPath = Join-Path $SelftestRoot 'valid_result.json'
$mock = Invoke-WinAgentJson @(
    'vlm-observation-run-mock',
    '--allow-legacy-mock-vlm', 'true',
    '--request', $requestPath,
    '--scenario', 'valid',
    '--output', $resultPath
)
$result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
$targetsOk = $true
foreach ($target in $result.possible_targets) {
    if ($target.observation_only -ne $true -or $target.requires_runtime_validation -ne $true) {
        $targetsOk = $false
    }
}
if ($mock.json.ok -and
    $result.result_schema_valid -eq $true -and
    $result.provider_role -eq 'assistive_only' -and
    $result.contains_action -eq $false -and
    $result.contains_executable_instruction -eq $false -and
    $targetsOk) {
    Add-Result 'valid mock result follows VLMObservationResult schema' 'PASS'
} else {
    Add-Result 'valid mock result follows VLMObservationResult schema' 'FAIL' $mock.text
}

$status = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
@(
    '# v6.5.0 VLM Observation Contract Schema Report',
    '',
    "- Result: $status",
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "- WinAgent: $WinAgent",
    '',
    '## Results',
    '',
    '```json',
    ($results | ConvertTo-Json -Depth 100),
    '```'
) | Set-Content -LiteralPath $ReportPath -Encoding UTF8

if ($failures.Count -ne 0) {
    throw "VLM observation contract selftest failed: $($failures -join '; ')"
}

Write-Output 'PASS: v6.5.0 VLM observation contract selftest'
Write-Output "Report: $ReportPath"

