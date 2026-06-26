param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$TestRepoRoot = & (Join-Path $Root 'scripts\Resolve-TestRepoRoot.ps1') -Root $Root
$TestWindowRoot = Join-Path $TestRepoRoot 'testwindow'
$TestWindowExe = Join-Path $TestWindowRoot 'bin\TestWindow.exe'
$Artifacts = Join-Path $Root 'artifacts'
$MotionRoot = Join-Path $Artifacts 'motion_profile'
$SyntheticRoot = Join-Path $MotionRoot 'synthetic'
$RawDir = Join-Path $SyntheticRoot 'raw'
$Profile = Join-Path $SyntheticRoot 'operator_motion_profile.synthetic.json'
$DefaultProfile = Join-Path $Root 'config\operator_motion_profile.json'
$ValidationReport = Join-Path $SyntheticRoot 'validation_report.md'
$Report = Join-Path $MotionRoot 'motion_profile_selftest_report.md'
$StateFile = Join-Path $TestWindowRoot 'runtime\state.txt'

function Fail($Message) { throw $Message }

function Invoke-WinAgentJson {
    param([string[]]$WinArgs, [int[]]$AllowedExitCodes = @(0))
    $output = & $WinAgent @WinArgs
    $exit = $LASTEXITCODE
    if ($AllowedExitCodes -notcontains $exit) {
        Fail "winagent $($WinArgs -join ' ') exited $exit with output: $output"
    }
    try { $json = $output | ConvertFrom-Json } catch { Fail "Invalid JSON: $output" }
    return @{ exit = $exit; text = [string]$output; json = $json }
}

function Stop-TestWindow {
    Get-Process TestWindow -ErrorAction SilentlyContinue | ForEach-Object {
        $_.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (!$_.HasExited) { Stop-Process -Id $_.Id -Force }
    }
}

function Get-StateValue([string]$Name) {
    if (!(Test-Path -LiteralPath $StateFile)) { return '' }
    $line = Get-Content -LiteralPath $StateFile | Where-Object { $_ -like "$Name=*" } | Select-Object -First 1
    if (!$line) { return '' }
    return $line.Substring($Name.Length + 1)
}

