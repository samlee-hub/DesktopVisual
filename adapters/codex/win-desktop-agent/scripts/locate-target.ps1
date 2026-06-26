param(
    [Parameter(Mandatory=$true)][string]$Title,
    [Parameter(Mandatory=$true)][string]$Selector
)

$Resolver = Join-Path $PSScriptRoot 'Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'

if (-not (Test-Path $WinAgent)) { Write-Error "winagent.exe not found. Build first."; exit 1 }

Write-Host "=== Locate: $Selector ===" -ForegroundColor Cyan
$output = & $WinAgent locate --title $Title --selector $Selector 2>&1
$exit = $LASTEXITCODE

try { $json = $output | ConvertFrom-Json } catch { Write-Error "Not JSON: $output"; exit 1 }

if (-not $json.ok) {
    $code = $json.error.code
    Write-Host "LOCATE FAILED: $code - $($json.error.message)" -ForegroundColor Red
    if ($code -eq 'LOCATOR_NOT_FOUND') { Write-Host "Zero matches. Do NOT guess coordinates." -ForegroundColor Yellow }
    if ($code -eq 'LOCATOR_NOT_UNIQUE') { Write-Host "Multiple matches. Use index or more specific selector." -ForegroundColor Yellow }
    if ($code -eq 'OCR_UNAVAILABLE') { Write-Host "OCR unavailable. Check version output for ocr_available." -ForegroundColor Yellow }
    exit 1
}

Write-Host "Located: method=$($json.data.locate_method)"
Write-Host "Client point: ($($json.data.client_point.x), $($json.data.client_point.y))"
Write-Host "Screen point: ($($json.data.screen_point.x), $($json.data.screen_point.y))"
if ($json.data.element -and $json.data.element -ne 'null') {
    Write-Host "Element: $($json.data.element.name) ($($json.data.element.control_type))"
}
Write-Host "Locate OK" -ForegroundColor Green
