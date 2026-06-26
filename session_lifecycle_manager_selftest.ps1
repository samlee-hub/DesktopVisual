param(
    [string]$Root = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $Root 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$SelftestRoot = Join-Path $Root 'artifacts\dev6.9.0_system_stabilization\selftest\session_lifecycle_manager'
$FixtureArtifacts = Join-Path $SelftestRoot 'fixture_artifacts'
$RuntimeSessions = Join-Path $FixtureArtifacts 'runtime_sessions'
$EvidenceDir = Join-Path $FixtureArtifacts 'dev6.9.0_fixture_feature'
$ReportJson = Join-Path $SelftestRoot 'session_lifecycle_manager_selftest_report.json'
$ReportMd = [System.IO.Path]::ChangeExtension($ReportJson, '.md')
$ResultJson = Join-Path $SelftestRoot 'session_lifecycle_manager_selftest_result.json'

function Fail($Message) { throw $Message }
function Write-Utf8($Path, $Text) {
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Set-Content -LiteralPath $Path -Encoding UTF8 -Value $Text
}

if (!(Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run build.ps1 first." }
if (Test-Path -LiteralPath $SelftestRoot) { Remove-Item -LiteralPath $SelftestRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $RuntimeSessions | Out-Null
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null

Write-Utf8 (Join-Path $EvidenceDir 'evidence_index.md') @'
# Fixture Evidence Index

- artifacts/runtime_sessions/rs-referenced.json
'@
Write-Utf8 (Join-Path $RuntimeSessions 'rs-referenced.json') '{"session_id":"rs-referenced","session_created_at":"2026-06-17 00:00:00"}'
Write-Utf8 (Join-Path $RuntimeSessions 'rs-stale-a.json') '{"session_id":"rs-stale-a","session_created_at":"2020-01-01 00:00:00","target_title":"same"}'
Write-Utf8 (Join-Path $RuntimeSessions 'rs-stale-b.json') '{"session_id":"rs-stale-b","session_created_at":"2020-01-01 00:00:00","target_title":"same"}'
(Get-Item -LiteralPath (Join-Path $RuntimeSessions 'rs-stale-a.json')).LastWriteTime = [datetime]'2020-01-01T00:00:00'
(Get-Item -LiteralPath (Join-Path $RuntimeSessions 'rs-stale-b.json')).LastWriteTime = [datetime]'2020-01-01T00:00:00'

$output = & $WinAgent session-lifecycle-audit --root $RuntimeSessions --output $ReportJson
$exit = $LASTEXITCODE
if ($exit -ne 0) { Fail "session-lifecycle-audit failed with exit $exit output: $output" }
if (!(Test-Path -LiteralPath $ReportJson)) { Fail "Missing JSON report: $ReportJson" }
if (!(Test-Path -LiteralPath $ReportMd)) { Fail "Missing Markdown report: $ReportMd" }

$report = Get-Content -Raw -LiteralPath $ReportJson | ConvertFrom-Json
if ($report.status -ne 'PASS') { Fail "Expected PASS report status, got $($report.status)" }
if ([int]$report.session_count -lt 3) { Fail "Expected at least 3 sessions." }

$referenced = @($report.sessions | Where-Object { $_.session_id -eq 'rs-referenced' })[0]
if ($null -eq $referenced) { Fail 'Referenced session missing from inventory.' }
if ($referenced.referenced_by_evidence -ne $true) { Fail 'Referenced session was not marked referenced.' }
if ($referenced.delete_recommended -eq $true -or $referenced.archive_recommended -eq $true) {
    Fail 'Referenced session was incorrectly recommended for archive/delete.'
}

$archivePlan = @($report.archive_plan)
if ($archivePlan.Count -lt 1) { Fail 'Archive plan was not generated.' }
$stale = @($report.sessions | Where-Object { $_.stale -eq $true })
if ($stale.Count -lt 1) { Fail 'No stale session was marked.' }

$result = [pscustomobject]@{
    schema_version = '6.9.0.system_stabilization.session_lifecycle_manager_selftest'
    status = 'PASS'
    report_json = $ReportJson
    report_md = $ReportMd
    archive_plan_generated = $true
    referenced_session_retained = $true
    ui_workflow_executed = $false
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ResultJson -Encoding UTF8
'session_lifecycle_manager_selftest PASS'
exit 0
