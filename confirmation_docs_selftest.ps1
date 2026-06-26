param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\confirmation_docs_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates v5.3.5 human confirmation docs and samples.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.3.5'
$Report = Join-Path $ArtifactDir 'confirmation_docs_selftest_report.md'
$Docs = @(
    (Join-Path $Root 'docs\HUMAN_CONFIRMATION.md'),
    (Join-Path $Root 'docs\SAFETY_MANIFEST.md'),
    (Join-Path $Root 'COMMAND_PROTOCOL.md'),
    (Join-Path $Root 'README.md'),
    (Join-Path $Root 'CHANGELOG.md')
)
$Samples = @((Join-Path $Root 'tasks\confirmation\local_mail_mock_send_confirm.json'))
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

$helpText = (& $WinAgent help 2>&1 | Out-String)
foreach ($command in @('risk-action-classify', 'confirmation-request-create', 'confirmation-gate-check', 'confirmation-flow-run')) {
    if ($helpText -notmatch [regex]::Escape($command)) { throw "help output missing $command" }
}
foreach ($path in $Docs + $Samples + @((Join-Path $Root 'VERSION'))) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required file missing: $path" }
}
foreach ($sample in $Samples) {
    Get-Content -LiteralPath $sample -Raw | ConvertFrom-Json | Out-Null
}
$humanDoc = Get-Content -LiteralPath (Join-Path $Root 'docs\HUMAN_CONFIRMATION.md') -Raw
$safetyDoc = Get-Content -LiteralPath (Join-Path $Root 'docs\SAFETY_MANIFEST.md') -Raw
$protocol = Get-Content -LiteralPath (Join-Path $Root 'COMMAND_PROTOCOL.md') -Raw
$readme = Get-Content -LiteralPath (Join-Path $Root 'README.md') -Raw
$changelog = Get-Content -LiteralPath (Join-Path $Root 'CHANGELOG.md') -Raw
$versionText = (Get-Content -LiteralPath (Join-Path $Root 'VERSION') -Raw).Trim()
foreach ($command in @('risk-action-classify', 'confirmation-request-create', 'confirmation-gate-check', 'confirmation-flow-run')) {
    if ($humanDoc -notmatch [regex]::Escape($command)) { throw "HUMAN_CONFIRMATION.md missing $command" }
    if ($protocol -notmatch [regex]::Escape($command)) { throw "COMMAND_PROTOCOL.md missing $command" }
    if ($readme -notmatch [regex]::Escape($command)) { throw "README.md missing $command" }
}
foreach ($phrase in @('blocked actions cannot be approved', 'Public release profiles', 'Agent/VLM escalation cannot bypass')) {
    if (($humanDoc + $safetyDoc) -notmatch [regex]::Escape($phrase)) { throw "confirmation safety docs missing $phrase" }
}
if ($changelog -notmatch 'v5.3.5') { throw 'CHANGELOG.md missing v5.3.5 entry.' }
$parsedVersion = [version]($versionText -replace '-.*$', '')
if ($parsedVersion.Major -ne 5 -or $parsedVersion -lt [version]'5.3.5') { throw "Expected VERSION v5.x and at least 5.3.5, got $versionText" }
$versionOutput = & $WinAgent version
$versionJson = $versionOutput | ConvertFrom-Json
$parsedRuntimeVersion = [version](($versionJson.data.version) -replace '-.*$', '')
if ($parsedRuntimeVersion.Major -ne 5 -or $parsedRuntimeVersion -lt [version]'5.3.5') { throw "Expected winagent version v5.x and at least 5.3.5, got $($versionJson.data.version)" }

$lines = @(
    '# v5.3.5 Confirmation Docs Selftest Report',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "- VERSION: $versionText",
    '',
    '## Help Output',
    '',
    '```text',
    $helpText.Trim(),
    '```'
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.3.5 Confirmation docs selftest'
Write-Host "Report: $Report"

