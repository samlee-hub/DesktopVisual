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
$SelftestRoot = Join-Path $ArtifactRoot 'selftest\validator'
$ReportPath = Join-Path $ArtifactRoot 'vlm_output_validator_report.md'
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
    param([bool]$ActiveProtection = $false, [bool]$CredentialRequired = $false)
    [ordered]@{
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
            screenshot = [ordered]@{ path = (Join-Path $SelftestRoot 'mock_screen.bmp'); method = 'mock' }
            uia_text_summary = 'Submit button, Email field'
            ocr_text_summary = 'DesktopVisual Mock Submit Email'
            visible_text_hash = 'hash-validator-selftest'
            element_summary = @([ordered]@{ element_id = 'uia-submit'; label = 'Submit'; role = 'Button'; text = 'Submit' })
            active_protection_detected = $ActiveProtection
            credential_required_detected = $CredentialRequired
        }
    }
}

$screenshot = Join-Path $SelftestRoot 'mock_screen.bmp'
Set-Content -LiteralPath $screenshot -Encoding Byte -Value @()
$observePath = Write-JsonFile (Join-Path $SelftestRoot 'observe_fixture.json') (New-ObserveFixture)
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

$activeObservePath = Write-JsonFile (Join-Path $SelftestRoot 'observe_active_fixture.json') (New-ObserveFixture -ActiveProtection $true)
$activeRequestPath = Join-Path $SelftestRoot 'request_active.json'
Invoke-WinAgentJson @(
    'vlm-observation-build-request',
    '--observe-json', $activeObservePath,
    '--screenshot', $screenshot,
    '--task-hint', 'summarize only',
    '--expected-context', 'active protection present',
    '--observation-purpose', 'scene_summary',
    '--output', $activeRequestPath
) | Out-Null

