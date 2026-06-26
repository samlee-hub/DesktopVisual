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
$SelftestRoot = Join-Path $ArtifactRoot 'selftest\boundary'
$ReportPath = Join-Path $ArtifactRoot 'assistive_only_boundary_report.md'
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
        visible_text_hash = 'hash-boundary-selftest'
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

function Invoke-DryRun {
    param([string]$Name, [string]$Scenario, [int[]]$AllowedExitCodes = @(0))
    $caseDir = Join-Path $SelftestRoot $Name
    New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
    $resultPath = Join-Path $caseDir 'result.json'
    $validationPath = Join-Path $caseDir 'validation.json'
    $boundaryPath = Join-Path $caseDir 'boundary.json'
    $cmd = Invoke-WinAgentJson @(
        'vlm-observation-dry-run',
        '--request', $requestPath,
        '--provider', 'mock',
        '--scenario', $Scenario,
        '--result', $resultPath,
        '--validation', $validationPath,
        '--boundary', $boundaryPath
    ) $AllowedExitCodes
    [pscustomobject]@{
        command = $cmd
        result = (Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json)
        validation = (Get-Content -LiteralPath $validationPath -Raw | ConvertFrom-Json)
        boundary = (Get-Content -LiteralPath $boundaryPath -Raw | ConvertFrom-Json)
    }
}

$valid = Invoke-DryRun -Name 'valid' -Scenario 'valid'
if ($valid.validation.validation_ok -eq $true -and
    $valid.boundary.boundary_enforced -eq $true -and
    $valid.boundary.runtime_executed -eq $false -and
    $valid.boundary.mouse_click_sent -eq $false -and
    $valid.boundary.keyboard_type_sent -eq $false -and
    $valid.boundary.safe_for_direct_execution -eq $false -and
    $valid.boundary.vlm_result_entered_runtime_action_path -eq $false -and
    $valid.boundary.step_contract_accepts_vlm_action -eq $false) {
    Add-Result 'dry-run valid observation enforces assistive-only boundary' 'PASS'
} else {
    Add-Result 'dry-run valid observation enforces assistive-only boundary' 'FAIL' ($valid | ConvertTo-Json -Depth 30)
}

$direct = Invoke-DryRun -Name 'direct_click' -Scenario 'direct_click' -AllowedExitCodes @(1)
if ($direct.validation.validation_ok -eq $false -and
    $direct.boundary.boundary_enforced -eq $true -and
    $direct.boundary.runtime_executed -eq $false -and
    $direct.boundary.mouse_click_sent -eq $false -and
    $direct.boundary.vlm_possible_target_directly_converted_to_action -eq $false -and
    $direct.boundary.safe_for_direct_execution -eq $false) {
    Add-Result 'direct-click VLM output is rejected and not executed' 'PASS'
} else {
    Add-Result 'direct-click VLM output is rejected and not executed' 'FAIL' ($direct | ConvertTo-Json -Depth 30)
}

$coordinate = Invoke-DryRun -Name 'coordinate_only' -Scenario 'coordinates_only' -AllowedExitCodes @(1)
if ($coordinate.validation.validation_ok -eq $false -and
    $coordinate.boundary.boundary_enforced -eq $true -and
    $coordinate.boundary.runtime_executed -eq $false -and
    $coordinate.boundary.safe_for_direct_execution -eq $false) {
    Add-Result 'coordinate-only VLM output is rejected and not executed' 'PASS'
} else {
    Add-Result 'coordinate-only VLM output is rejected and not executed' 'FAIL' ($coordinate | ConvertTo-Json -Depth 30)
}

$status = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
@(
    '# v6.5.0 Assistive-Only Boundary Report',
    '',
    "- Result: $status",
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "- Runtime executed: false",
    "- Boundary enforced: true",
    '',
    '## Results',
    '',
    '```json',
    ($results | ConvertTo-Json -Depth 100),
    '```'
) | Set-Content -LiteralPath $ReportPath -Encoding UTF8

if ($failures.Count -ne 0) {
    throw "VLM observation boundary selftest failed: $($failures -join '; ')"
}

Write-Output 'PASS: v6.5.0 VLM observation boundary selftest'
Write-Output "Report: $ReportPath"

