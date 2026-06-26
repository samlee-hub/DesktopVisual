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
$Report = Join-Path $Artifacts 'safety_selftest_report.md'
$SafetyConfig = Join-Path $Root 'config\safety.conf'

function Fail($Message) {
    throw $Message
}

function Invoke-WinAgentJson {
    param(
        [string[]]$WinArgs,
        [int[]]$AllowedExitCodes = @(0),
        [string]$SafetyConfigOverride = ''
    )

    $oldConfig = $env:DESKTOPVISUAL_SAFETY_CONFIG
    if ($SafetyConfigOverride) {
        $env:DESKTOPVISUAL_SAFETY_CONFIG = $SafetyConfigOverride
    }
    try {
        $output = & $WinAgent @WinArgs
        $exit = $LASTEXITCODE
    }
    finally {
        $env:DESKTOPVISUAL_SAFETY_CONFIG = $oldConfig
    }

    if ($null -eq $AllowedExitCodes -or @($AllowedExitCodes).Count -eq 0) {
        $AllowedExitCodes = @(0)
    }
    $allowedExitText = @($AllowedExitCodes | ForEach-Object { "$_" })
    if ($allowedExitText -notcontains "$exit") {
        Fail "winagent $($WinArgs -join ' ') exited $exit with output: $output"
    }
    try {
        $json = $output | ConvertFrom-Json
    }
    catch {
        Fail "Output was not valid JSON for winagent $($WinArgs -join ' '): $output"
    }
    return @{ exit = $exit; text = [string]$output; json = $json }
}

function Assert-ErrorCode {
    param($Result, [string]$Code)
    if ($Result.json.ok -ne $false) { Fail "Expected failure JSON with $Code." }
    if ($Result.json.error.code -ne $Code) { Fail "Expected $Code, got $($Result.json.error.code). Output: $($Result.text)" }
}

