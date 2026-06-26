param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\v5_rc_docs_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates v5.8.5 RC docs, versioning note, command consistency, and samples.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.8.5'
$Report = Join-Path $ArtifactDir 'v5_rc_docs_selftest_report.md'

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

function Fail($Message) { throw "FAIL: $Message" }

$versionText = (Get-Content -LiteralPath (Join-Path $Root 'VERSION') -Raw).Trim()
if ($versionText -ne '5.8.7') { Fail "Expected VERSION 5.8.7, got $versionText" }

$docs = @(
    'README.md',
    'CHANGELOG.md',
    'docs\ROADMAP.md',
    'COMMAND_PROTOCOL.md',
    'docs\TASK_RUNTIME.md',
    'docs\STEP_CONTRACT.md',
    'docs\TASK_RECOVERY.md',
    'docs\HUMAN_CONFIRMATION.md',
    'docs\TASK_TEMPLATES_V2.md',
    'docs\FILE_WORKFLOWS.md',
    'docs\KNOWN_LIMITATIONS.md',
    'docs\SAFETY_MANIFEST.md',
    'docs\V5_TASK_EXECUTION_RC.md'
)
foreach ($relative in $docs) {
    $path = Join-Path $Root $relative
    if (-not (Test-Path -LiteralPath $path)) { Fail "Missing doc: $relative" }
    $text = Get-Content -LiteralPath $path -Raw
    foreach ($marker in @('internal engineering stage','Version Normalization Pass','0.x.x','1.0.0')) {
        if ($text -notmatch [regex]::Escape($marker)) { Fail "$relative missing versioning marker: $marker" }
    }
}

$helpText = (& $WinAgent help 2>&1 | Out-String)
foreach ($command in @('run-task','task-status','task-events','task-report','task-confirm','task-cancel','task-session-run','step-verify','recovery-evaluate','confirmation-gate-check','task-template-v2-resolve','file-picker-flow')) {
    if ($helpText -notmatch [regex]::Escape($command)) { Fail "help output missing $command" }
}

$commandProtocol = Get-Content -LiteralPath (Join-Path $Root 'COMMAND_PROTOCOL.md') -Raw
foreach ($command in @('run-task','task-status','task-events','task-report','task-confirm','task-cancel')) {
    if ($commandProtocol -notmatch [regex]::Escape($command)) { Fail "COMMAND_PROTOCOL missing $command" }
}
if ($commandProtocol -notmatch 'v5.8.7' -or $commandProtocol -notmatch 'internal engineering stage') {
    Fail 'COMMAND_PROTOCOL missing v5.8.7 internal stage note'
}

foreach ($sample in @('v5_7_service_run_task_request.json','v5_7_service_status_request.json','v5_7_service_cancel_request.json')) {
    $json = Get-Content -LiteralPath (Join-Path $Root "samples\tasks\$sample") -Raw | ConvertFrom-Json
    if (-not $json.endpoint -or -not $json.body) { Fail "Sample $sample missing endpoint/body" }
}

$lines = @(
    '# v5.8.5 RC Docs Selftest',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    '- docs examples parse: PASS',
    '- command consistency check: PASS',
    '- version normalization note: PASS'
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.8.5 RC docs selftest'
Write-Host "Report: $Report"
