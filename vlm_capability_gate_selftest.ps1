param(
    [switch]$Help,
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\vlm_capability_gate_selftest.ps1 [-Root <path>]'
    Write-Host 'Verifies DesktopVisual v1.0.3 VLM capability/session gate and cache behavior.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ProbeImage = Join-Path $Root 'artifacts\vlm_capability_probe\vlm_probe_image.png'
$EvidenceRoot = Join-Path $Root 'artifacts\dev1.0.3_automatic_real_vlm_runtime_bridge'
$ReportPath = Join-Path $EvidenceRoot 'vlm_capability_gate_selftest_report.md'

New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null

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

try {
    Add-Check 'winagent exists' (Test-Path -LiteralPath $WinAgent) $WinAgent
    if (-not (Test-Path -LiteralPath $ProbeImage)) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ProbeImage) | Out-Null
        $probePngBase64 = 'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAF0lEQVR4nGNk+M/AwMDAxMAABYwMjAAAJHsCAkbG0o8AAAAASUVORK5CYII='
        [System.IO.File]::WriteAllBytes($ProbeImage, [Convert]::FromBase64String($probePngBase64))
    }
    Add-Check 'probe image exists' (Test-Path -LiteralPath $ProbeImage) $ProbeImage

    $session = 'vlm-gate-selftest-' + ([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))
    $first = Invoke-WinAgentJson @(
        'vlm-capability-probe',
        '--provider', 'codex-cli',
        '--session-id', $session,
        '--probe-image', $ProbeImage,
        '--timeout-ms', '60000',
        '--cache', 'true'
    )
    Add-Check 'first probe reports VLM_AVAILABLE' ($first.capability_status -eq 'VLM_AVAILABLE') "status=$($first.capability_status)"
    Add-Check 'first probe is not cache hit' (-not [bool]$first.cache_hit) "cache_hit=$($first.cache_hit)"
    Add-Check 'first probe reports image input support' ([bool]$first.image_input_supported) "image_input_supported=$($first.image_input_supported)"
    Add-Check 'cache file exists' (Test-Path -LiteralPath $first.cache_path) $first.cache_path
    Add-Check 'raw probe output exists' (Test-Path -LiteralPath $first.raw_probe_output_path) $first.raw_probe_output_path
    Add-Check 'provider field present' ($first.provider -eq 'codex-cli') "provider=$($first.provider)"
    Add-Check 'session id field present' ($first.session_id -eq $session) "session_id=$($first.session_id)"
    Add-Check 'raw path field present' (-not [string]::IsNullOrWhiteSpace($first.raw_probe_output_path)) $first.raw_probe_output_path

    $second = Invoke-WinAgentJson @(
        'vlm-capability-probe',
        '--provider', 'codex-cli',
        '--session-id', $session,
        '--probe-image', $ProbeImage,
        '--timeout-ms', '60000',
        '--cache', 'true'
    )
    Add-Check 'second probe hits cache' ([bool]$second.cache_hit) "cache_hit=$($second.cache_hit)"
    Add-Check 'second probe reuses same raw path' ($second.raw_probe_output_path -eq $first.raw_probe_output_path) $second.raw_probe_output_path
    Add-Check 'second probe keeps VLM_AVAILABLE' ($second.capability_status -eq 'VLM_AVAILABLE') "status=$($second.capability_status)"

    $unavailableSession = $session + '-unavailable'
    $unavailable = Invoke-WinAgentJson @(
        'vlm-capability-probe',
        '--provider', 'codex-cli',
        '--session-id', $unavailableSession,
        '--probe-image', $ProbeImage,
        '--timeout-ms', '60000',
        '--cache', 'true',
        '--simulation', 'unavailable'
    )
    Add-Check 'simulated unavailable is not fake available' ($unavailable.capability_status -in @('VLM_UNAVAILABLE', 'VLM_UNKNOWN')) "status=$($unavailable.capability_status)"
    Add-Check 'unavailable cache file exists' (Test-Path -LiteralPath $unavailable.cache_path) $unavailable.cache_path
    Add-Check 'unavailable output has no candidate count' ($null -eq $unavailable.PSObject.Properties['candidate_count']) 'candidate_count absent'
    Add-Check 'unavailable output has no target_found' ($null -eq $unavailable.PSObject.Properties['target_found']) 'target_found absent'

    $disabledSession = $session + '-disabled-provider'
    $disabled = Invoke-WinAgentJson @(
        'vlm-capability-probe',
        '--provider', 'disabled-provider',
        '--session-id', $disabledSession,
        '--probe-image', $ProbeImage,
        '--timeout-ms', '60000',
        '--cache', 'true'
    )
    Add-Check 'unsupported provider is unavailable or unknown' ($disabled.capability_status -in @('VLM_UNAVAILABLE', 'VLM_UNKNOWN')) "status=$($disabled.capability_status)"
    Add-Check 'unsupported provider does not fake image support' (-not [bool]$disabled.image_input_supported) "image_input_supported=$($disabled.image_input_supported)"

    $requiredFields = @('provider', 'session_id', 'capability_status', 'cache_hit', 'image_input_supported', 'raw_probe_output_path')
    foreach ($field in $requiredFields) {
        Add-Check "required output field ${field}" ($null -ne $first.PSObject.Properties[$field]) 'present'
    }

    $report = @(
        '# VLM Capability Gate Selftest Report',
        '',
        '- status: PASS',
        "- root: $Root",
        "- session_id: $session",
        "- first_cache_path: $($first.cache_path)",
        "- first_raw_probe_output_path: $($first.raw_probe_output_path)",
        "- unavailable_cache_path: $($unavailable.cache_path)",
        "- unsupported_provider_status: $($disabled.capability_status)",
        "- runtime_only_degradation_when_unavailable: true",
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Host "PASS: vlm_capability_gate_selftest ($ReportPath)"
    exit 0
} catch {
    $report = @(
        '# VLM Capability Gate Selftest Report',
        '',
        '- status: BLOCKED',
        "- root: $Root",
        "- error: $($_.Exception.Message)",
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Error "BLOCKED: vlm_capability_gate_selftest failed: $($_.Exception.Message). Report: $ReportPath"
    exit 1
}
