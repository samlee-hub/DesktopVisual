param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\f12_force_exit'
$Report = Join-Path $ArtifactDir 'f12_force_exit_selftest_report.md'
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

function Fail([string]$Message) {
    throw $Message
}

function Expected-F12Message {
    $codes = @(
        0x7528, 0x6237, 0x5DF2, 0x6309, 0x20, 0x46, 0x31, 0x32,
        0x20, 0x5F3A, 0x5236, 0x7ED3, 0x675F, 0x5F53, 0x524D,
        0x4EFB, 0x52A1, 0xFF0C, 0x41, 0x67, 0x65, 0x6E, 0x74,
        0x20, 0x5DF2, 0x505C, 0x6B62, 0x672C, 0x6B21, 0x884C,
        0x4E3A, 0x3002
    )
    return -join ($codes | ForEach-Object { [char]$_ })
}

function Invoke-WinAgentJson {
    param(
        [string[]]$WinArgs,
        [int[]]$AllowedExitCodes = @(0)
    )
    $output = & $WinAgent @WinArgs 2>&1
    $exit = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    if ($AllowedExitCodes -notcontains $exit) {
        Fail "winagent $($WinArgs -join ' ') exited $exit with output: $text"
    }
    try {
        $json = $text | ConvertFrom-Json
    } catch {
        Fail "winagent $($WinArgs -join ' ') did not return JSON: $text"
    }
    [pscustomobject]@{ exit = $exit; json = $json; text = $text; args = $WinArgs }
}

function Assert-F12Stop($Result, [string]$CaseName) {
    if ($Result.exit -eq 0) { Fail "$CaseName expected non-zero stop exit." }
    if ($Result.json.ok -ne $false) { Fail "$CaseName expected ok=false." }
    if ($Result.json.error.code -ne 'STOP_USER_FORCE_EXIT_F12') {
        Fail "$CaseName expected STOP_USER_FORCE_EXIT_F12, got $($Result.json.error.code). output=$($Result.text)"
    }
    if ($Result.json.error.message -ne (Expected-F12Message)) {
        Fail "$CaseName user message mismatch: $($Result.json.error.message)"
    }
    if ($Result.json.data.user_force_exit -ne $true) { Fail "$CaseName missing user_force_exit=true." }
    if ($Result.json.data.force_exit_key -ne 'F12') { Fail "$CaseName missing force_exit_key=F12." }
    if ($Result.json.data.force_exit_scope -ne 'current_task_only') { Fail "$CaseName missing current_task_only scope." }
    if ($Result.json.data.process_exit -ne $false) { Fail "$CaseName expected process_exit=false." }
}

if (-not (Test-Path -LiteralPath $WinAgent)) {
    Fail "Missing $WinAgent. Run build.ps1 first."
}

$idleEnv = $env:DESKTOPVISUAL_FORCE_F12_ABORT
$env:DESKTOPVISUAL_FORCE_F12_ABORT = '1'
try {
    $versionWhileIdle = Invoke-WinAgentJson -WinArgs @('version')
} finally {
    $env:DESKTOPVISUAL_FORCE_F12_ABORT = $idleEnv
}
if ($versionWhileIdle.json.ok -ne $true -or -not $versionWhileIdle.json.data.version) {
    Fail "Idle/version check under F12 simulation did not remain healthy: $($versionWhileIdle.text)"
}

$pos = Invoke-WinAgentJson -WinArgs @('mouse-position')
$x = [int]$pos.json.data.screen_x
$y = [int]$pos.json.data.screen_y

$oldForce = $env:DESKTOPVISUAL_FORCE_F12_ABORT
$env:DESKTOPVISUAL_FORCE_F12_ABORT = '1'
try {
    $stopped = Invoke-WinAgentJson -WinArgs @(
        'desktop-move',
        '--screen-x', "$x",
        '--screen-y', "$y",
        '--move-mode', 'instant',
        '--humanmode', 'false',
        '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY',
        '--target-description', 'f12 selftest no-op move',
        '--coordinate-source', 'f12_selftest_current_cursor'
    ) -AllowedExitCodes @(1)
} finally {
    $env:DESKTOPVISUAL_FORCE_F12_ABORT = $oldForce
}
Assert-F12Stop $stopped 'desktop-move force exit'

$afterVersion = Invoke-WinAgentJson -WinArgs @('version')
if ($afterVersion.json.ok -ne $true -or -not $afterVersion.json.data.version) {
    Fail "winagent did not respond to version after F12 stop: $($afterVersion.text)"
}

@(
    '# F12 Force Exit Selftest',
    '',
    '- Result: PASS',
    '- idle_state_f12_no_crash: true',
    '- executing_f12_stop_code: STOP_USER_FORCE_EXIT_F12',
    '- user_force_exit: true',
    '- force_exit_key: F12',
    '- force_exit_scope: current_task_only',
    '- process_exit: false',
    '- stop_wrapped_as_pass: false',
    '- version_after_stop: PASS'
) | Set-Content -LiteralPath $Report -Encoding UTF8

Write-Host 'F12_FORCE_EXIT_SELFTEST_PASS'
Write-Host "Report: $Report"
