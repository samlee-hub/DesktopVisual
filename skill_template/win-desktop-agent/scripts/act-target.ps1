param(
    [Parameter(Mandatory=$true)][string]$Title,
    [Parameter(Mandatory=$true)][string]$Selector,
    [Parameter(Mandatory=$true)][string]$Action,
    [string]$Text
)

$Resolver = Join-Path $PSScriptRoot 'Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'

if (-not (Test-Path $WinAgent)) { Write-Error "winagent.exe not found. Build first."; exit 1 }

Write-Host "=== Act: $Action on $Selector ===" -ForegroundColor Cyan

$args = @('act', '--title', $Title, '--selector', $Selector, '--action', $Action)
if ($Text) { $args += '--text'; $args += $Text }

$output = & $WinAgent @args 2>&1
$exit = $LASTEXITCODE

try { $json = $output | ConvertFrom-Json } catch { Write-Error "Not JSON: $output"; exit 1 }

if (-not $json.ok) {
    Write-Host "ACT FAILED: $($json.error.code) - $($json.error.message)" -ForegroundColor Red
    if ($json.error.code -eq 'SAFETY_POLICY_DENIED') { Write-Host "Window not in safety allowlist." -ForegroundColor Yellow }
    if ($json.error.code -eq 'WINDOW_FOCUS_FAILED') { Write-Host "Target window could not be focused." -ForegroundColor Yellow }
    exit 1
}

Write-Host "Action method: $($json.data.action_method)"
Write-Host "Focus verified: $($json.data.focus_verified)"
Write-Host "Act OK" -ForegroundColor Green
