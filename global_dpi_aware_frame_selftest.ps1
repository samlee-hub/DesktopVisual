param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.12.1_visible_ui_foundation_hardening'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Invoke-Agent([string[]]$WinArgs, [int[]]$Allowed = @(0)) {
    $output = & $WinAgent @WinArgs
    $exit = $LASTEXITCODE
    if ($Allowed -notcontains $exit) { throw "winagent $($WinArgs -join ' ') exited $exit with output: $output" }
    return $output | ConvertFrom-Json
}

function Assert($Condition, $Message) {
    if (-not $Condition) { throw $Message }
}

$globalOut = Join-Path $OutDir 'global_dpi_aware_frame_selftest.png'
$global = Invoke-Agent -WinArgs @('global-screenshot', '--out', $globalOut, '--format', 'png', '--include-metadata', 'true')
Assert ($global.ok -eq $true) 'global-screenshot should pass.'
Assert ($global.data.capture_scope -eq 'global_desktop') 'global-screenshot must report capture_scope=global_desktop.'
Assert ($global.data.can_be_final_evidence -eq $true) 'global screenshot must be final evidence capable.'
Assert ([int]$global.data.physical_width -gt 0 -and [int]$global.data.physical_height -gt 0) 'physical size must be populated.'
Assert ($global.data.virtual_screen_rect -ne $null) 'virtual_screen_rect must be present.'
Assert ($global.data.dpi_awareness -match 'per_monitor|system|dpi') 'dpi_awareness must be present.'
Assert (Test-Path -LiteralPath $globalOut) 'global screenshot file missing.'
Assert (Test-Path -LiteralPath $global.data.metadata_path) 'global screenshot metadata missing.'

$defaultOut = Join-Path $OutDir 'screenshot_default_global.bmp'
$default = Invoke-Agent -WinArgs @('screenshot', '--out', $defaultOut, '--include-metadata', 'true')
Assert ($default.ok -eq $true) 'screenshot --out should default to global capture.'
Assert ($default.data.defaulted_to_global_screenshot -eq $true) 'screenshot --out must declare defaulted_to_global_screenshot=true.'
Assert ($default.data.capture_scope -eq 'global_desktop') 'screenshot --out must use global_desktop when no title is provided.'
Assert ($default.data.can_be_final_evidence -eq $true) 'default screenshot must be valid final evidence.'

$report = Join-Path $OutDir 'global_dpi_frame_report.md'
@(
    '# Global DPI Aware Frame Selftest',
    '',
    '- result: PASS',
    "- global_out: $globalOut",
    "- default_out: $defaultOut",
    "- physical_width: $($global.data.physical_width)",
    "- physical_height: $($global.data.physical_height)",
    "- metadata_path: $($global.data.metadata_path)"
) | Set-Content -Encoding UTF8 -LiteralPath $report
Write-Host "PASS global_dpi_aware_frame_selftest"
exit 0
