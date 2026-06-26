param(
    [switch]$Help,
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\legacy_mock_vlm_quarantine_selftest.ps1 [-Root <path>]'
    Write-Host 'Verifies DesktopVisual v1.0.3.1 legacy mock VLM command quarantine.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$EvidenceRoot = Join-Path $Root 'artifacts\dev1.0.3.1_legacy_mock_vlm_quarantine'
$CaseRoot = Join-Path $EvidenceRoot 'legacy_mock_cases'
$ReportPath = Join-Path $EvidenceRoot 'legacy_mock_vlm_quarantine_selftest_report.md'
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
    $bitmap = New-Object System.Drawing.Bitmap 120, 80
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([System.Drawing.Color]::White)
        $brush = [System.Drawing.Brushes]::Black
        $font = New-Object System.Drawing.Font 'Arial', 12
        try {
            $graphics.DrawString('VLM TEST', $font, $brush, 20, 25)
        } finally {
            $font.Dispose()
        }
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Assert-LegacyDisabled {
    param(
        [string]$Name,
        [string[]]$Arguments,
        [string]$ExpectedHint
    )
    $run = Invoke-WinAgentJson $Arguments
    $code = Get-ErrorCode $run.json
    $isLegacyCode = $code -in @('LEGACY_MOCK_VLM_DEPRECATED', 'LEGACY_MOCK_VLM_DISABLED', 'USE_REAL_VLM_RUNTIME_BRIDGE')
    $hintOk = $run.text -match [regex]::Escape($ExpectedHint)
    Add-Check $Name (($run.exit -ne 0) -and (-not [bool]$run.json.ok) -and $isLegacyCode -and $hintOk) "exit=$($run.exit) code=$code text=$($run.text)"
    return $run
}

function Assert-NoOldCommandRecommendation {
    param([string]$Rel)
    $path = Join-Path $Root $Rel
    Add-Check "contract file exists ${Rel}" (Test-Path -LiteralPath $path) $path
    $text = Get-Content -LiteralPath $path -Raw
    $oldCommands = @(
        'vlm-observation-run-mock',
        'vlm-assisted-locate',
        'vlm-assisted-locate-dry-run',
        'vlm-assisted-locate-and-click-local-safe'
    )
    $matches = @()
    foreach ($old in $oldCommands) {
        if ($text -match [regex]::Escape($old)) {
            $matches += $old
        }
    }
    Add-Check "no old mock VLM command recommendation in ${Rel}" ($matches.Count -eq 0) ($matches -join ',')
}

try {
    Add-Check 'winagent exists' (Test-Path -LiteralPath $WinAgent) $WinAgent

    $requestPath = Join-Path $CaseRoot 'legacy_request.json'
    $mockOutputPath = Join-Path $CaseRoot 'legacy_mock_result.json'
    $assistResult = Join-Path $CaseRoot 'legacy_assist_result.json'
    $dryRunResult = Join-Path $CaseRoot 'legacy_dry_run_result.json'
    $clickResult = Join-Path $CaseRoot 'legacy_click_result.json'
    $imagePath = Join-Path $CaseRoot 'new_path_probe.png'
    $candidatePath = Join-Path $CaseRoot 'invalid_candidate.json'
    $stateFile = 'D:\testrepo\testwindow\runtime\state.txt'

    '{"request_id":"legacy-quarantine-request"}' | Set-Content -LiteralPath $requestPath -Encoding UTF8
    '{"not":"a valid candidate"}' | Set-Content -LiteralPath $candidatePath -Encoding UTF8
    New-TestImage -Path $imagePath
    $beforeState = if (Test-Path -LiteralPath $stateFile) { Get-Content -LiteralPath $stateFile -Raw } else { '<missing>' }

    Assert-LegacyDisabled 'default vlm-observation-run-mock is disabled' @(
        'vlm-observation-run-mock',
        '--request', $requestPath,
        '--scenario', 'valid',
        '--output', $mockOutputPath
    ) 'vlm-capability-probe' | Out-Null

    Assert-LegacyDisabled 'default vlm-assisted-locate is disabled' @(
        'vlm-assisted-locate',
        '--target', 'Submit',
        '--provider', 'mock',
        '--scenario', 'valid',
        '--result', $assistResult
    ) 'vlm-assist-locate' | Out-Null

    Assert-LegacyDisabled 'default vlm-assisted-locate-dry-run is disabled' @(
        'vlm-assisted-locate-dry-run',
        '--target', 'Submit',
        '--provider', 'mock',
        '--scenario', 'valid',
        '--result', $dryRunResult
    ) 'RealVlmRuntimeBridge' | Out-Null

    Assert-LegacyDisabled 'default locate-and-click legacy command is disabled before action' @(
        'vlm-assisted-locate-and-click-local-safe',
        '--target', 'Click Me',
        '--provider', 'mock',
        '--scenario', 'testwindow_click_me',
        '--title', 'Agent Test Window',
        '--expected-marker', 'clicks=999',
        '--result', $clickResult
    ) 'vlm-assist-locate' | Out-Null

    $afterState = if (Test-Path -LiteralPath $stateFile) { Get-Content -LiteralPath $stateFile -Raw } else { '<missing>' }
    Add-Check 'disabled locate-and-click did not modify TestWindow state' ($afterState -eq $beforeState) 'state file unchanged'

    $optIn = Invoke-WinAgentJson @(
        'vlm-observation-run-mock',
        '--request', $requestPath,
        '--scenario', 'valid',
        '--output', $mockOutputPath,
        '--allow-legacy-mock-vlm', 'true'
    )
    Add-Check 'opt-in legacy mock observation can run for test fixture' (($optIn.exit -eq 0) -and ([bool]$optIn.json.ok) -and (Test-Path -LiteralPath $mockOutputPath)) "exit=$($optIn.exit)"
    Add-Check 'opt-in output marks legacy mock true' ([bool]$optIn.json.data.legacy_mock_vlm) ($optIn.text)
    Add-Check 'opt-in output marks real VLM false' (-not [bool]$optIn.json.data.real_vlm) ($optIn.text)
    Add-Check 'opt-in output marks not for agent workflow' ([bool]$optIn.json.data.not_for_agent_workflow) ($optIn.text)

    foreach ($rel in @(
        'skill_template\win-desktop-agent\SKILL.md',
        'skill_template\win-desktop-agent\references\VISIBLE_FIRST_CONTRACT.md',
        'adapters\codex\win-desktop-agent\SKILL.md',
        'adapters\shared\TASK_FLOW.md',
        'adapters\shared\ERROR_HANDLING.md',
        'adapters\shared\REPORT_READING.md'
    )) {
        Assert-NoOldCommandRecommendation $rel
    }

    $probe = Invoke-WinAgentJson @(
        'vlm-capability-probe',
        '--provider', 'codex-cli',
        '--session-id', 'legacy-quarantine-new-path',
        '--probe-image', $imagePath,
        '--cache', 'false',
        '--simulation', 'unavailable'
    )
    Add-Check 'new vlm-capability-probe unaffected' (($probe.json.command -eq 'vlm-capability-probe') -and ((Get-ErrorCode $probe.json) -notlike 'LEGACY_*')) $probe.text

    $assist = Invoke-WinAgentJson @(
        'vlm-assist-locate',
        '--provider', 'codex-cli',
        '--session-id', 'legacy-quarantine-new-path',
        '--image', $imagePath,
        '--target', 'VLM TEST',
        '--capability-simulation', 'unavailable'
    )
    Add-Check 'new vlm-assist-locate unaffected' (($assist.json.command -eq 'vlm-assist-locate') -and ((Get-ErrorCode $assist.json) -notlike 'LEGACY_*')) $assist.text

    $validate = Invoke-WinAgentJson @(
        'vlm-candidate-validate',
        '--candidate-json', $candidatePath,
        '--image', $imagePath,
        '--target', 'VLM TEST'
    )
    Add-Check 'new vlm-candidate-validate unaffected' (($validate.json.command -eq 'vlm-candidate-validate') -and ((Get-ErrorCode $validate.json) -notlike 'LEGACY_*')) $validate.text

    $report = @(
        '# Legacy Mock VLM Quarantine Selftest Report',
        '',
        '- status: PASS',
        "- root: $Root",
        "- evidence_root: $EvidenceRoot",
        "- legacy_mock_output: $mockOutputPath",
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Host "PASS: legacy_mock_vlm_quarantine_selftest ($ReportPath)"
    exit 0
} catch {
    $report = @(
        '# Legacy Mock VLM Quarantine Selftest Report',
        '',
        '- status: BLOCKED',
        "- root: $Root",
        "- error: $($_.Exception.Message)",
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Error "BLOCKED: legacy_mock_vlm_quarantine_selftest failed: $($_.Exception.Message). Report: $ReportPath"
    exit 1
}
