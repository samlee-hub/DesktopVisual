param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\v5_rc_audit.ps1 [-Root <path>]'
    Write-Host 'Validates v5.8.1 feature freeze and audit documentation.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$ArtifactDir = Join-Path $Root 'artifacts\dev5.8.1'
$Report = Join-Path $ArtifactDir 'v5_rc_audit_report.md'
$Doc = Join-Path $Root 'docs\V5_TASK_EXECUTION_RC.md'

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

if (-not (Test-Path -LiteralPath $Doc)) { throw "Missing RC audit doc: $Doc" }
$text = Get-Content -LiteralPath $Doc -Raw
foreach ($marker in @('Feature Matrix','Missing Features','Known Limitations','Safety Review','Performance Review','Versioning Note','Task-Level Desktop Execution Runtime')) {
    if ($text -notmatch [regex]::Escape($marker)) { throw "RC audit doc missing marker: $marker" }
}

$lines = @(
    '# v5.8.1 Feature Freeze and Audit',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "- Audit doc: $Doc",
    '- v5 feature matrix: PASS',
    '- missing features: PASS',
    '- known limitations: PASS',
    '- safety review: PASS',
    '- performance review: PASS'
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.8.1 feature freeze and audit'
Write-Host "Report: $Report"
