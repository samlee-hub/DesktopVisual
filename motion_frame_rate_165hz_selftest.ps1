param([string]$Root = '')

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.12.1_visible_ui_foundation_hardening'
$Report = Join-Path $OutDir 'motion_165hz_report.md'
$SafetyConfig = Join-Path $OutDir 'motion_165hz_safety.conf'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Fail([string]$Message) { throw $Message }
function Assert($Condition, [string]$Message) { if (-not $Condition) { Fail $Message } }

function Invoke-Agent {
    param([string[]]$WinArgs, [int[]]$Allowed = @(0))
    $output = & $WinAgent @WinArgs
    $exit = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    if ($Allowed -notcontains $exit) {
        Fail "winagent $($WinArgs -join ' ') exited $exit with output: $text"
    }
    try { return [pscustomobject]@{ exit = $exit; text = $text; json = ($text | ConvertFrom-Json) } } catch { Fail "Invalid JSON: $text" }
}

if (-not (Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run $Root\build.ps1 first." }

@(
    'allowed_titles=',
    'allowed_processes=explorer.exe',
    'allowed_read_roots=${PROJECT_ROOT};${PROJECT_ROOT}\artifacts',
    'allowed_write_roots=${PROJECT_ROOT}\artifacts',
    'max_steps=100',
    'max_duration_ms=120000',
    'emergency_stop_key=F12',
    'allow_absolute_screen_click=true'
) | Set-Content -Encoding UTF8 -LiteralPath $SafetyConfig

Add-Type -AssemblyName System.Windows.Forms
$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$targetX = [Math]::Max($bounds.Left + 40, [Math]::Min($bounds.Right - 40, $bounds.Left + [Math]::Floor($bounds.Width * 0.35)))
$targetY = [Math]::Max($bounds.Top + 40, [Math]::Min($bounds.Bottom - 40, $bounds.Top + [Math]::Floor($bounds.Height * 0.35)))

$oldConfig = $env:DESKTOPVISUAL_SAFETY_CONFIG
$env:DESKTOPVISUAL_SAFETY_CONFIG = $SafetyConfig
try {
    $move = Invoke-Agent -WinArgs @(
        'desktop-move',
        '--screen-x', "$targetX",
        '--screen-y', "$targetY",
        '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY',
        '--target-description', '165Hz motion selftest',
        '--coordinate-source', 'motion_frame_rate_165hz_selftest',
        '--humanmode', 'true',
        '--latency-profile', 'fast-visible-ui',
        '--motion-profile', '165hz',
        '--motion-frame-rate', '165',
        '--move-duration-ms', '180'
    )
} finally {
    $env:DESKTOPVISUAL_SAFETY_CONFIG = $oldConfig
}

$json = $move.json
Assert ($json.ok -eq $true) "desktop-move 165Hz should pass: $($move.text)"
$motion = $json.data.human_action_result.motion
Assert ($motion.target_motion_frame_rate_hz -eq 165) 'target_motion_frame_rate_hz must be 165.'
Assert ([double]$motion.target_frame_interval_ms -gt 6.0 -and [double]$motion.target_frame_interval_ms -lt 6.2) 'target frame interval should be about 6.06 ms.'
Assert ($motion.frame_timestamps_recorded -eq $true) 'FAIL_MOTION_FRAME_TIMESTAMPS_MISSING'
Assert ($motion.frame_timestamps_ms.Count -ge 8) 'Motion evidence must include per-frame timestamps.'
Assert ([double]$motion.actual_frame_rate_hz -ge 120.0) 'FAIL_MOTION_FRAME_RATE_TOO_LOW'
Assert ([double]$motion.average_frame_interval_ms -le 10.0) 'Average frame interval must be <= 10 ms.'
Assert ([double]$motion.p95_frame_interval_ms -le 20.0) 'p95 frame interval must be <= 20 ms.'
Assert ($motion.target_miss -eq $false) 'Motion must not miss target.'
Assert ($motion.cursor_overshoot -eq $false) 'Motion must not overshoot cursor target.'

@(
    '# 165Hz Motion Frame Rate Selftest',
    '',
    '- result: PASS',
    '- target_motion_frame_rate_hz: 165',
    "- target_frame_interval_ms: $($motion.target_frame_interval_ms)",
    "- actual_frame_rate_hz: $($motion.actual_frame_rate_hz)",
    "- average_frame_interval_ms: $($motion.average_frame_interval_ms)",
    "- p95_frame_interval_ms: $($motion.p95_frame_interval_ms)",
    "- frame_timestamp_count: $($motion.frame_timestamps_ms.Count)",
    '- target_miss: false',
    '- cursor_overshoot: false'
) | Set-Content -Encoding UTF8 -LiteralPath $Report

Write-Host 'PASS motion_frame_rate_165hz_selftest'
exit 0