function Get-FileHashText([string]$Path) {
    if (!(Test-Path -LiteralPath $Path)) { return '<missing>' }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function New-SyntheticRawSample {
    param(
        [string]$Scenario,
        [int]$Index,
        [int]$StartX,
        [int]$StartY,
        [int]$EndX,
        [int]$EndY,
        [bool]$Drag = $false
    )

    $points = New-Object System.Collections.Generic.List[object]
    $steps = 42 + ($Index % 9)
    $duration = 260 + (($Index * 17) % 360)
    for ($i = 0; $i -lt $steps; $i++) {
        $t = if ($steps -le 1) { 1.0 } else { [double]$i / [double]($steps - 1) }
        $ease = $t * $t * (3.0 - 2.0 * $t)
        $dx = $EndX - $StartX
        $dy = $EndY - $StartY
        $normalX = if ([math]::Abs($dy) -gt 0) { -[math]::Sign($dy) } else { 0 }
        $normalY = if ([math]::Abs($dx) -gt 0) { [math]::Sign($dx) } else { 0 }
        $wave = [math]::Sin($t * [math]::PI) * (4 + ($Index % 5))
        $jitter = (($i * 37 + $Index * 11) % 5) - 2
        $x = [int][math]::Round($StartX + ($dx * $ease) + ($normalX * $wave) + $jitter)
        $y = [int][math]::Round($StartY + ($dy * $ease) + ($normalY * $wave) - $jitter)
        $points.Add([pscustomobject]@{
            x = $x
            y = $y
            screen_x = $x
            screen_y = $y
            client_x = $x - 100
            client_y = $y - 100
            timestamp_ms = [int][math]::Round($duration * $t)
            button_state = if ($Drag -and $i -gt 2 -and $i -lt ($steps - 3)) { 'left' } else { 'none' }
        })
    }

    $sampleId = '{0}_{1:000}' -f $Scenario, $Index
    $raw = [pscustomobject]@{
        version = 1
        scenario = $Scenario
        sample_id = $sampleId
        coordinate_space = 'screen'
        captured_at = '2026-06-02 00:00:00'
        title = 'Synthetic Motion Lab'
        points = $points
    }
    $path = Join-Path $RawDir ("raw_{0}.json" -f $sampleId)
    $raw | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
}

if (!(Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run $Root\build.ps1 first." }
if (!(Test-Path -LiteralPath $TestWindowExe)) { Fail "Missing $TestWindowExe. Run $Root\build.ps1 first." }

$defaultProfileBefore = Get-FileHashText $DefaultProfile

New-Item -ItemType Directory -Force -Path $RawDir | Out-Null
Remove-Item -LiteralPath $Profile -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $ValidationReport -Force -ErrorAction SilentlyContinue
Get-ChildItem -LiteralPath $RawDir -Filter 'raw_*.json' -File -ErrorAction SilentlyContinue | Remove-Item -Force

$scenarios = @(
    @{ Name = 'horizontal_lr'; X1 = 120; Y1 = 240; X2 = 560; Y2 = 242 },
    @{ Name = 'horizontal_rl'; X1 = 560; Y1 = 260; X2 = 120; Y2 = 258 },
    @{ Name = 'vertical_ud'; X1 = 320; Y1 = 120; X2 = 322; Y2 = 520 },
    @{ Name = 'vertical_du'; X1 = 340; Y1 = 520; X2 = 342; Y2 = 120 },
    @{ Name = 'diagonal_lu_rd'; X1 = 140; Y1 = 140; X2 = 560; Y2 = 520 },
    @{ Name = 'diagonal_rd_lu'; X1 = 560; Y1 = 520; X2 = 140; Y2 = 140 },
    @{ Name = 'diagonal_ru_ld'; X1 = 560; Y1 = 140; X2 = 140; Y2 = 520 },
    @{ Name = 'diagonal_ld_ru'; X1 = 140; Y1 = 520; X2 = 560; Y2 = 140 },
    @{ Name = 'short_precision'; X1 = 260; Y1 = 260; X2 = 302; Y2 = 282 },
    @{ Name = 'medium_precision'; X1 = 180; Y1 = 380; X2 = 420; Y2 = 300 },
    @{ Name = 'long_precision'; X1 = 80; Y1 = 100; X2 = 760; Y2 = 540 },
    @{ Name = 'drag_line'; X1 = 180; Y1 = 480; X2 = 650; Y2 = 480; Drag = $true }
)

$sampleIndex = 1
for ($round = 0; $round -lt 3; $round++) {
    foreach ($scenario in $scenarios) {
        New-SyntheticRawSample `
            -Scenario $scenario.Name `
            -Index $sampleIndex `
            -StartX ($scenario.X1 + $round) `
            -StartY ($scenario.Y1 + $round) `
            -EndX ($scenario.X2 - $round) `
            -EndY ($scenario.Y2 - $round) `
            -Drag ([bool]$scenario.Drag)
        $sampleIndex++
    }
}

$sourceRequired = Invoke-WinAgentJson -WinArgs @('motion-calibrate', '--input', $RawDir, '--out', $Profile) -AllowedExitCodes @(1, 2)
if ($sourceRequired.json.error.code -ne 'MOTION_PROFILE_SOURCE_REQUIRED') {
    Fail "Expected MOTION_PROFILE_SOURCE_REQUIRED when --source is omitted, got $($sourceRequired.json.error.code)"
}

$calibrate = Invoke-WinAgentJson -WinArgs @('motion-calibrate', '--source', 'synthetic', '--input', $RawDir, '--out', $Profile)
if ($calibrate.json.data.sample_count -lt 32) { Fail "Expected at least 32 samples: $($calibrate.text)" }
if ($calibrate.json.data.source -ne 'synthetic') { Fail "Expected synthetic source: $($calibrate.text)" }
if (!(Test-Path -LiteralPath $Profile)) { Fail "Synthetic profile was not written: $Profile" }

$info = Invoke-WinAgentJson -WinArgs @('motion-profile-info', '--profile', $Profile)
if ($info.json.data.exists -ne $true) { Fail "Profile info did not report exists=true: $($info.text)" }
if ($info.json.data.source -ne 'synthetic') { Fail "Profile info did not report source=synthetic: $($info.text)" }
if (@('usable','good') -notcontains [string]$info.json.data.quality) { Fail "Expected usable/good profile quality: $($info.text)" }
if ($info.json.data.supported_modes -notcontains 'operator-human') { Fail "Profile missing supported mode operator-human: $($info.text)" }

$validate = Invoke-WinAgentJson -WinArgs @('motion-profile-validate', '--profile', $Profile, '--out', $ValidationReport)
if ($validate.json.data.result -ne 'PASS') { Fail "Profile validation did not pass: $($validate.text)" }
if ($validate.json.data.source -ne 'synthetic') { Fail "Validation did not report source=synthetic: $($validate.text)" }
if (!(Test-Path -LiteralPath $ValidationReport)) { Fail "Missing validation report: $ValidationReport" }
if ((Get-Content -LiteralPath $ValidationReport -Raw) -notmatch 'Source: synthetic') { Fail 'Validation report does not include source.' }

$badProfile = Join-Path $SyntheticRoot 'invalid_profile.json'
'{"version":1,"quality":"broken"}' | Set-Content -LiteralPath $badProfile -Encoding UTF8
$invalid = Invoke-WinAgentJson -WinArgs @('motion-profile-validate', '--profile', $badProfile, '--out', (Join-Path $SyntheticRoot 'invalid_report.md')) -AllowedExitCodes @(1)
if ($invalid.json.error.code -ne 'MOTION_PROFILE_INVALID') { Fail "Expected MOTION_PROFILE_INVALID, got $($invalid.json.error.code)" }

Stop-TestWindow
$proc = Start-Process -FilePath $TestWindowExe -PassThru
try {
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 250
        $find = Invoke-WinAgentJson -WinArgs @('find', '--title', 'Agent Test Window') -AllowedExitCodes @(0, 1)
    } while ($find.exit -ne 0 -and (Get-Date) -lt $deadline)
    if ($find.exit -ne 0) { Fail 'Agent Test Window did not appear.' }

    $testOnly = Invoke-WinAgentJson -WinArgs @('click', '--title', 'Agent Test Window', '--x', '80', '--y', '90', '--move-mode', 'operator-human', '--profile', $Profile) -AllowedExitCodes @(1)
    if ($testOnly.json.error.code -ne 'MOTION_PROFILE_TEST_ONLY') { Fail "Expected MOTION_PROFILE_TEST_ONLY, got $($testOnly.json.error.code)" }

    $fallback = Invoke-WinAgentJson -WinArgs @('click', '--title', 'Agent Test Window', '--x', '80', '--y', '90', '--move-mode', 'operator-human', '--profile', $Profile, '--fallback', 'fast-human')
    if ($fallback.json.data.move_profile -ne 'fast-human') { Fail "Expected explicit fallback to fast-human: $($fallback.text)" }

    $click = Invoke-WinAgentJson -WinArgs @('click', '--title', 'Agent Test Window', '--x', '80', '--y', '90', '--move-mode', 'operator-human', '--profile', $Profile, '--allow-synthetic-profile')
    if ($click.json.data.move_profile -ne 'operator-human') { Fail "operator-human click missing profile field: $($click.text)" }
    if ($click.json.data.operator_profile_source -ne 'synthetic') { Fail "operator-human click missing synthetic source: $($click.text)" }
    if (!$click.json.data.operator_profile_path -or !$click.json.data.synthesized_point_count) { Fail "operator-human click missing operator fields: $($click.text)" }

    $drag = Invoke-WinAgentJson -WinArgs @('drag', '--title', 'Agent Test Window', '--from-x', '120', '--from-y', '160', '--to-x', '180', '--to-y', '160', '--move-mode', 'operator-human', '--profile', $Profile, '--allow-synthetic-profile')
    if ($drag.json.data.move_profile -ne 'operator-human') { Fail "operator-human drag missing profile field: $($drag.text)" }

    $act = Invoke-WinAgentJson -WinArgs @('act', '--title', 'Agent Test Window', '--selector', 'uia:name=Click Me', '--action', 'click', '--move-mode', 'operator-human', '--profile', $Profile, '--allow-synthetic-profile')
    if ($act.json.data.action_method -ne 'mouse_click' -and $act.json.data.action_method -ne 'invoke_pattern') { Fail "operator-human act failed: $($act.text)" }

    $taskPath = Join-Path $SyntheticRoot 'operator_task.task.json'
    $taskReport = Join-Path $SyntheticRoot 'operator_task_report.md'
    $taskProfile = $Profile.Replace('\', '\\')
    $taskStateFile = $StateFile.Replace('\', '\\')
    @"
{
  "version": 1,
  "name": "operator_motion_task",
  "target": { "title": "Agent Test Window", "process": "TestWindow.exe" },
  "budget": { "max_steps": 10, "max_duration_ms": 60000, "max_recoveries": 1 },
  "steps": [
    { "name": "operator_click", "type": "act", "selector": "coord:x=80,y=90", "action": "click", "move_mode": "operator-human",
      "profile": "$taskProfile", "allow_synthetic_profile": true,
      "expect": { "file_contains_path": "$taskStateFile", "file_contains_text": "clicks=" } }
  ]
}
"@ | Set-Content -LiteralPath $taskPath -Encoding UTF8
    $task = Invoke-WinAgentJson -WinArgs @('run-task', '--file', $taskPath, '--report', $taskReport)
    if ($task.json.ok -ne $true) { Fail "operator-human run-task failed: $($task.text)" }

    if ((Get-StateValue 'clicks') -eq '') { Fail 'TestWindow state file did not contain clicks.' }
}
finally {
    if ($proc -and !$proc.HasExited) {
        $proc.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (!$proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    }
}

$defaultProfileAfter = Get-FileHashText $DefaultProfile
if ($defaultProfileBefore -ne $defaultProfileAfter) {
    Fail "motion_profile_selftest changed config\operator_motion_profile.json."
}

$cleanup = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'clean_artifacts.ps1') -DryRun 2>&1
$cleanupText = ($cleanup | Out-String)
if ($cleanupText -notmatch [regex]::Escape('artifacts\motion_profile')) {
    Fail 'clean_artifacts.ps1 dry-run did not identify motion_profile artifacts.'
}

@(
    '# DesktopVisual Motion Profile Selftest',
    '',
    '- Result: PASS',
    "- synthetic raw samples: $($sampleIndex - 1)",
    "- synthetic raw dir: $RawDir",
    "- synthetic profile: $Profile",
    "- source: $($info.json.data.source)",
    "- quality: $($info.json.data.quality)",
    "- validation report: $ValidationReport",
    '- default config profile unchanged: PASS',
    '- operator-human synthetic without allow: MOTION_PROFILE_TEST_ONLY',
    '- operator-human click with allow: PASS',
    '- operator-human drag with allow: PASS',
    '- operator-human run-task with allow: PASS',
    '- explicit fallback fast-human: PASS',
    '- invalid profile: MOTION_PROFILE_INVALID',
    '- clean_artifacts motion_profile: PASS'
) | Set-Content -LiteralPath $Report -Encoding UTF8

Write-Host 'Motion profile selftest passed.'
Write-Host "Report: $Report"
