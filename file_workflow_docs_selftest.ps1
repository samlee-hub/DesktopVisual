param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\file_workflow_docs_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates v5.5.5 file workflow docs and samples.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.5.5'
$Report = Join-Path $ArtifactDir 'file_workflow_docs_selftest_report.md'
$Docs = Join-Path $Root 'docs\FILE_WORKFLOWS.md'
$Safety = Join-Path $Root 'docs\SAFETY_MANIFEST.md'
$Template = Join-Path $Root 'tasks\templates_v2\local_mail_mock_compose_attach_no_real_send.task-template-v2.json'
$Changelog = Join-Path $Root 'CHANGELOG.md'
$Version = Join-Path $Root 'VERSION'

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

$helpText = (& $WinAgent help 2>&1 | Out-String)
foreach ($command in @('file-path-resolve','file-picker-flow','attachment-verify','cross-window-check','local-mail-attach-flow')) {
    if ($helpText -notmatch [regex]::Escape($command)) { throw "Help output missing $command" }
}

foreach ($path in @($Docs, $Safety, $Template, $Changelog, $Version)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing required file: $path" }
}

$docsText = Get-Content -LiteralPath $Docs -Raw
$safetyText = Get-Content -LiteralPath $Safety -Raw
$templateText = Get-Content -LiteralPath $Template -Raw
$changelogText = Get-Content -LiteralPath $Changelog -Raw
$versionText = (Get-Content -LiteralPath $Version -Raw).Trim()

foreach ($marker in @('FilePickerFlow','FilePathResolver','AttachmentState','UploadVerification','CrossWindowTaskContext','FileActionRisk')) {
    if ($docsText -notmatch [regex]::Escape($marker)) { throw "docs/FILE_WORKFLOWS.md missing $marker" }
}
if ($safetyText -notmatch 'File / Attachment') { throw 'SAFETY_MANIFEST.md missing file workflow safety section.' }
if ($templateText -notmatch 'file_picker_flow' -or $templateText -notmatch 'upload_verification') { throw 'local_mail_mock template missing file picker/upload metadata.' }
if ($changelogText -notmatch 'v5.5.5') { throw 'CHANGELOG.md missing v5.5.5 entry.' }
$versionParts = $versionText.Split('.')
if ($versionParts.Count -lt 3) { throw "Expected semantic VERSION at least 5.5.6, got $versionText" }
$versionMajor = [int]$versionParts[0]
$versionMinor = [int]$versionParts[1]
$versionPatch = [int]$versionParts[2]
if ($versionMajor -ne 5 -or $versionMinor -lt 5 -or ($versionMinor -eq 5 -and $versionPatch -lt 6)) {
    throw "Expected VERSION at least 5.5.6, got $versionText"
}

Get-ChildItem -LiteralPath (Join-Path $Root 'tasks\file_workflows') -Filter '*.json' | ForEach-Object {
    Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json | Out-Null
}
Get-Content -LiteralPath (Join-Path $Root 'samples\tasks\local_mail_mock_attach_v55.task.json') -Raw | ConvertFrom-Json | Out-Null

$lines = @(
    '# v5.5.5 File Workflow Docs Selftest Report',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "- VERSION: $versionText",
    '- docs examples parse: PASS',
    '- sample task parse: PASS'
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.5.5 file workflow docs selftest'
Write-Host "Report: $Report"
