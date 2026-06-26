param(
    [switch]$Help,
    [string]$Root = '',
    [string]$OutDir = '',
    [string]$SourceRoot = '',
    [string]$ExportRoot = ''
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: package_source.ps1 [-Root <path>] [-OutDir <path>]'
    Write-Host 'Exports a clean public source tree and creates DesktopVisual-v<VERSION>-source.zip.'
    exit 0
}

if ($SourceRoot -and -not $Root) {
    $Root = $SourceRoot
}
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$SourceRoot = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $SourceRoot
$versionPath = Join-Path $SourceRoot 'VERSION'
$version = if (Test-Path -LiteralPath $versionPath) { (Get-Content -LiteralPath $versionPath -Raw).Trim() } else { 'unknown' }
if (-not $OutDir) {
    $OutDir = Join-Path $SourceRoot 'artifacts\release'
}
$OutDir = [System.IO.Path]::GetFullPath($OutDir)
if (-not $ExportRoot) {
    $ExportRoot = Join-Path $OutDir "DesktopVisual-v$version-source"
}
$ZipPath = Join-Path $OutDir "DesktopVisual-v$version-source.zip"

function Fail($Message) {
    throw $Message
}

function Copy-DirectoryIfPresent {
    param([string]$Name)
    $src = Join-Path $SourceRoot $Name
    $dst = Join-Path $ExportRoot $Name
    if (Test-Path -LiteralPath $src -PathType Container) {
        Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
    }
}

function Copy-FileIfPresent {
    param([string]$Name)
    $src = Join-Path $SourceRoot $Name
    if (Test-Path -LiteralPath $src -PathType Leaf) {
        Copy-Item -LiteralPath $src -Destination (Join-Path $ExportRoot $Name) -Force
    }
}

function Remove-ExportIgnoredContent {
    $excludedDirs = @(
        'artifacts', 'bin', 'dist', 'obj',
        'edge_profile', 'debug_profile', 'browser_profile', 'profile',
        'BrowserMetrics', 'Cache', 'Code Cache', 'Crashpad', 'GPUCache', 'Service Worker',
        'Local Storage', 'Session Storage', 'IndexedDB',
        'runs', 'temp', 'tmp', '.vs'
    )
    foreach ($dir in $excludedDirs) {
        Get-ChildItem -LiteralPath $ExportRoot -Recurse -Force -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ieq $dir } |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
    }

    $excludedPatterns = @('*.obj','*.pdb','*.ilk','*.exe','*.dll','*.lib','*.exp','*.log','*.bmp','*.png','*.jpg','*.jpeg','*.tmp','*.cache','*.zip','*.7z','Cookies','History','Login Data','Web Data')
    foreach ($pattern in $excludedPatterns) {
        Get-ChildItem -LiteralPath $ExportRoot -Recurse -Force -File -Filter $pattern -ErrorAction SilentlyContinue |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
    }

    $localOperatorProfile = Join-Path $ExportRoot 'config\operator_motion_profile.json'
    if (Test-Path -LiteralPath $localOperatorProfile) {
        Remove-Item -LiteralPath $localOperatorProfile -Force -ErrorAction SilentlyContinue
    }
}

if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
    Fail "Source root not found: $SourceRoot"
}

$resolvedExport = [System.IO.Path]::GetFullPath($ExportRoot)
$resolvedOut = [System.IO.Path]::GetFullPath($OutDir)
if (-not ($resolvedExport.StartsWith($resolvedOut, [System.StringComparison]::OrdinalIgnoreCase))) {
    Fail "Refusing to write export outside OutDir: $resolvedExport"
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
if (Test-Path -LiteralPath $ExportRoot) {
    Remove-Item -LiteralPath $ExportRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $ExportRoot | Out-Null

@('src','docs','cases','tasks','config','dogfood','adapters','benchmarks','skill_template','scripts') | ForEach-Object {
    Copy-DirectoryIfPresent $_
}

if (Test-Path -LiteralPath (Join-Path $SourceRoot 'samples') -PathType Container) {
    Copy-DirectoryIfPresent 'samples'
}

Get-ChildItem -LiteralPath $SourceRoot -File -Filter '*.ps1' | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $ExportRoot $_.Name) -Force
}

@(
    '.gitignore',
    'README.md',
    'CHANGELOG.md',
    'COMMAND_PROTOCOL.md',
    'VERSION',
    'AGENTS.md',
    'LICENSE',
    'script_lint.ps1',
    'portable_root_selftest.ps1',
    'RELEASE_NOTES_v3.0.md',
    'RELEASE_NOTES_v3.0.1.md',
    'RELEASE_NOTES_v3.0.2.md',
    'RELEASE_NOTES_v3.0.3.md',
    'RELEASE_NOTES_v3.0.4.md',
    'RELEASE_NOTES_v3.0.5.md'
) | ForEach-Object {
    Copy-FileIfPresent $_
}

Remove-ExportIgnoredContent

$fileCount = (Get-ChildItem -LiteralPath $ExportRoot -Recurse -File -Force | Measure-Object).Count
$manifest = Join-Path $ExportRoot 'SOURCE_PACKAGE_MANIFEST.md'

@(
    '# DesktopVisual Source Package Manifest',
    '',
    "- Export time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "- Source project path: $SourceRoot",
    "- Export path: $ExportRoot",
    "- Source zip: $ZipPath",
    "- Current VERSION: $version",
    "- Copied file count: $fileCount",
    '',
    '## Included',
    '',
    '- src/',
    '- docs/',
    '- cases/',
    '- tasks/',
    '- config/',
    '- dogfood/',
    '- adapters/',
    '- benchmarks/',
    '- skill_template/',
    '- scripts/',
    '- samples/ when present',
    '- root PowerShell scripts',
    '- README, CHANGELOG, COMMAND_PROTOCOL, VERSION, AGENTS, LICENSE when present',
    '',
    '## Excluded',
    '',
    '- artifacts/',
    '- bin/',
    '- dist/',
    '- obj/',
    '- edge_profile/',
    '- debug_profile/',
    '- browser_profile/',
    '- profile/',
    '- release archives',
    '- screenshots and bitmap/image runtime output',
    '- browser caches and generated profiles',
    '- local operator profile config/operator_motion_profile.json',
    '',
    '## Build',
    '',
    '```powershell',
    '.\build.ps1',
    '.\selftest.ps1',
    '```',
    '',
    'After cloning the public repository, run scripts from the clone root, pass `-Root <clone>`, or set `DESKTOPVISUAL_ROOT` to the clone path.'
) | Set-Content -LiteralPath $manifest -Encoding UTF8

if (Test-Path -LiteralPath $ZipPath) {
    Remove-Item -LiteralPath $ZipPath -Force
}
Compress-Archive -Path (Join-Path $ExportRoot '*') -DestinationPath $ZipPath -Force
if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) {
    Fail "Source zip was not created: $ZipPath"
}

Write-Host "Public export created: $ExportRoot"
Write-Host "Files copied: $fileCount"
Write-Host "Manifest: $manifest"
Write-Host "Source zip: $ZipPath"
