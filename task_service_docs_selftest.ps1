param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\task_service_docs_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates v5.7 task service docs, adapter notes, command help, and sample JSON.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.7.5'
$Report = Join-Path $ArtifactDir 'task_service_docs_selftest_report.md'

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

function Fail($Message) { throw "FAIL: $Message" }

$requiredFiles = @(
    'COMMAND_PROTOCOL.md',
    'docs\SERVICE_PROTOCOL.md',
    'docs\AGENT_ADAPTERS.md',
    'adapters\generic-cli\README.md',
    'README.md',
    'CHANGELOG.md',
    'VERSION',
    'samples\tasks\v5_7_service_run_task_request.json',
    'samples\tasks\v5_7_service_status_request.json',
    'samples\tasks\v5_7_service_cancel_request.json'
)
foreach ($relative in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $relative))) { Fail "Missing required file: $relative" }
}

$versionText = (Get-Content -LiteralPath (Join-Path $Root 'VERSION') -Raw).Trim()
$parsedVersion = [version]($versionText -replace '-.*$', '')
if ($parsedVersion.Major -ne 5 -or $parsedVersion -lt [version]'5.7.6') { Fail "Expected VERSION v5.x and at least 5.7.6, got $versionText" }

$helpText = (& $WinAgent help 2>&1 | Out-String)
foreach ($command in @('run-task','task-status','task-events','task-report','task-confirm','task-cancel')) {
    if ($helpText -notmatch [regex]::Escape($command)) { Fail "help output missing $command" }
}

$commandProtocol = Get-Content -LiteralPath (Join-Path $Root 'COMMAND_PROTOCOL.md') -Raw
$serviceProtocol = Get-Content -LiteralPath (Join-Path $Root 'docs\SERVICE_PROTOCOL.md') -Raw
$adapterDocs = Get-Content -LiteralPath (Join-Path $Root 'docs\AGENT_ADAPTERS.md') -Raw
$genericReadme = Get-Content -LiteralPath (Join-Path $Root 'adapters\generic-cli\README.md') -Raw
$readme = Get-Content -LiteralPath (Join-Path $Root 'README.md') -Raw
$changelog = Get-Content -LiteralPath (Join-Path $Root 'CHANGELOG.md') -Raw

foreach ($marker in @('task-status','task-events','task-report','task-confirm','task-cancel','machine_readable_status','cancel_audit.json')) {
    if ($commandProtocol -notmatch [regex]::Escape($marker)) { Fail "COMMAND_PROTOCOL.md missing $marker" }
}
foreach ($marker in @('/run_task','/get_task_status','/get_task_events','/confirm_task_action','/cancel_task','/read_task_report','safety_override=false','cancel_audit.json','External callers must not use service mode as a low-level coordinate action channel')) {
    if ($serviceProtocol -notmatch [regex]::Escape($marker)) { Fail "SERVICE_PROTOCOL.md missing $marker" }
}
foreach ($marker in @('Codex','Claude Code','custom service caller','task-status','/run_task')) {
    if ($adapterDocs -notmatch [regex]::Escape($marker)) { Fail "AGENT_ADAPTERS.md missing $marker" }
}
foreach ($marker in @('task-status','task-events','task-report','/run_task')) {
    if ($genericReadme -notmatch [regex]::Escape($marker)) { Fail "generic-cli README missing $marker" }
    if ($readme -notmatch [regex]::Escape($marker)) { Fail "README.md missing $marker" }
}
if ($changelog -notmatch 'v5.7.6') { Fail 'CHANGELOG.md missing v5.7.6 entry' }

foreach ($sample in @('v5_7_service_run_task_request.json','v5_7_service_status_request.json','v5_7_service_cancel_request.json')) {
    $json = Get-Content -LiteralPath (Join-Path $Root "samples\tasks\$sample") -Raw | ConvertFrom-Json
    if (-not $json.endpoint -or -not $json.body) { Fail "Sample $sample missing endpoint/body" }
}

$lines = @(
    '# v5.7.5 Task Service Docs Selftest',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    '- help command: PASS',
    '- docs markers: PASS',
    '- adapter examples: PASS',
    '- sample JSON parse: PASS'
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.7 task service docs selftest'
Write-Host "Report: $Report"

