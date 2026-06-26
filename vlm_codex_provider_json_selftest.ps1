param(
    [switch]$Help,
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\vlm_codex_provider_json_selftest.ps1 [-Root <path>]'
    Write-Host 'Verifies DesktopVisual v1.0.3 Codex CLI VLM provider JSON locate behavior.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$EvidenceRoot = Join-Path $Root 'artifacts\dev1.0.3_automatic_real_vlm_runtime_bridge'
$ReportPath = Join-Path $EvidenceRoot 'vlm_codex_provider_json_selftest_report.md'
$ImageDir = Join-Path $EvidenceRoot 'generated_test_images'
$ImagePath = Join-Path $ImageDir 'vlm_json_provider_test.png'
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
New-Item -ItemType Directory -Force -Path $ImageDir | Out-Null

$checks = New-Object System.Collections.Generic.List[string]

function Add-Check {
    param([string]$Name, [bool]$Passed, [string]$Detail)
    $status = if ($Passed) { 'PASS' } else { 'FAIL' }
    $script:checks.Add("- ${status}: ${Name} - ${Detail}") | Out-Null
    if (-not $Passed) {
        throw "${Name}: ${Detail}"
    }
}

function Invoke-WinAgentJson {
    param([string[]]$Arguments)
    $output = & $WinAgent @Arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "winagent exited with ${exitCode}: $($output -join [Environment]::NewLine)"
    }
    $text = ($output | Select-Object -Last 1)
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw 'winagent produced no JSON output'
    }
    return $text | ConvertFrom-Json
}

