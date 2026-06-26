param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\v5_8_rc_acceptance.ps1 [-Root <path>]'
    Write-Host 'Runs v5.8 Task Execution Release Candidate acceptance.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.8.6'
$Report = Join-Path $ArtifactDir 'v5_rc_acceptance_report.md'
$Summary = Join-Path $ArtifactDir 'v5_rc_acceptance_summary.json'
$GitStatusPath = Join-Path $ArtifactDir 'git_status.txt'
$GitStatusSummaryPath = Join-Path $ArtifactDir 'git_status_classification.json'

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

$results = New-Object System.Collections.Generic.List[object]

function Invoke-Step {
    param([string]$Name, [scriptblock]$Body)
    $start = Get-Date
    try {
        $output = & $Body 2>&1
        $exit = if ($LASTEXITCODE -ne $null) { $LASTEXITCODE } else { 0 }
        if ($exit -ne 0) { throw "Exit code $exit. Output: $(($output | Out-String).Trim())" }
        $results.Add([pscustomobject]@{ name=$Name; status='PASS'; duration_ms=[int]((Get-Date) - $start).TotalMilliseconds; output=(($output | Out-String).Trim()) }) | Out-Null
    } catch {
        $results.Add([pscustomobject]@{ name=$Name; status='FAIL'; duration_ms=[int]((Get-Date) - $start).TotalMilliseconds; output=$_.Exception.Message }) | Out-Null
        throw
    }
}

function Invoke-ScriptStep([string]$Name, [string]$ScriptName) {
    Invoke-Step $Name { powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root $ScriptName) -Root $Root }
}

function Get-GitStatusClassification {
    $raw = @(git -C $Root status --short)
    $classification = if ($raw.Count -eq 0) { 'CLEAN' } else { 'DIRTY_EXPECTED_INTERNAL_CHANGES' }
    return [pscustomobject]@{
        clean = ($raw.Count -eq 0)
        classification = $classification
        public_release_classification = if ($raw.Count -eq 0) { 'PUBLIC_RELEASE_TREE_REQUIRES_PHASE_11' } else { 'RELEASE_BLOCKED_DIRTY_TREE' }
        internal_rc_allowed = $true
        public_release_ready = $false
        dirty_entry_count = $raw.Count
        raw = $raw
    }
}

Invoke-Step 'build' { powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'build.ps1') -Root $Root }

Invoke-Step 'full relevant selftest' {
    $expectedVersion = (Get-Content -LiteralPath (Join-Path $Root 'VERSION') -Raw).Trim()
    $versionOutput = & $WinAgent version
    $version = $versionOutput | ConvertFrom-Json
    if (-not $version.ok -or $version.data.version -ne $expectedVersion) { throw "Expected winagent version $expectedVersion. Output: $versionOutput" }
    if (-not ($version.data.capabilities.available -contains 'task_execution_release_candidate')) { throw 'Missing task_execution_release_candidate capability.' }
    $helpText = (& $WinAgent help | Out-String)
    foreach ($command in @('run-task','task-status','task-events','task-report','task-confirm','task-cancel','task-session-run','step-verify','recovery-evaluate','confirmation-gate-check','task-template-v2-resolve','file-picker-flow')) {
        if ($helpText -notmatch [regex]::Escape($command)) { throw "Help output missing $command" }
    }
    $versionOutput
}

Invoke-ScriptStep 'feature freeze and audit' 'v5_rc_audit.ps1'
Invoke-ScriptStep 'evidence consolidation' 'v5_evidence_consolidation.ps1'

Invoke-ScriptStep 'task session tests' 'task_session_selftest.ps1'
Invoke-ScriptStep 'state machine tests' 'task_state_machine_selftest.ps1'
Invoke-ScriptStep 'minimal task runner tests' 'task_session_runner_selftest.ps1'
Invoke-ScriptStep 'task artifact tests' 'task_artifact_selftest.ps1'
Invoke-ScriptStep 'task runtime docs tests' 'task_docs_selftest.ps1'

Invoke-ScriptStep 'step contract tests' 'step_contract_selftest.ps1'
Invoke-ScriptStep 'step precondition tests' 'step_precondition_selftest.ps1'
Invoke-ScriptStep 'step verification tests' 'step_verification_selftest.ps1'
Invoke-ScriptStep 'step failure reason tests' 'step_failure_reason_selftest.ps1'
Invoke-ScriptStep 'step docs tests' 'step_docs_selftest.ps1'

Invoke-ScriptStep 'recovery policy tests' 'recovery_policy_selftest.ps1'
Invoke-ScriptStep 'recovery retry tests' 'recovery_retry_selftest.ps1'
Invoke-ScriptStep 'recovery escalation tests' 'recovery_escalation_selftest.ps1'
Invoke-ScriptStep 'recovery safe stop tests' 'recovery_safe_stop_selftest.ps1'
Invoke-ScriptStep 'recovery docs tests' 'recovery_docs_selftest.ps1'

Invoke-ScriptStep 'risk action tests' 'risk_action_selftest.ps1'
Invoke-ScriptStep 'confirmation request tests' 'confirmation_request_selftest.ps1'
Invoke-ScriptStep 'confirmation gate tests' 'confirmation_gate_selftest.ps1'
Invoke-ScriptStep 'confirmation flow tests' 'confirmation_flow_selftest.ps1'
Invoke-ScriptStep 'confirmation docs tests' 'confirmation_docs_selftest.ps1'

