param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.12.0_rc_gate_and_handoff'
$RunnerRoot = Join-Path $ArtifactRoot 'runner'
$RunnerResult = Join-Path $ArtifactRoot 'runner_result.json'
New-Item -ItemType Directory -Force -Path $RunnerRoot | Out-Null

function Invoke-Checked([scriptblock]$Block, [string]$Name) {
    & $Block | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "$Name failed with exit code $LASTEXITCODE" }
}

$developerPolicy = Join-Path $RunnerRoot 'developer_full_access_policy.json'
$releaseLedger = Join-Path $RunnerRoot 'release_hardening_deferred_ledger.json'
$releaseLedgerMd = Join-Path $RunnerRoot 'release_hardening_deferred_ledger.md'
$capabilityMatrix = Join-Path $RunnerRoot 'developer_capability_matrix.json'
$capabilityMatrixMd = Join-Path $RunnerRoot 'developer_capability_matrix.md'
$evidenceChain = Join-Path $RunnerRoot 'evidence_chain.json'
$workflowBoundary = Join-Path $RunnerRoot 'workflow_boundary_audit.json'
$versionIntegrity = Join-Path $RunnerRoot 'version_integrity.json'
$handoff = Join-Path $RunnerRoot 'handoff_package.json'
$developerRcGate = Join-Path $RunnerRoot 'developer_rc_gate.json'
$handoffCheck = Join-Path $RunnerRoot 'v6_12_rc_handoff_check.json'

Invoke-Checked { & $WinAgent developer-full-access-policy-check --output $developerPolicy } 'developer-full-access-policy-check'
Invoke-Checked { & $WinAgent release-hardening-deferred-ledger --output $releaseLedger --markdown-output $releaseLedgerMd } 'release-hardening-deferred-ledger'
Invoke-Checked { & $WinAgent capability-matrix-build --output $capabilityMatrix --markdown-output $capabilityMatrixMd } 'capability-matrix-build'
Invoke-Checked { & $WinAgent evidence-chain-verify --output $evidenceChain } 'evidence-chain-verify'
Invoke-Checked { & $WinAgent workflow-boundary-audit --output $workflowBoundary } 'workflow-boundary-audit'
Invoke-Checked { & $WinAgent version-integrity-check --output $versionIntegrity } 'version-integrity-check'
Invoke-Checked { & $WinAgent handoff-package-build --output $handoff } 'handoff-package-build'
Invoke-Checked { & $WinAgent developer-rc-gate --output $developerRcGate } 'developer-rc-gate'
Invoke-Checked { & $WinAgent v6-12-rc-handoff-check --output $handoffCheck } 'v6-12-rc-handoff-check'

$result = [ordered]@{
    schema_version = '6.12.0.rc_handoff_runner'
    status = 'RAW_COMPLETED_UNVERIFIED'
    runner_pass = $false
    developer_full_access_policy = $developerPolicy
    release_hardening_deferred_ledger = $releaseLedger
    capability_matrix = $capabilityMatrix
    evidence_chain = $evidenceChain
    workflow_boundary_audit = $workflowBoundary
    version_integrity = $versionIntegrity
    handoff_package = $handoff
    developer_rc_gate = $developerRcGate
    v6_12_rc_handoff_check = $handoffCheck
    old_ui_workflow_rerun = $false
    public_release_hardening_implemented = $false
    public_release_package_generated = $false
    stash_used = $false
    untracked_artifact_used_as_trusted_source = $false
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $RunnerResult -Encoding UTF8
$global:LASTEXITCODE = 0
Write-Host 'RAW_COMPLETED_UNVERIFIED'
