param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\task_docs_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates v5.0.5 Task Runtime docs and command contract.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.0.5'
$Report = Join-Path $ArtifactDir 'task_docs_selftest_report.md'
$TaskRuntimeDoc = Join-Path $Root 'docs\TASK_RUNTIME.md'
$Protocol = Join-Path $Root 'COMMAND_PROTOCOL.md'
$Readme = Join-Path $Root 'README.md'
$Changelog = Join-Path $Root 'CHANGELOG.md'
$Version = Join-Path $Root 'VERSION'

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "Missing winagent.exe. Run build.ps1 first: $WinAgent"
}

$helpText = (& $WinAgent help 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or $helpText -notmatch 'task-session-validate' -or $helpText -notmatch 'task-session-run') {
    throw "Expected help output to include TaskSession commands. output=$helpText"
}

foreach ($path in @($TaskRuntimeDoc, $Protocol, $Readme, $Changelog, $Version)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required docs/version file missing: $path"
    }
}

$protocolText = Get-Content -LiteralPath $Protocol -Raw
$taskDocText = Get-Content -LiteralPath $TaskRuntimeDoc -Raw
$readmeText = Get-Content -LiteralPath $Readme -Raw
$changelogText = Get-Content -LiteralPath $Changelog -Raw
$versionText = (Get-Content -LiteralPath $Version -Raw).Trim()
$parsedVersion = [version]($versionText -replace '-.*$', '')

foreach ($command in @('task-session-validate', 'task-session-transition', 'task-session-run')) {
    if ($protocolText -notmatch [regex]::Escape($command)) {
        throw "COMMAND_PROTOCOL.md missing $command"
    }
    if ($taskDocText -notmatch [regex]::Escape($command)) {
        throw "docs/TASK_RUNTIME.md missing $command"
    }
    if ($readmeText -notmatch [regex]::Escape($command)) {
        throw "README.md missing $command"
    }
}
if ($changelogText -notmatch 'v5.0.5') {
    throw 'CHANGELOG.md missing v5.0.5 entry.'
}
if ($parsedVersion.Major -ne 5 -or $parsedVersion -lt [version]'5.0.5') {
    throw "Expected VERSION to be v5.x and at least 5.0.5, got $versionText"
}

$jsonSamples = @(
    (Join-Path $Root 'tasks\session_schema\task_session.schema.json'),
    (Join-Path $Root 'tasks\session_schema\valid_standard_session.task-session.json'),
    (Join-Path $Root 'tasks\session_schema\local_form_fill_submit_mock.task-session.json'),
    (Join-Path $Root 'tasks\session_schema\local_form_fill_submit_mock_audit.task-session.json')
)
foreach ($jsonPath in $jsonSamples) {
    Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json | Out-Null
}

$lines = @(
    '# v5.0.5 Task Docs Selftest Report',
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
Write-Host 'PASS: v5.0.5 Task Runtime docs selftest'
Write-Host "Report: $Report"

