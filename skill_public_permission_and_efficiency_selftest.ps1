param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$ManifestPath = Join-Path $Root 'config\safety_manifest.json'
$SourceSkillPath = Join-Path $Root 'skill_template\win-desktop-agent\SKILL.md'
$AdapterSkillPath = Join-Path $Root 'adapters\codex\win-desktop-agent\SKILL.md'
$SharedSafetyRulesPath = Join-Path $Root 'adapters\shared\SAFETY_RULES.md'
$SharedTaskFlowPath = Join-Path $Root 'adapters\shared\TASK_FLOW.md'
$SharedErrorHandlingPath = Join-Path $Root 'adapters\shared\ERROR_HANDLING.md'
$SharedReportReadingPath = Join-Path $Root 'adapters\shared\REPORT_READING.md'
$CommandProtocolPath = Join-Path $Root 'COMMAND_PROTOCOL.md'
$KnownLimitationsPath = Join-Path $Root 'docs\KNOWN_LIMITATIONS.md'
$SafetyPath = Join-Path $Root 'docs\SAFETY.md'
$OutDir = Join-Path $Root 'artifacts\dev1.1.0_public_permission_agent_efficiency'
$ReportPath = Join-Path $OutDir 'skill_public_permission_and_efficiency_selftest_report.md'

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Fail($Message) { throw $Message }

function Require-Text {
    param(
        [string]$Name,
        [string]$Text,
        [string[]]$Patterns
    )
    foreach ($pattern in $Patterns) {
        if ($Text -notmatch $pattern) {
            Fail "$Name missing required pattern: $pattern"
        }
    }
}

function Reject-Text {
    param(
        [string]$Name,
        [string]$Text,
        [string[]]$Patterns
    )
    foreach ($pattern in $Patterns) {
        if ($Text -match $pattern) {
            Fail "$Name contains forbidden old policy pattern: $pattern"
        }
    }
}

$manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
foreach ($capability in @('third_party_apps','external_web','communication','content_decision','cross_window','global_desktop','browser','explorer','local_file_open','localhost')) {
    if ($manifest.permission_modes.PUBLIC_DEFAULT.$capability -ne $true) {
        Fail "config PUBLIC_DEFAULT must allow $capability."
    }
    if ($manifest.permission_modes.DEVELOPER_CAPABILITY_DISCOVERY.$capability -ne $true) {
        Fail "config developer profile must allow $capability."
    }
}
if ($manifest.report_policy.report_level -ne 'compact' -or $manifest.report_policy.evidence_level -ne 'full') {
    Fail 'config report policy must remain compact progress / full evidence.'
}

$sourceSkill = Get-Content -Raw -LiteralPath $SourceSkillPath
$adapterSkill = Get-Content -Raw -LiteralPath $AdapterSkillPath
$shared = @(
    (Get-Content -Raw -LiteralPath $SharedSafetyRulesPath),
    (Get-Content -Raw -LiteralPath $SharedTaskFlowPath),
    (Get-Content -Raw -LiteralPath $SharedErrorHandlingPath),
    (Get-Content -Raw -LiteralPath $SharedReportReadingPath)
) -join "`n"
$safetyDoc = if (Test-Path -LiteralPath $SafetyPath) { Get-Content -Raw -LiteralPath $SafetyPath } else { '' }
$docs = @(
    (Get-Content -Raw -LiteralPath $CommandProtocolPath),
    (Get-Content -Raw -LiteralPath $KnownLimitationsPath),
    $safetyDoc
) -join "`n"
$allText = "$sourceSkill`n$adapterSkill`n$shared`n$docs"

Require-Text 'source Skill public policy' $sourceSkill @(
    'PUBLIC_DEFAULT',
    'ordinary visible desktop',
    'third-party app',
    'browser',
    'https',
    'localhost',
    'Explorer',
    'validated absolute screen coordinate',
    'developer profile.*not.*tightened'
)
Require-Text 'adapter Skill public policy' $adapterSkill @(
    'PUBLIC_DEFAULT',
    'ordinary visible desktop',
    'third-party app',
    'browser',
    'https',
    'localhost',
    'Explorer',
    'developer profile.*not.*tightened'
)
Require-Text 'STOP boundaries' $allText @(
    'real exam',
    'proctoring',
    'lockdown browser',
    'CAPTCHA',
    'human verification',
    'anti-cheat',
    'protected desktop',
    'UAC'
)
Require-Text 'efficiency policy' $allText @(
    'compact progress',
    'full evidence',
    'report_level=compact',
    'evidence_level=full',
    'agent_context_digest\.md'
)

Reject-Text 'source Skill' $sourceSkill @(
    'PUBLIC_DEFAULT.*deferred',
    'public/formal release permission policy is deferred',
    'PUBLIC_DEFAULT.*does not allow ordinary app',
    'PUBLIC_DEFAULT.*does not allow.*localhost',
    'PUBLIC_DEFAULT.*does not allow.*Explorer'
)
Reject-Text 'adapter Skill' $adapterSkill @(
    'PUBLIC_DEFAULT.*deferred',
    'public/formal release permission policy is deferred',
    'PUBLIC_DEFAULT.*does not allow ordinary app',
    'PUBLIC_DEFAULT.*does not allow.*localhost',
    'PUBLIC_DEFAULT.*does not allow.*Explorer'
)

if ($docs -match 'PUBLIC_DEFAULT.*deferred|does not redefine PUBLIC_DEFAULT|release permission hardening deferred') {
    Fail 'docs must not describe v1.1.0 public permission as deferred.'
}
if ($allText -match 'public profile.*residual|public profile.*crippled|PUBLIC_DEFAULT.*all false') {
    Fail 'public profile must not be described as a disabled or crippled mode.'
}

$lines = @(
    '# Skill Public Permission And Efficiency Selftest',
    '',
    '- Result: PASS',
    "- Root: $Root",
    '- Public ordinary visible desktop capability: documented and configured',
    '- Public STOP triggers: documented',
    '- Developer profile: not tightened',
    '- Compact progress / full evidence: documented',
    '- Adapter and source Skill: no conflict',
    '- Docs and config policy: no conflict'
)
$lines | Set-Content -LiteralPath $ReportPath -Encoding UTF8

Write-Host 'skill_public_permission_and_efficiency_selftest PASS'
Write-Host "Report: $ReportPath"
