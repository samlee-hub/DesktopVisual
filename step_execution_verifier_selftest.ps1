param(
    [string]$Root = '',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$EvidenceRoot = Join-Path $Root 'artifacts\dev6.4.0_runtime_task_execution_from_compiled_agent_plan'
$CaseDir = Join-Path $EvidenceRoot 'selftest\step_execution_verifier'
New-Item -ItemType Directory -Force -Path $CaseDir | Out-Null

if (-not $SkipBuild) {
    & (Join-Path $Root 'build.ps1') -Root $Root
}

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$Input = Join-Path $CaseDir 'verifier_input.json'
$Output = Join-Path $CaseDir 'verifier_result.json'

@'
{
  "step_id": "verify-field",
  "step_index": 0,
  "runtime_action": "type_text",
  "target": "field1",
  "input_text": "alpha",
  "verification_hint": {
    "verify_type": "verify_field_value",
    "expected_marker": "",
    "expected_text": "",
    "expected_window_title": "",
    "expected_url_pattern": "",
    "expected_output_pattern": "",
    "expected_field_value": "alpha",
    "post_action_reobserve_required": true
  },
  "execution_state": {
    "context_text": "field1 alpha",
    "field_value": "alpha",
    "window_title": "mock form",
    "url": "file:///mock-form.html",
    "output_text": ""
  }
}
'@ | Set-Content -Encoding UTF8 $Input

& $WinAgent step-execution-verify --input $Input --output $Output | Out-File -Encoding utf8 (Join-Path $CaseDir 'verify.stdout.json')
if ($LASTEXITCODE -ne 0) {
    throw "step-execution-verify failed with exit code $LASTEXITCODE"
}

$json = Get-Content -Raw $Output | ConvertFrom-Json
if (-not $json.verification_ok) { throw 'verification_ok was not true' }
if ($json.verification_type -ne 'verify_field_value') { throw 'unexpected verification_type' }

"STEP_EXECUTION_VERIFIER_SELFTEST_PASS"
