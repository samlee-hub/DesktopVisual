param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ManifestPath = Join-Path $Root 'config\safety_manifest.json'
$SkillPath = Join-Path $Root 'skill_template\win-desktop-agent\SKILL.md'
$AdapterSkillPath = Join-Path $Root 'adapters\codex\win-desktop-agent\SKILL.md'
$AgentsPath = Join-Path $Root 'AGENTS.md'
$TaskFlowPath = Join-Path $Root 'adapters\shared\TASK_FLOW.md'
$ReportReadingPath = Join-Path $Root 'adapters\shared\REPORT_READING.md'
$OutDir = Join-Path $Root 'artifacts\dev1.1.0_public_permission_agent_efficiency'
$ReportPath = Join-Path $OutDir 'agent_compact_output_policy_selftest_report.md'

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
            Fail "$Name missing required policy pattern: $pattern"
        }
    }
}

function Invoke-AgentJson {
    param([string[]]$CmdArgs)
    $output = & $WinAgent @CmdArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        Fail "winagent $($CmdArgs -join ' ') exited $LASTEXITCODE with output: $output"
    }
    try {
        return ($output | ConvertFrom-Json)
    } catch {
        Fail "Invalid JSON from winagent $($CmdArgs -join ' '): $output"
    }
}

$manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
if ($manifest.report_policy.report_level -ne 'compact') { Fail 'report_policy.report_level must default to compact.' }
if ($manifest.report_policy.evidence_level -ne 'full') { Fail 'report_policy.evidence_level must default to full.' }
if ($manifest.report_policy.progress_output -ne 'compact') { Fail 'report_policy.progress_output must default to compact.' }
if ($manifest.report_policy.step_chat_detail -ne 'compact') { Fail 'report_policy.step_chat_detail must default to compact.' }
if ($manifest.report_policy.artifact_evidence -ne 'full') { Fail 'report_policy.artifact_evidence must default to full.' }

$safetyReport = Invoke-AgentJson -CmdArgs @('safety-report')
if ($safetyReport.data.report_policy.report_level -ne 'compact') { Fail 'safety-report must expose report_policy.report_level=compact.' }
if ($safetyReport.data.report_policy.evidence_level -ne 'full') { Fail 'safety-report must expose report_policy.evidence_level=full.' }

$skill = Get-Content -Raw -LiteralPath $SkillPath
$adapterSkill = Get-Content -Raw -LiteralPath $AdapterSkillPath
$agents = Get-Content -Raw -LiteralPath $AgentsPath
$taskFlow = Get-Content -Raw -LiteralPath $TaskFlowPath
$reportReading = Get-Content -Raw -LiteralPath $ReportReadingPath
$combinedDocs = "$agents`n$taskFlow`n$reportReading"

Require-Text 'source Skill' $skill @(
    'compact progress',
    'full evidence',
    'report_level=compact',
    'evidence_level=full'
)
Require-Text 'Codex adapter Skill' $adapterSkill @(
    'compact progress',
    'full evidence',
    'report_level=compact',
    'evidence_level=full'
)
Require-Text 'AGENTS/docs' $combinedDocs @(
    'read-once',
    'agent_context_digest\.md',
    'do not repeatedly reread full documents'
)
Require-Text 'failure policy' "$skill`n$adapterSkill`n$combinedDocs" @(
    'error',
    'evidence',
    'next repair',
    'compact output must not hide failures'
)
Require-Text 'scan policy' "$skill`n$adapterSkill`n$combinedDocs" @(
    'do not scan artifacts',
    '\.git',
    'bin',
    'obj'
)

if ($skill -match 'default.*long-form natural language' -or $adapterSkill -match 'default.*long-form natural language') {
    Fail 'Default mode must not require long-form natural language step narration.'
}
if ($combinedDocs -match 'repeat(ed)? full document reread.*default') {
    Fail 'Repeated full document reread must not be a default workflow.'
}

$lines = @(
    '# Agent Compact Output Policy Selftest',
    '',
    '- Result: PASS',
    "- Root: $Root",
    '- report_level: compact',
    '- evidence_level: full',
    '- progress_output: compact',
    '- step_chat_detail: compact',
    '- artifact_evidence: full',
    '- failure output: error/evidence/next repair',
    '- read-once digest: agent_context_digest.md',
    '- compact output must not hide failures'
)
$lines | Set-Content -LiteralPath $ReportPath -Encoding UTF8

Write-Host 'agent_compact_output_policy_selftest PASS'
Write-Host "Report: $ReportPath"
