param([string]$Root = '')

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$OutDir = Join-Path $Root 'artifacts\dev1.0.4_vs_cpp_complex_ide_workflow'
$Report = Join-Path $OutDir 'skill_vs_complex_ide_workflow_selftest_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$Checks = New-Object System.Collections.Generic.List[object]
$Failed = 0
$EmptyProject = -join @([char]0x7A7A, [char]0x9879)

function Add-Check([string]$Name, [string]$Status, [string]$Detail) {
    $script:Checks.Add([pscustomobject]@{
        name = $Name
        status = $Status
        detail = $Detail
    }) | Out-Null
    if ($Status -eq 'FAIL') { $script:Failed++ }
}

function Check([string]$Name, [scriptblock]$Body) {
    try {
        & $Body
        Add-Check $Name 'PASS' ''
    } catch {
        Add-Check $Name 'FAIL' $_.Exception.Message
    }
}

function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Read-Rel([string]$Rel) {
    $path = Join-Path $Root $Rel
    Assert (Test-Path -LiteralPath $path) "missing file: $Rel"
    return [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
}

function Assert-Matches([string]$Text, [string]$Pattern, [string]$Message) {
    Assert ($Text -match $Pattern) $Message
}

$version = Read-Rel 'VERSION'
$changeLog = Read-Rel 'CHANGELOG.md'
$readme = Read-Rel 'README.md'
$commandProtocol = Read-Rel 'COMMAND_PROTOCOL.md'
$architecture = Read-Rel 'docs\ARCHITECTURE.md'
$roadmap = Read-Rel 'docs\ROADMAP.md'
$knownLimitations = Read-Rel 'docs\KNOWN_LIMITATIONS.md'
$sourceSkill = Read-Rel 'skill_template\win-desktop-agent\SKILL.md'
$sourceWorkflow = Read-Rel 'skill_template\win-desktop-agent\references\REAL_DEV_WORKFLOW.md'
$sourceProtocol = Read-Rel 'skill_template\win-desktop-agent\references\COMMAND_PROTOCOL.md'
$sourceKnown = Read-Rel 'skill_template\win-desktop-agent\references\KNOWN_LIMITATIONS.md'
$adapterSkill = Read-Rel 'adapters\codex\win-desktop-agent\SKILL.md'
$adapterWorkflow = Read-Rel 'adapters\codex\win-desktop-agent\references\REAL_DEV_WORKFLOW.md'
$adapterProtocol = Read-Rel 'adapters\codex\win-desktop-agent\references\COMMAND_PROTOCOL.md'
$adapterKnown = Read-Rel 'adapters\codex\win-desktop-agent\references\KNOWN_LIMITATIONS.md'
$sharedTaskFlow = Read-Rel 'adapters\shared\TASK_FLOW.md'
$genericContract = Read-Rel 'adapters\generic-cli\desktopvisual-agent-contract.md'
$dReport = Read-Rel 'artifacts\dev1.0.4_vs_cpp_complex_ide_workflow\vs_cpp_complex_ide_workflow_selftest_report.md'

$docs = $changeLog + "`n" + $readme + "`n" + $commandProtocol + "`n" + $architecture + "`n" + $roadmap + "`n" + $knownLimitations
$skill = $sourceSkill + "`n" + $sourceWorkflow + "`n" + $sourceProtocol + "`n" + $sourceKnown + "`n" + $adapterSkill + "`n" + $adapterWorkflow + "`n" + $adapterProtocol + "`n" + $adapterKnown + "`n" + $sharedTaskFlow + "`n" + $genericContract

Check 'VERSION is 1.0.4' {
    Assert ($version.Trim() -eq '1.0.4') 'VERSION must be 1.0.4'
}

Check 'documentation states v1.0.4 VS C++ workflow scope' {
    Assert-Matches $docs 'DesktopVisual 1\.0\.4' 'missing v1.0.4 documentation'
    Assert-Matches $docs 'Visual Studio C\+\+' 'missing Visual Studio C++ documentation'
    Assert-Matches $docs 'SingleTestProject' 'missing SingleTestProject documentation'
    Assert-Matches $docs 'Capture/OCR performance pipeline|Capture/OCR Performance Pipeline' 'missing v1.0.5 deferral'
}

Check 'documentation preserves no release packaging scope' {
    Assert-Matches $docs 'does not.*release packages|does not.*release packaging|release packaging' 'missing release packaging boundary'
    Assert-Matches $docs 'release/public-dist' 'missing release/public-dist boundary'
}

Check 'Skill requires VS desktop icon launch and top-right X close' {
    Assert-Matches $skill 'visible desktop icon double-click' 'missing desktop icon double-click rule'
    Assert-Matches $skill 'top-right X' 'missing top-right X close rule'
    Assert-Matches $skill 'Start Menu.*invalid|Do not use Start Menu|Start Menu.*not' 'missing Start Menu prohibition/fallback rule'
}

Check 'Skill requires Empty Project and SingleTestProject reuse' {
    Assert-Matches $skill 'SingleTestProject' 'missing SingleTestProject'
    Assert-Matches $skill 'Empty Project' 'missing Empty Project'
    Assert-Matches $skill 'reuse|reused' 'missing project reuse rule'
}

Check 'Skill requires visible IDE file-add, editor input, build, and run' {
    Assert-Matches $skill 'Solution Explorer' 'missing Solution Explorer rule'
    Assert-Matches $skill 'Ctrl\+Shift\+A' 'missing new item fallback'
    Assert-Matches $skill 'visible VS editor|visible editor' 'missing visible editor input rule'
    Assert-Matches $skill 'Ctrl\+Shift\+B' 'missing build shortcut'
    Assert-Matches $skill 'Ctrl\+F5' 'missing run shortcut'
    Assert-Matches $skill 'visible console|visible output' 'missing visible output verification'
}

Check 'Skill forbids backend substitutes and old mock VLM' {
    Assert-Matches $skill 'backend.*project.*file.*build.*run|Backend project creation' 'missing backend substitute prohibition'
    Assert-Matches $skill 'msbuild' 'missing backend build prohibition'
    Assert-Matches $skill 'direct exe run|direct exe runs' 'missing direct exe run prohibition'
    Assert-Matches $skill 'old mock VLM|legacy mock VLM' 'missing old mock VLM prohibition'
    Assert-Matches $skill 'invalid PASS|cannot support PASS' 'missing invalid PASS wording'
}

Check 'Skill requires step checkpoints' {
    Assert-Matches $skill 'step checkpoint' 'missing step checkpoint rule'
    Assert-Matches $skill 'visible_observe_before' 'missing visible_observe_before field'
    Assert-Matches $skill 'verification_result' 'missing verification_result field'
    Assert-Matches $skill 'next_step_allowed' 'missing next_step_allowed field'
}

Check 'Feature D report has required PASS evidence fields' {
    Assert-Matches $dReport 'result=PASS' 'D report is not PASS'
    Assert-Matches $dReport 'stage_1_single_file_pass=true' 'missing Stage 1 PASS'
    Assert-Matches $dReport 'stage_2_multi_source_pass=true' 'missing Stage 2 PASS'
    Assert-Matches $dReport 'stage_3_multi_source_header_pass=true' 'missing Stage 3 PASS'
    Assert-Matches $dReport 'vs_open_method=desktop_icon_double_click' 'missing VS desktop icon open evidence'
    Assert-Matches $dReport 'desktop_vs_icon_found=true' 'missing VS icon evidence'
    Assert-Matches $dReport 'project_opened_by_visible_ui=true' 'missing visible project open evidence'
    Assert-Matches $dReport 'close_method=top_right_x_visible_click' 'missing top-right X close evidence'
    Assert-Matches $dReport 'backend_file_write_used=false' 'missing backend file write false'
    Assert-Matches $dReport 'backend_build_used=false' 'missing backend build false'
    Assert-Matches $dReport 'backend_run_used=false' 'missing backend run false'
    Assert-Matches $dReport 'old_mock_vlm_used=false' 'missing old mock VLM false'
    Assert-Matches $dReport 'output_verified=true' 'missing output verified'
    Assert ($dReport.Contains("template_required=$EmptyProject")) 'missing empty project template evidence'
}

$status = if ($Failed -eq 0) { 'PASS' } else { 'BLOCKED' }
$lines = @(
    '# Skill VS Complex IDE Workflow Selftest Report',
    '',
    "- result=$status",
    "- root=$Root",
    '',
    '## Checks',
    ''
)
foreach ($check in $Checks) {
    $lines += "- $($check.status): $($check.name) $($check.detail)"
}
Set-Content -LiteralPath $Report -Value ($lines -join [Environment]::NewLine) -Encoding UTF8

if ($Failed -ne 0) {
    Write-Error "BLOCKED: skill_vs_complex_ide_workflow_selftest failed. Report: $Report"
    exit 1
}

Write-Host "PASS: skill_vs_complex_ide_workflow_selftest ($Report)"
exit 0
