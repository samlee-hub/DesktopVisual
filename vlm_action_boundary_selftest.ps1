param(
    [switch]$Help,
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\vlm_action_boundary_selftest.ps1 [-Root <path>]'
    Write-Host 'Verifies DesktopVisual v1.0.3.1 VLM locate-only/action boundary hardening.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$EvidenceRoot = Join-Path $Root 'artifacts\dev1.0.3.1_legacy_mock_vlm_quarantine'
$CaseRoot = Join-Path $EvidenceRoot 'vlm_action_boundary_cases'
$ReportPath = Join-Path $EvidenceRoot 'vlm_action_boundary_selftest_report.md'
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
        provider_command = 'action-boundary-seeded-cache'
        codex_cli_version = 'action-boundary-simulated'
        capability_status = 'VLM_AVAILABLE'
        checked_at = [DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')
        image_input_supported = $true
        probe_image_path = $ImagePath
        raw_probe_output_path = (Join-Path $CaseRoot "${Session}_raw_probe.txt")
        reason = 'action boundary seeded available cache'
        ttl_or_expiration = "ttl_seconds=86400;expires_at_unix=$expires"
        expires_at_unix = $expires
        desktopvisual_version = '1.0.3.1'
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Assert-Text {
    param([string]$Rel, [string]$Pattern, [string]$Name)
    $path = Join-Path $Root $Rel
    Add-Check "file exists ${Rel}" (Test-Path -LiteralPath $path) $path
    $text = Get-Content -LiteralPath $path -Raw
    Add-Check $Name ($text -match $Pattern) $Rel
}

try {
    Add-Check 'winagent exists' (Test-Path -LiteralPath $WinAgent) $WinAgent

    $imagePath = Join-Path $CaseRoot 'action_boundary_image.png'
    New-TestImage -Path $imagePath
    $session = 'action-boundary-' + ([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))
    $cachePath = Write-AvailableCache -Session $session -ImagePath $imagePath

    $locate = Invoke-WinAgentJson @(
        'vlm-assist-locate',
        '--provider', 'codex-cli',
        '--session-id', $session,
        '--image', $imagePath,
        '--target', 'RUN_ALPHA_739',
        '--target-window-title', 'action-boundary-window',
        '--min-confidence', '0.65',
        '--simulation', 'valid',
        '--cache', 'true'
    )
    Add-Check 'vlm-assist-locate accepted simulated real-provider candidate' (($locate.exit -eq 0) -and ([bool]$locate.json.ok) -and ([bool]$locate.json.candidate_accepted)) "exit=$($locate.exit) error=$(Get-ErrorCode $locate.json) text=$($locate.text)"
    Add-Check 'accepted locate runtime_action_executed false' (-not [bool]$locate.json.runtime_action_executed) "runtime_action_executed=$($locate.json.runtime_action_executed)"
    Add-Check 'accepted locate vlm_action_executed false' (-not [bool]$locate.json.vlm_action_executed) "vlm_action_executed=$($locate.json.vlm_action_executed)"
    Add-Check 'accepted locate candidate_is_locate_only true' ([bool]$locate.json.candidate_is_locate_only) "candidate_is_locate_only=$($locate.json.candidate_is_locate_only)"
    Add-Check 'accepted locate requires runtime action' ([bool]$locate.json.requires_runtime_action) "requires_runtime_action=$($locate.json.requires_runtime_action)"
    Add-Check 'accepted locate requires coordinate mapping before action' ([bool]$locate.json.requires_coordinate_mapping_before_action) "requires_coordinate_mapping_before_action=$($locate.json.requires_coordinate_mapping_before_action)"
    Add-Check 'accepted locate requires target window lock before action' ([bool]$locate.json.requires_target_window_lock_before_action) "requires_target_window_lock_before_action=$($locate.json.requires_target_window_lock_before_action)"
    Add-Check 'accepted locate requires post-action verification' ([bool]$locate.json.requires_post_action_verification) "requires_post_action_verification=$($locate.json.requires_post_action_verification)"
    Add-Check 'candidate accepted is not click or input success' (($locate.text -notmatch '"click_success"\s*:\s*true') -and ($locate.text -notmatch '"input_success"\s*:\s*true') -and ($locate.text -notmatch '"action_executed"\s*:\s*true')) $locate.text

    $stateFile = 'D:\testrepo\testwindow\runtime\state.txt'
    $beforeState = if (Test-Path -LiteralPath $stateFile) { Get-Content -LiteralPath $stateFile -Raw } else { '<missing>' }
    $legacyClick = Invoke-WinAgentJson @(
        'vlm-assisted-locate-and-click-local-safe',
        '--target', 'Click Me',
        '--provider', 'mock',
        '--scenario', 'testwindow_click_me',
        '--title', 'Agent Test Window',
        '--expected-marker', 'clicks=999',
        '--result', (Join-Path $CaseRoot 'legacy_click_disabled.json')
    )
    $afterState = if (Test-Path -LiteralPath $stateFile) { Get-Content -LiteralPath $stateFile -Raw } else { '<missing>' }
    Add-Check 'old locate-and-click mock default disabled' (((Get-ErrorCode $legacyClick.json) -in @('LEGACY_MOCK_VLM_DEPRECATED', 'LEGACY_MOCK_VLM_DISABLED')) -and ($legacyClick.exit -ne 0)) "error=$(Get-ErrorCode $legacyClick.json)"
    Add-Check 'old locate-and-click did not execute action' ($afterState -eq $beforeState) 'state file unchanged'

    Assert-Text 'COMMAND_PROTOCOL.md' 'vlm-assist-locate.*locate[s]? only|locate-only' 'COMMAND_PROTOCOL says VLM locate does not execute action'
    Assert-Text 'COMMAND_PROTOCOL.md' 'candidate accepted.*not.*action executed|accepted.*does not.*executed' 'COMMAND_PROTOCOL says candidate accepted is not action executed'
    Assert-Text 'skill_template\win-desktop-agent\SKILL.md' 'must not move the mouse, click, type, execute commands|must not click, type, move the mouse' 'source Skill says VLM does not directly act'
    Assert-Text 'adapters\codex\win-desktop-agent\SKILL.md' 'must not click, type, move the mouse|must not.*execute commands' 'adapter Skill says VLM does not directly act'
    Assert-Text 'docs\ARCHITECTURE.md' 'coordinate mapping.*target window lock.*post-action|target window lock.*post-action' 'architecture documents v1.0.4 action prerequisites'
    Assert-Text 'docs\KNOWN_LIMITATIONS.md' 'locate/assist.*not directly action|does not directly.*action|cannot click' 'known limitations says VLM candidate is locate/assist before v1.0.4'
    Assert-Text 'adapters\shared\TASK_FLOW.md' 'Once backend fallback starts.*do not call VLM|run after backend fallback starts' 'shared rules keep no VLM after backend fallback'

    $report = @(
        '# VLM Action Boundary Selftest Report',
        '',
        '- status: PASS',
        "- root: $Root",
        "- evidence_root: $EvidenceRoot",
        "- seeded_cache: $cachePath",
        "- locate_raw_response: $($locate.json.raw_response_path)",
        "- locate_parsed_json: $($locate.json.parsed_json_path)",
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Host "PASS: vlm_action_boundary_selftest ($ReportPath)"
    exit 0
} catch {
    $report = @(
        '# VLM Action Boundary Selftest Report',
        '',
        '- status: BLOCKED',
        "- root: $Root",
        "- error: $($_.Exception.Message)",
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Error "BLOCKED: vlm_action_boundary_selftest failed: $($_.Exception.Message). Report: $ReportPath"
    exit 1
}
