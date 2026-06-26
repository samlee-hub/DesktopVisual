param(
    [string]$Root = '',
    [switch]$Help,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\dogfood_matrix.ps1 [-Root <path>] [-SkipBuild]'
    Write-Host 'Runs the bounded developer-tool dogfood matrix and writes artifacts\dogfood\dogfood_report.md plus dogfood_summary.json.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$DogfoodRoot = Join-Path $Root 'dogfood'
$Artifacts = Join-Path $Root 'artifacts\dogfood'
$LegacyReport = Join-Path $Root 'artifacts\dogfood_matrix_report.md'
$DogfoodReport = Join-Path $Artifacts 'dogfood_report.md'
$SummaryJson = Join-Path $Artifacts 'dogfood_summary.json'

New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null

if (-not $SkipBuild) {
    Write-Host "Building..." -ForegroundColor Cyan
    & "$Root\build.ps1" -Root $Root
    if ($LASTEXITCODE -ne 0) { throw "Build failed" }
}

$ver = & $WinAgent version 2>&1 | ConvertFrom-Json
Write-Host "DesktopVisual v$($ver.data.version) OCR=$($ver.data.ocr_available)" -ForegroundColor Cyan

$metadata = @{
    notepad = @{
        label = 'Notepad'
        safety_boundary = 'Launches only a clean Notepad process for artifacts\dogfood\notepad\notepad_dogfood.txt; skips if user Notepad exists.'
        expected_result = 'Types a generated marker, saves the artifacts temp file, and verifies file content.'
        skipped_condition = 'Existing Notepad process, missing clean target window, or focus/input unavailable.'
    }
    calculator = @{
        label = 'Calculator'
        safety_boundary = 'Launches only normal-user Calculator; skips if a Calculator window already exists.'
        expected_result = 'Computes 12+30 and verifies 42 through OCR or UIA.'
        skipped_condition = 'Existing Calculator window, missing Calculator app, or unverifiable localized UI.'
    }
    explorer = @{
        label = 'Explorer'
        safety_boundary = 'Opens Explorer only in artifacts\dogfood\explorer\explorer_work and cleans the temporary directory.'
        expected_result = 'Creates a generated folder inside the artifacts dogfood work directory.'
        skipped_condition = 'Explorer target window or shell shortcut is unavailable.'
    }
    local_html = @{
        label = 'Local HTML'
        safety_boundary = 'Uses a generated local HTML fixture under artifacts\dogfood\local_html; no browser profile, login, or external URL.'
        expected_result = 'Classifies mixed textbox, radio, checkbox, dropdown, textarea, and button controls through form-control.'
        skipped_condition = 'form-control command or local fixture parsing is unavailable.'
    }
    powershell = @{
        label = 'PowerShell'
        safety_boundary = 'Runs local non-admin read-only/test PowerShell commands and reads only generated artifacts output.'
        expected_result = 'Writes a test command result under artifacts and verifies it through winagent read-file.'
        skipped_condition = 'PowerShell or read-file allowlist is unavailable.'
    }
    vscode = @{
        label = 'VS Code'
        safety_boundary = 'Uses VS Code only with a generated file and isolated user-data dir under artifacts; skips if user Code is already running.'
        expected_result = 'Appends text to artifacts\dogfood\vscode\sample.txt and verifies the saved file.'
        skipped_condition = 'VS Code missing, existing Code process, clean target window unavailable, or editor focus unavailable.'
    }
}

$taskIds = @('notepad', 'calculator', 'explorer', 'local_html', 'powershell', 'vscode')
$results = @()
$totalStart = Get-Date

function Add-DogfoodMetadata {
    param(
        [object]$Result,
        [string]$TaskId
    )
    $meta = $metadata[$TaskId]
    if (-not $Result.PSObject.Properties['task_id']) {
        $Result | Add-Member -NotePropertyName task_id -NotePropertyValue $TaskId
    }
    if (-not $Result.PSObject.Properties['app'] -or -not $Result.app) {
        $Result | Add-Member -Force -NotePropertyName app -NotePropertyValue $meta.label
    }
    foreach ($field in @('safety_boundary', 'expected_result', 'skipped_condition')) {
        if (-not $Result.PSObject.Properties[$field] -or -not $Result.$field) {
            $Result | Add-Member -Force -NotePropertyName $field -NotePropertyValue $meta[$field]
        }
    }
    return $Result
}

foreach ($taskId in $taskIds) {
    $meta = $metadata[$taskId]
    Write-Host "`n=== $($meta.label) Dogfood ===" -ForegroundColor Yellow
    $runScript = Join-Path $DogfoodRoot "$taskId\run.ps1"
    $reportDir = Join-Path $Artifacts $taskId
    $reportOut = Join-Path $reportDir 'report.json'
    New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

    if (-not (Test-Path -LiteralPath $runScript)) {
        $results += Add-DogfoodMetadata ([PSCustomObject]@{
            app = $meta.label; status = 'SKIPPED'; reason = 'run.ps1 not found'; steps = 0
            report_path = ''; screenshots = @(); duration_ms = 0; locators = ''
        }) $taskId
        Write-Host "  SKIPPED: run.ps1 not found" -ForegroundColor Yellow
        continue
    }

    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $runScript -Root $Root -ReportOut $reportOut 2>&1 |
            ForEach-Object { Write-Host "  $_" }
        if (Test-Path -LiteralPath $reportOut) {
            $json = Get-Content -LiteralPath $reportOut -Raw | ConvertFrom-Json
            $json = Add-DogfoodMetadata $json $taskId
            $results += $json
            $color = if ($json.status -eq 'PASS') { 'Green' } elseif ($json.status -eq 'SKIPPED') { 'Yellow' } else { 'Red' }
            Write-Host "  >> $($json.status): $($json.reason)" -ForegroundColor $color
        } else {
            $results += Add-DogfoodMetadata ([PSCustomObject]@{
                app = $meta.label; status = 'FAIL'; reason = 'No report file generated'; steps = 0
                report_path = ''; screenshots = @(); duration_ms = 0; locators = ''
            }) $taskId
            Write-Host "  FAIL: No report file" -ForegroundColor Red
        }
    } catch {
        $results += Add-DogfoodMetadata ([PSCustomObject]@{
            app = $meta.label; status = 'FAIL'; reason = "Script error: $_"; steps = 0
            report_path = $reportOut; screenshots = @(); duration_ms = 0; locators = ''
        }) $taskId
        Write-Host "  FAIL: $_" -ForegroundColor Red
    }
}

