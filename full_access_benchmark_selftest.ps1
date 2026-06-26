param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$Artifacts = Join-Path $Root 'artifacts\benchmark\full_access'
$SummaryPath = Join-Path $Artifacts 'full_access_benchmark_summary.json'
$ReportPath = Join-Path $Artifacts 'full_access_benchmark_report.md'
$Checks = New-Object System.Collections.Generic.List[object]

function Add-Check([string]$Name, [bool]$Ok, [string]$Detail) {
    $script:Checks.Add([pscustomobject]@{ Name = $Name; Ok = $Ok; Detail = $Detail }) | Out-Null
    if ($Ok) { Write-Host "PASS: $Name - $Detail" }
    else { Write-Host "FAIL: $Name - $Detail" }
}

try {
    & (Join-Path $Root 'full_access_benchmark_matrix.ps1') -Root $Root
    Add-Check 'full_access_benchmark_matrix.ps1 runs' ($LASTEXITCODE -eq 0) 'matrix exit code 0'
} catch {
    Add-Check 'full_access_benchmark_matrix.ps1 runs' $false $_.Exception.Message
}

Add-Check 'summary exists' (Test-Path -LiteralPath $SummaryPath) $SummaryPath
Add-Check 'report exists' (Test-Path -LiteralPath $ReportPath) $ReportPath

$summary = $null
if (Test-Path -LiteralPath $SummaryPath) {
    try { $summary = Get-Content -LiteralPath $SummaryPath -Raw | ConvertFrom-Json } catch { $summary = $null }
}
Add-Check 'summary parses' ($null -ne $summary) 'ConvertFrom-Json'

if ($summary) {
    $required = @(
        'permission_mode_default_denied',
        'full_access_unlock',
        'global_app_launch',
        'external_web_navigation',
        'form_semantics_mixed',
        'decision_task_form',
        'checkpoint_loop_guard',
        'communication_simulated',
        'coding_workflow_simulated',
        'assessment_permission_notice'
    )
    foreach ($name in $required) {
        $scenario = @($summary.scenarios | Where-Object { $_.name -eq $name })[0]
        Add-Check "scenario $name present" ($null -ne $scenario) "status=$($scenario.status)"
    }

    Add-Check 'no FAIL scenarios' ([int]$summary.fail -eq 0) "fail=$($summary.fail)"
    Add-Check 'PASS present' ([int]$summary.pass -gt 0) "pass=$($summary.pass)"
    Add-Check 'SKIPPED semantics present' (@($summary.scenarios | Where-Object { $_.status -eq 'SKIPPED' -and $_.skipped_reason }).Count -ge 1) 'interactive unlock expected'

    $metricNames = @(
        'full_access_unlock_success',
        'permission_mode_success',
        'form_control_classification_accuracy',
        'decision_task_success_rate',
        'loop_guard_trigger_success',
        'user_takeover_trigger_success',
        'communication_simulation_success',
        'coding_workflow_success',
        'stop_condition_success_rate',
        'report_completeness_score'
    )
    foreach ($metric in $metricNames) {
        Add-Check "metric $metric exists" ($summary.metrics.PSObject.Properties.Name -contains $metric) "$metric"
    }
    Add-Check 'form classification accuracy is 100' ([double]$summary.metrics.form_control_classification_accuracy -eq 100) "accuracy=$($summary.metrics.form_control_classification_accuracy)"
    Add-Check 'coding workflow success' ($summary.metrics.coding_workflow_success -eq $true) "coding=$($summary.metrics.coding_workflow_success)"
    Add-Check 'communication simulation success' ($summary.metrics.communication_simulation_success -eq $true) "communication=$($summary.metrics.communication_simulation_success)"
    Add-Check 'loop guard trigger success' ($summary.metrics.loop_guard_trigger_success -eq $true) "loop=$($summary.metrics.loop_guard_trigger_success)"
    Add-Check 'stop condition success rate nonzero' ([double]$summary.metrics.stop_condition_success_rate -gt 0) "stop_rate=$($summary.metrics.stop_condition_success_rate)"
    Add-Check 'report completeness score nonzero' ([double]$summary.metrics.report_completeness_score -gt 0) "score=$($summary.metrics.report_completeness_score)"
}

try {
    & (Join-Path $Root 'export_full_access_evidence_pack.ps1') -Root $Root
    Add-Check 'export_full_access_evidence_pack.ps1 runs' ($LASTEXITCODE -eq 0) 'export exit code 0'
} catch {
    Add-Check 'export_full_access_evidence_pack.ps1 runs' $false $_.Exception.Message
}

$zip = Join-Path $Root 'artifacts\evidence\DesktopVisual-v3.3.10-full-access-evidence-pack.zip'
Add-Check 'full access evidence zip exists' (Test-Path -LiteralPath $zip) $zip

if (Test-Path -LiteralPath $zip) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
    try {
        $entries = @($archive.Entries | ForEach-Object { $_.FullName -replace '\\','/' })
        foreach ($requiredEntry in @(
            'full_access_benchmark_report.md',
            'full_access_benchmark_summary.json',
            'VERSION',
            'CHANGELOG.md',
            'docs/SAFETY_MODEL.md',
            'docs/KNOWN_LIMITATIONS.md',
            'docs/DECISION_TASK_RUNTIME.md',
            'docs/FORM_SEMANTICS.md',
            'docs/CODING_WORKFLOW.md',
            'docs/COMMUNICATION_RUNTIME.md'
        )) {
            Add-Check "evidence contains $requiredEntry" ($entries -contains $requiredEntry) $requiredEntry
        }
        $bad = @($entries | Where-Object { $_ -match '(^|/)(bin|obj|dist|browser_profile|edge_profile|Cache|GPUCache|raw|motion_profile/raw)/' })
        Add-Check 'evidence excludes sensitive/generated dirs' ($bad.Count -eq 0) "bad_entries=$($bad.Count)"
    } finally {
        $archive.Dispose()
    }
}

$failed = @($Checks | Where-Object { -not $_.Ok })
if ($failed.Count -gt 0) { exit 1 }
exit 0
