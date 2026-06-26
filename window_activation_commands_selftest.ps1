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
$Report = Join-Path $ArtifactDir 'window_activation_report.md'
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

function Fail([string]$Message) { throw $Message }

function Invoke-WinAgentJson {
    param([string[]]$WinArgs, [int[]]$AllowedExitCodes = @(0))
    $output = & $WinAgent @WinArgs 2>&1
    $exit = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    if ($AllowedExitCodes -notcontains $exit) {
        Fail "winagent $($WinArgs -join ' ') exited $exit with output: $text"
    }
    try { $json = $text | ConvertFrom-Json } catch { Fail "Invalid JSON from $($WinArgs -join ' '): $text" }
    [pscustomobject]@{ exit = $exit; json = $json; text = $text }
}

if (-not (Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run build.ps1 first." }
if (-not (Test-Path -LiteralPath $TestWindowExe)) { Fail "Missing $TestWindowExe. Run build.ps1 first." }

Get-Process TestWindow -ErrorAction SilentlyContinue | ForEach-Object {
    $_.CloseMainWindow() | Out-Null
    Start-Sleep -Milliseconds 200
    if (-not $_.HasExited) { Stop-Process -Id $_.Id -Force }
}

$proc = Start-Process -FilePath $TestWindowExe -PassThru
try {
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 200
        $find = Invoke-WinAgentJson -WinArgs @('find', '--title', 'Agent Test Window') -AllowedExitCodes @(0, 1)
    } while ($find.exit -ne 0 -and (Get-Date) -lt $deadline)
    if ($find.exit -ne 0) { Fail 'Agent Test Window did not appear.' }

    $focus = Invoke-WinAgentJson -WinArgs @('focus-window', '--title', 'Agent', '--timeout-ms', '2500')
    if ($focus.json.ok -ne $true) { Fail "focus-window failed: $($focus.text)" }
    if ($focus.json.data.canonical_command -ne 'activate-window') { Fail 'focus-window must record canonical_command=activate-window.' }
    if ($focus.json.data.foreground_after_present -ne $true) { Fail 'focus-window did not verify foreground.' }
    if (-not $focus.json.data.target_window_title -or $focus.json.data.target_window_title -notmatch 'Agent Test Window') {
        Fail "focus-window did not partial-match Agent Test Window: $($focus.text)"
    }
    $hwnd = [string]$focus.json.data.hwnd
    if ([string]::IsNullOrWhiteSpace($hwnd)) { Fail 'focus-window did not return hwnd.' }

    foreach ($cmd in @('activate-window', 'bring-window-front')) {
        $result = Invoke-WinAgentJson -WinArgs @($cmd, '--hwnd', $hwnd, '--timeout-ms', '2500')
        if ($result.json.ok -ne $true) { Fail "$cmd failed: $($result.text)" }
        if ($result.json.data.foreground_after_present -ne $true) { Fail "$cmd did not verify foreground." }
    }

    $minimized = Invoke-WinAgentJson -WinArgs @('minimize-window', '--hwnd', $hwnd, '--timeout-ms', '2500')
    if ($minimized.json.ok -ne $true -or $minimized.json.data.window_minimized -ne $true) {
        Fail "minimize-window failed: $($minimized.text)"
    }

    $restored = Invoke-WinAgentJson -WinArgs @('restore-window', '--hwnd', $hwnd, '--timeout-ms', '2500')
    if ($restored.json.ok -ne $true -or $restored.json.data.foreground_after_present -ne $true) {
        Fail "restore-window failed foreground verification: $($restored.text)"
    }

    $missing = Invoke-WinAgentJson -WinArgs @('activate-window', '--title', 'No Such DesktopVisual Selftest Window') -AllowedExitCodes @(1)
    if ($missing.json.error.code -ne 'WINDOW_NOT_FOUND') { Fail "Expected WINDOW_NOT_FOUND, got $($missing.json.error.code)." }
    if ($null -eq $missing.json.data.candidate_windows) { Fail 'failure output must include candidate_windows.' }

    @(
        '# Window Activation Commands Selftest',
        '',
        '- Result: PASS',
        '- focus-window exists: true',
        '- activate-window exists: true',
        '- bring-window-front exists: true',
        '- minimize-window exists: true',
        '- restore-window exists: true',
        '- partial_title_match: true',
        "- hwnd_exact_match: $hwnd",
        '- foreground_verification: true',
        '- failure_candidate_windows: true'
    ) | Set-Content -LiteralPath $Report -Encoding UTF8

    Write-Host 'WINDOW_ACTIVATION_COMMANDS_SELFTEST_PASS'
    Write-Host "Report: $Report"
}
finally {
    if ($proc -and -not $proc.HasExited) {
        $proc.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    }
}
