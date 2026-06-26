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
$SelftestRoot = Join-Path $ArtifactRoot 'selftest\mock_provider'
$ReportPath = Join-Path $ArtifactRoot 'mock_provider_report.md'
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

$screenshot = Join-Path $SelftestRoot 'mock_screen.bmp'
Set-Content -LiteralPath $screenshot -Encoding Byte -Value @()
$observePath = Write-JsonFile (Join-Path $SelftestRoot 'observe_fixture.json') ([ordered]@{
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
        screenshot = [ordered]@{ path = $screenshot; method = 'mock' }
        uia_text_summary = 'Submit button, Email field'
        ocr_text_summary = 'DesktopVisual Mock Submit Email'
        visible_text_hash = 'hash-mock-provider-selftest'
        element_summary = @([ordered]@{ element_id = 'uia-submit'; label = 'Submit'; role = 'Button'; text = 'Submit' })
    }
})
$requestPath = Join-Path $SelftestRoot 'request.json'
Invoke-WinAgentJson @(
    'vlm-observation-build-request',
    '--observe-json', $observePath,
    '--screenshot', $screenshot,
    '--task-hint', 'find submit',
    '--expected-context', 'DesktopVisual Mock Window',
    '--observation-purpose', 'target_candidates_observation_only',
    '--output', $requestPath
) | Out-Null

$results = [System.Collections.Generic.List[object]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Result {
    param([string]$Name, [string]$Status, [string]$Detail = '')
    $results.Add([pscustomobject]@{ name = $Name; status = $Status; detail = $Detail }) | Out-Null
    if ($Status -ne 'PASS') { $failures.Add("${Name}: $Detail") | Out-Null }
}

function Run-MockScenario {
    param([string]$Scenario)
    $path = Join-Path $SelftestRoot "$Scenario.result.json"
    $cmd = Invoke-WinAgentJson @('vlm-observation-run-mock', '--request', $requestPath, '--scenario', $Scenario, '--output', $path, '--allow-legacy-mock-vlm', 'true')
    [pscustomobject]@{ command = $cmd; path = $path; text = (Get-Content -LiteralPath $path -Raw) }
}

$valid = Run-MockScenario 'valid'
$validJson = $valid.text | ConvertFrom-Json
if ($valid.command.json.ok -and
    $validJson.provider_name -eq 'mock_vlm_provider' -and
    $validJson.provider_role -eq 'assistive_only' -and
    $validJson.result_schema_valid -eq $true -and
    $validJson.possible_targets[0].observation_only -eq $true -and
    $validJson.possible_targets[0].requires_runtime_validation -eq $true -and
    $validJson.contains_action -eq $false) {
    Add-Result 'mock valid observation result' 'PASS'
} else {
    Add-Result 'mock valid observation result' 'FAIL' $valid.command.text
}

$directClick = (Run-MockScenario 'direct_click').text | ConvertFrom-Json
if ($directClick.contains_action -eq $true -and $directClick.contains_executable_instruction -eq $true -and $directClick.direct_click) {
    Add-Result 'mock direct click malicious result' 'PASS'
} else {
    Add-Result 'mock direct click malicious result' 'FAIL'
}

$coordinatesOnly = (Run-MockScenario 'coordinates_only').text | ConvertFrom-Json
if ($coordinatesOnly.coordinate_only_action -eq $true -and $coordinatesOnly.contains_coordinates -eq $true -and $coordinatesOnly.contains_executable_instruction -eq $true) {
    Add-Result 'mock coordinates-only result' 'PASS'
} else {
    Add-Result 'mock coordinates-only result' 'FAIL'
}

$malformed = Run-MockScenario 'malformed_json'
$malformedFailed = $false
try { $null = $malformed.text | ConvertFrom-Json } catch { $malformedFailed = $true }
if ($malformedFailed) {
    Add-Result 'mock malformed JSON result' 'PASS'
} else {
    Add-Result 'mock malformed JSON result' 'FAIL'
}

$badRole = (Run-MockScenario 'bad_provider_role').text | ConvertFrom-Json
if ($badRole.provider_role -ne 'assistive_only') {
    Add-Result 'mock provider_role mismatch result' 'PASS'
} else {
    Add-Result 'mock provider_role mismatch result' 'FAIL'
}

$promptInjection = (Run-MockScenario 'prompt_injection').text | ConvertFrom-Json
if ($promptInjection.scene_summary -match 'ignore previous instructions' -and $promptInjection.contains_action -eq $false) {
    Add-Result 'mock prompt-injection-like text result' 'PASS'
} else {
    Add-Result 'mock prompt-injection-like text result' 'FAIL'
}

$bypass = (Run-MockScenario 'active_protection_bypass').text | ConvertFrom-Json
if ($bypass.contains_bypass_instruction -eq $true) {
    Add-Result 'mock active-protection bypass suggestion' 'PASS'
} else {
    Add-Result 'mock active-protection bypass suggestion' 'FAIL'
}

$credential = (Run-MockScenario 'credential_handling').text | ConvertFrom-Json
if ($credential.contains_credential_instruction -eq $true) {
    Add-Result 'mock credential-handling suggestion' 'PASS'
} else {
    Add-Result 'mock credential-handling suggestion' 'FAIL'
}

$status = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
@(
    '# v6.5.0 Mock VLM Provider Report',
    '',
    "- Result: $status",
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "- Runtime executed: false",
    "- API key required: false",
    '',
    '## Results',
    '',
    '```json',
    ($results | ConvertTo-Json -Depth 100),
    '```'
) | Set-Content -LiteralPath $ReportPath -Encoding UTF8

if ($failures.Count -ne 0) {
    throw "Mock VLM provider selftest failed: $($failures -join '; ')"
}

Write-Output 'PASS: v6.5.0 Mock VLM provider selftest'
Write-Output "Report: $ReportPath"

