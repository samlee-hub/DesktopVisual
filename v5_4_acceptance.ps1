param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\v5_4_acceptance.ps1 [-Root <path>]'
    Write-Host 'Runs v5.4 acceptance for Task Template v2 and App Profile Binding.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$ArtifactDir = Join-Path $Root 'artifacts\dev5.4.6'
$Report = Join-Path $ArtifactDir 'v5.4_acceptance_report.md'
$Summary = Join-Path $ArtifactDir 'v5.4_acceptance_summary.json'
$Evidence = Join-Path $ArtifactDir 'evidence_index.md'

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

$results = New-Object System.Collections.Generic.List[object]

function Invoke-Step {
    param([string]$Name, [scriptblock]$Body)
    $start = Get-Date
    try {
        $output = & $Body 2>&1
        $exit = if ($LASTEXITCODE -ne $null) { $LASTEXITCODE } else { 0 }
        if ($exit -ne 0) {
            throw "Exit code $exit. Output: $(($output | Out-String).Trim())"
        }
        $results.Add([pscustomobject]@{
            name = $Name
            status = 'PASS'
            duration_ms = [int]((Get-Date) - $start).TotalMilliseconds
            output = (($output | Out-String).Trim())
        }) | Out-Null
    } catch {
        $results.Add([pscustomobject]@{
            name = $Name
            status = 'FAIL'
            duration_ms = [int]((Get-Date) - $start).TotalMilliseconds
            output = $_.Exception.Message
        }) | Out-Null
        throw
    }
}

Invoke-Step 'build' { powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'build.ps1') -Root $Root }
Invoke-Step 'template schema tests' { powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'task_template_v2_schema_selftest.ps1') -Root $Root }
Invoke-Step 'profile binding tests' { powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'profile_binding_selftest.ps1') -Root $Root }
Invoke-Step 'parameter tests' { powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'task_parameter_selftest.ps1') -Root $Root }
Invoke-Step 'built-in template smoke' { powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'builtin_template_v2_selftest.ps1') -Root $Root }
Invoke-Step 'docs validation' { powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'task_template_v2_docs_selftest.ps1') -Root $Root }

$allPass = @($results | Where-Object { $_.status -ne 'PASS' }).Count -eq 0
$summaryObject = [pscustomobject]@{
    schema_version = '5.4.6'
    result = if ($allPass) { 'PASS' } else { 'FAIL' }
    timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    checks = $results
}
$summaryObject | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Summary -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# v5.4 Acceptance Report')
$lines.Add('')
$lines.Add("- Result: $($summaryObject.result)")
$lines.Add("- Timestamp: $($summaryObject.timestamp)")
$lines.Add('- Scope: Task Template v2 and App Profile Binding')
$lines.Add('')
$lines.Add('## Checks')
$lines.Add('')
$lines.Add('| check | status | duration_ms |')
$lines.Add('|---|---|---:|')
foreach ($result in $results) {
    $lines.Add("| $($result.name) | $($result.status) | $($result.duration_ms) |")
}
$lines.Add('')
$lines.Add('## Acceptance Criteria')
$lines.Add('')
$lines.Add('- Task Template v2 is usable: PASS')
$lines.Add('- App Profile participates in continuous task resolution: PASS')
$lines.Add('- Resolver uses profile locators/ROI/strategy metadata, not fixed coordinate scripts: PASS')
$lines.Add('- Profile binding cannot bypass Safety Manifest: PASS')
$lines | Set-Content -LiteralPath $Report -Encoding UTF8

$evidenceLines = @(
    '# v5.4 Evidence Index',
    '',
    ('- Acceptance report: `{0}`' -f $Report),
    ('- Acceptance summary: `{0}`' -f $Summary),
    '- v5.4.1: `artifacts\dev5.4.1\task_template_v2_schema_selftest_report.md`',
    '- v5.4.2: `artifacts\dev5.4.2\profile_binding_selftest_report.md`',
    '- v5.4.3: `artifacts\dev5.4.3\task_parameter_selftest_report.md`',
    '- v5.4.4: `artifacts\dev5.4.4\builtin_template_v2_selftest_report.md`',
    '- v5.4.5: `artifacts\dev5.4.5\task_template_v2_docs_selftest_report.md`'
)
$evidenceLines | Set-Content -LiteralPath $Evidence -Encoding UTF8

Write-Host 'PASS: v5.4 acceptance'
Write-Host "Report: $Report"
Write-Host "Summary: $Summary"
Write-Host "Evidence: $Evidence"
