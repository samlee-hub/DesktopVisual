param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$Version = (Get-Content -LiteralPath (Join-Path $Root 'VERSION') -Raw).Trim()
$BenchmarkArtifacts = Join-Path $Root 'artifacts\benchmark\full_access'
$EvidenceRoot = Join-Path $Root 'artifacts\evidence'
$Staging = Join-Path $EvidenceRoot 'DesktopVisual-v3.3.10-full-access-evidence-pack'
$ZipPath = Join-Path $EvidenceRoot 'DesktopVisual-v3.3.10-full-access-evidence-pack.zip'

if ($Version -ne '3.3.10') {
    throw "Full Access evidence pack requires VERSION 3.3.10, got $Version"
}

if (-not (Test-Path -LiteralPath (Join-Path $BenchmarkArtifacts 'full_access_benchmark_summary.json'))) {
    & (Join-Path $Root 'full_access_benchmark_matrix.ps1') -Root $Root
    if ($LASTEXITCODE -ne 0) { throw 'full_access_benchmark_matrix.ps1 failed' }
}

New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
if (Test-Path -LiteralPath $Staging) { Remove-Item -LiteralPath $Staging -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Staging | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Staging 'docs') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Staging 'selected_task_reports') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Staging 'selected_screenshots') | Out-Null

Copy-Item -LiteralPath (Join-Path $BenchmarkArtifacts 'full_access_benchmark_report.md') -Destination (Join-Path $Staging 'full_access_benchmark_report.md') -Force
Copy-Item -LiteralPath (Join-Path $BenchmarkArtifacts 'full_access_benchmark_summary.json') -Destination (Join-Path $Staging 'full_access_benchmark_summary.json') -Force

foreach ($file in @('VERSION','CHANGELOG.md')) {
    Copy-Item -LiteralPath (Join-Path $Root $file) -Destination $Staging -Force
}

foreach ($doc in @(
    'SAFETY_MODEL.md',
    'KNOWN_LIMITATIONS.md',
    'DECISION_TASK_RUNTIME.md',
    'FORM_SEMANTICS.md',
    'CODING_WORKFLOW.md',
    'COMMUNICATION_RUNTIME.md'
)) {
    $src = Join-Path $Root "docs\$doc"
    if (Test-Path -LiteralPath $src) {
        Copy-Item -LiteralPath $src -Destination (Join-Path $Staging 'docs') -Force
    }
}

$reportDir = Join-Path $BenchmarkArtifacts 'reports'
if (Test-Path -LiteralPath $reportDir) {
    Get-ChildItem -LiteralPath $reportDir -File -Filter '*.md' |
        Select-Object -First 12 |
        ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Staging 'selected_task_reports') -Force }
}

$manifest = Join-Path $Staging 'EVIDENCE_PACK_MANIFEST.md'
@(
    '# DesktopVisual v3.3.10 Full Access Evidence Pack',
    '',
    "- Version: $Version",
    "- Export time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    '',
    '## Included',
    '',
    '- full_access_benchmark_report.md',
    '- full_access_benchmark_summary.json',
    '- selected task reports',
    '- selected screenshots directory (empty unless benchmark produced screenshots)',
    '- VERSION',
    '- CHANGELOG.md',
    '- docs/SAFETY_MODEL.md',
    '- docs/KNOWN_LIMITATIONS.md',
    '- docs/DECISION_TASK_RUNTIME.md',
    '- docs/FORM_SEMANTICS.md',
    '- docs/CODING_WORKFLOW.md',
    '- docs/COMMUNICATION_RUNTIME.md',
    '',
    '## Excluded',
    '',
    '- real account information',
    '- real chat or email contents',
    '- browser profiles and caches',
    '- raw motion data',
    '- bin/ and obj/',
    '- sensitive logs'
) | Set-Content -LiteralPath $manifest -Encoding UTF8

if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }
Compress-Archive -Path (Join-Path $Staging '*') -DestinationPath $ZipPath -Force
if (-not (Test-Path -LiteralPath $ZipPath)) { throw "Evidence pack not created: $ZipPath" }

Write-Host "Full Access evidence pack: $ZipPath"
exit 0
