param(
    [switch]$Help,
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\skill_vlm_contract_selftest.ps1 [-Root <path>]'
    Write-Host 'Verifies v1.0.3 Skill and adapter VLM assist contract text.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$EvidenceRoot = Join-Path $Root 'artifacts\dev1.0.3_automatic_real_vlm_runtime_bridge'
$ReportPath = Join-Path $EvidenceRoot 'skill_vlm_contract_selftest_report.md'
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null

$files = @(
    'skill_template\win-desktop-agent\SKILL.md',
    'skill_template\win-desktop-agent\references\VISIBLE_FIRST_CONTRACT.md',
    'skill_template\win-desktop-agent\references\AGENT_USAGE_GUIDE.md',
    'skill_template\win-desktop-agent\references\REAL_DEV_WORKFLOW.md',
    'skill_template\win-desktop-agent\references\COMMAND_PROTOCOL.md',
    'skill_template\win-desktop-agent\references\KNOWN_LIMITATIONS.md',
    'adapters\codex\win-desktop-agent\SKILL.md',
    'adapters\shared\TASK_FLOW.md',
    'adapters\shared\ERROR_HANDLING.md',
    'adapters\shared\REPORT_READING.md'
)

$checks = New-Object System.Collections.Generic.List[string]

function Add-Check {
    param([string]$Name, [bool]$Passed, [string]$Detail)
    $status = if ($Passed) { 'PASS' } else { 'FAIL' }
    $script:checks.Add("- ${status}: ${Name} - ${Detail}") | Out-Null
    if (-not $Passed) { throw "${Name}: ${Detail}" }
}

function Read-Rel {
    param([string]$Rel)
    $path = Join-Path $Root $Rel
    Add-Check "file exists ${Rel}" (Test-Path -LiteralPath $path) $path
    return Get-Content -LiteralPath $path -Raw
}

try {
    $combined = ''
    foreach ($file in $files) {
        $combined += [Environment]::NewLine + (Read-Rel $file)
    }
    $sourceSkill = Read-Rel 'skill_template\win-desktop-agent\SKILL.md'
    $adapterSkill = Read-Rel 'adapters\codex\win-desktop-agent\SKILL.md'

    Add-Check 'source Skill mentions provider-gated VLM assist' ($sourceSkill -match 'provider-gated VLM assist') 'source skill'
    Add-Check 'adapter Skill mentions provider-gated VLM assist' ($adapterSkill -match 'provider-gated VLM assist') 'adapter skill'
    Add-Check 'VLM does not directly operate computer' ($combined -match 'must not (click|directly operate|move the mouse|type)') 'direct operation forbidden'
    Add-Check 'VLM does not participate in backend fallback' ($combined -match 'does not participate in backend fallback|must not.*backend fallback|after backend fallback') 'backend fallback forbidden'
    Add-Check 'VLM not every step' ($combined -match 'not call VLM on every step|do not call VLM on every step|do not probe or call VLM on every step') 'not every step'
    Add-Check 'VLM unavailable Runtime-only' ($combined -match 'VLM_UNAVAILABLE.*Runtime-only|Runtime-only.*VLM_UNAVAILABLE') 'runtime-only degradation'
    Add-Check 'VLM candidate Runtime validate' ($combined -match 'Runtime (must )?validate|Runtime validated|validates candidates') 'runtime validation'
    Add-Check 'VLM cannot bypass active protection' ($combined -match 'bypass active protection|active protection.*STOP') 'active protection stop'
    Add-Check 'does not claim all environments support VLM' ($combined -match 'availability depends|VLM_UNAVAILABLE|provider-gated') 'provider availability caveat'
    Add-Check 'shared rules include VLM evidence' ($combined -match 'vlm_assist_enabled' -and $combined -match 'vlm_after_backend_attempted') 'shared evidence fields'

    $report = @(
        '# Skill VLM Contract Selftest Report',
        '',
        '- status: PASS',
        "- root: $Root",
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Host "PASS: skill_vlm_contract_selftest ($ReportPath)"
    exit 0
} catch {
    $report = @(
        '# Skill VLM Contract Selftest Report',
        '',
        '- status: BLOCKED',
        "- root: $Root",
        "- error: $($_.Exception.Message)",
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Error "BLOCKED: skill_vlm_contract_selftest failed: $($_.Exception.Message). Report: $ReportPath"
    exit 1
}
