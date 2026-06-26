param(
    [string]$Root = '',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$ExpectedVersion = (Get-Content -LiteralPath (Join-Path $Root 'VERSION') -Raw).Trim()

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev5.9.1_pre_v6_handoff\humanmode_motion_pacing'
$TracePath = Join-Path $ArtifactRoot 'action_trace.jsonl'
New-Item -ItemType Directory -Force -Path $ArtifactRoot | Out-Null
Set-Content -LiteralPath $TracePath -Value '' -Encoding UTF8

function Fail($Message) { throw $Message }

function Invoke-AgentJson([string[]]$CmdArgs, [switch]$AllowFailure) {
    $output = & $WinAgent @CmdArgs 2>&1
    $exit = $LASTEXITCODE
    if ($exit -ne 0 -and -not $AllowFailure) {
        Fail "winagent $($CmdArgs -join ' ') exited $exit with output: $output"
    }
    try {
        $json = $output | ConvertFrom-Json
    } catch {
        Fail "Invalid JSON from winagent $($CmdArgs -join ' '): $output"
    }
    $json | Add-Member -NotePropertyName _exit_code -NotePropertyValue $exit -Force
    return $json
}

function Write-JsonLine($Path, $Object) {
    ($Object | ConvertTo-Json -Compress -Depth 30) | Add-Content -LiteralPath $Path -Encoding UTF8
}

function Add-TraceFromResult($Result) {
    $har = $Result.data.human_action_result
    if (-not $har) { Fail 'Missing data.human_action_result.' }
    Write-JsonLine $TracePath ([pscustomobject]@{
        action_type = 'mouse_move_humanmode_start'
        from_x = $har.cursor.start_x
        from_y = $har.cursor.start_y
        target_x = $har.target.x
        target_y = $har.target.y
        duration_ms = $har.motion.move_duration_ms
        planned_steps = $har.motion.planned_steps
        easing = $har.motion.easing
        timestamp = $har.timing.move_start_ts
    })
    $path = @($har.motion.planned_path)
    foreach ($idx in (@(0, [Math]::Floor(($path.Count - 1) / 2), ($path.Count - 1)) | Select-Object -Unique)) {
        Write-JsonLine $TracePath ([pscustomobject]@{
            action_type = 'mouse_move_humanmode_step'
            step_index = [int]($idx + 1)
            step_count = $path.Count
            x = $path[$idx].x
            y = $path[$idx].y
            timestamp = $har.timing.move_start_ts
        })
    }
    Write-JsonLine $TracePath ([pscustomobject]@{
        action_type = 'mouse_move_humanmode_end'
        final_x = $har.cursor.final_x
        final_y = $har.cursor.final_y
        target_x = $har.target.x
        target_y = $har.target.y
        within_epsilon = $har.cursor.within_target_epsilon_before_click
        timestamp = $har.timing.move_end_ts
    })
    if ($har.action_type -in @('mouse_click', 'mouse_double_click')) {
        Write-JsonLine $TracePath ([pscustomobject]@{
            action_type = 'dwell_before_click'
            duration_ms = $har.motion.dwell_before_click_ms
            timestamp = $har.timing.dwell_start_ts
        })
        Write-JsonLine $TracePath ([pscustomobject]@{
            action_type = 'mouse_click_down'
            x = $har.cursor.actual_before_click_x
            y = $har.cursor.actual_before_click_y
            timestamp = $har.timing.click_down_ts
        })
        Write-JsonLine $TracePath ([pscustomobject]@{
            action_type = 'mouse_click_up'
            x = $har.cursor.actual_before_click_x
            y = $har.cursor.actual_before_click_y
            timestamp = $har.timing.click_up_ts
        })
    }
    if ($har.action_type -eq 'mouse_double_click') {
        Write-JsonLine $TracePath ([pscustomobject]@{
            action_type = 'double_click_interval'
            duration_ms = $har.motion.double_click_interval_ms
            timestamp = $har.timing.click_up_ts
        })
        Write-JsonLine $TracePath ([pscustomobject]@{
            action_type = 'mouse_click_down'
            x = $har.cursor.actual_before_click_x
            y = $har.cursor.actual_before_click_y
            timestamp = $har.timing.second_click_down_ts
        })
        Write-JsonLine $TracePath ([pscustomobject]@{
            action_type = 'mouse_click_up'
            x = $har.cursor.actual_before_click_x
            y = $har.cursor.actual_before_click_y
            timestamp = $har.timing.second_click_up_ts
        })
    }
}

function Assert-HumanResult($Result, [string]$ExpectedType) {
    if (-not $Result.ok) { Fail "Expected command ok=true. output=$($Result | ConvertTo-Json -Compress -Depth 30)" }
    $har = $Result.data.human_action_result
    if (-not $har) { Fail 'Missing HumanActionResult.' }
    if ($har.schema_version -ne 'human_action_result.v1') { Fail "Unexpected schema_version $($har.schema_version)." }
    if ($har.runtime_version -ne $ExpectedVersion) { Fail "Unexpected runtime_version $($har.runtime_version)." }
    if ($har.action_type -ne $ExpectedType) { Fail "Expected action_type $ExpectedType, got $($har.action_type)." }
    if (-not $har.humanmode -or $har.backend_action -or $har.direct_launch -or $har.fallback_used) { Fail 'HumanActionResult backend/fallback flags are invalid.' }
    if ([int]$har.motion.move_duration_ms -lt 250) { Fail "move_duration_ms too low: $($har.motion.move_duration_ms)." }
    if ([int]$har.motion.actual_steps -lt 8) { Fail "actual_steps too low: $($har.motion.actual_steps)." }
    if (-not $har.cursor.within_target_epsilon_before_click) { Fail 'Cursor was not within target epsilon.' }
    if ($ExpectedType -in @('mouse_click', 'mouse_double_click')) {
        if ([int]$har.motion.dwell_before_click_ms -lt 80) { Fail "dwell_before_click_ms too low: $($har.motion.dwell_before_click_ms)." }
        if (-not $har.verification.click_after_move_end -or -not $har.verification.dwell_completed_before_click) { Fail 'Click verification flags are invalid.' }
        if (-not $har.actual_click_sent) { Fail 'Click was not sent.' }
    }
    if ($ExpectedType -eq 'mouse_double_click') {
        if ([int]$har.motion.double_click_interval_ms -lt 80) { Fail "double_click_interval_ms too low: $($har.motion.double_click_interval_ms)." }
        if (-not $har.actual_double_click_sent) { Fail 'Double-click was not sent.' }
    }
}

if (-not $SkipBuild) {
    & "$Root\build.ps1" -Root $Root
    if ($LASTEXITCODE -ne 0) { Fail 'Build failed.' }
}

Add-Type -AssemblyName System.Windows.Forms
$screen = [System.Windows.Forms.SystemInformation]::VirtualScreen
$start = Invoke-AgentJson -CmdArgs @('mouse-position')
$baseX = [Math]::Min($screen.Right - 80, [Math]::Max($screen.Left + 80, [int]$start.data.screen_x + 80))
$baseY = [Math]::Min($screen.Bottom - 80, [Math]::Max($screen.Top + 80, [int]$start.data.screen_y + 50))
$points = @(
    @{ x = $baseX; y = $baseY },
    @{ x = [Math]::Min($screen.Right - 80, $baseX + 70); y = [Math]::Min($screen.Bottom - 80, $baseY + 50) },
    @{ x = [Math]::Max($screen.Left + 80, $baseX - 70); y = [Math]::Min($screen.Bottom - 80, $baseY + 90) }
)

$moveResultPath = Join-Path $ArtifactRoot 'desktop_move_human_action_result.json'
$clickResultPath = Join-Path $ArtifactRoot 'desktop_click_human_action_result.json'
$doubleResultPath = Join-Path $ArtifactRoot 'desktop_double_click_human_action_result.json'
$failureResultPath = Join-Path $ArtifactRoot 'desktop_click_failure_human_action_result.json'

$move = Invoke-AgentJson -CmdArgs @('desktop-move', '--screen-x', "$($points[0].x)", '--screen-y', "$($points[0].y)", '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY', '--humanmode', 'true', '--result-json', $moveResultPath, '--target-description', 'v5.9.3 safe move target', '--coordinate-source', 'manual_fixed')
Assert-HumanResult $move 'mouse_move'
Add-TraceFromResult $move

$click = Invoke-AgentJson -CmdArgs @('desktop-click', '--screen-x', "$($points[1].x)", '--screen-y', "$($points[1].y)", '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY', '--humanmode', 'true', '--result-json', $clickResultPath, '--target-description', 'v5.9.3 safe click target', '--coordinate-source', 'manual_fixed')
Assert-HumanResult $click 'mouse_click'
Add-TraceFromResult $click

$double = Invoke-AgentJson -CmdArgs @('desktop-double-click', '--screen-x', "$($points[2].x)", '--screen-y', "$($points[2].y)", '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY', '--humanmode', 'true', '--result-json', $doubleResultPath, '--target-description', 'v5.9.3 safe double-click target', '--coordinate-source', 'manual_fixed')
Assert-HumanResult $double 'mouse_double_click'
Add-TraceFromResult $double

$failure = Invoke-AgentJson -CmdArgs @('desktop-click', '--screen-x', "$($screen.Right + 5000)", '--screen-y', "$($screen.Bottom + 5000)", '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY', '--humanmode', 'true', '--result-json', $failureResultPath) -AllowFailure
if ($failure.ok -or $failure._exit_code -eq 0) { Fail 'Invalid target failure returned ok or exit code 0.' }
if (-not $failure.data.human_action_result -or $failure.data.human_action_result.ok -or -not $failure.data.human_action_result.error.code) {
    Fail 'Failure HumanActionResult missing ok=false or error.code.'
}

foreach ($path in @($moveResultPath, $clickResultPath, $doubleResultPath, $failureResultPath)) {
    if (-not (Test-Path -LiteralPath $path)) { Fail "Missing result-json artifact $path." }
    Get-Content -LiteralPath $path -Raw | ConvertFrom-Json | Out-Null
}

$trace = Get-Content -LiteralPath $TracePath | Where-Object { $_.Trim() }
foreach ($line in $trace) { $line | ConvertFrom-Json | Out-Null }
$traceObjects = $trace | ForEach-Object { $_ | ConvertFrom-Json }
if (-not ($traceObjects.action_type -contains 'mouse_move_humanmode_start')) { Fail 'Trace missing mouse_move_humanmode_start.' }
if (-not ($traceObjects.action_type -contains 'mouse_move_humanmode_step')) { Fail 'Trace missing mouse_move_humanmode_step.' }
if (-not ($traceObjects.action_type -contains 'mouse_move_humanmode_end')) { Fail 'Trace missing mouse_move_humanmode_end.' }
if (-not ($traceObjects.action_type -contains 'dwell_before_click')) { Fail 'Trace missing dwell_before_click.' }
if (-not ($traceObjects.action_type -contains 'double_click_interval')) { Fail 'Trace missing double_click_interval.' }

$summary = [pscustomobject]@{
    ok = $true
    version = $ExpectedVersion
    humanmode_pacing_checked = $true
    min_move_duration_ms = @($move.data.human_action_result.motion.move_duration_ms, $click.data.human_action_result.motion.move_duration_ms, $double.data.human_action_result.motion.move_duration_ms | Measure-Object -Minimum).Minimum
    min_dwell_before_click_ms = @($click.data.human_action_result.motion.dwell_before_click_ms, $double.data.human_action_result.motion.dwell_before_click_ms | Measure-Object -Minimum).Minimum
    min_double_click_interval_ms = $double.data.human_action_result.motion.double_click_interval_ms
    click_before_move_end_count = 0
    instant_click_after_move_count = 0
    human_action_result_count = 4
    human_action_result_parse_errors = 0
    trace_path = $TracePath
}
$summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'humanmode_motion_pacing_test_result.json') -Encoding UTF8

@(
    "# v$ExpectedVersion HumanMode Motion Pacing Regression Test",
    '',
    '- Result: PASS',
    "- Trace: $TracePath",
    "- HumanActionResult count: $($summary.human_action_result_count)",
    "- Min move duration ms: $($summary.min_move_duration_ms)",
    "- Min dwell before click ms: $($summary.min_dwell_before_click_ms)",
    "- Min double-click interval ms: $($summary.min_double_click_interval_ms)",
    '- Failure contract: ok=false with error.code verified'
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'humanmode_motion_pacing_test_report.md') -Encoding UTF8

Write-Host "v$ExpectedVersion HumanMode motion pacing test PASS."
Write-Host "Artifacts: $ArtifactRoot"
