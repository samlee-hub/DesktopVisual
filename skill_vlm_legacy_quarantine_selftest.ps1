param(
    [switch]$Help,
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\skill_vlm_legacy_quarantine_selftest.ps1 [-Root <path>]'
    Write-Host 'Verifies DesktopVisual v1.0.3.1 Skill/adapter legacy mock VLM quarantine contract.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$EvidenceRoot = Join-Path $Root 'artifacts\dev1.0.3.1_legacy_mock_vlm_quarantine'
$ReportPath = Join-Path $EvidenceRoot 'skill_vlm_legacy_quarantine_selftest_report.md'
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null

$checks = New-Object System.Collections.Generic.List[string]
$oldCommandPattern = 'vlm-observation-run-mock|vlm-assisted-locate(?:-dry-run|-and-click-local-safe)?'

function Add-Check {
    param([string]$Name, [bool]$Passed, [string]$Detail)
    $status = if ($Passed) { 'PASS' } else { 'FAIL' }
    $script:checks.Add("- ${status}: ${Name} - ${Detail}") | Out-Null
    if (-not $Passed) {
        throw "${Name}: ${Detail}"
    }
}

function Read-Rel {
    param([string]$Rel)
    $path = Join-Path $Root $Rel
    Add-Check "file exists ${Rel}" (Test-Path -LiteralPath $path) $path
    return Get-Content -LiteralPath $path -Raw
}

function Assert-NoOldCommand {
    param([string]$Rel, [string]$Name)
    $text = Read-Rel $Rel
    Add-Check $Name ($text -notmatch $oldCommandPattern) $Rel
}

try {
    $sourceSkill = Read-Rel 'skill_template\win-desktop-agent\SKILL.md'
    $sourceVisible = Read-Rel 'skill_template\win-desktop-agent\references\VISIBLE_FIRST_CONTRACT.md'
    $sourceKnown = Read-Rel 'skill_template\win-desktop-agent\references\KNOWN_LIMITATIONS.md'
    $adapterSkill = Read-Rel 'adapters\codex\win-desktop-agent\SKILL.md'
    $taskFlow = Read-Rel 'adapters\shared\TASK_FLOW.md'
    $errorHandling = Read-Rel 'adapters\shared\ERROR_HANDLING.md'
    $reportReading = Read-Rel 'adapters\shared\REPORT_READING.md'
    $protocol = Read-Rel 'COMMAND_PROTOCOL.md'

    Assert-NoOldCommand 'skill_template\win-desktop-agent\SKILL.md' 'source Skill does not recommend old mock VLM commands'
    Assert-NoOldCommand 'skill_template\win-desktop-agent\references\VISIBLE_FIRST_CONTRACT.md' 'source visible-first reference does not recommend old mock VLM commands'
    Assert-NoOldCommand 'adapters\codex\win-desktop-agent\SKILL.md' 'adapter Skill does not recommend old mock VLM commands'
    Assert-NoOldCommand 'adapters\shared\TASK_FLOW.md' 'shared TASK_FLOW does not recommend old mock VLM commands'
    Assert-NoOldCommand 'adapters\shared\ERROR_HANDLING.md' 'shared ERROR_HANDLING does not recommend old mock VLM commands'
    Assert-NoOldCommand 'adapters\shared\REPORT_READING.md' 'shared REPORT_READING does not recommend old mock VLM commands'

    Add-Check 'COMMAND_PROTOCOL marks old commands legacy/deprecated/test-only' (
        ($protocol -match 'Legacy Mock VLM') -and
        ($protocol -match 'Deprecated') -and
        ($protocol -match 'Test-only') -and
        ($protocol -match $oldCommandPattern)
    ) 'COMMAND_PROTOCOL.md'

    $combinedSkill = $sourceSkill + "`n" + $sourceVisible + "`n" + $sourceKnown + "`n" + $adapterSkill + "`n" + $taskFlow + "`n" + $errorHandling + "`n" + $reportReading
    Add-Check 'Skill states new VLM path is normal path' (($combinedSkill -match 'vlm-capability-probe') -and ($combinedSkill -match 'vlm-assist-locate') -and ($combinedSkill -match 'vlm-candidate-validate') -and ($combinedSkill -match 'normal VLM path|normal path|v1\.0\.3\+')) 'new commands present'
    Add-Check 'Skill states VLM does not directly act' ($combinedSkill -match 'must not (click|move the mouse|type)|does not directly operate|not the controller') 'direct action forbidden'
    Add-Check 'Skill states VLM does not participate in backend fallback' ($combinedSkill -match 'does not participate in backend fallback|must not.*backend fallback|Once backend fallback starts') 'backend fallback forbidden'
    Add-Check 'Skill states VLM_UNAVAILABLE degrades Runtime-only' ($combinedSkill -match 'VLM_UNAVAILABLE.*Runtime-only|Runtime-only.*VLM_UNAVAILABLE') 'runtime-only degradation'
    Add-Check 'Skill states v1.0.4 complex IDE uses real bridge not mock' (($combinedSkill -match 'v1\.0\.4') -and ($combinedSkill -match 'RealVlmRuntimeBridge|real VLM bridge') -and ($combinedSkill -notmatch 'mock.*v1\.0\.4 complex IDE')) 'v1.0.4 real bridge'

    $report = @(
        '# Skill VLM Legacy Quarantine Selftest Report',
        '',
        '- status: PASS',
        "- root: $Root",
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Host "PASS: skill_vlm_legacy_quarantine_selftest ($ReportPath)"
    exit 0
} catch {
    $report = @(
        '# Skill VLM Legacy Quarantine Selftest Report',
        '',
        '- status: BLOCKED',
        "- root: $Root",
        "- error: $($_.Exception.Message)",
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Error "BLOCKED: skill_vlm_legacy_quarantine_selftest failed: $($_.Exception.Message). Report: $ReportPath"
    exit 1
}
