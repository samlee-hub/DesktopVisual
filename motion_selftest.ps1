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
$Report = Join-Path $Artifacts 'motion_selftest_report.md'
$DefaultHumanProfile = Join-Path $Root 'config\operator_motion_profile.json'

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

    foreach ($mode in @('instant', 'fast-human', 'demo-human')) {
        $result = Invoke-WinAgentJson -WinArgs @('click', '--title', 'Agent Test Window', '--x', '80', '--y', '90', '--move-mode', $mode)
        if (!$result.json.data.move_profile -or $null -eq $result.json.data.distance_px -or $null -eq $result.json.data.step_count) {
            Fail "Motion fields missing for $mode`: $($result.text)"
        }
        if ($mode -eq 'fast-human' -and [int]$result.json.data.duration_ms -gt 500) {
            Fail "fast-human short motion too slow: $($result.text)"
        }
    }

    $profileInfo = $null
    $hasHumanProfile = $false
    if (Test-Path -LiteralPath $DefaultHumanProfile) {
        $profileInfo = Invoke-WinAgentJson -WinArgs @('motion-profile-info', '--profile', $DefaultHumanProfile) -AllowedExitCodes @(0, 1)
        $hasHumanProfile = $profileInfo.exit -eq 0 -and $profileInfo.json.data.source -eq 'human'
    }

    if ($hasHumanProfile) {
        $humanClick = Invoke-WinAgentJson -WinArgs @('click', '--title', 'Agent Test Window', '--x', '90', '--y', '90', '--move-mode', 'human')
        if ($humanClick.json.data.move_profile -ne 'operator-human') {
            Fail "human click should use operator-human, got $($humanClick.json.data.move_profile): $($humanClick.text)"
        }
        if (-not $humanClick.json.data.operator_profile_path -or $humanClick.json.data.operator_profile_source -ne 'human') {
            Fail "human click missing operator profile metadata: $($humanClick.text)"
        }

        Invoke-WinAgentJson -WinArgs @('click', '--title', 'Agent Test Window', '--x', '90', '--y', '90', '--move-mode', 'instant') | Out-Null
        $shortHuman = Invoke-WinAgentJson -WinArgs @('click', '--title', 'Agent Test Window', '--x', '95', '--y', '95', '--move-mode', 'human')
        if ($shortHuman.json.data.move_profile -ne 'operator-human' -or $shortHuman.json.data.path_type -ne 'operator-statistical') {
            Fail "short human movement should use operator-human statistical path: $($shortHuman.text)"
        }
        if ([int]$shortHuman.json.data.distance_px -gt 20 -or [int]$shortHuman.json.data.duration_ms -gt 70) {
            Fail "short human movement is too slow or too long: $($shortHuman.text)"
        }
        if ([int]$shortHuman.json.data.synthesized_point_count -gt 5) {
            Fail "short human movement has too many micro-steps: $($shortHuman.text)"
        }
        if ([int]$shortHuman.json.duration_ms -gt 240) {
            Fail "short human command elapsed time is too slow: $($shortHuman.text)"
        }

        Invoke-WinAgentJson -WinArgs @('click', '--title', 'Agent Test Window', '--x', '60', '--y', '70', '--move-mode', 'instant') | Out-Null
        $mediumHuman = Invoke-WinAgentJson -WinArgs @('click', '--title', 'Agent Test Window', '--x', '200', '--y', '150', '--move-mode', 'human')
        if ([int]$mediumHuman.json.data.distance_px -lt 120) {
            Fail "medium human movement did not cover the expected distance: $($mediumHuman.text)"
        }
        if ([int]$mediumHuman.json.data.duration_ms -gt 210) {
            Fail "medium human movement is too slow: $($mediumHuman.text)"
        }
        if ([int]$mediumHuman.json.data.synthesized_point_count -gt 14) {
            Fail "medium human movement has too many micro-steps: $($mediumHuman.text)"
        }
        if ([int]$mediumHuman.json.duration_ms -gt 520) {
            Fail "medium human command elapsed time is too slow: $($mediumHuman.text)"
        }
        if ([int]$mediumHuman.json.data.duration_ms -le [int]$shortHuman.json.data.duration_ms) {
            Fail "medium human movement should take longer than short triangular movement: short=$($shortHuman.text) medium=$($mediumHuman.text)"
        }
    } else {
        $humanClick = Invoke-WinAgentJson -WinArgs @('click', '--title', 'Agent Test Window', '--x', '90', '--y', '90', '--move-mode', 'human') -AllowedExitCodes @(1)
        if ($humanClick.json.error.code -notin @('MOTION_PROFILE_NOT_FOUND', 'MOTION_PROFILE_INVALID', 'MOTION_PROFILE_SOURCE_REQUIRED', 'MOTION_PROFILE_NOT_HUMAN', 'MOTION_PROFILE_TEST_ONLY')) {
            Fail "human click should fail on missing/non-human operator profile, got $($humanClick.json.error.code): $($humanClick.text)"
        }
    }

    if ($hasHumanProfile) {
        $defaultClick = Invoke-WinAgentJson -WinArgs @('click', '--title', 'Agent Test Window', '--x', '95', '--y', '95')
        if ($defaultClick.json.data.move_profile -ne 'operator-human') {
            Fail "Default click mode should be operator-human, got $($defaultClick.json.data.move_profile): $($defaultClick.text)"
        }
        if ($defaultClick.json.data.operator_profile_source -ne 'human') {
            Fail "Default click should use the local human operator profile: $($defaultClick.text)"
        }
    } else {
        $defaultClick = Invoke-WinAgentJson -WinArgs @('click', '--title', 'Agent Test Window', '--x', '95', '--y', '95') -AllowedExitCodes @(1)
        if ($defaultClick.json.error.code -notin @('MOTION_PROFILE_NOT_FOUND', 'MOTION_PROFILE_INVALID', 'MOTION_PROFILE_SOURCE_REQUIRED', 'MOTION_PROFILE_NOT_HUMAN', 'MOTION_PROFILE_TEST_ONLY')) {
            Fail "Default click should fail on missing/non-human operator profile, got $($defaultClick.json.error.code): $($defaultClick.text)"
        }
    }

    $bad = Invoke-WinAgentJson -WinArgs @('click', '--title', 'Agent Test Window', '--x', '80', '--y', '90', '--move-mode', 'slow-human') -AllowedExitCodes @(1)
    if ($bad.json.error.code -ne 'INVALID_ARGUMENT') { Fail "Expected INVALID_ARGUMENT, got $($bad.json.error.code)" }

    Invoke-WinAgentJson -WinArgs @('click', '--title', 'Agent Test Window', '--x', '90', '--y', '150') | Out-Null
    foreach ($mode in @('fast-human', 'demo-human')) {
        $typed = Invoke-WinAgentJson -WinArgs @('type', '--title', 'Agent Test Window', '--text', "motion_$mode", '--type-mode', $mode)
        if ($typed.json.data.type_mode -ne $mode) { Fail "type mode mismatch: $($typed.text)" }
    }
    $defaultTyped = Invoke-WinAgentJson -WinArgs @('type', '--title', 'Agent Test Window', '--text', 'motion_default')
    if ($defaultTyped.json.data.type_mode -ne 'demo-human') {
        Fail "Default type mode should be demo-human, got $($defaultTyped.json.data.type_mode): $($defaultTyped.text)"
    }

    @(
        '# DesktopVisual Motion Selftest',
        '',
        '- Result: PASS',
        '- instant click: PASS',
        '- fast-human click: PASS',
        '- demo-human click: PASS',
        '- human click mode: operator-human',
        '- short human movement speed: PASS',
        '- medium human movement speed: PASS',
        '- default click mode: operator-human',
        "- default human profile: $DefaultHumanProfile",
        '- invalid move-mode: INVALID_ARGUMENT',
        '- fast-human/demo-human type: PASS',
        '- default type mode: demo-human'
    ) | Set-Content -Encoding UTF8 -LiteralPath $Report

    Write-Host 'Motion selftest passed.'
    Write-Host "Report: $Report"
}
finally {
    if ($proc -and !$proc.HasExited) {
        $proc.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (!$proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    }
}