if (!(Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run $Root\build.ps1 first." }
if (!(Test-Path -LiteralPath $TestWindowExe)) { Fail "Missing $TestWindowExe. Run $Root\build.ps1 first." }
if (!(Test-Path -LiteralPath $SafetyConfig)) { Fail "Missing safety config: $SafetyConfig" }

New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null

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

    $allowed = Invoke-WinAgentJson -WinArgs @('click', '--title', 'Agent Test Window', '--x', '80', '--y', '90')
    if ($allowed.json.ok -ne $true) { Fail "Allowed whitelist click failed: $($allowed.text)" }

    $denyTitleConfig = Join-Path $Artifacts 'safety_deny_title.conf'
    @(
        'allowed_titles=Some Other Window'
        'allowed_processes=TestWindow.exe'
        "allowed_read_roots=`${PROJECT_ROOT};`${PROJECT_ROOT}\artifacts;$TestWindowRoot"
        "allowed_write_roots=`${PROJECT_ROOT}\artifacts;$TestWindowRoot"
        'max_steps=100'
        'max_duration_ms=120000'
        'emergency_stop_key=F12'
        'allow_absolute_screen_click=false'
    ) | Set-Content -Encoding UTF8 -LiteralPath $denyTitleConfig
    $deniedTitle = Invoke-WinAgentJson -WinArgs @('click', '--title', 'Agent Test Window', '--x', '80', '--y', '90') -AllowedExitCodes @(1) -SafetyConfigOverride $denyTitleConfig
    Assert-ErrorCode $deniedTitle 'SAFETY_POLICY_DENIED'

    $denyProcessConfig = Join-Path $Artifacts 'safety_deny_process.conf'
    @(
        'allowed_titles=Agent Test Window'
        'allowed_processes=notepad.exe'
        "allowed_read_roots=`${PROJECT_ROOT};`${PROJECT_ROOT}\artifacts;$TestWindowRoot"
        "allowed_write_roots=`${PROJECT_ROOT}\artifacts;$TestWindowRoot"
        'max_steps=100'
        'max_duration_ms=120000'
        'emergency_stop_key=F12'
        'allow_absolute_screen_click=false'
    ) | Set-Content -Encoding UTF8 -LiteralPath $denyProcessConfig
    $deniedProcess = Invoke-WinAgentJson -WinArgs @('click', '--title', 'Agent Test Window', '--x', '80', '--y', '90') -AllowedExitCodes @(1) -SafetyConfigOverride $denyProcessConfig
    Assert-ErrorCode $deniedProcess 'SAFETY_POLICY_DENIED'

    $stepLimitConfig = Join-Path $Artifacts 'safety_step_limit.conf'
    @(
        'allowed_titles=Agent Test Window'
        'allowed_processes=TestWindow.exe'
        "allowed_read_roots=`${PROJECT_ROOT};`${PROJECT_ROOT}\artifacts;$TestWindowRoot"
        "allowed_write_roots=`${PROJECT_ROOT}\artifacts;$TestWindowRoot"
        'max_steps=2'
        'max_duration_ms=120000'
        'emergency_stop_key=F12'
        'allow_absolute_screen_click=false'
    ) | Set-Content -Encoding UTF8 -LiteralPath $stepLimitConfig
    $stepLimitCase = Join-Path $Artifacts 'safety_step_limit.case'
    @(
        'target_title=Agent Test Window'
        'wait 0'
        'wait 0'
    ) | Set-Content -Encoding UTF8 -LiteralPath $stepLimitCase
    $stepLimitReport = Join-Path $Artifacts 'safety_step_limit_report.md'
    $stepLimit = Invoke-WinAgentJson -WinArgs @('run-case', '--file', $stepLimitCase, '--report', $stepLimitReport) -AllowedExitCodes @(1) -SafetyConfigOverride $stepLimitConfig
    Assert-ErrorCode $stepLimit 'CASE_STEP_LIMIT_EXCEEDED'

    $durationConfig = Join-Path $Artifacts 'safety_duration_limit.conf'
    @(
        'allowed_titles=Agent Test Window'
        'allowed_processes=TestWindow.exe'
        "allowed_read_roots=`${PROJECT_ROOT};`${PROJECT_ROOT}\artifacts;$TestWindowRoot"
        "allowed_write_roots=`${PROJECT_ROOT}\artifacts;$TestWindowRoot"
        'max_steps=100'
        'max_duration_ms=1'
        'emergency_stop_key=F12'
        'allow_absolute_screen_click=false'
    ) | Set-Content -Encoding UTF8 -LiteralPath $durationConfig
    $durationCase = Join-Path $Artifacts 'safety_duration_limit.case'
    @(
        'target_title=Agent Test Window'
        'wait 20'
        'wait 0'
    ) | Set-Content -Encoding UTF8 -LiteralPath $durationCase
    $durationReport = Join-Path $Artifacts 'safety_duration_limit_report.md'
    $durationLimit = Invoke-WinAgentJson -WinArgs @('run-case', '--file', $durationCase, '--report', $durationReport) -AllowedExitCodes @(1) -SafetyConfigOverride $durationConfig
    Assert-ErrorCode $durationLimit 'CASE_DURATION_LIMIT_EXCEEDED'

    $absoluteClick = Invoke-WinAgentJson -WinArgs @('click', '--x', '10', '--y', '10') -AllowedExitCodes @(2)
    Assert-ErrorCode $absoluteClick 'INVALID_ARGUMENT'

    $lines = @(
        '# DesktopVisual Safety Selftest',
        '',
        '- Result: PASS',
        '- Version: v1.4.0 Selector Locate And Act',
        '- Default safety config: present',
        '- Whitelisted TestWindow action: PASS',
        '- Non-whitelisted title denied: SAFETY_POLICY_DENIED',
        '- Non-whitelisted process denied: SAFETY_POLICY_DENIED',
        '- max_steps denied case: CASE_STEP_LIMIT_EXCEEDED',
        '- max_duration_ms denied case: CASE_DURATION_LIMIT_EXCEEDED',
        '- absolute screen click command: unavailable/INVALID_ARGUMENT',
        '- emergency_stop_key: F12, documented; not simulated automatically',
        '',
        '## JSON Samples',
        '',
        '```json',
        $allowed.text,
        $deniedTitle.text,
        $deniedProcess.text,
        $stepLimit.text,
        $durationLimit.text,
        $absoluteClick.text,
        '```'
    )
    $lines | Set-Content -Encoding UTF8 -LiteralPath $Report

    Write-Host 'Safety selftest passed.'
    Write-Host "Report: $Report"
}
finally {
    if ($proc -and !$proc.HasExited) {
        $proc.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (!$proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    }
}

exit 0
