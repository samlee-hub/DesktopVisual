param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\task_dogfood_report_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates v5.6 task-level dogfood report and artifacts.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$ArtifactDir = Join-Path $Root 'artifacts\dev5.6.6'
$Report = Join-Path $ArtifactDir 'task_dogfood_report.md'
$Summary = Join-Path $ArtifactDir 'task_dogfood_summary.json'
$SelftestReport = Join-Path $ArtifactDir 'task_dogfood_report_selftest_report.md'

if (-not (Test-Path -LiteralPath $Report)) { throw "Missing dogfood report: $Report" }
if (-not (Test-Path -LiteralPath $Summary)) { throw "Missing dogfood summary: $Summary" }

$summaryJson = Get-Content -LiteralPath $Summary -Raw | ConvertFrom-Json
$reportText = Get-Content -LiteralPath $Report -Raw

foreach ($marker in @('task states','step results','recovery attempts','confirmations','latency','artifacts','failure reasons','Audit path','Latency Summary','Skip Justification')) {
    if ($reportText -notmatch [regex]::Escape($marker)) {
        throw "Report missing marker: $marker"
    }
}

$cases = @($summaryJson.cases)
$pass = @($cases | Where-Object { $_.status -eq 'PASS' }).Count
$fail = @($cases | Where-Object { $_.status -eq 'FAIL' }).Count
$skip = @($cases | Where-Object { $_.status -eq 'SKIPPED' }).Count
if ($summaryJson.total -ne $cases.Count) { throw 'Summary total mismatch.' }
if ($summaryJson.pass -ne $pass -or $summaryJson.fail -ne $fail -or $summaryJson.skipped -ne $skip) { throw 'Summary counts mismatch.' }
if ($pass -lt 4) { throw "Expected at least 4 PASS cases, got $pass" }
if ($fail -ne 0) { throw "Expected no FAIL cases, got $fail" }
if (-not $summaryJson.latency_summary -or $summaryJson.latency_summary.measured -ne $true) { throw 'Missing measured latency summary.' }
if ([int]$summaryJson.latency_summary.suite_duration_ms -lt 0) { throw 'Invalid suite latency.' }

$requiredCases = @(
    'local_form_fill_submit',
    'notepad_edit_verify',
    'local_problem_page_run_read_result',
    'compile_runtime_error_mock',
    'local_mail_mock_attachment_flow',
    'explorer_file_select_flow',
    'powershell_run_read_report_flow'
)
foreach ($required in $requiredCases) {
    if (-not (@($cases | Where-Object { $_.case_id -eq $required }).Count)) {
        throw "Missing required dogfood case: $required"
    }
}

foreach ($case in $cases) {
    if (-not $case.evidence_path -or -not (Test-Path -LiteralPath $case.evidence_path)) {
        throw "Missing evidence artifact for $($case.case_id)"
    }
    foreach ($artifact in @($case.artifacts)) {
        if ($artifact -and -not (Test-Path -LiteralPath $artifact)) {
            throw "Case $($case.case_id) references missing artifact: $artifact"
        }
    }
    if ($case.fixed_coordinates_used -ne $false) { throw "Case used fixed coordinates: $($case.case_id)" }
    if ($case.external_high_risk_operation -ne $false) { throw "Case used high-risk external operation: $($case.case_id)" }
    if ($case.real_external -ne $false) { throw "Case was marked real_external: $($case.case_id)" }
    if (-not $case.workflow_scope) { throw "Case missing workflow_scope: $($case.case_id)" }
    if ($case.status -eq 'SKIPPED' -and -not $case.skip_justification) { throw "Skipped case missing justification: $($case.case_id)" }
    if ([int]$case.latency_ms -lt 0) { throw "Case has invalid latency: $($case.case_id)" }
}

$lines = @(
    '# v5.6 Dogfood Report Selftest',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "- PASS cases: $pass",
    "- SKIPPED cases: $skip",
    '- report parse: PASS',
    '- artifact existence: PASS',
    '- latency summary validation: PASS',
    '- required case registry validation: PASS',
    '- mock/local/real external distinction: PASS',
    '- SKIP justification validation: PASS'
)
$lines | Set-Content -LiteralPath $SelftestReport -Encoding UTF8
Write-Host 'PASS: v5.6 dogfood report selftest'
Write-Host "Report: $SelftestReport"
