param(
    [string]$Root = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $Root 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$SelftestRoot = Join-Path $Root 'artifacts\dev6.9.0_system_stabilization\selftest\workflow_system_boundary'
$ReportJson = Join-Path $SelftestRoot 'workflow_system_boundary_selftest_report.json'
$ReportMd = [System.IO.Path]::ChangeExtension($ReportJson, '.md')
$NegativeJson = Join-Path $SelftestRoot 'workflow_system_boundary_runner_only_negative.json'
$ResultJson = Join-Path $SelftestRoot 'workflow_system_boundary_selftest_result.json'

function Fail($Message) { throw $Message }

if (!(Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run build.ps1 first." }
if (Test-Path -LiteralPath $SelftestRoot) { Remove-Item -LiteralPath $SelftestRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $SelftestRoot | Out-Null

$output = & $WinAgent workflow-boundary-check --output $ReportJson
$exit = $LASTEXITCODE
if ($exit -ne 0) { Fail "workflow-boundary-check failed with exit $exit output: $output" }
if (!(Test-Path -LiteralPath $ReportJson)) { Fail "Missing JSON report: $ReportJson" }
if (!(Test-Path -LiteralPath $ReportMd)) { Fail "Missing Markdown report: $ReportMd" }

$report = Get-Content -Raw -LiteralPath $ReportJson | ConvertFrom-Json
if ($report.status -ne 'PASS') { Fail "Expected PASS boundary report, got $($report.status)" }
foreach ($workflowType in @('explorer','browser_form','communication','vlm_observation','vlm_candidate','compiled_plan_execution')) {
    $entry = @($report.workflows | Where-Object { $_.workflow_type -eq $workflowType })[0]
    if ($null -eq $entry) { Fail "Missing workflow boundary entry: $workflowType" }
    if ($entry.status -notin @('PASS','PASS_ASSISTIVE_ONLY')) { Fail "Workflow $workflowType status was $($entry.status)" }
}

$negativeOutput = & $WinAgent workflow-boundary-check --output $NegativeJson --inject-runner-only-mock true
$negativeExit = $LASTEXITCODE
if ($negativeExit -eq 0) { Fail "runner-only negative check unexpectedly passed: $negativeOutput" }
$negative = Get-Content -Raw -LiteralPath $NegativeJson | ConvertFrom-Json
if ($negative.status -ne 'BLOCKED') { Fail "Expected negative BLOCKED status, got $($negative.status)" }
if ($negative.blocked_reason -ne 'BLOCKED_RUNNER_ONLY_WORKFLOW_DETECTED') { Fail "Unexpected negative blocked reason: $($negative.blocked_reason)" }

$result = [pscustomobject]@{
    schema_version = '6.9.0.system_stabilization.workflow_system_boundary_selftest'
    status = 'PASS'
    report_json = $ReportJson
    report_md = $ReportMd
    runner_only_mock_rejected = $true
    ui_workflow_executed = $false
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ResultJson -Encoding UTF8
'workflow_system_boundary_selftest PASS'
exit 0
