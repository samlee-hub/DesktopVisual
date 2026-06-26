param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\recovery_escalation_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates v5.2.3 EscalationRequest generation.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.2.3'
$Report = Join-Path $ArtifactDir 'recovery_escalation_selftest_report.md'
$Semantic = Join-Path $Root 'tasks\recovery_policy\escalation_semantic_unresolved.json'
$Unknown = Join-Path $Root 'tasks\recovery_policy\escalation_unknown_scene.json'
$NoProvider = Join-Path $Root 'tasks\recovery_policy\escalation_no_provider.json'

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

foreach ($path in @($Semantic, $Unknown, $NoProvider)) {
    Get-Content -LiteralPath $path -Raw | ConvertFrom-Json | Out-Null
}

function New-Escalation {
    param(
        [string]$Reason,
        [string]$Context
    )
    $output = & $WinAgent escalation-request-create --reason $Reason --task local_form_fill_submit_mock --step click_submit_and_verify --context $Context
    if ($LASTEXITCODE -ne 0) {
        throw "escalation-request-create failed for $Reason. Output: $output"
    }
    $json = $output | ConvertFrom-Json
    if (-not $json.ok) { throw "escalation-request-create returned ok=false for $Reason" }
    foreach ($field in @('reason', 'current_task', 'current_step', 'scene_state', 'candidate_count', 'screenshot_artifact', 'element_graph_artifact', 'risk_level', 'recommended_action', 'fallback_if_provider_unavailable')) {
        if ($null -eq $json.data.$field) { throw "EscalationRequest missing $field for $Reason" }
    }
    return $output
}

$semanticOutput = New-Escalation -Reason 'semantic_unresolved' -Context $Semantic
$semanticJson = $semanticOutput | ConvertFrom-Json
if ($semanticJson.data.recommended_action -ne 'escalate_to_agent') { throw "Expected semantic_unresolved to recommend escalate_to_agent." }
if ($semanticJson.data.allowed_routes -notcontains 'escalate_to_agent') { throw 'semantic_unresolved missing escalate_to_agent route.' }

$unknownOutput = New-Escalation -Reason 'unknown_scene' -Context $Unknown
$unknownJson = $unknownOutput | ConvertFrom-Json
if ($unknownJson.data.recommended_action -ne 'ask_user') { throw "Expected unknown_scene to recommend ask_user." }

$noProviderOutput = New-Escalation -Reason 'semantic_unresolved' -Context $NoProvider
$noProviderJson = $noProviderOutput | ConvertFrom-Json
if ($noProviderJson.data.recommended_action -ne 'ask_user') { throw "Expected no-provider case to recommend ask_user." }
if ($noProviderJson.data.fallback_if_provider_unavailable -ne 'ask_user_or_stop') { throw 'Expected no provider fallback ask_user_or_stop.' }
if ($noProviderJson.data.allowed_routes -contains 'escalate_to_agent') { throw 'No-provider case must not allow escalate_to_agent.' }

$lines = @(
    '# v5.2.3 Escalation Selftest Report',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    '- semantic_unresolved mock: PASS',
    '- unknown_scene mock: PASS',
    '- no provider fallback: PASS',
    '',
    '## Outputs',
    '',
    '```json',
    $semanticOutput,
    $unknownOutput,
    $noProviderOutput,
    '```'
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.2.3 Escalation selftest'
Write-Host "Report: $Report"
