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
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }

$global = Invoke-Agent -WinArgs @('coordinate-map', '--direction', 'pixel-to-screen', '--capture-scope', 'global_desktop', '--capture-left', '0', '--capture-top', '0', '--capture-width', '100', '--capture-height', '100', '--pixel-x', '10', '--pixel-y', '20')
Assert ($global.ok -eq $true) 'global pixel mapping should pass.'
Assert ($global.data.screen_x -eq 10 -and $global.data.screen_y -eq 20) 'global pixel mapping returned wrong coordinate.'
Assert ($global.data.mapper_used -eq $true -and $global.data.mapping_valid -eq $true) 'mapper fields must be true.'

$window = Invoke-Agent -WinArgs @('coordinate-map', '--direction', 'pixel-to-screen', '--capture-scope', 'window_only', '--capture-left', '100', '--capture-top', '200', '--capture-width', '400', '--capture-height', '300', '--target-left', '100', '--target-top', '200', '--target-right', '500', '--target-bottom', '500', '--pixel-x', '25', '--pixel-y', '30')
Assert ($window.ok -eq $true) 'window pixel mapping should pass.'
Assert ($window.data.screen_x -eq 125 -and $window.data.screen_y -eq 230) 'window pixel mapping returned wrong coordinate.'

$mixed = Invoke-Agent -WinArgs @('coordinate-map', '--direction', 'pixel-to-screen', '--capture-scope', 'window_only', '--capture-left', '0', '--capture-top', '0', '--capture-width', '400', '--capture-height', '300', '--target-left', '100', '--target-top', '100', '--target-right', '500', '--target-bottom', '400', '--pixel-x', '20', '--pixel-y', '20') -Allowed @(1)
Assert ($mixed.ok -eq $false) 'mixed coordinate source should fail.'
Assert ($mixed.error.code -eq 'FAIL_CAPTURE_TARGET_RECT_MISMATCH') 'mixed coordinate source must return FAIL_CAPTURE_TARGET_RECT_MISMATCH.'

$report = Join-Path $OutDir 'coordinate_mapper_report.md'
@(
    '# Screenshot Coordinate Mapper Selftest',
    '',
    '- result: PASS',
    '- global pixel to screen: PASS',
    '- window pixel to screen: PASS',
    '- mixed coordinate rejection: PASS'
) | Set-Content -Encoding UTF8 -LiteralPath $report
Write-Host "PASS screenshot_coordinate_mapper_selftest"
exit 0
