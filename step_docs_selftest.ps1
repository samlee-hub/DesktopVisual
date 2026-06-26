param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\step_docs_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates v5.1.5 StepContract docs and samples.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.1.5'
$Report = Join-Path $ArtifactDir 'step_docs_selftest_report.md'
$StepDoc = Join-Path $Root 'docs\STEP_CONTRACT.md'
$Protocol = Join-Path $Root 'COMMAND_PROTOCOL.md'
$Readme = Join-Path $Root 'README.md'
$Changelog = Join-Path $Root 'CHANGELOG.md'
$Version = Join-Path $Root 'VERSION'
$Samples = @(
    (Join-Path $Root 'samples\tasks\local_form_submit.task.json'),
    (Join-Path $Root 'samples\tasks\local_problem_mock.task.json')
)

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

$helpText = (& $WinAgent help 2>&1 | Out-String)
foreach ($command in @('step-contract-validate', 'step-precondition-check', 'step-verify', 'step-failure-classify')) {
    if ($helpText -notmatch [regex]::Escape($command)) {
        throw "help output missing $command"
    }
}

foreach ($path in @($StepDoc, $Protocol, $Readme, $Changelog, $Version) + $Samples) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required file missing: $path"
    }
}
foreach ($sample in $Samples) {
    Get-Content -LiteralPath $sample -Raw | ConvertFrom-Json | Out-Null
}

$stepDocText = Get-Content -LiteralPath $StepDoc -Raw
$protocolText = Get-Content -LiteralPath $Protocol -Raw
$readmeText = Get-Content -LiteralPath $Readme -Raw
$changelogText = Get-Content -LiteralPath $Changelog -Raw
$versionText = (Get-Content -LiteralPath $Version -Raw).Trim()

foreach ($command in @('step-contract-validate', 'step-precondition-check', 'step-verify', 'step-failure-classify')) {
    if ($stepDocText -notmatch [regex]::Escape($command)) { throw "STEP_CONTRACT.md missing $command" }
    if ($protocolText -notmatch [regex]::Escape($command)) { throw "COMMAND_PROTOCOL.md missing $command" }
    if ($readmeText -notmatch [regex]::Escape($command)) { throw "README.md missing $command" }
}
if ($changelogText -notmatch 'v5.1.5') { throw 'CHANGELOG.md missing v5.1.5 entry.' }
$parsedVersion = [version]($versionText -replace '-.*$', '')
if ($parsedVersion.Major -ne 5 -or $parsedVersion -lt [version]'5.1.5') { throw "Expected VERSION v5.x and at least 5.1.5, got $versionText" }

$lines = @(
    '# v5.1.5 Step Docs Selftest Report',
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
Write-Host 'PASS: v5.1.5 Step docs selftest'
Write-Host "Report: $Report"

