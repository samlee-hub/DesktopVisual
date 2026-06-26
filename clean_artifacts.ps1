param(
    [string]$Root = '',
    [switch]$DryRun,
    [switch]$DeleteGenerated,
    [switch]$KeepLatest
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot

function Get-SizeText {
    param([System.IO.FileSystemInfo]$Item)
    if ($Item -is [System.IO.FileInfo]) { return "$($Item.Length) bytes" }
    $sum = (Get-ChildItem -LiteralPath $Item.FullName -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    return "$([math]::Round(($sum / 1MB), 2)) MB"
}

function Assert-AllowedTarget {
    param([string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $allowedRoots = @(
        (Join-Path $Root 'artifacts'),
        (Join-Path $Root 'bin'),
        (Join-Path $Root 'obj'),
        (Join-Path $Root 'dist'),
        (Join-Path $Root 'edge_profile'),
        (Join-Path $Root 'debug_profile')
    )
    foreach ($root in $allowedRoots) {
        if ($full.Equals($root, [System.StringComparison]::OrdinalIgnoreCase) -or
            $full.StartsWith($root + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            return
        }
    }
    throw "Refusing to clean path outside allowed generated roots: $full"
}

$isDryRun = $DryRun -or -not $DeleteGenerated
$candidates = New-Object System.Collections.Generic.List[System.IO.FileSystemInfo]

$artifactRoot = Join-Path $Root 'artifacts'
if (Test-Path -LiteralPath $artifactRoot) {
    $patterns = @('*.bmp','*.png','*.jpg','*.jpeg','*.log','*.md','*.json','*.tmp','*.cache')
    foreach ($pattern in $patterns) {
        Get-ChildItem -LiteralPath $artifactRoot -Recurse -Force -File -Filter $pattern -ErrorAction SilentlyContinue |
            ForEach-Object { $candidates.Add($_) }
    }
    $motionRaw = Join-Path $artifactRoot 'motion_profile\raw'
    if (Test-Path -LiteralPath $motionRaw) {
        $candidates.Add((Get-Item -LiteralPath $motionRaw))
    }
}

@('bin','obj','edge_profile','debug_profile') | ForEach-Object {
    $path = Join-Path $Root $_
    if (Test-Path -LiteralPath $path) {
        $candidates.Add((Get-Item -LiteralPath $path))
    }
}

$dist = Join-Path $Root 'dist'
if (Test-Path -LiteralPath $dist) {
    Get-ChildItem -LiteralPath $dist -Force -File -Include '*.zip','*.7z','*.tar','*.gz' -ErrorAction SilentlyContinue |
        ForEach-Object { $candidates.Add($_) }
}

$items = @($candidates | Sort-Object FullName -Unique)
if ($KeepLatest -and $items.Count -gt 0) {
    $latest = $items | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $items = @($items | Where-Object { $_.FullName -ne $latest.FullName })
    Write-Host "KeepLatest: preserving $($latest.FullName)"
}

Write-Host "DesktopVisual generated artifact cleanup"
Write-Host "Mode: $(if ($isDryRun) { 'DRY RUN' } else { 'DELETE GENERATED' })"
$motionRawSummary = Join-Path $Root 'artifacts\motion_profile\raw'
if (Test-Path -LiteralPath $motionRawSummary) {
    Write-Host "Motion profile raw directory: $motionRawSummary"
}
Write-Host "Candidate count: $($items.Count)"

foreach ($item in $items) {
    Assert-AllowedTarget $item.FullName
    Write-Host ("- {0} [{1}]" -f $item.FullName, (Get-SizeText $item))
}

if ($isDryRun) {
    Write-Host "No files deleted. Re-run with -DeleteGenerated to delete listed generated items."
    exit 0
}

foreach ($item in $items) {
    Assert-AllowedTarget $item.FullName
    Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Deleted generated items: $($items.Count)"
