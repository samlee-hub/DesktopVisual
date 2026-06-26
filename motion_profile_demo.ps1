param(
    [string]$Root = '',
    [switch]$Help,
    [int]$DurationMs = 3000,
    [int]$Rounds = 1
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\motion_profile_demo.ps1 [-DurationMs <ms>] [-Rounds <count>]'
    Write-Host 'Runs an interactive Motion Lab demo and writes a human operator motion profile.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$TestWindowExe = 'D:\testrepo\testwindow\bin\TestWindow.exe'
$MotionRoot = Join-Path $Root 'artifacts\motion_profile'
$RawDir = Join-Path $MotionRoot 'human\raw'
$Profile = Join-Path $Root 'config\operator_motion_profile.json'
$ValidationReport = Join-Path $MotionRoot 'human\validation_report.md'
$DemoReport = Join-Path $MotionRoot 'demo_report.md'

function Invoke-AgentJson {
    param([string[]]$Args, [int[]]$AllowedExitCodes = @(0))
    $output = & $WinAgent @Args
    $exit = $LASTEXITCODE
    if ($AllowedExitCodes -notcontains $exit) {
        throw "winagent $($Args -join ' ') exited $exit with output: $output"
    }
    return $output | ConvertFrom-Json
}

if (!(Test-Path -LiteralPath $WinAgent)) { throw "Missing $WinAgent. Run $Root\build.ps1 first." }
if (!(Test-Path -LiteralPath $TestWindowExe)) { throw "Missing $TestWindowExe. Run $Root\build.ps1 first." }

New-Item -ItemType Directory -Force -Path $RawDir | Out-Null

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

Get-Process TestWindow -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
$motionLab = Start-Process -FilePath $TestWindowExe -ArgumentList 'motion-lab' -PassThru
try {
    Start-Sleep -Milliseconds 800
    $sample = 1
    for ($round = 1; $round -le $Rounds; $round++) {
        foreach ($scenario in $scenarios) {
            $out = Join-Path $RawDir ('raw_{0}_{1:000}.json' -f $scenario, $sample)
            Write-Host ""
            Write-Host "Scenario $scenario ($sample). Move or drag as shown in Motion Lab for $DurationMs ms."
            Read-Host "Press Enter to start recording"
            Invoke-AgentJson -Args @('motion-record', '--title', 'Motion Lab', '--scenario', $scenario, '--duration-ms', "$DurationMs", '--out', $out) | Out-Null
            $sample++
        }
    }

    $calibrate = Invoke-AgentJson -Args @('motion-calibrate', '--source', 'human', '--input', $RawDir, '--out', $Profile)
    $info = Invoke-AgentJson -Args @('motion-profile-info', '--profile', $Profile)
    $validate = Invoke-AgentJson -Args @('motion-profile-validate', '--profile', $Profile, '--out', $ValidationReport)

    if (!$motionLab.HasExited) {
        $motionLab.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (!$motionLab.HasExited) { Stop-Process -Id $motionLab.Id -Force }
    }

    $testWindow = Start-Process -FilePath $TestWindowExe -PassThru
    try {
        Start-Sleep -Milliseconds 800
        $click = Invoke-AgentJson -Args @('click', '--title', 'Agent Test Window', '--x', '80', '--y', '90', '--move-mode', 'operator-human')
    }
    finally {
        if ($testWindow -and !$testWindow.HasExited) {
            $testWindow.CloseMainWindow() | Out-Null
            Start-Sleep -Milliseconds 300
            if (!$testWindow.HasExited) { Stop-Process -Id $testWindow.Id -Force }
        }
    }

    @(
        '# DesktopVisual Operator Motion Profile Demo',
        '',
        "- Result: $($validate.data.result)",
        ('- Raw directory: `{0}`' -f $RawDir),
        ('- Profile: `{0}`' -f $Profile),
        "- Sample count: $($calibrate.data.sample_count)",
        "- Quality: $($info.data.quality)",
        "- Source: $($info.data.source)",
        ('- Validation report: `{0}`' -f $ValidationReport),
        "- Operator click move profile: $($click.data.move_profile)",
        "- Operator synthesized points: $($click.data.synthesized_point_count)"
    ) | Set-Content -LiteralPath $DemoReport -Encoding UTF8

    Write-Host "Demo report: $DemoReport"
}
finally {
    Get-Process TestWindow -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}
