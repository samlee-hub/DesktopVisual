param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\task_template_v2_docs_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates v5.4.5 Task Template v2 docs and samples.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.4.5'
$Report = Join-Path $ArtifactDir 'task_template_v2_docs_selftest_report.md'
$Docs = Join-Path $Root 'docs\TASK_TEMPLATES_V2.md'
$Changelog = Join-Path $Root 'CHANGELOG.md'
$Readme = Join-Path $Root 'README.md'
$Protocol = Join-Path $Root 'COMMAND_PROTOCOL.md'
$Version = Join-Path $Root 'VERSION'

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "Missing winagent.exe. Run build.ps1 first: $WinAgent"
}

$helpText = (& $WinAgent help 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or $helpText -notmatch 'task-template-v2-validate' -or $helpText -notmatch 'task-template-v2-resolve') {
    throw "Expected help output to include Task Template v2 commands. output=$helpText"
}

foreach ($path in @($Docs, $Changelog, $Readme, $Protocol, $Version)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required docs/version file missing: $path"
    }
}

$docsText = Get-Content -LiteralPath $Docs -Raw
$changelogText = Get-Content -LiteralPath $Changelog -Raw
$readmeText = Get-Content -LiteralPath $Readme -Raw
$protocolText = Get-Content -LiteralPath $Protocol -Raw
$versionText = (Get-Content -LiteralPath $Version -Raw).Trim()

foreach ($marker in @('TaskTemplateV2','ProfileBoundLocator','ProfileBoundVerification','TaskParameter','TaskTemplateResolver','task-template-v2-validate','task-template-v2-resolve')) {
    if ($docsText -notmatch [regex]::Escape($marker)) {
        throw "docs/TASK_TEMPLATES_V2.md missing $marker"
    }
}
foreach ($command in @('task-template-v2-validate','task-template-v2-resolve')) {
    if ($readmeText -notmatch [regex]::Escape($command)) { throw "README.md missing $command" }
    if ($protocolText -notmatch [regex]::Escape($command)) { throw "COMMAND_PROTOCOL.md missing $command" }
}
if ($changelogText -notmatch 'v5.4.5') { throw 'CHANGELOG.md missing v5.4.5 entry.' }
$parsedVersion = [version]($versionText -replace '-.*$', '')
if ($parsedVersion.Major -ne 5 -or $parsedVersion -lt [version]'5.4.6') { throw "Expected VERSION v5.x and at least 5.4.6, got $versionText" }

Get-ChildItem -LiteralPath (Join-Path $Root 'samples\tasks') -Filter '*.json' | ForEach-Object {
    Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json | Out-Null
}
Get-ChildItem -LiteralPath (Join-Path $Root 'samples\profiles') -Filter '*.json' | ForEach-Object {
    Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json | Out-Null
}

$lines = @(
    '# v5.4.5 Task Template v2 Docs Selftest Report',
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
Write-Host 'PASS: v5.4.5 Task Template v2 docs selftest'
Write-Host "Report: $Report"

