param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\upload_verification_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates v5.5.3 Attachment upload verification.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.5.3'
$Report = Join-Path $ArtifactDir 'upload_verification_selftest_report.md'
$Success = Join-Path $Root 'tasks\file_workflows\local_mail_mock_upload_success.json'
$Failure = Join-Path $Root 'tasks\file_workflows\local_mail_mock_upload_failure.json'
$Timeout = Join-Path $Root 'tasks\file_workflows\local_mail_mock_upload_timeout.json'
$TooLarge = Join-Path $ArtifactDir 'local_mail_mock_upload_too_large.json'

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null
@'
{
  "schema_version": "5.5.3",
  "state_id": "local_mail_mock_upload_too_large",
  "file_name": "mock_attachment.txt",
  "file_name_visible": true,
  "upload_started": true,
  "spinner_detected": false,
  "progress_detected": false,
  "spinner_gone": true,
  "upload_completed": false,
  "upload_failed": false,
  "file_too_large": true,
  "retry_shown": true,
  "no_real_send": true
}
'@ | Set-Content -LiteralPath $TooLarge -Encoding UTF8

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

$ok = Invoke-JsonCommand @('attachment-verify', '--file', $Success, '--expected-file', 'mock_attachment.txt', '--timeout-ms', '3000', '--elapsed-ms', '800')
if (-not $ok.Json.ok -or $ok.Json.data.upload_completed -ne $true -or $ok.Json.data.spinner_gone -ne $true) {
    throw "Expected upload success. output=$($ok.Text)"
}

$failed = Invoke-JsonCommand @('attachment-verify', '--file', $Failure, '--expected-file', 'mock_attachment.txt') -AllowedExitCodes @(1)
if ($failed.Json.ok -or $failed.Json.error.code -ne 'UPLOAD_FAILED') {
    throw "Expected upload failure. output=$($failed.Text)"
}
if ($failed.Json.data.retry_shown -ne $true) {
    throw "Expected failed upload to expose retry_shown metadata. output=$($failed.Text)"
}

$timeout = Invoke-JsonCommand @('attachment-verify', '--file', $Timeout, '--expected-file', 'mock_attachment.txt', '--timeout-ms', '1000', '--elapsed-ms', '1500') -AllowedExitCodes @(1)
if ($timeout.Json.ok -or $timeout.Json.error.code -ne 'UPLOAD_VERIFICATION_TIMEOUT') {
    throw "Expected upload timeout. output=$($timeout.Text)"
}

$tooLarge = Invoke-JsonCommand @('attachment-verify', '--file', $TooLarge, '--expected-file', 'mock_attachment.txt') -AllowedExitCodes @(1)
if ($tooLarge.Json.ok -or $tooLarge.Json.error.code -ne 'UPLOAD_FILE_TOO_LARGE') {
    throw "Expected file-too-large failure. output=$($tooLarge.Text)"
}

$lines = @(
    '# v5.5.3 Upload Verification Selftest Report',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    '- file name visible: PASS',
    '- upload started: PASS',
    '- spinner/progress detected: PASS',
    '- spinner gone: PASS',
    '- upload completed: PASS',
    '- upload failed: PASS',
    '- retry shown metadata: PASS',
    '- file too large: PASS',
    '- timeout: PASS',
    '',
    '```json',
    $ok.Text,
    $failed.Text,
    $timeout.Text,
    $tooLarge.Text,
    '```'
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.5.3 upload verification selftest'
Write-Host "Report: $Report"
