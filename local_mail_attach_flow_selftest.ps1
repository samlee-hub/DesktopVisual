param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\local_mail_attach_flow_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates the v5.5 local mail mock attach flow.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.5.6'
$Report = Join-Path $ArtifactDir 'local_mail_attach_flow_selftest_report.md'
$Task = Join-Path $Root 'samples\tasks\local_mail_mock_attach_v55.task.json'

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

$output = & $WinAgent local-mail-attach-flow --file $Task 2>&1
$exit = $LASTEXITCODE
$text = ($output | Out-String).Trim()
$json = $text | ConvertFrom-Json
if ($exit -ne 0 -or -not $json.ok) {
    throw "Expected local mail attach flow to pass. exit=$exit output=$text"
}
if ($json.data.no_real_send -ne $true -or $json.data.real_email_sent -ne $false -or $json.data.file_picker.no_real_upload -ne $true -or $json.data.upload_completed -ne $true -or $json.data.cross_window.returned_to_parent -ne $true) {
    throw "Expected no-real-send completed upload and cross-window return. output=$text"
}

$lines = @(
    '# v5.5.6 Local Mail Attach Flow Selftest Report',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    '- file picker controlled attachment mock: PASS',
    '- upload complete verification: PASS',
    '- cross-window return: PASS',
    '- no real email send: PASS',
    '- no real upload: PASS',
    '',
    '```json',
    $text,
    '```'
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.5.6 local mail attach flow selftest'
Write-Host "Report: $Report"
