param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$TestWindowExe = 'D:\testrepo\testwindow\bin\TestWindow.exe'
$Artifacts = Join-Path $Root 'artifacts\dev4.2.0'
$Events = Join-Path $Artifacts 'events.jsonl'
$Report = Join-Path $Artifacts 'observe_loop_report.md'
$SelftestReport = Join-Path $Artifacts 'observe_loop_selftest_report.md'

function Fail($Message) { throw $Message }

function Invoke-WinAgentJson {
    param([string[]]$WinArgs, [int[]]$AllowedExitCodes = @(0))
    $output = & $WinAgent @WinArgs 2>&1
    $exit = $LASTEXITCODE
    if ($AllowedExitCodes -notcontains $exit) {
        Fail "winagent $($WinArgs -join ' ') exited $exit with output: $output"
    }
    try {
        $json = $output | ConvertFrom-Json
    } catch {
        Fail "Invalid JSON from winagent $($WinArgs -join ' '): $output"
    }
    return @{ exit = $exit; text = [string]$output; json = $json }
}

if (!(Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run $Root\build.ps1 first." }
if (!(Test-Path -LiteralPath $TestWindowExe)) { Fail "Missing $TestWindowExe. Run $Root\build.ps1 first." }

New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null
Remove-Item -LiteralPath $Events, $Report, $SelftestReport -ErrorAction SilentlyContinue

Get-Process TestWindow -ErrorAction SilentlyContinue | ForEach-Object {
    $_.CloseMainWindow() | Out-Null
    Start-Sleep -Milliseconds 300
    if (!$_.HasExited) { Stop-Process -Id $_.Id -Force }
}

$tw = Start-Process -FilePath $TestWindowExe -PassThru
try {
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 250
        $find = Invoke-WinAgentJson -WinArgs @('find', '--title', 'Agent Test Window') -AllowedExitCodes @(0, 1)
    } while ($find.exit -ne 0 -and (Get-Date) -lt $deadline)
    if ($find.exit -ne 0) { Fail 'Agent Test Window did not appear.' }

    $loopArgs = @(
        'observe-loop',
        '--title', 'Agent Test Window',
        '--interval-ms', '150',
        '--max-duration-ms', '5000',
        '--max-events', '8',
        '--max-no-change-rounds', '20',
        '--debounce-ms', '250',
        '--roi', '0,0,400,300',
        '--changed-regions-only',
        '--out', $Events,
        '--report', $Report
    )
    $loop = Start-Process -FilePath $WinAgent -ArgumentList $loopArgs -NoNewWindow -PassThru
    Start-Sleep -Milliseconds 700

    $changeAttempt = 'PASS'
    $click = Invoke-WinAgentJson -WinArgs @('uia-click', '--title', 'Agent Test Window', '--name', 'Click Me') -AllowedExitCodes @(0, 1)
    if ($click.exit -ne 0) {
        $changeAttempt = "SKIPPED external change action: $($click.json.error.code)"
    }
    Start-Sleep -Milliseconds 600
    if ($click.exit -eq 0) {
        $type = Invoke-WinAgentJson -WinArgs @('uia-type', '--title', 'Agent Test Window', '--name', 'Input', '--text', 'loop changed') -AllowedExitCodes @(0, 1)
        if ($type.exit -ne 0) {
            $changeAttempt = "PARTIAL external type action skipped: $($type.json.error.code)"
        }
    }

    if (!$loop.WaitForExit(8000)) {
        Stop-Process -Id $loop.Id -Force
        Fail 'observe-loop did not exit within guard timeout.'
    }
    $loop.Refresh()
    if ($null -ne $loop.ExitCode -and $loop.ExitCode -ne 0) { Fail "observe-loop exited $($loop.ExitCode)." }
    if (!(Test-Path -LiteralPath $Events)) { Fail "Missing events artifact: $Events" }
    if (!(Test-Path -LiteralPath $Report)) { Fail "Missing report artifact: $Report" }

    $lines = @(Get-Content -LiteralPath $Events | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($lines.Count -lt 2) { Fail "Expected at least 2 events, got $($lines.Count)." }
    $parsedEvents = @()
    foreach ($line in $lines) {
        try {
            $parsedEvents += ($line | ConvertFrom-Json)
        } catch {
            Fail "Invalid JSONL event: $line"
        }
    }
    $types = @($parsedEvents | ForEach-Object { $_.type })
    if ($types -notcontains 'target_ready') { Fail "Missing target_ready event. Types: $($types -join ',')" }
    if (($types -notcontains 'region_changed') -and ($types -notcontains 'text_changed') -and ($types -notcontains 'element_appeared')) {
        Fail "Expected a change event. Types: $($types -join ',')"
    }
    $last = $parsedEvents[-1]
    if (!$last.cache -or $null -eq $last.cache.cache_hit) { Fail 'Events missing cache/delta metadata.' }
    if (!$last.loop_guard) { Fail 'Events missing loop_guard metadata.' }
    if (!(Select-String -LiteralPath $Report -Pattern 'Observe Loop Report' -SimpleMatch -Quiet)) { Fail 'Report missing title.' }

    @(
        '# DesktopVisual observe-loop Selftest',
        '',
        '- Result: PASS',
        "- Events: ${Events}",
        "- Report: $Report",
        "- Event count: $($lines.Count)",
        "- Event types: $($types -join ', ')",
        "- External change attempt: $changeAttempt",
        '- JSONL parse: PASS',
        '- Loop guard: PASS'
    ) | Set-Content -Encoding UTF8 -LiteralPath $SelftestReport

    Write-Host 'observe-loop selftest passed.'
    Write-Host "Report: $SelftestReport"
} finally {
    Get-Process winagent -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $PID } | ForEach-Object {
        if ($_.Path -eq $WinAgent) { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
    }
    if ($tw -and !$tw.HasExited) {
        $tw.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (!$tw.HasExited) { Stop-Process -Id $tw.Id -Force }
    }
}
