param(
    [string]$Root = '',
    [switch]$Help
)

if ($Help) {
    Write-Host 'Usage: .\serve_stop.ps1'
    Write-Host 'Requests DesktopVisual service shutdown, then stops the recorded service PID if needed.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$PipeName = '\\.\pipe\DesktopVisualService'
$PidFile = Join-Path $Root 'artifacts\service_pid.txt'

Write-Host "Stopping DesktopVisual Service..." -ForegroundColor Cyan

# Try named pipe shutdown request
try {
    $pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', 'DesktopVisualService', [System.IO.Pipes.PipeDirection]::InOut)
    $pipe.Connect(3000)
    $writer = New-Object System.IO.StreamWriter($pipe)
    $writer.AutoFlush = $true
    $writer.WriteLine('{"endpoint":"/shutdown","body":{}}')
    $reader = New-Object System.IO.StreamReader($pipe)
    $response = $reader.ReadLine()
    Write-Host "Shutdown response: $response"
    $pipe.Close()
    Start-Sleep -Milliseconds 1000
} catch {
    Write-Host "Pipe shutdown failed: $_" -ForegroundColor Yellow
}

# Force kill if still running
if (Test-Path $PidFile) {
    $pid = Get-Content $PidFile
    try { Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue; Write-Host "Process $pid stopped." } catch {}
    Remove-Item $PidFile -ErrorAction SilentlyContinue
}

Write-Host "Service stopped." -ForegroundColor Green
