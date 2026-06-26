param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$EvidenceRoot = Join-Path $Root 'artifacts\dev6.6.0_vlm_assisted_unknown_ui_candidate_handling'
$RawRoot = Join-Path $EvidenceRoot 'raw\v6_6_0_runner'
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$TestWindowExe = 'D:\testrepo\testwindow\bin\TestWindow.exe'
$StateFile = 'D:\testrepo\testwindow\runtime\state.txt'
New-Item -ItemType Directory -Force -Path $RawRoot | Out-Null

if (-not (Test-Path -LiteralPath $WinAgent)) { throw "winagent.exe missing: $WinAgent" }

function Save-Json($Path, $Object) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $Object | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-Agent {
    param([string[]]$Arguments, [string]$Stdout, [string]$Stderr)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Stdout) | Out-Null
    & $WinAgent @Arguments > $Stdout 2> $Stderr
    return $LASTEXITCODE
}

function Stop-TestWindow {
    Get-Process TestWindow -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Wait-TestWindow {
    param([string]$CaseDir)
    for ($i = 0; $i -lt 30; $i++) {
        $stdout = Join-Path $CaseDir ('find_{0:00}.stdout.json' -f $i)
        $stderr = Join-Path $CaseDir ('find_{0:00}.stderr.txt' -f $i)
        $exit = Invoke-Agent -Arguments @('find', '--title', 'Agent Test Window') -Stdout $stdout -Stderr $stderr
        if ($exit -eq 0) { return $true }
        Start-Sleep -Milliseconds 200
    }
    return $false
}

function Write-MockFixtures {
    $fixtures = @(
        'D:\testrepo\testwindow\desktopvisual_vlm_unknown_ui_mock.html',
        'D:\testrepo\testwindow\desktopvisual_vlm_ambiguous_candidate_mock.html',
        'D:\testrepo\testwindow\desktopvisual_vlm_offscreen_candidate_mock.html',
        'D:\testrepo\testwindow\desktopvisual_vlm_protection_region_mock.html'
    )
    foreach ($fixture in $fixtures) {
        if (-not (Test-Path -LiteralPath $fixture)) {
            throw "Required mock fixture missing: $fixture"
        }
    }
    return $fixtures
}

function Run-LocateCase {
    param(
        [string]$Group,
        [string]$Name,
        [string]$Command = 'vlm-assisted-locate-dry-run',
        [string]$Target = 'Submit',
        [string]$Scenario = 'valid',
        [int]$ExpectedExit = 0,
        [string[]]$ExtraArgs = @()
    )
    $caseDir = Join-Path $RawRoot "$Group\$Name"
    $evidenceDir = Join-Path $caseDir 'evidence'
    $resultPath = Join-Path $caseDir 'result.json'
    $stdout = Join-Path $caseDir 'stdout.json'
    $stderr = Join-Path $caseDir 'stderr.txt'
    New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
    $args = @(
        $Command,
        '--allow-legacy-mock-vlm', 'true',
        '--target', $Target,
        '--provider', 'mock',
        '--scenario', $Scenario,
        '--result', $resultPath,
        '--evidence-dir', $evidenceDir
    ) + $ExtraArgs
    $exit = Invoke-Agent -Arguments $args -Stdout $stdout -Stderr $stderr
    [ordered]@{
        group = $Group
        name = $Name
        command = $Command
        target = $Target
        scenario = $Scenario
        expected_exit_code = $ExpectedExit
        exit_code = $exit
        result = $resultPath
        stdout = $stdout
        stderr = $stderr
        evidence_dir = $evidenceDir
        extra_args = $ExtraArgs
    }
}

function Run-LocalSafeCase {
    $caseDir = Join-Path $RawRoot 'positive\local_safe_click'
    $evidenceDir = Join-Path $caseDir 'evidence'
    $resultPath = Join-Path $caseDir 'result.json'
    $stdout = Join-Path $caseDir 'stdout.json'
    $stderr = Join-Path $caseDir 'stderr.txt'
    New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
    if (-not (Test-Path -LiteralPath $TestWindowExe)) { throw "TestWindow.exe missing: $TestWindowExe" }
    Stop-TestWindow
    Remove-Item -LiteralPath $StateFile -ErrorAction SilentlyContinue
    Start-Process -FilePath $TestWindowExe | Out-Null
    $ready = Wait-TestWindow -CaseDir $caseDir
    $exit = 1
    if ($ready) {
        $exit = Invoke-Agent -Arguments @(
            'vlm-assisted-locate-and-click-local-safe',
            '--allow-legacy-mock-vlm', 'true',
            '--target', 'Click Me',
            '--provider', 'mock',
            '--scenario', 'testwindow_click_me',
            '--title', 'Agent Test Window',
            '--expected-marker', 'clicks=1',
            '--result', $resultPath,
            '--evidence-dir', $evidenceDir,
            '--move-mode', 'instant'
        ) -Stdout $stdout -Stderr $stderr
    } else {
        'Agent Test Window did not appear.' | Set-Content -LiteralPath $stderr -Encoding UTF8
    }
    $stateSnapshot = Join-Path $caseDir 'state_after.txt'
    if (Test-Path -LiteralPath $StateFile) {
        Copy-Item -LiteralPath $StateFile -Destination $stateSnapshot -Force
    }
    Stop-TestWindow
    [ordered]@{
        group = 'positive'
        name = 'local_safe_click'
        command = 'vlm-assisted-locate-and-click-local-safe'
        target = 'Click Me'
        scenario = 'testwindow_click_me'
        expected_exit_code = 0
        exit_code = $exit
        result = $resultPath
        stdout = $stdout
        stderr = $stderr
        evidence_dir = $evidenceDir
        state_snapshot = $stateSnapshot
        testwindow_ready = $ready
    }
}

$fixtures = Write-MockFixtures
$cases = New-Object System.Collections.Generic.List[object]

$cases.Add((Run-LocateCase -Group 'positive' -Name 'runtime_locate_failed_to_vlm_candidate' -Command 'vlm-assisted-locate-dry-run' -Target 'Submit' -Scenario 'valid' -ExpectedExit 0)) | Out-Null
$cases.Add((Run-LocateCase -Group 'positive' -Name 'locate_only_api' -Command 'vlm-assisted-locate' -Target 'Submit' -Scenario 'valid' -ExpectedExit 0)) | Out-Null
$cases.Add((Run-LocateCase -Group 'positive' -Name 'approx_region_candidate' -Target 'Submit' -Scenario 'approximate_region_only' -ExpectedExit 0)) | Out-Null
$cases.Add((Run-LocateCase -Group 'positive' -Name 'roi_candidate' -Target 'Submit' -Scenario 'roi_candidate' -ExpectedExit 0 -ExtraArgs @('--roi','true'))) | Out-Null
$cases.Add((Run-LocateCase -Group 'positive' -Name 'multiple_candidates_one_unique_valid' -Target 'Submit' -Scenario 'multiple_one_unique' -ExpectedExit 0)) | Out-Null
$localSafeCase = Run-LocalSafeCase
$localSafeExecuted = [int]($localSafeCase['exit_code']) -eq 0
$cases.Add($localSafeCase) | Out-Null

$negative = @(
    @{ name='vlm_direct_click_output'; target='Submit'; scenario='direct_click'; reason='VLM_DIRECT_ACTION_REJECTED' },
    @{ name='vlm_direct_coordinate_click_point'; target='Submit'; scenario='direct_coordinate_click_point'; reason='VLM_COORDINATE_ACTION_REJECTED' },
    @{ name='vlm_coordinate_action_output'; target='Submit'; scenario='coordinates_only'; reason='VLM_COORDINATE_ACTION_REJECTED' },
    @{ name='vlm_executable_action_output'; target='Submit'; scenario='executable_action'; reason='VLM_DIRECT_ACTION_REJECTED' },
    @{ name='candidate_outside_viewport'; target='Submit'; scenario='outside_viewport_candidate'; reason='CANDIDATE_OUTSIDE_VIEWPORT' },
    @{ name='candidate_offscreen'; target='Submit'; scenario='offscreen_candidate'; reason='CANDIDATE_OFFSCREEN' },
    @{ name='candidate_no_runtime_corroboration'; target='Warp Drive'; scenario='hallucinated_target'; reason='CANDIDATE_NO_RUNTIME_CORROBORATION' },
    @{ name='candidate_active_protection_region'; target='CAPTCHA Continue'; scenario='protection_region_candidate'; reason='CANDIDATE_ACTIVE_PROTECTION_REGION' },
    @{ name='candidate_credential_region'; target='Password'; scenario='credential_region_candidate'; reason='CANDIDATE_CREDENTIAL_REGION' },
    @{ name='ambiguous_candidates'; target='Submit'; scenario='ambiguous_candidates'; reason='CANDIDATE_NOT_UNIQUE' },
    @{ name='stale_observe_candidate'; target='Submit'; scenario='valid'; reason='CANDIDATE_STALE_OBSERVE'; extra=@('--stale-observe','true') },
    @{ name='provider_role_not_assistive_only'; target='Submit'; scenario='bad_provider_role'; reason='VLM_PROVIDER_ROLE_INVALID' },
    @{ name='missing_observation_only'; target='Submit'; scenario='missing_observation_only'; reason='VLM_DIRECT_ACTION_REJECTED' },
    @{ name='missing_requires_runtime_validation'; target='Submit'; scenario='missing_requires_runtime_validation'; reason='VLM_CANDIDATE_REQUIRES_RUNTIME_VALIDATION' },
    @{ name='hallucinated_target_rejected'; target='Warp Drive'; scenario='hallucinated_target'; reason='CANDIDATE_NO_RUNTIME_CORROBORATION' },
    @{ name='low_confidence_no_corroboration'; target='Ghost Action'; scenario='low_confidence_no_corroboration'; reason='CANDIDATE_LOW_CONFIDENCE' },
    @{ name='captcha_bypass_rejected'; target='Submit'; scenario='captcha_bypass'; reason='VLM_BYPASS_INSTRUCTION_REJECTED' },
    @{ name='credential_handling_rejected'; target='Submit'; scenario='credential_handling'; reason='VLM_CREDENTIAL_INSTRUCTION_REJECTED' },
    @{ name='anti_cheat_bypass_rejected'; target='Submit'; scenario='anti_cheat_bypass'; reason='VLM_ACTIVE_PROTECTION_BYPASS_REJECTED' },
    @{ name='active_protection_context_rejected'; target='Submit'; scenario='valid'; reason='ACTIVE_PROTECTION_CONTEXT'; extra=@('--active-protection','true') },
    @{ name='credential_required_context_rejected'; target='Submit'; scenario='valid'; reason='CREDENTIAL_REQUIRED_CONTEXT'; extra=@('--credential-required','true') }
)

foreach ($item in $negative) {
    $extra = if ($item.ContainsKey('extra')) { [string[]]$item.extra } else { @() }
    $record = Run-LocateCase -Group 'negative' -Name $item.name -Target $item.target -Scenario $item.scenario -ExpectedExit 1 -ExtraArgs $extra
    $record['expected_rejection'] = $item.reason
    $cases.Add($record) | Out-Null
}

$runnerResult = [ordered]@{}
$runnerResult['schema_version'] = '6.6.0.vlm_candidate.runner'
$runnerResult['generated_at'] = (Get-Date).ToString('o')
$runnerResult['status'] = 'RAW_COMPLETED_UNVERIFIED'
$runnerResult['result_is_pass'] = $false
$runnerResult['runtime_executed'] = $localSafeExecuted
$runnerResult['runtime_execution_scope'] = 'local_safe_testwindow_only'
$runnerResult['runner_only_vlm_candidate_bridge'] = $false
$runnerResult['fixture_paths'] = @($fixtures)
$runnerResult['raw_root'] = $RawRoot
$runnerResult['cases'] = $cases.ToArray()
Save-Json (Join-Path $EvidenceRoot 'v6_6_0_runner_raw_result.json') $runnerResult

@(
    '# v6.6.0 VLM Candidate Runner Raw Report',
    '',
    '- Status: RAW_COMPLETED_UNVERIFIED',
    '- Result is PASS: false',
    "- Cases: $($cases.Count)",
    "- Raw root: $RawRoot",
    '',
    'Runner output is raw evidence only. Verifier and gate own PASS authority.'
) | Set-Content -LiteralPath (Join-Path $EvidenceRoot 'v6_6_0_runner_raw_report.md') -Encoding UTF8

'RAW_COMPLETED_UNVERIFIED'