$totalDuration = [math]::Round(((Get-Date) - $totalStart).TotalMilliseconds)
$resultList = @($results)
$pass = @($resultList | Where-Object { $_.status -eq 'PASS' }).Count
$fail = @($resultList | Where-Object { $_.status -eq 'FAIL' }).Count
$skip = @($resultList | Where-Object { $_.status -eq 'SKIPPED' }).Count
$total = $resultList.Count
$excludingSkip = $total - $skip
$passRate = if ($excludingSkip -gt 0) { [math]::Round(($pass / $excludingSkip) * 100, 1) } else { 0 }
$failureReasons = @($resultList | Where-Object { $_.status -eq 'FAIL' } | ForEach-Object { $_.reason })

$summary = [PSCustomObject]@{
    version = $ver.data.version
    timestamp = (Get-Date).ToString('s')
    total = $total
    pass = $pass
    fail = $fail
    skipped = $skip
    pass_rate_excluding_skipped = $passRate
    report_path = $DogfoodReport
    legacy_report_path = $LegacyReport
    tasks = @($resultList)
    notes = @(
        'Dogfood is bounded evidence for listed local developer-tool scenarios only.',
        'A PASS does not prove arbitrary software control.',
        'SKIPPED is not PASS and should be reported distinctly.'
    )
}
$summary | ConvertTo-Json -Depth 8 | Out-File -LiteralPath $SummaryJson -Encoding utf8

