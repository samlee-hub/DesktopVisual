param(
    [switch]$Help,
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\vlm_candidate_validation_selftest.ps1 [-Root <path>]'
    Write-Host 'Verifies DesktopVisual v1.0.3 Runtime VLM candidate validation.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$EvidenceRoot = Join-Path $Root 'artifacts\dev1.0.3_automatic_real_vlm_runtime_bridge'
$CaseRoot = Join-Path $EvidenceRoot 'candidate_validation_cases'
$ReportPath = Join-Path $EvidenceRoot 'vlm_candidate_validation_selftest_report.md'
$ImagePath = Join-Path $CaseRoot 'candidate_validation_image.png'
$RawPath = Join-Path $CaseRoot 'candidate_raw_response.json'
$ParsedPath = Join-Path $CaseRoot 'candidate_parsed_response.json'
New-Item -ItemType Directory -Force -Path $CaseRoot | Out-Null

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
    $bitmap = New-Object System.Drawing.Bitmap 400, 200
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([System.Drawing.Color]::White)
        $font = New-Object System.Drawing.Font 'Arial', 18
        try {
            $rect = New-Object System.Drawing.Rectangle 120, 70, 150, 50
            $graphics.FillRectangle([System.Drawing.Brushes]::LightGray, $rect)
            $graphics.DrawRectangle([System.Drawing.Pens]::Black, $rect)
            $graphics.DrawString('RUN_ALPHA_739', $font, [System.Drawing.Brushes]::Black, 126, 82)
        } finally {
            $font.Dispose()
        }
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function New-BaseCandidate {
    [ordered]@{
        schema_version = '1.0.3.vlm_candidate'
        screenshot_id = 'shot-candidate-001'
        frame_id = 'frame-candidate-001'
        image_path = $ImagePath
        provider = 'codex-cli'
        session_id = 'candidate-validation-session'
        prompt_hash = 'prompt-hash-001'
        raw_response_path = $RawPath
        parsed_json_path = $ParsedPath
        requested_target = 'RUN_ALPHA_739'
        ok = $true
        target_found = $true
        target_label = 'RUN_ALPHA_739'
        target_type = 'button'
        confidence = 0.91
        bbox = [ordered]@{ x = 120; y = 70; w = 150; h = 50 }
        point = [ordered]@{ x = 195; y = 95 }
        coordinate_space = 'image_pixels'
        image_width = 400
        image_height = 200
        reason = 'RUN_ALPHA_739 is visible on the button.'
        visible_text = @('RUN_ALPHA_739')
        uncertainty = ''
        safety_flags = @()
        requires_human_review = $false
    }
}

function Write-CandidateCase {
    param(
        [string]$Name,
        [scriptblock]$Mutate
    )
    $candidate = New-BaseCandidate
    if ($Mutate) {
        & $Mutate $candidate
    }
    $path = Join-Path $CaseRoot "${Name}.json"
    $candidate | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Invoke-ValidateCase {
    param([string]$Path)
    Invoke-WinAgentJson @(
        'vlm-candidate-validate',
        '--candidate-json', $Path,
        '--image', $ImagePath,
        '--target-window-title', 'candidate-validation-fixture',
        '--target', 'RUN_ALPHA_739',
        '--min-confidence', '0.65'
    )
}

try {
    Add-Check 'winagent exists' (Test-Path -LiteralPath $WinAgent) $WinAgent
    New-TestImage -Path $ImagePath
    Set-Content -LiteralPath $RawPath -Value '{"raw":"provider response"}' -Encoding UTF8
    Set-Content -LiteralPath $ParsedPath -Value '{"parsed":"provider json"}' -Encoding UTF8

    $validPath = Write-CandidateCase 'valid_candidate' $null
    $valid = Invoke-ValidateCase $validPath
    Add-Check 'valid candidate accepted' ([bool]$valid.candidate_accepted) "rejected=$($valid.candidate_rejected_reason)"
    Add-Check 'validator does not execute action' (-not [bool]$valid.runtime_action_executed) "runtime_action_executed=$($valid.runtime_action_executed)"

    $bboxPath = Write-CandidateCase 'bbox_out_of_bounds' { param($c) $c.bbox.x = 380; $c.bbox.w = 50 }
    $bbox = Invoke-ValidateCase $bboxPath
    Add-Check 'bbox out of bounds rejected' ($bbox.candidate_rejected_reason -eq 'bbox_out_of_bounds') "rejected=$($bbox.candidate_rejected_reason)"

    $pointPath = Write-CandidateCase 'point_out_of_bounds' { param($c) $c.point.x = 999 }
    $point = Invoke-ValidateCase $pointPath
    Add-Check 'point out of bounds rejected' ($point.candidate_rejected_reason -eq 'point_out_of_bounds') "rejected=$($point.candidate_rejected_reason)"

    $confidencePath = Write-CandidateCase 'low_confidence' { param($c) $c.confidence = 0.2 }
    $confidence = Invoke-ValidateCase $confidencePath
    Add-Check 'low confidence rejected' ($confidence.candidate_rejected_reason -eq 'confidence_below_minimum') "rejected=$($confidence.candidate_rejected_reason)"

    $spacePath = Write-CandidateCase 'wrong_coordinate_space' { param($c) $c.coordinate_space = 'screen_pixels' }
    $space = Invoke-ValidateCase $spacePath
    Add-Check 'wrong coordinate space rejected' ($space.candidate_rejected_reason -eq 'coordinate_space_not_image_pixels') "rejected=$($space.candidate_rejected_reason)"

    $missingFramePath = Write-CandidateCase 'missing_frame' { param($c) $c.Remove('screenshot_id'); $c.Remove('frame_id') }
    $missingFrame = Invoke-ValidateCase $missingFramePath
    Add-Check 'missing screenshot/frame rejected' ($missingFrame.candidate_rejected_reason -eq 'screenshot_id_or_frame_id_missing') "rejected=$($missingFrame.candidate_rejected_reason)"

    $missingImagePath = Write-CandidateCase 'missing_image_path' { param($c) $c.image_path = (Join-Path $CaseRoot 'does_not_exist.png') }
    $missingImage = Invoke-ValidateCase $missingImagePath
    Add-Check 'missing image rejected' ($missingImage.candidate_rejected_reason -eq 'image_path_not_found') "rejected=$($missingImage.candidate_rejected_reason)"

    $mismatchPath = Write-CandidateCase 'target_mismatch' { param($c) $c.target_label = 'OTHER_BUTTON'; $c.visible_text = @('OTHER_BUTTON'); $c.reason = 'OTHER_BUTTON is visible.' }
    $mismatch = Invoke-ValidateCase $mismatchPath
    Add-Check 'target semantic mismatch rejected' ($mismatch.candidate_rejected_reason -eq 'target_semantic_mismatch') "rejected=$($mismatch.candidate_rejected_reason)"

    foreach ($flag in @('active_protection', 'captcha', 'anti_cheat', 'protected_desktop')) {
        $flagPath = Write-CandidateCase "safety_${flag}" { param($c) $c.safety_flags = @($flag) }
        $flagResult = Invoke-ValidateCase $flagPath
        Add-Check "safety flag ${flag} rejected" ($flagResult.candidate_rejected_reason -like "safety_flag_${flag}*") "rejected=$($flagResult.candidate_rejected_reason)"
    }

    $naturalPath = Join-Path $CaseRoot 'natural_language_response.txt'
    Set-Content -LiteralPath $naturalPath -Value 'The button is near the middle of the image.' -Encoding UTF8
    $natural = Invoke-ValidateCase $naturalPath
    Add-Check 'raw natural language response rejected' ($natural.candidate_rejected_reason -eq 'invalid_json') "rejected=$($natural.candidate_rejected_reason)"

    $report = @(
        '# VLM Candidate Validation Selftest Report',
        '',
        '- status: PASS',
        "- root: $Root",
        "- valid_candidate: $validPath",
        "- image_path: $ImagePath",
        "- raw_response_path: $RawPath",
        "- parsed_json_path: $ParsedPath",
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Host "PASS: vlm_candidate_validation_selftest ($ReportPath)"
    exit 0
} catch {
    $report = @(
        '# VLM Candidate Validation Selftest Report',
        '',
        '- status: BLOCKED',
        "- root: $Root",
        "- error: $($_.Exception.Message)",
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Error "BLOCKED: vlm_candidate_validation_selftest failed: $($_.Exception.Message). Report: $ReportPath"
    exit 1
}
