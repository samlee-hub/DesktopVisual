param([Parameter(Mandatory=$true)][string]$ReportFile)

if (-not (Test-Path $ReportFile)) { Write-Error "Report not found: $ReportFile"; exit 1 }

$content = Get-Content $ReportFile -Raw

Write-Host "=== Report Summary ===" -ForegroundColor Cyan

if ($content -match 'Case name: `(.+?)`') { Write-Host "Case: $($Matches[1])" }
if ($content -match 'Case version: (\d+)') { Write-Host "Case version: $($Matches[1])" }
if ($content -match 'Target title: `(.+?)`') { Write-Host "Target: $($Matches[1])" }
if ($content -match 'Result: (\w+)') {
    $result = $Matches[1]
    $color = if ($result -eq 'SUCCESS') { 'Green' } else { 'Red' }
    Write-Host "Result: $result" -ForegroundColor $color
}
if ($content -match 'Step count: (\d+)') { Write-Host "Steps: $($Matches[1])" }
if ($content -match 'Passed step count: (\d+)') { Write-Host "Passed: $($Matches[1])" }
if ($content -match 'Failed step index: (\d+)') { Write-Host "Failed step index: $($Matches[1])" }
if ($content -match 'Failure error_code: `(\w+)`') { Write-Host "Error code: $($Matches[1])" -ForegroundColor Red }
if ($content -match 'Failure message: (.+)') { Write-Host "Message: $($Matches[1])" -ForegroundColor Red }

# Variables (v2)
if ($content -match '## Variables') { Write-Host "Variables: present" -ForegroundColor Cyan }

# Expect results (v2)
if ($content -match '## Expect Results') {
    Write-Host "Expect Results:" -ForegroundColor Cyan
    $expectSection = $content -split '## Expect Results' | Select-Object -Last 1
    $expectSection = $expectSection -split '## ' | Select-Object -First 1
    $lines = $expectSection -split "`n" | Where-Object { $_ -match '^\|' -and $_ -notmatch 'step \| type' -and $_ -notmatch '^\|--' }
    foreach ($line in $lines) {
        Write-Host "  $line"
    }
}

# Wait results (v2)
if ($content -match '## Wait Results') {
    Write-Host "Wait Results:" -ForegroundColor Cyan
    $waitSection = $content -split '## Wait Results' | Select-Object -Last 1
    $waitSection = $waitSection -split '## ' | Select-Object -First 1
    $lines = $waitSection -split "`n" | Where-Object { $_ -match '^\|' -and $_ -notmatch 'step \| condition' -and $_ -notmatch '^\|--' }
    foreach ($line in $lines) { Write-Host "  $line" }
}

# Observations
if ($content -match '## Observations') {
    $obsCount = ([regex]::Matches($content, 'observe count: (\d+)')).Groups[1].Value
    Write-Host "Observations: $obsCount"
}

Write-Host "=== End Summary ===" -ForegroundColor Cyan
