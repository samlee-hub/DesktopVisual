param(
    [string]$Root = '',
    [int]$DurationMs = 3000,
    [int]$SamplesPerScenario = 3
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\motion_calibration_session.ps1 [-DurationMs <ms>] [-SamplesPerScenario <count>]'
    Write-Host 'Runs guided Motion Lab collection and installs a source=human operator motion profile.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$TestWindowExe = 'D:\testrepo\testwindow\bin\TestWindow.exe'
$MotionRoot = Join-Path $Root 'artifacts\motion_profile\human'
$RawDir = Join-Path $MotionRoot 'raw'
$CandidateProfile = Join-Path $MotionRoot 'operator_motion_profile.human.candidate.json'
$Profile = Join-Path $Root 'config\operator_motion_profile.json'
$ValidationReport = Join-Path $MotionRoot 'validation_report.md'
$Report = Join-Path $MotionRoot 'calibration_report.md'
$MotionState = 'D:\testrepo\testwindow\motion_state.txt'

function Invoke-AgentJson {
param(
    [switch]$Help,
        [Parameter(Mandatory=$true)]
        [string[]]$AgentArgs,

        [int[]]$AllowedExitCodes = @(0)
    )

    if (-not $AgentArgs -or $AgentArgs.Count -eq 0) {
        throw 'Invoke-AgentJson received empty AgentArgs.'
    }

    $output = & $WinAgent @AgentArgs
    $exit = $LASTEXITCODE

    if ($AllowedExitCodes -notcontains $exit) {
        throw "winagent $($AgentArgs -join ' ') exited $exit with output: $output"
    }

    return @{
        exit = $exit
        text = [string]$output
        json = ($output | ConvertFrom-Json)
    }
}

function Stop-TestWindow {
    Get-Process TestWindow -ErrorAction SilentlyContinue | ForEach-Object {
        $_.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (!$_.HasExited) { Stop-Process -Id $_.Id -Force }
    }
}

function Write-MotionState([string]$Scenario, [int]$SampleIndex, [string]$Status) {
    @(
        'window_title=Motion Lab - Agent Test Window',
        'mode=motion_lab',
        "current_scenario=$Scenario",
        "sample_index=$SampleIndex",
        "samples_per_scenario=$SamplesPerScenario",
        'start=80,120',
        'end=560,320',
        "duration_ms=$DurationMs",
        "status=$Status",
        "updated_at=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    ) | Set-Content -LiteralPath $MotionState -Encoding UTF8
}

function Write-CalibrationReport([string]$Result, [string[]]$Lines) {
    New-Item -ItemType Directory -Force -Path $MotionRoot | Out-Null
    @(
        '# DesktopVisual Human Motion Calibration',
        '',
        "- Result: $Result"
    ) + $Lines | Set-Content -LiteralPath $Report -Encoding UTF8
}

if (!(Test-Path -LiteralPath $WinAgent)) { throw "Missing $WinAgent. Run $Root\build.ps1 first." }
if (!(Test-Path -LiteralPath $TestWindowExe)) { throw "Missing $TestWindowExe. Run $Root\build.ps1 first." }
if ($SamplesPerScenario -lt 3) { throw 'SamplesPerScenario must be at least 3.' }

New-Item -ItemType Directory -Force -Path $RawDir | Out-Null
Remove-Item -LiteralPath $CandidateProfile -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $ValidationReport -Force -ErrorAction SilentlyContinue

$scenarios = @(
    'horizontal_lr',
    'horizontal_rl',
    'vertical_ud',
    'vertical_du',
    'diagonal_lu_rd',
    'diagonal_rd_lu',
    'diagonal_ru_ld',
    'diagonal_ld_ru',
    'short_precision',
    'medium_precision',
    'long_precision',
    'drag_line'
)

Stop-TestWindow
$motionLab = Start-Process -FilePath $TestWindowExe -ArgumentList 'motion-lab' -PassThru
$completed = $false
try {
    Start-Sleep -Milliseconds 800
    $sampleIndex = 1
    foreach ($scenario in $scenarios) {
        for ($round = 1; $round -le $SamplesPerScenario; $round++) {
            $out = Join-Path $RawDir ('raw_{0}_{1:000}.json' -f $scenario, $sampleIndex)
            Write-MotionState -Scenario $scenario -SampleIndex $sampleIndex -Status 'waiting'
            Write-Host ''
            Write-Host "Scenario: $scenario  Sample: $round/$SamplesPerScenario"
            Write-Host 'Move the mouse to the START marker. Press Enter to begin, then move or drag to the END marker before recording ends.'
            Write-Host 'Recorded data is limited to mouse coordinates, timestamps, and button state.'
            [void](Read-Host 'Press Enter to start')
            for ($i = 3; $i -ge 1; $i--) {
                Write-MotionState -Scenario $scenario -SampleIndex $sampleIndex -Status "countdown_$i"
                Write-Host "$i..."
                Start-Sleep -Seconds 1
            }
            Write-MotionState -Scenario $scenario -SampleIndex $sampleIndex -Status 'recording'
            Invoke-AgentJson -AgentArgs @('motion-record', '--title', 'Motion Lab', '--scenario', $scenario, '--duration-ms', "$DurationMs", '--out', $out) | Out-Null
            Write-MotionState -Scenario $scenario -SampleIndex $sampleIndex -Status 'recorded'
            $sampleIndex++
        }
    }

    $calibrate = Invoke-AgentJson -AgentArgs @('motion-calibrate', '--source', 'human', '--input', $RawDir, '--out', $CandidateProfile) -AllowedExitCodes @(0, 1)
    if ($calibrate.exit -ne 0) {
        Write-CalibrationReport 'FAILED' @(
            "- Reason: $($calibrate.json.error.code)",
            "- Raw directory: $RawDir",
            '- Formal profile was not overwritten.'
        )
        throw "Calibration failed: $($calibrate.text)"
    }

    $info = Invoke-AgentJson -AgentArgs @('motion-profile-info', '--profile', $CandidateProfile)
    if ($info.json.data.source -ne 'human') {
        throw "Candidate profile source is not human: $($info.text)"
    }
    $validate = Invoke-AgentJson -AgentArgs @('motion-profile-validate', '--profile', $CandidateProfile, '--out', $ValidationReport)

    Copy-Item -LiteralPath $CandidateProfile -Destination $Profile -Force
    $completed = $true

    $qualityWarning = if ($info.json.data.quality -eq 'low') { 'Profile quality is low; collect at least 32 samples for routine use.' } else { 'none' }
    Write-CalibrationReport 'PASS' @(
        "- Raw directory: $RawDir",
        "- Profile: $Profile",
        "- Source: $($info.json.data.source)",
        "- Sample count: $($info.json.data.sample_count)",
        "- Scenario count: $($info.json.data.scenario_count)",
        "- Quality: $($info.json.data.quality)",
        "- Validation: $($validate.json.data.result)",
        "- Validation report: $ValidationReport",
        "- Warning: $qualityWarning"
    )

    Write-Host "Human calibration report: $Report"
    Write-Host "Human profile written: $Profile"
}
finally {
    if (!$completed) {
        Write-MotionState -Scenario '' -SampleIndex 0 -Status 'interrupted_or_failed'
    }
    if ($motionLab -and !$motionLab.HasExited) {
        $motionLab.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (!$motionLab.HasExited) { Stop-Process -Id $motionLab.Id -Force }
    }
}