Invoke-ScriptStep 'template schema tests' 'task_template_v2_schema_selftest.ps1'
Invoke-ScriptStep 'profile binding tests' 'profile_binding_selftest.ps1'
Invoke-ScriptStep 'parameter tests' 'task_parameter_selftest.ps1'
Invoke-ScriptStep 'built-in template smoke' 'builtin_template_v2_selftest.ps1'
Invoke-ScriptStep 'template docs tests' 'task_template_v2_docs_selftest.ps1'

Invoke-ScriptStep 'file path tests' 'file_path_resolver_selftest.ps1'
Invoke-ScriptStep 'file picker tests' 'file_picker_flow_selftest.ps1'
Invoke-ScriptStep 'upload verification tests' 'upload_verification_selftest.ps1'
Invoke-ScriptStep 'cross-window tests' 'cross_window_context_selftest.ps1'
Invoke-ScriptStep 'local mail attach flow tests' 'local_mail_attach_flow_selftest.ps1'
Invoke-ScriptStep 'file workflow docs tests' 'file_workflow_docs_selftest.ps1'

Invoke-ScriptStep 'dogfood suite' 'task_dogfood_benchmark.ps1'
Invoke-ScriptStep 'dogfood report validation' 'task_dogfood_report_selftest.ps1'
Invoke-ScriptStep 'service protocol tests' 'task_service_protocol_selftest.ps1'
Invoke-ScriptStep 'service report compatibility tests' 'task_report_compat_selftest.ps1'
Invoke-ScriptStep 'service cancel/safe stop tests' 'task_cancel_safe_stop_selftest.ps1'
Invoke-ScriptStep 'service docs tests' 'task_service_docs_selftest.ps1'

Invoke-ScriptStep 'safety RC subset' 'v5_safety_permission_rc_check.ps1'
Invoke-ScriptStep 'latency RC subset' 'v5_task_latency_rc_check.ps1'
Invoke-ScriptStep 'docs validation' 'v5_rc_docs_selftest.ps1'

$gitStatus = Get-GitStatusClassification
$gitStatus.raw | Set-Content -LiteralPath $GitStatusPath -Encoding UTF8
$gitStatus | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $GitStatusSummaryPath -Encoding UTF8
$results.Add([pscustomobject]@{ name='git status classification'; status='INFO'; duration_ms=0; output="classification=$($gitStatus.classification); public_release_classification=$($gitStatus.public_release_classification); saved to $GitStatusSummaryPath" }) | Out-Null

$allPass = @($results | Where-Object { $_.status -eq 'FAIL' }).Count -eq 0
$summaryObject = [pscustomobject]@{
    schema_version = '5.8.7'
    result = if ($allPass) { 'PASS' } else { 'FAIL' }
    timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    vlm_dependency = $false
    llm_vlm_call_count_default = 0
    internal_rc_pass = $allPass
    public_release_ready = $false
    public_release_blockers = @(
        if (-not $gitStatus.clean) { 'RELEASE_BLOCKED_DIRTY_TREE' }
        'PHASE_11_FINAL_RELEASE_STANDARD_VALIDATION_NOT_RUN'
        'VERSION_NORMALIZATION_PASS_NOT_RUN'
        'PUBLIC_RELEASE_TREE_NOT_PREPARED'
    )
    next_track = 'Phase 11 final release-standard validation, then future v6 boundary work only after explicit command'
    git_status = $gitStatus
    checks = $results
}
$summaryObject | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Summary -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# v5 Task Execution Release Candidate Acceptance')
$lines.Add('')
$lines.Add("- Result: $($summaryObject.result)")
$lines.Add("- Timestamp: $($summaryObject.timestamp)")
$lines.Add('- Scope: Task-Level Desktop Execution Runtime')
$lines.Add("- Internal RC pass: $($summaryObject.internal_rc_pass)")
$lines.Add("- Public release ready: $($summaryObject.public_release_ready)")
$lines.Add('- VLM dependency: none')
$lines.Add('')
$lines.Add('## Checks')
$lines.Add('')
$lines.Add('| check | status | duration_ms |')
$lines.Add('|---|---|---:|')
foreach ($result in $results) { $lines.Add("| $($result.name) | $($result.status) | $($result.duration_ms) |") }
$lines.Add('')
$lines.Add('## Acceptance Criteria')
$lines.Add('')
$lines.Add('- v5 can be accurately described as Task-Level Desktop Execution Runtime: PASS')
$lines.Add('- Known App/Profile and controlled tasks can execute, verify, recover, confirm, and audit: PASS')
$lines.Add('- No VLM dependency: PASS')
$lines.Add('- No unfamiliar-screen semantic generalization promise: PASS')
$lines.Add('- No real high-risk task execution: PASS')
$lines.Add('- Evidence pack complete for internal RC: PASS')
$lines.Add('- Public release readiness: BLOCKED until Phase 11, release normalization, public release tree preparation, and clean release audit')
$lines.Add('- v6 started: false')
$lines.Add("- Git status snapshot: $GitStatusPath")
$lines.Add("- Git status classification: $GitStatusSummaryPath")
$lines | Set-Content -LiteralPath $Report -Encoding UTF8

Write-Host 'PASS: v5 Task Execution Release Candidate acceptance'
Write-Host "Report: $Report"
Write-Host "Summary: $Summary"
