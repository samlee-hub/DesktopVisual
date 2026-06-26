param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\recovery_docs_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates v5.2.5 Task Recovery docs and command contract.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.2.5'
$Report = Join-Path $ArtifactDir 'recovery_docs_selftest_report.md'
$TaskRecoveryDoc = Join-Path $Root 'docs\TASK_RECOVERY.md'
$Protocol = Join-Path $Root 'COMMAND_PROTOCOL.md'
$Readme = Join-Path $Root 'README.md'
$Changelog = Join-Path $Root 'CHANGELOG.md'
$Version = Join-Path $Root 'VERSION'
$Samples = @(
    (Join-Path $Root 'tasks\recovery_policy\valid_standard_recovery_policy.json'),
    (Join-Path $Root 'tasks\recovery_policy\delayed_button_not_ready.json'),
    (Join-Path $Root 'tasks\recovery_policy\delayed_text_missing.json'),
    (Join-Path $Root 'tasks\recovery_policy\stale_candidate_context.json'),
    (Join-Path $Root 'tasks\recovery_policy\escalation_semantic_unresolved.json'),
    (Join-Path $Root 'tasks\recovery_policy\escalation_unknown_scene.json'),
    (Join-Path $Root 'tasks\recovery_policy\escalation_no_provider.json'),
    (Join-Path $Root 'tasks\recovery_policy\blocked_scene_captcha.json')
)

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

$helpText = (& $WinAgent help 2>&1 | Out-String)
foreach ($command in @('recovery-policy-validate', 'recovery-evaluate', 'escalation-request-create', 'safe-stop-check')) {
    if ($helpText -notmatch [regex]::Escape($command)) {
        throw "help output missing $command"
    }
}

foreach ($path in @($TaskRecoveryDoc, $Protocol, $Readme, $Changelog, $Version) + $Samples) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required file missing: $path"
    }
}
foreach ($sample in $Samples) {
    Get-Content -LiteralPath $sample -Raw | ConvertFrom-Json | Out-Null
}

$docText = Get-Content -LiteralPath $TaskRecoveryDoc -Raw
$protocolText = Get-Content -LiteralPath $Protocol -Raw
$readmeText = Get-Content -LiteralPath $Readme -Raw
$changelogText = Get-Content -LiteralPath $Changelog -Raw
$versionText = (Get-Content -LiteralPath $Version -Raw).Trim()

foreach ($command in @('recovery-policy-validate', 'recovery-evaluate', 'escalation-request-create', 'safe-stop-check')) {
    if ($docText -notmatch [regex]::Escape($command)) { throw "TASK_RECOVERY.md missing $command" }
    if ($protocolText -notmatch [regex]::Escape($command)) { throw "COMMAND_PROTOCOL.md missing $command" }
    if ($readmeText -notmatch [regex]::Escape($command)) { throw "README.md missing $command" }
}
foreach ($phrase in @('Recovery Matrix', 'Safety Stop Matrix', 'SAFETY_DENIED', 'llm_or_vlm_call_count')) {
    if ($docText -notmatch [regex]::Escape($phrase)) { throw "TASK_RECOVERY.md missing $phrase" }
}
if ($changelogText -notmatch 'v5.2.5') { throw 'CHANGELOG.md missing v5.2.5 entry.' }
$parsedVersion = [version]($versionText -replace '-.*$', '')
if ($parsedVersion.Major -ne 5 -or $parsedVersion -lt [version]'5.2.5') { throw "Expected VERSION v5.x and at least 5.2.5, got $versionText" }

$versionOutput = & $WinAgent version
$versionJson = $versionOutput | ConvertFrom-Json
$parsedRuntimeVersion = [version](($versionJson.data.version) -replace '-.*$', '')
if ($parsedRuntimeVersion.Major -ne 5 -or $parsedRuntimeVersion -lt [version]'5.2.5') { throw "Expected winagent version v5.x and at least 5.2.5, got $($versionJson.data.version)" }

$lines = @(
    '# v5.2.5 Recovery Docs Selftest Report',
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
Write-Host 'PASS: v5.2.5 Recovery docs selftest'
Write-Host "Report: $Report"

