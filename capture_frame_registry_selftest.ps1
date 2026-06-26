param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev1.0.5_capture_ocr_performance_pipeline'
$ReportPath = Join-Path $OutDir 'capture_frame_registry_selftest_report.md'
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

    $capture = Invoke-Agent @('capture-fullscreen-frame', '--originating-command', 'capture_frame_registry_selftest')
    Add-Check 'capture ok' ($capture.ok -eq $true) "ok=$($capture.ok)"
    Add-Check 'command name' ($capture.command -eq 'capture-fullscreen-frame') "command=$($capture.command)"
    Add-Check 'frame id present' (-not [string]::IsNullOrWhiteSpace($capture.data.frame_id)) "frame_id=$($capture.data.frame_id)"
    Add-Check 'screenshot id present' (-not [string]::IsNullOrWhiteSpace($capture.data.screenshot_id)) "screenshot_id=$($capture.data.screenshot_id)"
    Add-Check 'frame in memory' ($capture.data.frame_in_memory -eq $true) "frame_in_memory=$($capture.data.frame_in_memory)"
    Add-Check 'full screen capture' ($capture.data.full_screen_capture -eq $true) "full_screen_capture=$($capture.data.full_screen_capture)"
    Add-Check 'evidence path assigned' (-not [string]::IsNullOrWhiteSpace($capture.data.evidence_png_path)) "path=$($capture.data.evidence_png_path)"
    Add-Check 'async or written evidence' (($capture.data.async_evidence_write -eq $true) -or ($capture.data.evidence_write_status -eq 'written')) "status=$($capture.data.evidence_write_status)"
    Add-Check 'reasonable screen width' ([int]$capture.data.screen_width -gt 100) "width=$($capture.data.screen_width)"
    Add-Check 'reasonable screen height' ([int]$capture.data.screen_height -gt 100) "height=$($capture.data.screen_height)"
    Add-Check 'pixel format present' ($capture.data.pixel_format -match 'BGRA|BGR|RGBA') "pixel_format=$($capture.data.pixel_format)"
    Add-Check 'content hash present' (-not [string]::IsNullOrWhiteSpace($capture.data.content_hash)) "hash=$($capture.data.content_hash)"
    Add-Check 'metadata path present' (-not [string]::IsNullOrWhiteSpace($capture.data.metadata_path)) "metadata=$($capture.data.metadata_path)"
    Add-Check 'metadata exists' (Test-Path -LiteralPath $capture.data.metadata_path) $capture.data.metadata_path
    Add-Check 'backend capture not used' ($capture.data.backend_capture_used -eq $false) "backend_capture_used=$($capture.data.backend_capture_used)"
    Add-Check 'OCR png dependency removed flag' ($capture.data.ocr_png_dependency_removed -eq $true) "ocr_png_dependency_removed=$($capture.data.ocr_png_dependency_removed)"

    $flush = Invoke-Agent @('evidence-flush', '--frame-id', $capture.data.frame_id)
    Add-Check 'flush ok' ($flush.ok -eq $true) "ok=$($flush.ok)"
    Add-Check 'evidence png exists after flush' (Test-Path -LiteralPath $capture.data.evidence_png_path) $capture.data.evidence_png_path

    $report = @(
        '# Capture Frame Registry Selftest Report',
        '',
        '- status: PASS',
        "- frame_id: $($capture.data.frame_id)",
        "- screenshot_id: $($capture.data.screenshot_id)",
        "- evidence_png_path: $($capture.data.evidence_png_path)",
        "- metadata_path: $($capture.data.metadata_path)",
        "- evidence_write_status: $($flush.data.evidence_write_status)",
        "- ocr_png_dependency_removed: true",
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Host "PASS: capture_frame_registry_selftest ($ReportPath)"
    exit 0
} catch {
    $report = @(
        '# Capture Frame Registry Selftest Report',
        '',
        '- status: BLOCKED',
        "- error: $($_.Exception.Message)",
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Error "BLOCKED: capture_frame_registry_selftest failed: $($_.Exception.Message). Report: $ReportPath"
    exit 1
}
