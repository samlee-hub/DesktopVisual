param(
    [string]$Root = '',
    [string]$TestRepoRoot = ''
)

$ErrorActionPreference = 'Stop'

if (-not $Root) {
    $rootResolver = Join-Path $PSScriptRoot 'Resolve-DesktopVisualRoot.ps1'
    $Root = & $rootResolver -StartPath $PSScriptRoot
}

if (-not $TestRepoRoot) { $TestRepoRoot = $env:DESKTOPVISUAL_TESTREPO_ROOT }
if (-not $TestRepoRoot) {
    $sibling = Join-Path (Split-Path -Parent $Root) 'testrepo'
    if (Test-Path -LiteralPath $sibling) { $TestRepoRoot = $sibling }
}
if (-not $TestRepoRoot) { $TestRepoRoot = 'D:\testrepo' }

[System.IO.Path]::GetFullPath($TestRepoRoot)
