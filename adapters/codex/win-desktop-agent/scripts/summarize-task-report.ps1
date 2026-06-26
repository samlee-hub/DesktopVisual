param([Parameter(Mandatory=$true)][string]$ReportFile)

if (-not (Test-Path $ReportFile)) { Write-Error "Report not found: $ReportFile"; exit 1 }
$content = Get-Content $ReportFile -Raw

Write-Host "=== Task Report Summary ===" -ForegroundColor Cyan

if ($content -match 'Task: `(.+?)`') { Write-Host "Task: $($Matches[1])" }
if ($content -match 'Result: (\w+)') {
    $r = $Matches[1]
    Write-Host "Result: $r" -ForegroundColor $(if ($r -eq 'SUCCESS') { 'Green' } else { 'Red' })
}
if ($content -match 'Duration: (\d+) ms') { Write-Host "Duration: $($Matches[1])ms" }
if ($content -match 'Steps: (\d+) total, (\d+) passed') { Write-Host "Steps: $($Matches[1]) total, $($Matches[2]) passed" }
if ($content -match 'Recoveries: (\d+)') { Write-Host "Recoveries: $($Matches[1])" }

# Extract failure info
if ($content -match 'Final error: `(\w+)` - (.+)') {
    Write-Host "Error: $($Matches[1])" -ForegroundColor Red
    Write-Host "Message: $($Matches[2])" -ForegroundColor Red
}

# Extract recommendations
if ($content -match '## Final Recommendation\s*\n(.+)') {
    Write-Host "Recommendation: $($Matches[1])" -ForegroundColor Yellow
}

# Step timeline summary
$steps = [regex]::Matches($content, '### (.+?) \((.+?)\) - (\w+)')
foreach ($step in $steps) {
    $color = if ($step.Groups[3].Value -eq 'PASS') { 'Green' } else { 'Red' }
    Write-Host "  [$($step.Groups[2].Value)] $($step.Groups[1].Value): $($step.Groups[3].Value)" -ForegroundColor $color
}

Write-Host "=== End Summary ===" -ForegroundColor Cyan
