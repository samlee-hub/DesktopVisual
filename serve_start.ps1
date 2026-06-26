param(
    [string]$Root = '',
    [switch]$Help,
    [int]$Port = 17873,
    [string]$Token = "",
    [int]$MaxSessionMs = 3600000
)

if ($Help) {
    Write-Host 'Usage: .\serve_start.ps1 [-Port <port>] [-Token <token>] [-MaxSessionMs <ms>]'
    Write-Host 'Starts the explicit local DesktopVisual named-pipe service.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$PipeName = '\\.\pipe\DesktopVisualService'

if (-not (Test-Path $WinAgent)) { Write-Error "winagent.exe not found. Build first."; exit 1 }

# Check if already running
if ([System.IO.Directory]::GetFiles('\\.\pipe\') -match 'DesktopVisualService') {
    Write-Host "Service pipe already exists. Stop it first with serve_stop.ps1" -ForegroundColor Yellow
    exit 1
}

Write-Host "Starting DesktopVisual Service..." -ForegroundColor Cyan
$args = @('serve', '--port', $Port, '--max-session-ms', $MaxSessionMs)
if ($Token) { $args += '--token'; $args += $Token }

$proc = Start-Process -FilePath $WinAgent -ArgumentList $args -NoNewWindow -PassThru
Start-Sleep -Milliseconds 500

if ($proc.HasExited) {
    Write-Error "Service process exited immediately (code $($proc.ExitCode))"
    exit 1
}

Write-Host "Service PID: $($proc.Id)" -ForegroundColor Green
Write-Host "Pipe: $PipeName"
$proc.Id | Out-File (Join-Path $Root 'artifacts\service_pid.txt')
Write-Host "Started. Use serve_stop.ps1 to stop."
