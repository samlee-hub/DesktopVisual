param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev1.0.5_capture_ocr_performance_pipeline'
$ReportPath = Join-Path $OutDir 'async_evidence_flush_selftest_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

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

try {
    Add-Check 'winagent exists' (Test-Path -LiteralPath $WinAgent) $WinAgent
    $capture = Invoke-Agent @('capture-fullscreen-frame', '--originating-command', 'async_evidence_flush_selftest')
    Add-Check 'capture ok' ($capture.ok -eq $true) "ok=$($capture.ok)"
    Add-Check 'async evidence declared' ($capture.data.async_evidence_write -eq $true) "async=$($capture.data.async_evidence_write)"
    Add-Check 'initial evidence status valid' ($capture.data.evidence_write_status -in @('pending', 'written')) "status=$($capture.data.evidence_write_status)"

    $ocr = Invoke-Agent @('ocr-fullscreen-frame', '--frame-id', $capture.data.frame_id)
    Add-Check 'ocr runs before evidence flush' ($ocr.ok -eq $true) "ok=$($ocr.ok)"
    Add-Check 'ocr did not wait for png read' ($ocr.data.png_read_for_ocr -eq $false) "png_read_for_ocr=$($ocr.data.png_read_for_ocr)"

    $flush = Invoke-Agent @('evidence-flush', '--frame-id', $capture.data.frame_id)
    Add-Check 'flush ok' ($flush.ok -eq $true) "ok=$($flush.ok)"
    Add-Check 'flush reports frame id' (($flush.data.frame_ids -join ',') -match [regex]::Escape($capture.data.frame_id)) "frame_ids=$($flush.data.frame_ids -join ',')"
    Add-Check 'evidence png exists' (Test-Path -LiteralPath $capture.data.evidence_png_path) $capture.data.evidence_png_path
    Add-Check 'flush barrier exercised' ($flush.data.flush_barrier -eq $true) "flush_barrier=$($flush.data.flush_barrier)"

    $failedFlush = Invoke-Agent @('evidence-flush', '--frame-id', $capture.data.frame_id, '--simulate-failure', 'true') -AllowedExitCodes @(1)
    Add-Check 'simulated writer failure reports EVIDENCE_FLUSH_FAILED' ($failedFlush.error.code -eq 'EVIDENCE_FLUSH_FAILED') "error=$($failedFlush.error.code)"
    Add-Check 'simulated failure not pass' ($failedFlush.ok -eq $false) "ok=$($failedFlush.ok)"

    $report = @(
        '# Async Evidence Flush Selftest Report',
        '',
        '- status: PASS',
        "- frame_id: $($capture.data.frame_id)",
        "- screenshot_id: $($capture.data.screenshot_id)",
        "- initial_evidence_write_status: $($capture.data.evidence_write_status)",
        "- flushed_count: $($flush.data.flushed_count)",
        "- failed_count: $($flush.data.failed_count)",
        "- evidence_png_path: $($capture.data.evidence_png_path)",
        '- simulated_failure_error_code: EVIDENCE_FLUSH_FAILED',
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Host "PASS: async_evidence_flush_selftest ($ReportPath)"
    exit 0
} catch {
    $report = @(
        '# Async Evidence Flush Selftest Report',
        '',
        '- status: BLOCKED',
        "- error: $($_.Exception.Message)",
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Error "BLOCKED: async_evidence_flush_selftest failed: $($_.Exception.Message). Report: $ReportPath"
    exit 1
}
