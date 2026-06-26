param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev1.0.5_capture_ocr_performance_pipeline'
$ReportPath = Join-Path $OutDir 'vlm_frame_transport_selftest_report.md'
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
    $capture = Invoke-Agent @('capture-fullscreen-frame', '--originating-command', 'vlm_frame_transport_selftest')
    $transport = Invoke-Agent @('vlm-frame-transport-check', '--frame-id', $capture.data.frame_id, '--target', 'DesktopVisual')

    Add-Check 'transport ok' ($transport.ok -eq $true) "ok=$($transport.ok)"
    Add-Check 'frame id bound' ($transport.data.frame_id -eq $capture.data.frame_id) "frame_id=$($transport.data.frame_id)"
    Add-Check 'screenshot id bound' ($transport.data.screenshot_id -eq $capture.data.screenshot_id) "screenshot_id=$($transport.data.screenshot_id)"
    Add-Check 'provider codex cli' ($transport.data.provider -eq 'codex-cli') "provider=$($transport.data.provider)"
    Add-Check 'provider transport file path' ($transport.data.provider_transport -eq 'file_path') "transport=$($transport.data.provider_transport)"
    Add-Check 'provider requires file input' ($transport.data.provider_requires_file_input -eq $true) "requires=$($transport.data.provider_requires_file_input)"
    Add-Check 'memory bytes not supported by codex cli' ($transport.data.supports_memory_bytes -eq $false) "supports=$($transport.data.supports_memory_bytes)"
    Add-Check 'vlm input generated from frame' ($transport.data.vlm_input_generated_from_frame -eq $true) "generated=$($transport.data.vlm_input_generated_from_frame)"
    Add-Check 'no recapture for vlm' ($transport.data.screenshot_recaptured_for_vlm -eq $false) "recaptured=$($transport.data.screenshot_recaptured_for_vlm)"
    Add-Check 'ocr did not read vlm png' ($transport.data.ocr_read_vlm_png -eq $false) "ocr_read_vlm_png=$($transport.data.ocr_read_vlm_png)"
    Add-Check 'candidate locate only' ($transport.data.candidate_is_locate_only -eq $true) "locate_only=$($transport.data.candidate_is_locate_only)"
    Add-Check 'vlm input path exists' (Test-Path -LiteralPath $transport.data.vlm_input_image_path) $transport.data.vlm_input_image_path
    Add-Check 'old mock not used' ($transport.data.old_mock_vlm_used -eq $false) "old_mock=$($transport.data.old_mock_vlm_used)"

    $unavailable = Invoke-Agent @('vlm-frame-transport-check', '--frame-id', $capture.data.frame_id, '--provider', 'disabled-provider', '--target', 'DesktopVisual')
    Add-Check 'provider unavailable degrades runtime only' ($unavailable.data.runtime_only_degradation -eq $true) "runtime_only=$($unavailable.data.runtime_only_degradation)"
    Add-Check 'unavailable does not fake vlm' ($unavailable.data.vlm_candidate_fabricated -eq $false) "fabricated=$($unavailable.data.vlm_candidate_fabricated)"

    $report = @(
        '# VLM Frame Transport Selftest Report',
        '',
        '- status: PASS',
        "- frame_id: $($capture.data.frame_id)",
        "- screenshot_id: $($capture.data.screenshot_id)",
        "- provider: $($transport.data.provider)",
        "- provider_transport: $($transport.data.provider_transport)",
        "- provider_requires_file_input: $($transport.data.provider_requires_file_input)",
        "- supports_memory_bytes: $($transport.data.supports_memory_bytes)",
        "- vlm_input_image_path: $($transport.data.vlm_input_image_path)",
        '- screenshot_recaptured_for_vlm: false',
        '- ocr_read_vlm_png: false',
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Host "PASS: vlm_frame_transport_selftest ($ReportPath)"
    exit 0
} catch {
    $report = @(
        '# VLM Frame Transport Selftest Report',
        '',
        '- status: BLOCKED',
        "- error: $($_.Exception.Message)",
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Error "BLOCKED: vlm_frame_transport_selftest failed: $($_.Exception.Message). Report: $ReportPath"
    exit 1
}
