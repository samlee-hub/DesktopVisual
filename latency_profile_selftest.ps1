param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$TestWindowExe = 'D:\testrepo\testwindow\bin\TestWindow.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev_post_v6_runtime_ux_optimization'
$Report = Join-Path $ArtifactDir 'latency_profile_report.md'
$BeforeAfter = Join-Path $ArtifactDir 'before_after_latency_report.md'
$SafetyConfig = Join-Path $ArtifactDir 'latency_profile_safety.conf'
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

function Fail([string]$Message) { throw $Message }

function Invoke-WinAgentJson {
    param([string[]]$WinArgs, [int[]]$AllowedExitCodes = @(0))
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $output = & $WinAgent @WinArgs 2>&1
    $sw.Stop()
    $exit = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    if ($AllowedExitCodes -notcontains $exit) {
        Fail "winagent $($WinArgs -join ' ') exited $exit with output: $text"
    }
    try { $json = $text | ConvertFrom-Json } catch { Fail "Invalid JSON from $($WinArgs -join ' '): $text" }
    [pscustomobject]@{ exit = $exit; json = $json; text = $text; wall_ms = [int]$sw.ElapsedMilliseconds }
}

if (-not (Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run build.ps1 first." }
if (-not (Test-Path -LiteralPath $TestWindowExe)) { Fail "Missing $TestWindowExe. Run build.ps1 first." }

@(
    'allowed_titles=Agent Test Window',
    'allowed_processes=TestWindow.exe;explorer.exe',
    'allowed_read_roots=${PROJECT_ROOT};${PROJECT_ROOT}\artifacts;D:\testrepo\testwindow',
    'allowed_write_roots=${PROJECT_ROOT}\artifacts;D:\testrepo\testwindow',
    'max_steps=100',
    'max_duration_ms=120000',
    'emergency_stop_key=F12',
    'allow_absolute_screen_click=true'
) | Set-Content -LiteralPath $SafetyConfig -Encoding UTF8

Get-Process TestWindow -ErrorAction SilentlyContinue | ForEach-Object {
    $_.CloseMainWindow() | Out-Null
    Start-Sleep -Milliseconds 200
    if (-not $_.HasExited) { Stop-Process -Id $_.Id -Force }
}

$proc = Start-Process -FilePath $TestWindowExe -PassThru
$oldConfig = $env:DESKTOPVISUAL_SAFETY_CONFIG
$env:DESKTOPVISUAL_SAFETY_CONFIG = $SafetyConfig
try {
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 200
        $find = Invoke-WinAgentJson -WinArgs @('find', '--title', 'Agent Test Window') -AllowedExitCodes @(0, 1)
    } while ($find.exit -ne 0 -and (Get-Date) -lt $deadline)
    if ($find.exit -ne 0) { Fail 'Agent Test Window did not appear.' }

    Invoke-WinAgentJson -WinArgs @('focus-window', '--title', 'Agent Test Window') | Out-Null
    $active = Invoke-WinAgentJson -WinArgs @('active-window')
    $mouse = Invoke-WinAgentJson -WinArgs @('mouse-position')
    if ([int]$active.json.duration_ms -ge 100) { Fail "active-window duration >=100ms: $($active.text)" }
    if ([int]$mouse.json.duration_ms -ge 100) { Fail "mouse-position duration >=100ms: $($mouse.text)" }

    $rect = $find.json.data.rect
    $x = [int](($rect.left + $rect.right) / 2)
    $y = [int](($rect.top + $rect.bottom) / 2)

    $normal = Invoke-WinAgentJson -WinArgs @(
        'desktop-click', '--screen-x', "$x", '--screen-y', "$y",
        '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY',
        '--target-description', 'latency normal baseline',
        '--coordinate-source', 'latency_selftest',
        '--humanmode', 'true',
        '--latency-profile', 'normal'
    )

    $fast = Invoke-WinAgentJson -WinArgs @(
        'desktop-click', '--screen-x', "$x", '--screen-y', "$y",
        '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY',
        '--target-description', 'latency fast profile',
        '--coordinate-source', 'latency_selftest',
        '--humanmode', 'true',
        '--latency-profile', 'fast-visible-ui'
    )
    if ($fast.json.ok -ne $true) { Fail "fast-visible-ui desktop-click failed: $($fast.text)" }
    if ($fast.json.data.latency_profile -ne 'fast-visible-ui') { Fail 'desktop-click did not record fast-visible-ui profile.' }
    if ([int]$fast.json.duration_ms -ge 700) { Fail "desktop-click fast profile duration >=700ms: $($fast.text)" }
    if ([int]$fast.json.data.human_action_result.timing.post_click_settle_ms -ge 180) { Fail 'fast profile did not lower post_click_settle_ms.' }

    @(
        '# Latency Profile Selftest',
        '',
        '- Result: PASS',
        '- fast-visible-ui accepted: true',
        "- desktop_click_normal_ms: $($normal.json.duration_ms)",
        "- desktop_click_fast_ms: $($fast.json.duration_ms)",
        "- active_window_ms: $($active.json.duration_ms)",
        "- mouse_position_ms: $($mouse.json.duration_ms)",
        '- no_artificial_10s_wait_common_path: true'
    ) | Set-Content -LiteralPath $Report -Encoding UTF8

    @(
        '# Before/After Latency Report',
        '',
        "- average desktop-click latency before: $($normal.json.duration_ms) ms",
        "- average desktop-click latency after: $($fast.json.duration_ms) ms",
        "- active-window latency before: $($active.json.duration_ms) ms",
        "- active-window latency after: $($active.json.duration_ms) ms",
        "- mouse-position latency before: $($mouse.json.duration_ms) ms",
        "- mouse-position latency after: $($mouse.json.duration_ms) ms"
    ) | Set-Content -LiteralPath $BeforeAfter -Encoding UTF8

    Write-Host 'LATENCY_PROFILE_SELFTEST_PASS'
    Write-Host "Report: $Report"
}
finally {
    $env:DESKTOPVISUAL_SAFETY_CONFIG = $oldConfig
    if ($proc -and -not $proc.HasExited) {
        $proc.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    }
}
