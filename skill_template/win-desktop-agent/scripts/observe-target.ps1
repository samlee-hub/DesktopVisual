param([Parameter(Mandatory=$true)][string]$Title)

$Resolver = Join-Path $PSScriptRoot 'Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'

if (-not (Test-Path $WinAgent)) {
    Write-Error "winagent.exe not found at $WinAgent. Run $Root\build.ps1 first."
    exit 1
}

Write-Host "=== Observe: $Title ===" -ForegroundColor Cyan
$output = & $WinAgent observe --title $Title 2>&1
$exit = $LASTEXITCODE

if ($exit -ne 0) {
    Write-Error "observe failed with exit code $exit"
    Write-Host $output
    exit $exit
}

try {
    $json = $output | ConvertFrom-Json
    if (-not $json.ok) {
        Write-Host "ERROR: $($json.error.code) - $($json.error.message)" -ForegroundColor Red
        exit 1
    }
    Write-Host "Target: $($json.data.target_window.title) (hwnd=$($json.data.target_window.hwnd))"
    Write-Host "Focus verified: $($json.data.focus_verified)"
    Write-Host "UIA elements: $($json.data.uia.element_count)"
    Write-Host "Mouse: ($($json.data.mouse.screen_x), $($json.data.mouse.screen_y))"
    if ($json.data.screenshot.path) { Write-Host "Screenshot: $($json.data.screenshot.path)" }
    if ($json.data.warnings.Count -gt 0) {
        Write-Host "Warnings:" -ForegroundColor Yellow
        $json.data.warnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    }
    Write-Host "Observe OK" -ForegroundColor Green
} catch {
    Write-Error "Failed to parse observe output as JSON"
    Write-Host $output
    exit 1
}
