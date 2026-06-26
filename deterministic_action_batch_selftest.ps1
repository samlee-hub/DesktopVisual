param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.12.1_visible_ui_foundation_hardening'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Invoke-Agent([string[]]$WinArgs, [int[]]$Allowed = @(0)) {
    $output = & $WinAgent @WinArgs
    $exit = $LASTEXITCODE
    if ($Allowed -notcontains $exit) { throw "winagent $($WinArgs -join ' ') exited $exit with output: $output" }
    return $output | ConvertFrom-Json
}
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }

$plan = Join-Path $OutDir 'visible_action_batch_plan.json'
$result = Join-Path $OutDir 'visible_action_batch_result.json'
@'
{
  "dry_run": true,
  "target": { "title": "dry-run-target", "allow_dry_run_target": true },
  "steps": [
    { "action": "foreground-preempt" },
    { "action": "acquire-target-lock" },
    { "action": "global-screenshot" },
    { "action": "focus-input" },
    { "action": "type-text", "text": "hello" },
    { "action": "wait-condition", "condition": "wait-until-text-visible", "text": "hello", "timeout_ms": 1000 },
    { "action": "global-verification-screenshot" },
    { "action": "result-extraction" }
  ]
}
'@ | Set-Content -Encoding UTF8 -LiteralPath $plan

$batch = Invoke-Agent -WinArgs @('visible-action-batch', '--plan', $plan, '--out', $result)
Assert ($batch.ok -eq $true) 'visible-action-batch dry-run should pass.'
Assert ($batch.data.deterministic_action_batch -eq $true) 'batch flag missing.'
Assert ($batch.data.outer_process_roundtrips_reduced -eq $true) 'batch must report reduced outer roundtrips.'
Assert (Test-Path -LiteralPath $result) 'batch result file missing.'

$badPlan = Join-Path $OutDir 'visible_action_batch_fixed_sleep_plan.json'
$badResult = Join-Path $OutDir 'visible_action_batch_fixed_sleep_result.json'
@'
{
  "dry_run": true,
  "steps": [
    { "action": "fixed-sleep", "duration_ms": 5000 }
  ]
}
'@ | Set-Content -Encoding UTF8 -LiteralPath $badPlan

$bad = Invoke-Agent -WinArgs @('visible-action-batch', '--plan', $badPlan, '--out', $badResult) -Allowed @(1)
Assert ($bad.ok -eq $false) 'fixed sleep batch should fail.'
Assert ($bad.error.code -eq 'FAIL_BATCH_WAIT_TIMEOUT') 'fixed sleep failure code mismatch.'

$report = Join-Path $OutDir 'deterministic_action_batch_report.md'
@(
    '# Deterministic Action Batch Selftest',
    '',
    '- result: PASS',
    '- dry-run batch plan: PASS',
    '- fixed sleep rejection: PASS'
) | Set-Content -Encoding UTF8 -LiteralPath $report
Write-Host "PASS deterministic_action_batch_selftest"
exit 0
