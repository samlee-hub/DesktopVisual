param(
    [switch]$Help,
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\vlm_command_schema_hardening_selftest.ps1 [-Root <path>]'
    Write-Host 'Verifies DesktopVisual v1.0.3.1 real VLM command envelope/schema/report hardening.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$EvidenceRoot = Join-Path $Root 'artifacts\dev1.0.3.1_legacy_mock_vlm_quarantine'
$CaseRoot = Join-Path $EvidenceRoot 'vlm_schema_cases'
$ReportPath = Join-Path $EvidenceRoot 'vlm_command_schema_hardening_selftest_report.md'
$CacheRoot = Join-Path $Root 'artifacts\vlm_session_cache'
New-Item -ItemType Directory -Force -Path $CaseRoot | Out-Null
New-Item -ItemType Directory -Force -Path $CacheRoot | Out-Null

$checks = New-Object System.Collections.Generic.List[string]

function Add-Check {
    param([string]$Name, [bool]$Passed, [string]$Detail)
    $status = if ($Passed) { 'PASS' } else { 'FAIL' }
    $script:checks.Add("- ${status}: ${Name} - ${Detail}") | Out-Null
    if (-not $Passed) {
        throw "${Name}: ${Detail}"
    }
}

function Get-ErrorCode {
    param($Json)
    if ($null -ne $Json.PSObject.Properties['error_code']) {
        return [string]$Json.error_code
    }
    if ($null -ne $Json.error -and $null -ne $Json.error.PSObject.Properties['code']) {
        return [string]$Json.error.code
    }
    return ''
}

function Assert-Envelope {
    param($Json, [string]$Command)
    Add-Check "${Command} has ok" ($null -ne $Json.PSObject.Properties['ok']) 'ok present'
    Add-Check "${Command} command field" ($Json.command -eq $Command) "command=$($Json.command)"
    Add-Check "${Command} timestamp field" (-not [string]::IsNullOrWhiteSpace([string]$Json.timestamp)) "timestamp=$($Json.timestamp)"
    Add-Check "${Command} duration_ms field" ($null -ne $Json.PSObject.Properties['duration_ms']) "duration_ms=$($Json.duration_ms)"
    Add-Check "${Command} data mirror field" ($null -ne $Json.PSObject.Properties['data']) 'data present'
    Add-Check "${Command} evidence field" ($null -ne $Json.PSObject.Properties['evidence']) 'evidence present'
}

function Invoke-WinAgentJson {
    param([string[]]$Arguments)
    $output = & $WinAgent @Arguments 2>&1
    $exit = $LASTEXITCODE
    $text = ($output | Select-Object -Last 1)
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "winagent produced no JSON output for $($Arguments -join ' ')"
    }
    try {
        $json = $text | ConvertFrom-Json
    } catch {
        throw "invalid JSON from winagent $($Arguments -join ' '): $text"
    }
    [pscustomobject]@{
        exit = $exit
        json = $json
        text = $text
        args = $Arguments
    }
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

function Write-AvailableCache {
    param([string]$Session, [string]$ImagePath)
    $path = Join-Path $CacheRoot "codex-cli_${Session}.json"
    $expires = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 86400
    [ordered]@{
        schema_version = '1.0.3.vlm_capability_session_cache'
        session_id = $Session
        provider = 'codex-cli'
        provider_command = 'schema-hardening-seeded-cache'
        codex_cli_version = 'schema-hardening-simulated'
        capability_status = 'VLM_AVAILABLE'
        checked_at = [DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')
        image_input_supported = $true
        probe_image_path = $ImagePath
        raw_probe_output_path = (Join-Path $CaseRoot "${Session}_raw_probe.txt")
        reason = 'schema hardening seeded available cache'
        ttl_or_expiration = "ttl_seconds=86400;expires_at_unix=$expires"
        expires_at_unix = $expires
        desktopvisual_version = '1.0.3.1'
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function New-Candidate {
    param([string]$Path, [string]$ImagePath, [string]$RawPath, [string]$ParsedPath)
    Set-Content -LiteralPath $RawPath -Value '{"raw":"provider response"}' -Encoding UTF8
    Set-Content -LiteralPath $ParsedPath -Value '{"parsed":"provider json"}' -Encoding UTF8
    [ordered]@{
        schema_version = '1.0.3.vlm_candidate'
        screenshot_id = 'shot-schema-001'
        frame_id = 'frame-schema-001'
        image_path = $ImagePath
        provider = 'codex-cli'
        session_id = 'schema-candidate-session'
        prompt_hash = 'prompt-schema-001'
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
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

try {
    Add-Check 'winagent exists' (Test-Path -LiteralPath $WinAgent) $WinAgent

    $imagePath = Join-Path $CaseRoot 'schema_image.png'
    New-TestImage -Path $imagePath
    Add-Check 'schema test image exists' (Test-Path -LiteralPath $imagePath) $imagePath

    $probe = Invoke-WinAgentJson @(
        'vlm-capability-probe',
        '--provider', 'codex-cli',
        '--session-id', 'schema-probe-unavailable',
        '--probe-image', $imagePath,
        '--cache', 'false',
        '--simulation', 'unavailable'
    )
    Assert-Envelope $probe.json 'vlm-capability-probe'
    Add-Check 'probe provider root/data mirror' (($probe.json.provider -eq 'codex-cli') -and ($probe.json.data.provider -eq 'codex-cli')) "provider=$($probe.json.provider)"
    Add-Check 'probe capability status root/data mirror' (($probe.json.capability_status -eq 'VLM_UNAVAILABLE') -and ($probe.json.data.capability_status -eq 'VLM_UNAVAILABLE')) "status=$($probe.json.capability_status)"

    $assistSession = 'schema-assist-' + ([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))
    $cachePath = Write-AvailableCache -Session $assistSession -ImagePath $imagePath
    $low = Invoke-WinAgentJson @(
        'vlm-assist-locate',
        '--provider', 'codex-cli',
        '--session-id', $assistSession,
        '--image', $imagePath,
        '--target', 'RUN_ALPHA_739',
        '--target-window-title', 'schema-window',
        '--min-confidence', '0.65',
        '--simulation', 'low_confidence',
        '--cache', 'true'
    )
    Assert-Envelope $low.json 'vlm-assist-locate'
    Add-Check 'assist root fields preserved' (($low.json.provider -eq 'codex-cli') -and ($low.json.vlm_status -eq 'VLM_AVAILABLE') -and ($null -ne $low.json.PSObject.Properties['candidate_accepted'])) "status=$($low.json.vlm_status)"
    Add-Check 'assist data mirror present' (($low.json.data.provider -eq 'codex-cli') -and ($low.json.data.vlm_status -eq $low.json.vlm_status) -and ($low.json.data.runtime_action_executed -eq $false)) ($low.json.data | ConvertTo-Json -Compress)
    Add-Check 'assist raw response path exists' (Test-Path -LiteralPath $low.json.raw_response_path) $low.json.raw_response_path
    Add-Check 'assist parsed JSON path exists' (Test-Path -LiteralPath $low.json.parsed_json_path) $low.json.parsed_json_path
    Add-Check 'assist rejected candidate has error/evidence' ((Get-ErrorCode $low.json) -ne '' -and $null -ne $low.json.evidence.candidate_rejected_reason) "error=$(Get-ErrorCode $low.json)"
    Add-Check 'assist runtime action false' (-not [bool]$low.json.runtime_action_executed) "runtime_action_executed=$($low.json.runtime_action_executed)"

    $invalid = Invoke-WinAgentJson @(
        'vlm-assist-locate',
        '--provider', 'codex-cli',
        '--session-id', $assistSession,
        '--image', $imagePath,
        '--target', 'RUN_ALPHA_739',
        '--simulation', 'invalid_json',
        '--cache', 'true'
    )
    Assert-Envelope $invalid.json 'vlm-assist-locate'
    Add-Check 'invalid JSON has clear error/evidence' (((Get-ErrorCode $invalid.json) -in @('VLM_INVALID_RESPONSE', 'invalid_json')) -and ($invalid.json.evidence.candidate_rejected_reason -eq 'invalid_json')) "error=$(Get-ErrorCode $invalid.json) rejected=$($invalid.json.evidence.candidate_rejected_reason)"

    $timeout = Invoke-WinAgentJson @(
        'vlm-assist-locate',
        '--provider', 'codex-cli',
        '--session-id', $assistSession,
        '--image', $imagePath,
        '--target', 'RUN_ALPHA_739',
        '--simulation', 'timeout',
        '--cache', 'true'
    )
    Assert-Envelope $timeout.json 'vlm-assist-locate'
    Add-Check 'timeout has clear error/evidence' (((Get-ErrorCode $timeout.json) -eq 'VLM_TIMEOUT') -and ($timeout.json.evidence.vlm_status -eq 'VLM_TIMEOUT')) "error=$(Get-ErrorCode $timeout.json)"

    $unavailable = Invoke-WinAgentJson @(
        'vlm-assist-locate',
        '--provider', 'codex-cli',
        '--session-id', ($assistSession + '-unavailable'),
        '--image', $imagePath,
        '--target', 'RUN_ALPHA_739',
        '--capability-simulation', 'unavailable',
        '--cache', 'false'
    )
    Assert-Envelope $unavailable.json 'vlm-assist-locate'
    Add-Check 'unavailable has clear error/evidence' (((Get-ErrorCode $unavailable.json) -eq 'capability_gate_not_available') -and ($unavailable.json.evidence.capability_status -eq 'VLM_UNAVAILABLE')) "error=$(Get-ErrorCode $unavailable.json) capability=$($unavailable.json.evidence.capability_status)"

    $candidatePath = Join-Path $CaseRoot 'valid_candidate.json'
    $rawPath = Join-Path $CaseRoot 'candidate_raw.json'
    $parsedPath = Join-Path $CaseRoot 'candidate_parsed.json'
    New-Candidate -Path $candidatePath -ImagePath $imagePath -RawPath $rawPath -ParsedPath $parsedPath
    $candidate = Invoke-WinAgentJson @(
        'vlm-candidate-validate',
        '--candidate-json', $candidatePath,
        '--image', $imagePath,
        '--target', 'RUN_ALPHA_739',
        '--target-window-title', 'schema-window',
        '--min-confidence', '0.65'
    )
    Assert-Envelope $candidate.json 'vlm-candidate-validate'
    Add-Check 'candidate validate result root/data mirror' (($candidate.json.validation_result -eq 'PASS') -and ($candidate.json.data.validation_result -eq 'PASS') -and ([bool]$candidate.json.runtime_validation_passed)) "validation=$($candidate.json.validation_result)"

    $naturalPath = Join-Path $CaseRoot 'natural_language.txt'
    Set-Content -LiteralPath $naturalPath -Value 'The target is probably near the middle.' -Encoding UTF8
    $natural = Invoke-WinAgentJson @(
        'vlm-candidate-validate',
        '--candidate-json', $naturalPath,
        '--image', $imagePath,
        '--target', 'RUN_ALPHA_739'
    )
    Assert-Envelope $natural.json 'vlm-candidate-validate'
    Add-Check 'natural language candidate rejected with error/evidence' (((Get-ErrorCode $natural.json) -eq 'invalid_json') -and ($natural.json.evidence.candidate_rejected_reason -eq 'invalid_json')) "error=$(Get-ErrorCode $natural.json)"

    $reportRules = Get-Content -LiteralPath (Join-Path $Root 'adapters\shared\REPORT_READING.md') -Raw
    Add-Check 'shared report rules do not recommend old mock commands' ($reportRules -notmatch 'vlm-observation-run-mock|vlm-assisted-locate') 'REPORT_READING.md'
    Add-Check 'shared report rules mention root and data/evidence mirror' (($reportRules -match 'root fields') -and ($reportRules -match 'data/evidence')) 'REPORT_READING.md'

    $requestPath = Join-Path $CaseRoot 'legacy_request.json'
    Set-Content -LiteralPath $requestPath -Value '{"request_id":"schema-legacy-request"}' -Encoding UTF8
    $legacy = Invoke-WinAgentJson @('vlm-observation-run-mock', '--request', $requestPath, '--scenario', 'valid', '--output', (Join-Path $CaseRoot 'legacy_result.json'))
    Add-Check 'legacy default failure has clear error_code' (((Get-ErrorCode $legacy.json) -in @('LEGACY_MOCK_VLM_DEPRECATED', 'LEGACY_MOCK_VLM_DISABLED')) -and ($legacy.exit -ne 0)) "error=$(Get-ErrorCode $legacy.json)"

    $report = @(
        '# VLM Command Schema Hardening Selftest Report',
        '',
        '- status: PASS',
        "- root: $Root",
        "- evidence_root: $EvidenceRoot",
        "- seeded_cache: $cachePath",
        "- low_confidence_raw_response: $($low.json.raw_response_path)",
        "- low_confidence_parsed_json: $($low.json.parsed_json_path)",
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Host "PASS: vlm_command_schema_hardening_selftest ($ReportPath)"
    exit 0
} catch {
    $report = @(
        '# VLM Command Schema Hardening Selftest Report',
        '',
        '- status: BLOCKED',
        "- root: $Root",
        "- error: $($_.Exception.Message)",
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Error "BLOCKED: vlm_command_schema_hardening_selftest failed: $($_.Exception.Message). Report: $ReportPath"
    exit 1
}
