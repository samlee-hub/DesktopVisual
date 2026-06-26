param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$EvidenceRoot = Join-Path $Root 'artifacts\dev6.5.0_vlm_assisted_observation_contract'
$RawRoot = Join-Path $EvidenceRoot 'raw\v6_5_0_runner'
New-Item -ItemType Directory -Force -Path $RawRoot | Out-Null

$WinAgent = Join-Path $Root 'bin\winagent.exe'
if (-not (Test-Path $WinAgent)) {
    throw "winagent.exe missing: $WinAgent"
}

function Save-Json($Path, $Object) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $Object | ConvertTo-Json -Depth 80 | Set-Content -Encoding UTF8 $Path
}

function Invoke-Agent {
    param([string[]]$Arguments, [string]$Stdout, [string]$Stderr)
    & $WinAgent @Arguments > $Stdout 2> $Stderr
    return $LASTEXITCODE
}

function New-ObserveFixture {
    param(
        [string]$Name,
        [bool]$ActiveProtection = $false,
        [bool]$CredentialRequired = $false,
        [object]$Region = $null
    )
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
            screenshot = [ordered]@{ path = (Join-Path $RawRoot "$Name\mock_screen.bmp"); method = 'mock' }
            uia_text_summary = 'Submit button, Email field, Result area'
            ocr_text_summary = 'DesktopVisual Mock Submit Email Result'
            visible_text_hash = "hash-v65-$Name"
            element_summary = @(
                [ordered]@{ element_id = 'uia-email'; label = 'Email'; role = 'Edit'; text = ''; bounds = [ordered]@{ left = 130; top = 180; right = 500; bottom = 220 } },
                [ordered]@{ element_id = 'uia-submit'; label = 'Submit'; role = 'Button'; text = 'Submit'; bounds = [ordered]@{ left = 130; top = 240; right = 230; bottom = 280 } }
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

function Build-Request {
    param(
        [string]$Name,
        [string]$Purpose = 'target_candidates_observation_only',
        [bool]$ActiveProtection = $false,
        [bool]$CredentialRequired = $false,
        [object]$Region = $null
    )
    $caseDir = Join-Path $RawRoot "requests\$Name"
    New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
    $screenshot = Join-Path $caseDir 'mock_screen.bmp'
    Set-Content -LiteralPath $screenshot -Encoding Byte -Value @()
    $observePath = Join-Path $caseDir 'observe.json'
    Save-Json $observePath (New-ObserveFixture -Name $Name -ActiveProtection:$ActiveProtection -CredentialRequired:$CredentialRequired -Region $Region)
    $requestPath = Join-Path $caseDir 'request.json'
    $stdout = Join-Path $caseDir 'build_request.stdout.json'
    $stderr = Join-Path $caseDir 'build_request.stderr.txt'
    $exit = Invoke-Agent -Arguments @(
        'vlm-observation-build-request',
        '--observe-json', $observePath,
        '--screenshot', $screenshot,
        '--task-hint', "task hint $Name",
        '--expected-context', 'DesktopVisual Mock Window',
        '--observation-purpose', $Purpose,
        '--output', $requestPath
    ) -Stdout $stdout -Stderr $stderr
    [ordered]@{
        name = $Name
        exit_code = $exit
        observe = $observePath
        screenshot = $screenshot
        request = $requestPath
        stdout = $stdout
        stderr = $stderr
    }
}

function Run-Mock-Validate {
    param(
        [string]$Group,
        [string]$Name,
        [object]$RequestRecord,
        [string]$Scenario,
        [bool]$ExpectedValidationOk
    )
    $caseDir = Join-Path $RawRoot "$Group\$Name"
    New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
    $resultPath = Join-Path $caseDir 'result.json'
    $validationPath = Join-Path $caseDir 'validation.json'
    $mockStdout = Join-Path $caseDir 'run_mock.stdout.json'
    $mockStderr = Join-Path $caseDir 'run_mock.stderr.txt'
    $validateStdout = Join-Path $caseDir 'validate.stdout.json'
    $validateStderr = Join-Path $caseDir 'validate.stderr.txt'
    $mockExit = Invoke-Agent -Arguments @('vlm-observation-run-mock','--request',$RequestRecord.request,'--scenario',$Scenario,'--output',$resultPath,'--allow-legacy-mock-vlm','true') -Stdout $mockStdout -Stderr $mockStderr
    $validateExit = Invoke-Agent -Arguments @('vlm-observation-validate','--request',$RequestRecord.request,'--result',$resultPath,'--output',$validationPath) -Stdout $validateStdout -Stderr $validateStderr
    [ordered]@{
        group = $Group
        name = $Name
        scenario = $Scenario
        expected_validation_ok = $ExpectedValidationOk
        request = $RequestRecord.request
        result = $resultPath
        validation = $validationPath
        mock_exit_code = $mockExit
        validate_exit_code = $validateExit
        mock_stdout = $mockStdout
        mock_stderr = $mockStderr
        validate_stdout = $validateStdout
        validate_stderr = $validateStderr
        evidence_dir = $caseDir
    }
}

function Run-DryRun {
    param(
        [string]$Name,
        [object]$RequestRecord,
        [string]$Scenario,
        [bool]$ExpectedValidationOk
    )
    $caseDir = Join-Path $RawRoot "dry_run\$Name"
    New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
    $resultPath = Join-Path $caseDir 'result.json'
    $validationPath = Join-Path $caseDir 'validation.json'
    $boundaryPath = Join-Path $caseDir 'boundary.json'
    $stdout = Join-Path $caseDir 'dry_run.stdout.json'
    $stderr = Join-Path $caseDir 'dry_run.stderr.txt'
    $exit = Invoke-Agent -Arguments @('vlm-observation-dry-run','--request',$RequestRecord.request,'--provider','mock','--scenario',$Scenario,'--result',$resultPath,'--validation',$validationPath,'--boundary',$boundaryPath) -Stdout $stdout -Stderr $stderr
    [ordered]@{
        group = 'dry_run'
        name = $Name
        scenario = $Scenario
        expected_validation_ok = $ExpectedValidationOk
        request = $RequestRecord.request
        result = $resultPath
        validation = $validationPath
        boundary = $boundaryPath
        dry_run_exit_code = $exit
        stdout = $stdout
        stderr = $stderr
        evidence_dir = $caseDir
    }
}

$requests = [ordered]@{
    default = Build-Request -Name 'default'
    roi = Build-Request -Name 'roi' -Purpose 'layout_understanding' -Region ([ordered]@{ left = 120; top = 150; right = 520; bottom = 360 })
    active = Build-Request -Name 'active_protection' -Purpose 'scene_summary' -ActiveProtection $true
    credential = Build-Request -Name 'credential_required' -Purpose 'scene_summary' -CredentialRequired $true
}

$cases = New-Object System.Collections.Generic.List[object]

$cases.Add((Run-Mock-Validate -Group 'positive' -Name 'build_observation_request_from_runtime_observe' -RequestRecord $requests.default -Scenario 'valid' -ExpectedValidationOk $true)) | Out-Null
$cases.Add((Run-Mock-Validate -Group 'positive' -Name 'valid_mock_vlm_observation_result' -RequestRecord $requests.default -Scenario 'valid' -ExpectedValidationOk $true)) | Out-Null
$cases.Add((Run-Mock-Validate -Group 'positive' -Name 'roi_observation_request' -RequestRecord $requests.roi -Scenario 'valid' -ExpectedValidationOk $true)) | Out-Null
$cases.Add((Run-Mock-Validate -Group 'positive' -Name 'active_protection_context_summary_only' -RequestRecord $requests.active -Scenario 'active_context_summary_only' -ExpectedValidationOk $true)) | Out-Null
$cases.Add((Run-Mock-Validate -Group 'positive' -Name 'credential_required_context_summary_only' -RequestRecord $requests.credential -Scenario 'credential_context_summary_only' -ExpectedValidationOk $true)) | Out-Null
$cases.Add((Run-DryRun -Name 'dry_run_no_runtime_execution' -RequestRecord $requests.default -Scenario 'valid' -ExpectedValidationOk $true)) | Out-Null

$negativeScenarios = @(
    @{ name='direct_click_output'; scenario='direct_click'; request=$requests.default },
    @{ name='coordinates_only_action'; scenario='coordinates_only'; request=$requests.default },
    @{ name='executable_action_output'; scenario='executable_action'; request=$requests.default },
    @{ name='runtime_command_output'; scenario='runtime_command'; request=$requests.default },
    @{ name='provider_role_not_assistive_only'; scenario='bad_provider_role'; request=$requests.default },
    @{ name='malformed_json'; scenario='malformed_json'; request=$requests.default },
    @{ name='possible_targets_missing_observation_only'; scenario='missing_observation_only'; request=$requests.default },
    @{ name='possible_targets_missing_requires_runtime_validation'; scenario='missing_requires_runtime_validation'; request=$requests.default },
    @{ name='prompt_injection_classified_non_executable'; scenario='prompt_injection'; request=$requests.default; expected=$true },
    @{ name='captcha_bypass_suggestion'; scenario='captcha_bypass'; request=$requests.default },
    @{ name='credential_handling_suggestion'; scenario='credential_handling'; request=$requests.default },
    @{ name='anti_cheat_script_detection_bypass_suggestion'; scenario='anti_cheat_bypass'; request=$requests.default },
    @{ name='active_protection_executable_candidate'; scenario='active_protection_executable_candidate'; request=$requests.active },
    @{ name='vlm_action_runtime_boundary_attempt'; scenario='direct_click'; request=$requests.default; dry=$true },
    @{ name='direct_coordinate_click_point'; scenario='direct_coordinate_click_point'; request=$requests.default },
    @{ name='approximate_region_only_non_executable'; scenario='approximate_region_only'; request=$requests.default; expected=$true }
)

foreach ($item in $negativeScenarios) {
    $expectedOk = if ($item.ContainsKey('expected')) { [bool]$item.expected } else { $false }
    if ($item.ContainsKey('dry') -and $item.dry) {
        $cases.Add((Run-DryRun -Name $item.name -RequestRecord $item.request -Scenario $item.scenario -ExpectedValidationOk $expectedOk)) | Out-Null
    } else {
        $cases.Add((Run-Mock-Validate -Group 'negative' -Name $item.name -RequestRecord $item.request -Scenario $item.scenario -ExpectedValidationOk $expectedOk)) | Out-Null
    }
}

$runnerResult = [ordered]@{
    schema_version = '6.5.0.vlm_observation.runner'
    generated_at = (Get-Date).ToString('o')
    status = 'RAW_COMPLETED_UNVERIFIED'
    result_is_pass = $false
    runner_only_vlm_contract = $false
    runtime_executed = $false
    requests = $requests
    cases = $cases.ToArray()
}
$runnerResultPath = Join-Path $EvidenceRoot 'v6_5_0_runner_raw_result.json'
Save-Json $runnerResultPath $runnerResult

$lines = @('# v6.5.0 VLM Observation Runner Raw Report','')
$lines += '- Status: RAW_COMPLETED_UNVERIFIED'
$lines += '- Runner result is not PASS.'
$lines += '- Runtime executed: false'
$lines += ''
foreach ($case in $cases) {
    $exit = if ($case.Contains('dry_run_exit_code')) { $case.dry_run_exit_code } else { $case.validate_exit_code }
    $lines += "- $($case.group)/$($case.name): scenario=$($case.scenario) exit=$exit expected_validation_ok=$($case.expected_validation_ok)"
}
$lines | Set-Content -Encoding UTF8 (Join-Path $EvidenceRoot 'v6_5_0_runner_raw_report.md')

'RAW_COMPLETED_UNVERIFIED'
exit 0

