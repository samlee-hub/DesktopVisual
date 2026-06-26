param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\v5_5_acceptance.ps1 [-Root <path>]'
    Write-Host 'Runs v5.5 acceptance for file, attachment, and cross-window workflows.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$ArtifactDir = Join-Path $Root 'artifacts\dev5.5.6'
$Report = Join-Path $ArtifactDir 'v5.5_acceptance_report.md'
$Summary = Join-Path $ArtifactDir 'v5.5_acceptance_summary.json'
$Evidence = Join-Path $ArtifactDir 'evidence_index.md'

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

$results = New-Object System.Collections.Generic.List[object]

function Invoke-Step {
    param([string]$Name, [scriptblock]$Body)
    $start = Get-Date
    try {
        $output = & $Body 2>&1
        $exit = if ($LASTEXITCODE -ne $null) { $LASTEXITCODE } else { 0 }
        if ($exit -ne 0) { throw "Exit code $exit. Output: $(($output | Out-String).Trim())" }
        $results.Add([pscustomobject]@{ name = $Name; status = 'PASS'; duration_ms = [int]((Get-Date) - $start).TotalMilliseconds; output = (($output | Out-String).Trim()) }) | Out-Null
    } catch {
        $results.Add([pscustomobject]@{ name = $Name; status = 'FAIL'; duration_ms = [int]((Get-Date) - $start).TotalMilliseconds; output = $_.Exception.Message }) | Out-Null
        throw
    }
}

Invoke-Step 'build' { powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'build.ps1') -Root $Root }
Invoke-Step 'file path tests' { powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'file_path_resolver_selftest.ps1') -Root $Root }
Invoke-Step 'file picker tests' { powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'file_picker_flow_selftest.ps1') -Root $Root }
Invoke-Step 'upload verification tests' { powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'upload_verification_selftest.ps1') -Root $Root }
Invoke-Step 'cross-window tests' { powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'cross_window_context_selftest.ps1') -Root $Root }
Invoke-Step 'local mail mock attach flow' { powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'local_mail_attach_flow_selftest.ps1') -Root $Root }
Invoke-Step 'safety tests' { powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'file_workflow_docs_selftest.ps1') -Root $Root }

$allPass = @($results | Where-Object { $_.status -ne 'PASS' }).Count -eq 0
$summaryObject = [pscustomobject]@{
    schema_version = '5.5.6'
    result = if ($allPass) { 'PASS' } else { 'FAIL' }
    timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    checks = $results
}
$summaryObject | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Summary -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# v5.5 Acceptance Report')
$lines.Add('')
$lines.Add("- Result: $($summaryObject.result)")
$lines.Add("- Timestamp: $($summaryObject.timestamp)")
$lines.Add('- Scope: File / Attachment / Cross-window Controlled Workflow')
$lines.Add('')
$lines.Add('## Checks')
$lines.Add('')
$lines.Add('| check | status | duration_ms |')
$lines.Add('|---|---|---:|')
foreach ($result in $results) { $lines.Add("| $($result.name) | $($result.status) | $($result.duration_ms) |") }
$lines.Add('')
$lines.Add('## Acceptance Criteria')
$lines.Add('')
$lines.Add('- Controlled mock attachment through file picker: PASS')
$lines.Add('- Upload completion and failure states are verified: PASS')
$lines.Add('- File picker cross-window context is handled: PASS')
$lines.Add('- Real email sending is not performed: PASS')
$lines.Add('- Dangerous paths and sensitive externalization defaults are blocked: PASS')
$lines | Set-Content -LiteralPath $Report -Encoding UTF8

$evidenceLines = @(
    '# v5.5 Evidence Index',
    '',
    ('- Acceptance report: `{0}`' -f $Report),
    ('- Acceptance summary: `{0}`' -f $Summary),
    '- v5.5.1: `artifacts\dev5.5.1\file_path_resolver_selftest_report.md`',
    '- v5.5.2: `artifacts\dev5.5.2\file_picker_flow_selftest_report.md`',
    '- v5.5.3: `artifacts\dev5.5.3\upload_verification_selftest_report.md`',
    '- v5.5.4: `artifacts\dev5.5.4\cross_window_context_selftest_report.md`',
    '- v5.5.5: `artifacts\dev5.5.5\file_workflow_docs_selftest_report.md`',
    '- v5.5.6: `artifacts\dev5.5.6\local_mail_attach_flow_selftest_report.md`'
)
$evidenceLines | Set-Content -LiteralPath $Evidence -Encoding UTF8

Write-Host 'PASS: v5.5 acceptance'
Write-Host "Report: $Report"
Write-Host "Summary: $Summary"
Write-Host "Evidence: $Evidence"
