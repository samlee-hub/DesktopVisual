param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\cross_window_context_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates v5.5.4 CrossWindowTaskContext behavior.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.5.4'
$Report = Join-Path $ArtifactDir 'cross_window_context_selftest_report.md'
$Success = Join-Path $Root 'tasks\file_workflows\cross_window_success.json'
$WrongForeground = Join-Path $Root 'tasks\file_workflows\cross_window_wrong_foreground.json'

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

function Invoke-JsonCommand {
    param([string[]]$Arguments, [int[]]$AllowedExitCodes = @(0))
    $output = & $WinAgent @Arguments 2>&1
    $exit = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    if ($AllowedExitCodes -notcontains $exit) {
        throw "Unexpected exit $exit for $($Arguments -join ' '): $text"
    }
    $json = $text | ConvertFrom-Json
    return [pscustomobject]@{ ExitCode = $exit; Text = $text; Json = $json }
}

$ok = Invoke-JsonCommand @('cross-window-check', '--file', $Success)
if (-not $ok.Json.ok -or $ok.Json.data.returned_to_parent -ne $true -or $ok.Json.data.focus_restored -ne $true -or $ok.Json.data.window_changed_event -ne $true) {
    throw "Expected cross-window success. output=$($ok.Text)"
}

$wrong = Invoke-JsonCommand @('cross-window-check', '--file', $WrongForeground) -AllowedExitCodes @(1)
if ($wrong.Json.ok -or $wrong.Json.error.code -ne 'CROSS_WINDOW_WRONG_FOREGROUND') {
    throw "Expected wrong foreground stop. output=$($wrong.Text)"
}

$lines = @(
    '# v5.5.4 Cross Window Context Selftest Report',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    '- open picker -> close -> return parent: PASS',
    '- foreground verification: PASS',
    '- window_changed event: PASS',
    '- focus restore: PASS',
    '- wrong foreground stop/recover: PASS',
    '',
    '```json',
    $ok.Text,
    $wrong.Text,
    '```'
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.5.4 cross-window context selftest'
Write-Host "Report: $Report"
