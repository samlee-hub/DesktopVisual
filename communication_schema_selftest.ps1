param(
    [string]$Root = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.9.0_communication_workflow'
$ArtifactDir = Join-Path $ArtifactRoot 'selftest\schema'
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

if (-not (Test-Path $WinAgent)) {
    & (Join-Path $Root 'build.ps1') | Out-Host
}

function Write-JsonFile($Path, $Object) {
    $Object | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Base-CommunicationSpec($Id, $Type) {
    return @{
        workflow_id = $Id
        task_id = "$Id-task"
        type = $Type
        recipient = 'qa@example.invalid'
        subject = "DesktopVisual $Type schema selftest"
        body = "DV_COMMUNICATION_CONTEXT_MARKER body for $Type"
        context_source = 'Fixture'
        expected_context = @{
            expected_process_pattern = 'winagent.exe'
            expected_title_pattern = 'communication_v6_9'
            required_markers = @('DV_COMMUNICATION_CONTEXT_MARKER')
            wrong_page_patterns = @('wrong-recipient')
            active_protection_patterns = @('captcha','human verification')
            credential_required_patterns = @('password','token')
            foreground_required = $false
            window_binding_required = $false
        }
        verification_hint = @{
            verify_type = 'verify_communication_created'
            expected_marker = 'DV_COMMUNICATION_CONTEXT_MARKER'
            expected_text = "DesktopVisual $Type schema selftest"
            expected_output_pattern = 'DV_COMMUNICATION_CONTEXT_MARKER'
            post_action_reobserve_required = $true
        }
        risk_level = 'REVERSIBLE_DRAFT'
        confirmation_policy = @{ confirmation_required = $false; confirmation_reason = ''; developer_full_access_allowed = $false; public_release_confirmation_required = $false; manual_handoff_required = $false }
        stop_policy = @{ stop_on_wrong_context = $true; stop_on_wrong_field = $true; stop_on_target_stale = $true; stop_on_target_not_unique = $true; stop_on_active_protection = $true; stop_on_credential_required = $true; stop_on_unverified_result = $true; stop_on_runtime_guard_failure = $true }
        recovery_policy = @{ recovery_allowed = $true; recovery_scope = 'communication_context_rebind'; recovery_target = 'same_context'; max_recovery_attempts = 1; resume_from_checkpoint_allowed = $true; replay_from_checkpoint_allowed = $false; stop_if_recovery_fails = $true }
        session_policy = @{ session_required = $true; session_reuse_allowed = $true; force_reobserve_before_action = $true; cache_policy = 'force_reobserve'; locator_cache_allowed = $false }
        evidence_policy = @{ raw_evidence_required = $true; verifier_required = $true; gate_required = $true; mouse_evidence_required = $false; latency_required = $true }
    }
}

function Invoke-Compile($Name, $Spec, [int]$ExpectedExit, [string]$ExpectedNeedle) {
    $input = Join-Path $ArtifactDir "$Name.workflow.json"
    $output = Join-Path $ArtifactDir "$Name.step_contract.json"
    $stdout = Join-Path $ArtifactDir "$Name.stdout.json"
    Write-JsonFile $input $Spec
    & $WinAgent compile-communication-workflow --input $input --output $output *> $stdout
    $exitCode = $LASTEXITCODE
    $text = Get-Content -Raw -LiteralPath $stdout
    if ($exitCode -ne $ExpectedExit) {
        throw "$Name expected exit $ExpectedExit, got $exitCode. Output: $text"
    }
    if ($ExpectedNeedle -and $text -notmatch [regex]::Escape($ExpectedNeedle)) {
        throw "$Name expected output to contain '$ExpectedNeedle'. Output: $text"
    }
    return [pscustomobject]@{ name = $Name; exit_code = $exitCode; output = $stdout; contract = $output }
}

$results = @()
$results += Invoke-Compile 'valid_draft' (Base-CommunicationSpec 'schema-draft' 'draft') 0 '"compile_ok":true'
$results += Invoke-Compile 'valid_message' (Base-CommunicationSpec 'schema-message' 'message') 0 '"compile_ok":true'
$results += Invoke-Compile 'valid_email' (Base-CommunicationSpec 'schema-email' 'email') 0 '"compile_ok":true'

$missingRecipient = Base-CommunicationSpec 'schema-missing-recipient' 'draft'
$missingRecipient.Remove('recipient')
$results += Invoke-Compile 'missing_recipient' $missingRecipient 1 'COMMUNICATION_SCHEMA_MISSING_RECIPIENT'

$badType = Base-CommunicationSpec 'schema-bad-type' 'send'
$results += Invoke-Compile 'unsupported_type' $badType 1 'COMMUNICATION_TYPE_UNSUPPORTED'

$external = Base-CommunicationSpec 'schema-external-api' 'email'
$external.requested_action_backend = 'external_provider_sdk'
$results += Invoke-Compile 'external_api_rejected' $external 1 'COMMUNICATION_EXTERNAL_API_REJECTED'

$summary = [pscustomobject]@{
    schema_version = '6.9.0.communication_workflow.schema_selftest'
    result = 'PASS'
    cases = $results
}
$summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ArtifactDir 'communication_schema_selftest_result.json') -Encoding UTF8

$lines = @('# v6.9.0 Communication Schema Report','')
$lines += '- result: PASS'
foreach ($case in $results) {
    $lines += "- $($case.name): exit=$($case.exit_code)"
}
$lines | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'schema_report.md') -Encoding UTF8

'communication_schema_selftest PASS'