$md = @"
# DesktopVisual Dogfood Report

- Version: $($ver.data.version)
- OCR available: $($ver.data.ocr_available)
- OCR engine: $($ver.data.ocr_engine)
- Total time: ${totalDuration}ms
- Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
- Summary JSON: $SummaryJson

## Results

| Task | Status | Safety Boundary | Expected Result | SKIPPED Condition | Reason | Steps | Report | Screenshots | Duration (ms) | Locator methods used |
|---|---|---|---|---|---|---:|---|---:|---:|---|
"@

foreach ($r in $resultList) {
    $reason = ([string]$r.reason).Replace('|', '/')
    $boundary = ([string]$r.safety_boundary).Replace('|', '/')
    $expected = ([string]$r.expected_result).Replace('|', '/')
    $skippedCondition = ([string]$r.skipped_condition).Replace('|', '/')
    $reportPath = if ($r.report_path) { [string]$r.report_path } else { '' }
    $screenshotCount = @($r.screenshots).Count
    $steps = if ($null -ne $r.steps) { [int]$r.steps } else { 0 }
    $md += "`n| $($r.app) | $($r.status) | $boundary | $expected | $skippedCondition | $reason | $steps | $reportPath | $screenshotCount | $($r.duration_ms) | $($r.locators) |"
}

$md += @"


## Per-Task Reports

"@

foreach ($r in $resultList) {
    if ($r.report_path -and (Test-Path -LiteralPath $r.report_path)) {
        $md += "- [$($r.app)]($($r.report_path))`n"
    }
}

$md += @"

## Screenshots

"@

$screenshotCount = 0
foreach ($r in $resultList) {
    foreach ($s in @($r.screenshots)) {
        if ($s -and (Test-Path -LiteralPath $s -ErrorAction SilentlyContinue)) {
            $md += "- $s`n"
            $screenshotCount++
        }
    }
}
if ($screenshotCount -eq 0) { $md += "(no screenshots)`n" }

$md += @"

## Statistics

- total: $total
- pass: $pass
- fail: $fail
- skipped: $skip
- pass_rate_excluding_skipped: ${passRate}%
"@

if ($failureReasons.Count -gt 0) {
    $md += "`n## main_failure_reasons`n`n"
    foreach ($reason in $failureReasons) {
        $md += "- $reason`n"
    }
} else {
    $md += "`n## main_failure_reasons`n`n- none`n"
}

$md += @"

## Notes

- Dogfood tests target bounded normal-user desktop or local developer-tool scenarios.
- SKIPPED means the app, a clean target window, or a required OS capability is not available on this system.
- FAIL means the test ran but did not achieve the expected outcome.
- All dogfood file operations are confined to $Artifacts.
- Browser-like dogfood uses generated local files only; no external websites, real accounts, browser profiles, payments, passwords, captcha, social apps, games, anti-cheat, UAC, or administrator windows are used.
- Dogfood is bounded confidence evidence, not proof that DesktopVisual can control arbitrary software.
"@

$md | Out-File -LiteralPath $DogfoodReport -Encoding utf8
$md | Out-File -LiteralPath $LegacyReport -Encoding utf8

Write-Host "`n=== Matrix Complete ===" -ForegroundColor Cyan
Write-Host "Report: $DogfoodReport" -ForegroundColor White
Write-Host "Summary: $SummaryJson" -ForegroundColor White
Write-Host "Legacy report: $LegacyReport" -ForegroundColor White
Write-Host "Total: $total | Pass: $pass | Fail: $fail | Skip: $skip | Pass Rate: ${passRate}%" -ForegroundColor Cyan
Write-Host ""
Write-Host $md

if ($fail -gt 0) { exit 1 }
exit 0