function New-TestImage {
    param([string]$Path)
    Add-Type -AssemblyName System.Drawing
    $bitmap = New-Object System.Drawing.Bitmap 900, 500
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([System.Drawing.Color]::White)
        $titleFont = New-Object System.Drawing.Font 'Arial', 28
        $buttonFont = New-Object System.Drawing.Font 'Arial', 20
        try {
            $graphics.DrawString('DesktopVisual VLM JSON Test', $titleFont, [System.Drawing.Brushes]::Black, 80, 60)
            $button = New-Object System.Drawing.Rectangle 280, 210, 300, 90
            $graphics.FillRectangle([System.Drawing.Brushes]::LightGray, $button)
            $graphics.DrawRectangle([System.Drawing.Pens]::Black, $button)
            $graphics.DrawString('RUN_ALPHA_739', $buttonFont, [System.Drawing.Brushes]::Black, 330, 240)
            $points = @(
                (New-Object System.Drawing.Point 720, 220),
                (New-Object System.Drawing.Point 650, 340),
                (New-Object System.Drawing.Point 790, 340)
            )
            $graphics.FillPolygon([System.Drawing.Brushes]::Green, $points)
        } finally {
            $titleFont.Dispose()
            $buttonFont.Dispose()
        }
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

try {
    Add-Check 'winagent exists' (Test-Path -LiteralPath $WinAgent) $WinAgent
    New-TestImage -Path $ImagePath
    Add-Check 'test image exists' (Test-Path -LiteralPath $ImagePath) $ImagePath

    $session = 'vlm-json-selftest-' + ([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))
    $success = Invoke-WinAgentJson @(
        'vlm-assist-locate',
        '--provider', 'codex-cli',
        '--session-id', $session,
        '--image', $ImagePath,
        '--target', 'RUN_ALPHA_739',
        '--target-window-title', 'vlm-json-selftest',
        '--timeout-ms', '180000',
        '--min-confidence', '0.65'
    )
    Add-Check 'success locate reports VLM_AVAILABLE' ($success.vlm_status -eq 'VLM_AVAILABLE') "vlm_status=$($success.vlm_status)"
    Add-Check 'raw response exists' (Test-Path -LiteralPath $success.raw_response_path) $success.raw_response_path
    Add-Check 'parsed response exists' (Test-Path -LiteralPath $success.parsed_json_path) $success.parsed_json_path
    Add-Check 'target found true' ([bool]$success.target_found) "target_found=$($success.target_found)"
    Add-Check 'candidate count at least one' ([int]$success.candidate_count -ge 1) "candidate_count=$($success.candidate_count)"
    Add-Check 'confidence meets threshold' ([double]$success.confidence -ge 0.65) "confidence=$($success.confidence)"
    Add-Check 'bbox within image bounds' (($success.bbox.x -ge 0) -and ($success.bbox.y -ge 0) -and (($success.bbox.x + $success.bbox.w) -le $success.image_width) -and (($success.bbox.y + $success.bbox.h) -le $success.image_height)) "bbox=$($success.bbox | ConvertTo-Json -Compress)"
    Add-Check 'runtime validation passed' ([bool]$success.runtime_validation_passed) "runtime_validation_passed=$($success.runtime_validation_passed)"
    Add-Check 'runtime action not executed' (-not [bool]$success.runtime_action_executed) "runtime_action_executed=$($success.runtime_action_executed)"

    $wrong = Invoke-WinAgentJson @(
        'vlm-assist-locate',
        '--provider', 'codex-cli',
        '--session-id', $session,
        '--image', $ImagePath,
        '--target', 'DOES_NOT_EXIST_928',
        '--target-window-title', 'vlm-json-selftest',
        '--timeout-ms', '180000',
        '--min-confidence', '0.65'
    )
    Add-Check 'wrong target is not accepted' (-not [bool]$wrong.candidate_accepted) "accepted=$($wrong.candidate_accepted)"
    Add-Check 'wrong target not faked' ((-not [bool]$wrong.target_found) -or ($wrong.candidate_rejected_reason -ne '')) "target_found=$($wrong.target_found) rejected=$($wrong.candidate_rejected_reason)"

    $invalid = Invoke-WinAgentJson @(
        'vlm-assist-locate',
        '--provider', 'codex-cli',
        '--session-id', $session,
        '--image', $ImagePath,
        '--target', 'RUN_ALPHA_739',
        '--target-window-title', 'vlm-json-selftest',
        '--timeout-ms', '60000',
        '--min-confidence', '0.65',
        '--simulation', 'invalid_json'
    )
    Add-Check 'invalid JSON rejected' (($invalid.vlm_status -eq 'VLM_INVALID_RESPONSE') -or (-not [bool]$invalid.candidate_accepted)) "vlm_status=$($invalid.vlm_status) rejected=$($invalid.candidate_rejected_reason)"

    $low = Invoke-WinAgentJson @(
        'vlm-assist-locate',
        '--provider', 'codex-cli',
        '--session-id', $session,
        '--image', $ImagePath,
        '--target', 'RUN_ALPHA_739',
        '--target-window-title', 'vlm-json-selftest',
        '--timeout-ms', '60000',
        '--min-confidence', '0.65',
        '--simulation', 'low_confidence'
    )
    Add-Check 'low confidence rejected' ((-not [bool]$low.candidate_accepted) -and ($low.candidate_rejected_reason -eq 'confidence_below_minimum')) "rejected=$($low.candidate_rejected_reason)"

    $timeout = Invoke-WinAgentJson @(
        'vlm-assist-locate',
        '--provider', 'codex-cli',
        '--session-id', $session,
        '--image', $ImagePath,
        '--target', 'RUN_ALPHA_739',
        '--target-window-title', 'vlm-json-selftest',
        '--timeout-ms', '60000',
        '--min-confidence', '0.65',
        '--simulation', 'timeout'
    )
    Add-Check 'timeout reported without hang' (($timeout.vlm_status -eq 'VLM_TIMEOUT') -and (-not [bool]$timeout.candidate_accepted)) "vlm_status=$($timeout.vlm_status)"

    $unavailable = Invoke-WinAgentJson @(
        'vlm-assist-locate',
        '--provider', 'codex-cli',
        '--session-id', ($session + '-unavailable'),
        '--image', $ImagePath,
        '--target', 'RUN_ALPHA_739',
        '--target-window-title', 'vlm-json-selftest',
        '--timeout-ms', '60000',
        '--min-confidence', '0.65',
        '--capability-simulation', 'unavailable'
    )
    Add-Check 'provider unavailable does not fake candidate' (($unavailable.capability_status -eq 'VLM_UNAVAILABLE') -and (-not [bool]$unavailable.candidate_accepted) -and ([int]$unavailable.candidate_count -eq 0)) "capability=$($unavailable.capability_status) candidates=$($unavailable.candidate_count)"

    $report = @(
        '# VLM Codex Provider JSON Selftest Report',
        '',
        '- status: PASS',
        "- root: $Root",
        "- session_id: $session",
        "- image_path: $ImagePath",
        "- success_raw_response_path: $($success.raw_response_path)",
        "- success_parsed_json_path: $($success.parsed_json_path)",
        "- invalid_json_status: $($invalid.vlm_status)",
        "- timeout_status: $($timeout.vlm_status)",
        "- unavailable_status: $($unavailable.capability_status)",
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Host "PASS: vlm_codex_provider_json_selftest ($ReportPath)"
    exit 0
} catch {
    $report = @(
        '# VLM Codex Provider JSON Selftest Report',
        '',
        '- status: BLOCKED',
        "- root: $Root",
        "- error: $($_.Exception.Message)",
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Error "BLOCKED: vlm_codex_provider_json_selftest failed: $($_.Exception.Message). Report: $ReportPath"
    exit 1
}
