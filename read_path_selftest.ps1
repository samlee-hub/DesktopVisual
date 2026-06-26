param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$Artifacts = Join-Path $Root 'artifacts'
$Report = Join-Path $Artifacts 'read_path_selftest_report.md'

function Fail($Message) {
    throw $Message
}

function Invoke-WinAgentJson {
    param(
        [string[]]$WinArgs,
        [int[]]$AllowedExitCodes = @(0)
    )
    $output = & $WinAgent @WinArgs
    $exit = $LASTEXITCODE
    if ($AllowedExitCodes -notcontains $exit) {
        Fail "winagent $($WinArgs -join ' ') exited $exit with output: $output"
    }
    try {
        $json = $output | ConvertFrom-Json
    } catch {
        Fail "Output was not valid JSON: $output"
    }
    return @{ exit = $exit; text = [string]$output; json = $json }
}

if (!(Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run $Root\build.ps1 first." }

New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null

$allowedPath = Join-Path $Root 'VERSION'
$allowed = Invoke-WinAgentJson -WinArgs @('read-file', '--path', $allowedPath)
if ($allowed.json.ok -ne $true) {
    Fail "Expected allowed read to succeed: $($allowed.text)"
}

$deniedPath = 'C:\Windows\win.ini'
if (!(Test-Path -LiteralPath $deniedPath)) {
    $deniedPath = 'C:\Windows\System32\drivers\etc\hosts'
}
$denied = Invoke-WinAgentJson -WinArgs @('read-file', '--path', $deniedPath) -AllowedExitCodes @(1)
if ($denied.json.ok -ne $false -or $denied.json.error.code -ne 'SAFETY_POLICY_DENIED') {
    Fail "Expected SAFETY_POLICY_DENIED for $deniedPath, got: $($denied.text)"
}

@(
    '# DesktopVisual Read Path Selftest',
    '',
    '- Result: PASS',
    "- Allowed read: $allowedPath",
    "- Denied read: $deniedPath",
    '- Denied error: SAFETY_POLICY_DENIED'
) | Set-Content -Encoding UTF8 -LiteralPath $Report

Write-Host 'Read path selftest passed.'
Write-Host "Report: $Report"
