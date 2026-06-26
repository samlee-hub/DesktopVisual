param([string]$Root = '')

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.12.1_performance_timeline'
$Report = Join-Path $OutDir 'operation_timeline_profiler_selftest_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Fail([string]$Message) { throw $Message }
function Assert($Condition, [string]$Message) { if (-not $Condition) { Fail $Message } }

if (-not (Test-Path -LiteralPath $WinAgent)) {
    Fail "Missing $WinAgent. Run $Root\build.ps1 first."
}

$output = & $WinAgent operation-timeline-profiler-selftest
$exit = $LASTEXITCODE
$text = ($output | Out-String).Trim()
if ($exit -ne 0) {
    Fail "operation-timeline-profiler-selftest exited $exit with output: $text"
}

try {
    $json = $text | ConvertFrom-Json
} catch {
    Fail "operation-timeline-profiler-selftest did not emit JSON: $text"
}

Assert ($json.ok -eq $true) 'Profiler selftest command must return ok=true.'
Assert ($json.data.schema_version -eq 'operation_timeline.v1') 'Schema version mismatch.'
Assert ($json.data.required_fields.Count -ge 35) 'Required fields list is incomplete.'
Assert ($json.data.required_fields -contains 'wall_clock_ms') 'wall_clock_ms must be a required field.'
Assert ($json.data.required_fields -contains 'runtime_duration_ms') 'runtime_duration_ms must be a required field.'
Assert ($json.data.required_fields -contains 'orchestration_overhead_ms') 'orchestration_overhead_ms must be a required field.'
Assert ([int]$json.data.sample.orchestration_overhead_ms -eq 4800) 'Overhead calculation should be wall-runtime.'
Assert ($json.data.sample.external_orchestration_delay -eq $true) 'Short runtime plus long wall-clock must be classified as external orchestration delay.'
Assert ($json.data.sample.fixed_sleep_candidate -eq $true) 'Fixed sleep over 1000 ms should be classified as a candidate.'
Assert ([int]$json.data.category_totals.process_spawn_ms -eq 300) 'Category totals should include process_spawn_ms.'

@(
    '# Operation Timeline Profiler Selftest',
    '',
    '- result: PASS',
    '- schema_version: operation_timeline.v1',
    "- required_fields: $($json.data.required_fields.Count)",
    "- sample_orchestration_overhead_ms: $($json.data.sample.orchestration_overhead_ms)",
    "- external_orchestration_delay: $($json.data.sample.external_orchestration_delay)",
    "- fixed_sleep_candidate: $($json.data.sample.fixed_sleep_candidate)"
) | Set-Content -Encoding UTF8 -LiteralPath $Report

Write-Host 'PASS operation_timeline_profiler_selftest'
exit 0
