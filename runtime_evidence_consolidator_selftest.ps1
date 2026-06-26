param(
    [string]$Root = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $Root 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$SelftestRoot = Join-Path $Root 'artifacts\dev6.9.0_system_stabilization\selftest\runtime_evidence_consolidator'
$FixtureRoot = Join-Path $SelftestRoot 'fixture_artifacts'
$ReportJson = Join-Path $SelftestRoot 'runtime_evidence_consolidator_selftest_report.json'
$ReportMd = [System.IO.Path]::ChangeExtension($ReportJson, '.md')
$ResultJson = Join-Path $SelftestRoot 'runtime_evidence_consolidator_selftest_result.json'

function Fail($Message) { throw $Message }
function Write-Utf8($Path, $Text) {
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Set-Content -LiteralPath $Path -Encoding UTF8 -Value $Text
}

if (!(Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run build.ps1 first." }
if (Test-Path -LiteralPath $SelftestRoot) { Remove-Item -LiteralPath $SelftestRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $FixtureRoot | Out-Null

$EvidenceDir = Join-Path $FixtureRoot 'dev6.9.0_fixture_feature'
$RuntimeSessions = Join-Path $FixtureRoot 'runtime_sessions'
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
New-Item -ItemType Directory -Force -Path $RuntimeSessions | Out-Null

Write-Utf8 (Join-Path $EvidenceDir 'final_status_report.md') '# fixture final status report'
Write-Utf8 (Join-Path $EvidenceDir 'evidence_index.md') @'
# Fixture Evidence Index

- runtime session: artifacts/runtime_sessions/rs-referenced.json
- gate: v6_9_0_acceptance_gate_report.md
'@
Write-Utf8 (Join-Path $EvidenceDir 'v6_9_0_acceptance_gate_report.md') '# fixture acceptance gate report'
Write-Utf8 (Join-Path $EvidenceDir 'execution_result.json') '{"final_status":"PASS","runtime_session_id":"rs-referenced"}'
Write-Utf8 (Join-Path $RuntimeSessions 'rs-referenced.json') '{"session_id":"rs-referenced","session_created_at":"2026-06-17 00:00:00"}'
Write-Utf8 (Join-Path $RuntimeSessions 'rs-unreferenced.json') '{"session_id":"rs-unreferenced","session_created_at":"2026-06-17 00:01:00"}'
Write-Utf8 (Join-Path $FixtureRoot 'temp.log') 'temporary fixture log'

$output = & $WinAgent evidence-consolidate --root $FixtureRoot --output $ReportJson
$exit = $LASTEXITCODE
if ($exit -ne 0) { Fail "evidence-consolidate failed with exit $exit output: $output" }
if (!(Test-Path -LiteralPath $ReportJson)) { Fail "Missing JSON report: $ReportJson" }
if (!(Test-Path -LiteralPath $ReportMd)) { Fail "Missing Markdown report: $ReportMd" }

$report = Get-Content -Raw -LiteralPath $ReportJson | ConvertFrom-Json
if ($report.status -ne 'PASS') { Fail "Expected PASS report status, got $($report.status)" }
foreach ($requiredType in @('final_report','acceptance_gate_report','evidence_index','runtime_session')) {
    if (@($report.inventory | Where-Object { $_.artifact_type -eq $requiredType }).Count -lt 1) {
        Fail "Missing artifact classification $requiredType"
    }
}

$protected = @($report.inventory | Where-Object { $_.artifact_type -in @('final_report','acceptance_gate_report','evidence_index') })
foreach ($item in $protected) {
    if ($item.safe_to_delete -eq $true) {
        Fail "Protected core evidence was marked deletable: $($item.artifact_path)"
    }
}

$unreferenced = @($report.unreferenced_runtime_sessions | Where-Object { $_ -like '*rs-unreferenced.json' })
if ($unreferenced.Count -ne 1) { Fail 'Unreferenced runtime session was not reported.' }

$result = [pscustomobject]@{
    schema_version = '6.9.0.system_stabilization.runtime_evidence_consolidator_selftest'
    status = 'PASS'
    report_json = $ReportJson
    report_md = $ReportMd
    protected_core_evidence_not_deletable = $true
    unreferenced_runtime_session_detected = $true
    ui_workflow_executed = $false
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ResultJson -Encoding UTF8
'runtime_evidence_consolidator_selftest PASS'
exit 0
