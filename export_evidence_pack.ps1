param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$Version = (Get-Content -LiteralPath (Join-Path $Root 'VERSION') -Raw).Trim()
$BenchmarkArtifacts = Join-Path $Root 'artifacts\benchmark'
$EvidenceRoot = Join-Path $Root 'artifacts\evidence'
$Staging = Join-Path $EvidenceRoot "DesktopVisual-v$Version-evidence-pack"
$ZipPath = Join-Path $EvidenceRoot "DesktopVisual-v$Version-evidence-pack.zip"
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null

if (-not (Test-Path -LiteralPath (Join-Path $BenchmarkArtifacts 'benchmark_summary.json'))) {
    & (Join-Path $Root 'benchmark_matrix.ps1') -Root $Root
    if ($LASTEXITCODE -ne 0) { throw 'benchmark_matrix.ps1 failed' }
}

if (Test-Path -LiteralPath $Staging) {
    Remove-Item -LiteralPath $Staging -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $Staging | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Staging 'benchmark_reports') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Staging 'docs') | Out-Null

foreach ($file in @(
    'benchmark_report.md',
    'benchmark_summary.json'
)) {
    Copy-Item -LiteralPath (Join-Path $BenchmarkArtifacts $file) -Destination $Staging -Force
}

$reportDir = Join-Path $BenchmarkArtifacts 'reports'
if (Test-Path -LiteralPath $reportDir) {
    Get-ChildItem -LiteralPath $reportDir -File -Filter '*.md' -ErrorAction SilentlyContinue |
        Select-Object -First 10 |
        ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Staging 'benchmark_reports') -Force }
}

foreach ($file in @('VERSION','CHANGELOG.md')) {
    if (Test-Path -LiteralPath (Join-Path $Root $file)) {
        Copy-Item -LiteralPath (Join-Path $Root $file) -Destination $Staging -Force
    }
}

foreach ($doc in @('BENCHMARK_METHODOLOGY.md','SAFETY.md','KNOWN_LIMITATIONS.md')) {
    $src = Join-Path $Root "docs\$doc"
    if (Test-Path -LiteralPath $src) {
        Copy-Item -LiteralPath $src -Destination (Join-Path $Staging 'docs') -Force
    }
}

$manifest = Join-Path $Staging 'EVIDENCE_PACK_MANIFEST.md'
@(
    '# DesktopVisual Evidence Pack Manifest',
    '',
    "- Version: $Version",
    "- Export time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "- Source root: $Root",
    '',
    '## Included',
    '',
    '- benchmark_report.md',
    '- benchmark_summary.json',
    '- selected benchmark task reports',
    '- VERSION',
    '- CHANGELOG.md',
    '- BENCHMARK_METHODOLOGY.md',
    '- SAFETY.md',
    '- KNOWN_LIMITATIONS.md',
    '',
    '## Excluded',
    '',
    '- bin/',
    '- obj/',
    '- dist/',
    '- browser profiles and caches',
    '- raw motion data',
    '- historical artifacts'
) | Set-Content -LiteralPath $manifest -Encoding UTF8

if (Test-Path -LiteralPath $ZipPath) {
    Remove-Item -LiteralPath $ZipPath -Force
}
Compress-Archive -Path (Join-Path $Staging '*') -DestinationPath $ZipPath -Force
if (-not (Test-Path -LiteralPath $ZipPath)) {
    throw "Evidence pack not created: $ZipPath"
}

Write-Host "Evidence pack: $ZipPath"
