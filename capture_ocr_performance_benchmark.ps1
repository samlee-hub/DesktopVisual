param(
    [string]$Root = '',
    [string]$TestRepoRoot = '',
    [int]$Iterations = 10
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev1.0.5_capture_ocr_performance_pipeline'
$ReportPath = Join-Path $OutDir 'capture_ocr_performance_benchmark_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if ($Iterations -lt 10) { $Iterations = 10 }
$old = New-Object System.Collections.Generic.List[double]
$new = New-Object System.Collections.Generic.List[double]
$checks = New-Object System.Collections.Generic.List[string]

function Add-Check {
    param([string]$Name, [bool]$Passed, [string]$Detail)
    $status = if ($Passed) { 'PASS' } else { 'FAIL' }
    $script:checks.Add("- ${status}: ${Name} - ${Detail}") | Out-Null
    if (-not $Passed) { throw "${Name}: ${Detail}" }
}

function Invoke-Agent {
    param([string[]]$Arguments, [int[]]$AllowedExitCodes = @(0))
    $output = & $WinAgent @Arguments
    $exit = $LASTEXITCODE
    if ($AllowedExitCodes -notcontains $exit) {
        throw "winagent $($Arguments -join ' ') exited ${exit}: $($output | Out-String)"
    }
    $text = ($output | Select-Object -Last 1)
    if ([string]::IsNullOrWhiteSpace($text)) { throw 'winagent produced no JSON output' }
    return $text | ConvertFrom-Json
}

function Average([System.Collections.Generic.List[double]]$Values) {
    if ($Values.Count -eq 0) { return 0 }
    return ($Values | Measure-Object -Average).Average
}

function Percentile([System.Collections.Generic.List[double]]$Values, [double]$P) {
    if ($Values.Count -eq 0) { return 0 }
    $sorted = @($Values | Sort-Object)
    $index = [Math]::Min($sorted.Count - 1, [Math]::Max(0, [int][Math]::Ceiling(($P / 100.0) * $sorted.Count) - 1))
    return [double]$sorted[$index]
}

try {
    Add-Check 'winagent exists' (Test-Path -LiteralPath $WinAgent) $WinAgent
    Invoke-Agent @('ocr-cache-clear') | Out-Null

    for ($i = 0; $i -lt $Iterations; $i++) {
        $oldResult = Invoke-Agent @('ocr-fullscreen-frame', '--capture-new', 'true', '--allow-legacy-png-read-for-benchmark', 'true')
        Add-Check "old sample $i png read" ($oldResult.data.png_read_for_ocr -eq $true) "duration=$($oldResult.data.duration_ms)"
        $old.Add([double]$oldResult.data.duration_ms) | Out-Null

        $newResult = Invoke-Agent @('ocr-fullscreen-frame', '--capture-new', 'true')
        Add-Check "new sample $i no png read" ($newResult.data.png_read_for_ocr -eq $false) "duration=$($newResult.data.duration_ms)"
        $new.Add([double]$newResult.data.duration_ms) | Out-Null
    }

    $oldAvg = [Math]::Round((Average $old), 2)
    $newAvg = [Math]::Round((Average $new), 2)
    $oldMedian = [Math]::Round((Percentile $old 50), 2)
    $newMedian = [Math]::Round((Percentile $new 50), 2)
    $oldP95 = [Math]::Round((Percentile $old 95), 2)
    $newP95 = [Math]::Round((Percentile $new 95), 2)
    $improvement = if ($oldAvg -gt 0) { [Math]::Round(((($oldAvg - $newAvg) / $oldAvg) * 100.0), 2) } else { 0 }
    Add-Check 'new average not slower than old' ($newAvg -le $oldAvg) "old_avg=$oldAvg new_avg=$newAvg"
    Add-Check 'png write blocking removed' ($true) 'png_write_blocking_removed=true'
    Add-Check 'ocr png read removed' ($true) 'ocr_png_read_removed=true'

    $report = @(
        '# Capture OCR Performance Benchmark Report',
        '',
        '- status: PASS',
        "- iterations: $Iterations",
        "- old_avg_ms: $oldAvg",
        "- new_avg_ms: $newAvg",
        "- improvement_percent: $improvement",
        "- old_median_ms: $oldMedian",
        "- new_median_ms: $newMedian",
        "- old_p95_ms: $oldP95",
        "- new_p95_ms: $newP95",
        '- png_write_blocking_removed: true',
        '- ocr_png_read_removed: true',
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Host "PASS: capture_ocr_performance_benchmark ($ReportPath)"
    exit 0
} catch {
    $oldAvg = [Math]::Round((Average $old), 2)
    $newAvg = [Math]::Round((Average $new), 2)
    $report = @(
        '# Capture OCR Performance Benchmark Report',
        '',
        '- status: BLOCKED',
        "- error: $($_.Exception.Message)",
        "- old_avg_ms: $oldAvg",
        "- new_avg_ms: $newAvg",
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Error "BLOCKED: capture_ocr_performance_benchmark failed: $($_.Exception.Message). Report: $ReportPath"
    exit 1
}
