param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\file_picker_flow_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates v5.5.2 mock FilePickerFlow behavior.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.5.2'
$Report = Join-Path $ArtifactDir 'file_picker_flow_selftest_report.md'
$Flow = Join-Path $Root 'tasks\file_workflows\local_mock_file_picker_success.json'
$CancelFlow = Join-Path $Root 'tasks\file_workflows\local_mock_file_picker_cancel.json'
$TimeoutFlow = Join-Path $ArtifactDir 'local_mock_file_picker_timeout.json'

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null
@'
{
  "schema_version": "5.5.2",
  "flow_id": "local_mock_file_picker_timeout",
  "parent_window": "DesktopVisual Mail Mock",
  "picker_window": "Open",
  "file_path": "artifacts/dev5.5.1/allowed/mock_attachment.txt",
  "picker_detected": true,
  "path_input": true,
  "open_confirmed": false,
  "picker_closed": false,
  "target_app_changed": false,
  "cancelled": false,
  "timeout": true,
  "no_real_upload": true
}
'@ | Set-Content -LiteralPath $TimeoutFlow -Encoding UTF8

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

$success = Invoke-JsonCommand @('file-picker-flow', '--file', $Flow)
if (-not $success.Json.ok -or $success.Json.data.picker_detected -ne $true -or $success.Json.data.picker_closed -ne $true -or $success.Json.data.target_app_changed -ne $true) {
    throw "Expected successful mock picker flow. output=$($success.Text)"
}

$cancel = Invoke-JsonCommand @('file-picker-flow', '--file', $CancelFlow) -AllowedExitCodes @(1)
if ($cancel.Json.ok -or $cancel.Json.error.code -ne 'FILE_PICKER_CANCELLED') {
    throw "Expected cancelled picker failure. output=$($cancel.Text)"
}

$timeout = Invoke-JsonCommand @('file-picker-flow', '--file', $TimeoutFlow) -AllowedExitCodes @(1)
if ($timeout.Json.ok -or $timeout.Json.error.code -ne 'FILE_PICKER_TIMEOUT') {
    throw "Expected picker timeout failure. output=$($timeout.Text)"
}

$lines = @(
    '# v5.5.2 File Picker Flow Selftest Report',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    '- detect file picker window: PASS',
    '- input file path: PASS',
    '- confirm open: PASS',
    '- verify picker closed or target changed: PASS',
    '- cancel: PASS',
    '- timeout: PASS',
    '',
    '```json',
    $success.Text,
    $cancel.Text,
    $timeout.Text,
    '```'
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.5.2 file picker flow selftest'
Write-Host "Report: $Report"
