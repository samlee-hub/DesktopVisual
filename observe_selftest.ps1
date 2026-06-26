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
$Report = Join-Path $Artifacts 'observe_selftest_report.md'
$CaseFile = Join-Path $Artifacts 'observe_selftest.case'
$CaseReport = Join-Path $Artifacts 'observe_case_report.md'
$ObserveOut = Join-Path $Artifacts 'observe_case_data.json'

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

if (!(Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run $Root\build.ps1 first." }
if (!(Test-Path -LiteralPath $TestWindowExe)) { Fail "Missing $TestWindowExe. Run $Root\build.ps1 first." }

New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null
Remove-Item -LiteralPath $ObserveOut -ErrorAction SilentlyContinue
Get-Process TestWindow -ErrorAction SilentlyContinue | ForEach-Object {
    $_.CloseMainWindow() | Out-Null
    Start-Sleep -Milliseconds 300
    if (!$_.HasExited) { Stop-Process -Id $_.Id -Force }
}

$proc = Start-Process -FilePath $TestWindowExe -PassThru
try {
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 250
        $find = Invoke-WinAgentJson -WinArgs @('find', '--title', 'Agent Test Window') -AllowedExitCodes @(0, 1)
    } while ($find.exit -ne 0 -and (Get-Date) -lt $deadline)
    if ($find.exit -ne 0) { Fail 'Agent Test Window did not appear.' }

    $observe = Invoke-WinAgentJson -WinArgs @('observe', '--title', 'Agent Test Window')
    if ($observe.json.ok -ne $true -or $observe.json.command -ne 'observe') { Fail "observe did not return success envelope: $($observe.text)" }
    if (!$observe.json.target -or !$observe.json.data.target_window) { Fail "observe missing target_window: $($observe.text)" }
    if (!$observe.json.data.active_window) { Fail "observe missing active_window: $($observe.text)" }
    if ($null -eq $observe.json.data.focus_verified) { Fail "observe missing focus_verified: $($observe.text)" }
    if ($null -eq $observe.json.data.mouse.screen_x -or $null -eq $observe.json.data.mouse.screen_y) { Fail "observe missing mouse: $($observe.text)" }
    if (!$observe.json.data.screenshot.path -or !(Test-Path -LiteralPath $observe.json.data.screenshot.path)) { Fail "observe screenshot missing: $($observe.text)" }
    if ($observe.json.data.uia.available -ne $true) { Fail "observe UIA unavailable unexpectedly: $($observe.text)" }
    if ([int]$observe.json.data.uia.element_count -le 0) { Fail "observe UIA element_count invalid: $($observe.text)" }
    $elementNames = @($observe.json.data.uia.elements | ForEach-Object { $_.name })
    if (($elementNames -notcontains 'Click Me') -and ($elementNames -notcontains 'Input')) {
        Fail "observe UIA elements did not contain Click Me or Input: $($observe.text)"
    }

    $missing = Invoke-WinAgentJson -WinArgs @('observe', '--title', 'Definitely Missing Agent Test Window') -AllowedExitCodes @(1)
    if ($missing.json.error.code -ne 'WINDOW_NOT_FOUND') { Fail "Expected WINDOW_NOT_FOUND, got $($missing.json.error.code)" }

    @(
        'target_title=Agent Test Window',
        "observe $ObserveOut"
    ) | Set-Content -Encoding UTF8 -LiteralPath $CaseFile
    $case = Invoke-WinAgentJson -WinArgs @('run-case', '--file', $CaseFile, '--report', $CaseReport)
    if ($case.json.ok -ne $true) { Fail "observe case failed: $($case.text)" }
    if (!(Test-Path -LiteralPath $ObserveOut)) { Fail "observe case output was not written: $ObserveOut" }
    $caseObserve = Get-Content -LiteralPath $ObserveOut -Raw | ConvertFrom-Json
    if (!$caseObserve.target_window -or !$caseObserve.screenshot.path) { Fail "observe case data incomplete: $ObserveOut" }
    if (!(Select-String -LiteralPath $CaseReport -Pattern '## Observations' -SimpleMatch -Quiet)) { Fail "Case report missing Observations section." }

    @(
        '# DesktopVisual Observe Selftest',
        '',
        '- Result: PASS',
        "- observe screenshot: $($observe.json.data.screenshot.path)",
        "- observe uia element_count: $($observe.json.data.uia.element_count)",
        "- observe focus_verified: $($observe.json.data.focus_verified)",
        "- observe case output: $ObserveOut",
        '- missing window: WINDOW_NOT_FOUND'
    ) | Set-Content -Encoding UTF8 -LiteralPath $Report

    Write-Host 'Observe selftest passed.'
    Write-Host "Report: $Report"
}
finally {
    if ($proc -and !$proc.HasExited) {
        $proc.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (!$proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    }
}
