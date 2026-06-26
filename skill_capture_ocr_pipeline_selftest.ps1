param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$OutDir = Join-Path $Root 'artifacts\dev1.0.5_capture_ocr_performance_pipeline'
$ReportPath = Join-Path $OutDir 'skill_capture_ocr_pipeline_selftest_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$checks = New-Object System.Collections.Generic.List[string]

function Add-Check {
    param([string]$Name, [bool]$Passed, [string]$Detail)
    $status = if ($Passed) { 'PASS' } else { 'FAIL' }
    $script:checks.Add("- ${status}: ${Name} - ${Detail}") | Out-Null
    if (-not $Passed) { throw "${Name}: ${Detail}" }
}

function Read-Text {
    param([string]$RelativePath)
    $path = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing file: $RelativePath" }
    return Get-Content -LiteralPath $path -Raw
}

try {
    $skill = Read-Text 'skill_template\win-desktop-agent\SKILL.md'
    $adapter = Read-Text 'adapters\codex\win-desktop-agent\SKILL.md'
    $taskFlow = Read-Text 'adapters\shared\TASK_FLOW.md'
    $reportReading = Read-Text 'adapters\shared\REPORT_READING.md'
    $visibleContract = Read-Text 'skill_template\win-desktop-agent\references\VISIBLE_FIRST_CONTRACT.md'
    $combined = $skill + "`n" + $adapter + "`n" + $taskFlow + "`n" + $reportReading + "`n" + $visibleContract

    Add-Check 'full screen source of truth' ($combined -match 'full-screen frame source-of-truth|full-screen capture source-of-truth') 'source-of-truth language present'
    Add-Check 'OCR memory frame first' ($combined -match 'OCR memory-frame-first|memory frame first|memory-frame-first') 'memory-frame-first language present'
    Add-Check 'PNG evidence retained' ($combined -match 'PNG evidence.*retain|PNG evidence.*preserve|evidence PNG.*retain') 'PNG retention language present'
    Add-Check 'async evidence save' ($combined -match 'async.*evidence|asynchronous.*evidence') 'async evidence language present'
    Add-Check 'flush before failure blocked' ($combined -match 'flush.*(failure|BLOCKED)|failure.*flush|BLOCKED.*flush') 'flush barrier language present'
    Add-Check 'foreground crop from full-screen frame' ($combined -match 'foreground.*crop.*full-screen frame|window.*crop.*full-screen frame') 'crop-from-frame language present'
    Add-Check 'fallback same frame' ($combined -match 'fallback.*same frame|same frame.*fallback') 'same-frame fallback language present'
    Add-Check 'OCR result frame binding' ($combined -match 'frame_id.*screenshot_id|screenshot_id.*frame_id') 'frame/screenshot binding present'
    Add-Check 'VLM provider dependent transport' ($combined -match 'provider-dependent.*transport|provider dependent.*transport') 'provider transport language present'
    Add-Check 'Codex CLI needs file path' ($combined -match 'Codex CLI.*file path|Codex CLI.*--image') 'Codex CLI file path language present'
    Add-Check 'VLM input generated from frame' ($combined -match 'VLM input.*from.*frame|input image.*from.*frame') 'VLM frame-generated input present'
    Add-Check 'old mock VLM forbidden' ($combined -match 'legacy mock VLM.*not.*normal|old mock VLM.*not|mock VLM.*not.*normal') 'mock VLM forbidden language present'

    $report = @(
        '# Skill Capture OCR Pipeline Selftest Report',
        '',
        '- status: PASS',
        '- full_screen_capture_source_of_truth: true',
        '- ocr_memory_frame_first: true',
        '- png_evidence_retained: true',
        '- async_evidence_flush: true',
        '- foreground_crop_from_frame: true',
        '- same_frame_fallback: true',
        '- vlm_provider_dependent_transport: true',
        '- codex_cli_file_path_transport: true',
        '- legacy_mock_vlm_not_normal_path: true',
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Host "PASS: skill_capture_ocr_pipeline_selftest ($ReportPath)"
    exit 0
} catch {
    $report = @(
        '# Skill Capture OCR Pipeline Selftest Report',
        '',
        '- status: BLOCKED',
        "- error: $($_.Exception.Message)",
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Error "BLOCKED: skill_capture_ocr_pipeline_selftest failed: $($_.Exception.Message). Report: $ReportPath"
    exit 1
}
