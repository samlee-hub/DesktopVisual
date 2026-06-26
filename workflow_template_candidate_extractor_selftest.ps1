param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.11.0_workflow_template_learning_batch_acceleration\selftests\workflow_template_candidate_extractor'
$CandidateOut = Join-Path $OutDir 'explorer_candidate.json'
$DirtyOut = Join-Path $OutDir 'dirty_candidate_attempt.json'
$ReportPath = Join-Path $OutDir 'workflow_template_candidate_extractor_selftest_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$acceptedExplorer = Join-Path $Root 'artifacts\dev6.7.0_explorer_agent_workflows_rerun\final_status_report.md'
& $WinAgent workflow-template-extract --source $acceptedExplorer --workflow-type explorer --output $CandidateOut | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'workflow-template-extract failed for accepted Explorer evidence' }
$candidate = Get-Content -Raw -LiteralPath $CandidateOut | ConvertFrom-Json
if ($candidate.template_status -ne 'candidate') { throw 'extractor must generate candidate only' }
if ($candidate.workflow_type -ne 'explorer') { throw 'workflow_type should be explorer' }
if ($candidate.executable -ne $false) { throw 'candidate must not be executable' }
if ($candidate.source_evidence_refs.Count -lt 1) { throw 'source evidence refs missing' }

$dirtySource = Join-Path $OutDir 'dirty_untracked_artifact.md'
Set-Content -LiteralPath $dirtySource -Encoding UTF8 -Value '# dirty untracked PASS'
& $WinAgent workflow-template-extract --source $dirtySource --workflow-type explorer --output $DirtyOut *> $null
if ($LASTEXITCODE -eq 0) { throw 'dirty/untrusted source extraction should fail' }
$dirtyText = if (Test-Path -LiteralPath $DirtyOut) { Get-Content -Raw -LiteralPath $DirtyOut } else { '' }
if ($dirtyText -notmatch 'FAIL_UNTRUSTED_TEMPLATE_SOURCE') { throw 'dirty source should return FAIL_UNTRUSTED_TEMPLATE_SOURCE' }

Set-Content -LiteralPath $ReportPath -Encoding UTF8 -Value @"
# Workflow Template Candidate Extractor Selftest

- status: PASS
- case1_explorer_accepted_evidence_candidate: PASS
- template_status: candidate
- workflow_type: explorer
- source_evidence_refs_present: true
- direct_execution_allowed: false
- dirty_artifact_source: FAIL_UNTRUSTED_TEMPLATE_SOURCE
- runtime_executed: false
"@
$global:LASTEXITCODE = 0
Write-Host 'workflow_template_candidate_extractor_selftest PASS'