$results = [System.Collections.Generic.List[object]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Result {
    param([string]$Name, [string]$Status, [string]$Detail = '')
    $results.Add([pscustomobject]@{ name = $Name; status = $Status; detail = $Detail }) | Out-Null
    if ($Status -ne 'PASS') { $failures.Add("${Name}: $Detail") | Out-Null }
}

function New-MockResult {
    param([string]$Scenario, [string]$Request = $requestPath)
    $resultPath = Join-Path $SelftestRoot "$Scenario.result.json"
    Invoke-WinAgentJson @('vlm-observation-run-mock', '--request', $Request, '--scenario', $Scenario, '--output', $resultPath, '--allow-legacy-mock-vlm', 'true') | Out-Null
    return $resultPath
}

function Validate-Result {
    param([string]$Name, [string]$Scenario, [bool]$ExpectedOk, [string[]]$ExpectedCodes = @(), [string]$Request = $requestPath)
    $resultPath = New-MockResult -Scenario $Scenario -Request $Request
    $validationPath = Join-Path $SelftestRoot "$Name.validation.json"
    $cmd = Invoke-WinAgentJson @('vlm-observation-validate', '--request', $Request, '--result', $resultPath, '--output', $validationPath) @(0,1)
    $validation = Get-Content -LiteralPath $validationPath -Raw | ConvertFrom-Json
    $errorsText = ($validation.validation_errors | ConvertTo-Json -Depth 20)
    $warningsText = ($validation.validation_warnings | ConvertTo-Json -Depth 20)
    $okMatches = ($validation.validation_ok -eq $ExpectedOk)
    $codesMatch = $true
    foreach ($code in $ExpectedCodes) {
        if ($errorsText -notmatch [regex]::Escape($code) -and $warningsText -notmatch [regex]::Escape($code)) {
            $codesMatch = $false
        }
    }
    if ($okMatches -and $codesMatch -and $validation.safe_for_direct_execution -eq $false) {
        Add-Result $Name 'PASS'
    } else {
        Add-Result $Name 'FAIL' $cmd.text
    }
    return $validation
}

$valid = Validate-Result -Name 'valid observation result' -Scenario 'valid' -ExpectedOk $true
if (-not ($valid.assistive_only -eq $true -and $valid.safe_for_runtime_candidate_pipeline -eq $true)) {
    Add-Result 'valid result candidate pipeline flag' 'FAIL' ($valid | ConvertTo-Json -Depth 20)
}

Validate-Result -Name 'approximate region only non-executable pass' -Scenario 'approximate_region_only' -ExpectedOk $true | Out-Null
Validate-Result -Name 'direct click output rejected' -Scenario 'direct_click' -ExpectedOk $false -ExpectedCodes @('VLM_DIRECT_ACTION_REJECTED') | Out-Null
Validate-Result -Name 'coordinates-only output rejected' -Scenario 'coordinates_only' -ExpectedOk $false -ExpectedCodes @('VLM_COORDINATE_ACTION_REJECTED') | Out-Null
Validate-Result -Name 'executable action output rejected' -Scenario 'executable_action' -ExpectedOk $false -ExpectedCodes @('VLM_DIRECT_ACTION_REJECTED') | Out-Null
Validate-Result -Name 'runtime command output rejected' -Scenario 'runtime_command' -ExpectedOk $false -ExpectedCodes @('VLM_RUNTIME_COMMAND_REJECTED') | Out-Null
Validate-Result -Name 'provider_role mismatch rejected' -Scenario 'bad_provider_role' -ExpectedOk $false -ExpectedCodes @('VLM_PROVIDER_ROLE_INVALID') | Out-Null
Validate-Result -Name 'malformed JSON rejected' -Scenario 'malformed_json' -ExpectedOk $false -ExpectedCodes @('VLM_MALFORMED_JSON') | Out-Null
Validate-Result -Name 'possible target missing observation_only rejected' -Scenario 'missing_observation_only' -ExpectedOk $false -ExpectedCodes @('VLM_DIRECT_ACTION_REJECTED') | Out-Null
Validate-Result -Name 'possible target missing runtime validation rejected' -Scenario 'missing_requires_runtime_validation' -ExpectedOk $false -ExpectedCodes @('VLM_CANDIDATE_REQUIRES_RUNTIME_VALIDATION') | Out-Null
Validate-Result -Name 'prompt injection classified warning' -Scenario 'prompt_injection' -ExpectedOk $true -ExpectedCodes @('VLM_PROMPT_INJECTION_CLASSIFIED') | Out-Null
Validate-Result -Name 'CAPTCHA bypass suggestion rejected' -Scenario 'captcha_bypass' -ExpectedOk $false -ExpectedCodes @('VLM_BYPASS_INSTRUCTION_REJECTED') | Out-Null
Validate-Result -Name 'credential handling suggestion rejected' -Scenario 'credential_handling' -ExpectedOk $false -ExpectedCodes @('VLM_CREDENTIAL_INSTRUCTION_REJECTED') | Out-Null
Validate-Result -Name 'anti-cheat bypass suggestion rejected' -Scenario 'anti_cheat_bypass' -ExpectedOk $false -ExpectedCodes @('VLM_ACTIVE_PROTECTION_BYPASS_REJECTED') | Out-Null
Validate-Result -Name 'active protection executable candidate rejected' -Scenario 'active_protection_executable_candidate' -ExpectedOk $false -ExpectedCodes @('VLM_DIRECT_ACTION_REJECTED') -Request $activeRequestPath | Out-Null

$summaryOnly = Validate-Result -Name 'active protection summary-only observation allowed' -Scenario 'active_context_summary_only' -ExpectedOk $true -Request $activeRequestPath
if ($summaryOnly.safe_for_runtime_candidate_pipeline -ne $false) {
    Add-Result 'blocked context candidate pipeline disabled' 'FAIL' ($summaryOnly | ConvertTo-Json -Depth 20)
}

$status = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
@(
    '# v6.5.0 VLM Output Validator Report',
    '',
    "- Result: $status",
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "- safe_for_direct_execution_always_false: true",
    '',
    '## Results',
    '',
    '```json',
    ($results | ConvertTo-Json -Depth 100),
    '```'
) | Set-Content -LiteralPath $ReportPath -Encoding UTF8

if ($failures.Count -ne 0) {
    throw "VLM observation validator selftest failed: $($failures -join '; ')"
}

Write-Output 'PASS: v6.5.0 VLM observation validator selftest'
Write-Output "Report: $ReportPath"

