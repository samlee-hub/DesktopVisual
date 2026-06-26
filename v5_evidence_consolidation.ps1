param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\v5_evidence_consolidation.ps1 [-Root <path>]'
    Write-Host 'Consolidates v5.0 through v5.7 evidence for v5.8.2.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$ArtifactDir = Join-Path $Root 'artifacts\dev5.8.2'
$Report = Join-Path $ArtifactDir 'v5_evidence_consolidation_report.md'
$Summary = Join-Path $ArtifactDir 'v5_evidence_consolidation_summary.json'

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

$items = @(
    @{ area='v5.0 task session evidence'; path='artifacts\dev5.0.6\v5.0_acceptance_report.md' },
    @{ area='v5.1 verification evidence'; path='artifacts\dev5.1.6\v5.1_acceptance_report.md' },
    @{ area='v5.2 recovery evidence'; path='artifacts\dev5.2.6\v5.2_acceptance_report.md' },
    @{ area='v5.3 confirmation evidence'; path='artifacts\dev5.3.6\v5.3_acceptance_report.md' },
    @{ area='v5.4 template/profile evidence'; path='artifacts\dev5.4.6\v5.4_acceptance_report.md' },
    @{ area='v5.5 file workflow evidence'; path='artifacts\dev5.5.6\v5.5_acceptance_report.md' },
    @{ area='v5.6 dogfood evidence'; path='artifacts\dev5.6.6\v5.6_acceptance_report.md' },
    @{ area='v5.7 service evidence'; path='artifacts\dev5.7.6\v5.7_acceptance_report.md' },
    @{ area='v5.6 dogfood summary'; path='artifacts\dev5.6.6\task_dogfood_summary.json' },
    @{ area='v5.7 service summary'; path='artifacts\dev5.7.6\v5.7_acceptance_summary.json' }
)

$records = New-Object System.Collections.Generic.List[object]
foreach ($item in $items) {
    $full = Join-Path $Root $item.path
    if (-not (Test-Path -LiteralPath $full)) { throw "Missing evidence path: $($item.path)" }
    if ($full.EndsWith('.json')) { Get-Content -LiteralPath $full -Raw | ConvertFrom-Json | Out-Null }
    $records.Add([pscustomobject]@{
        area = $item.area
        path = $full
        exists = $true
        size_bytes = (Get-Item -LiteralPath $full).Length
    }) | Out-Null
}

$summaryObject = [pscustomobject]@{
    schema_version = '5.8.2'
    result = 'PASS'
    timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    evidence_count = $records.Count
    evidence = $records
}
$summaryObject | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Summary -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# v5 Evidence Consolidation')
$lines.Add('')
$lines.Add('- Result: PASS')
$lines.Add("- Timestamp: $($summaryObject.timestamp)")
$lines.Add("- Summary: $Summary")
$lines.Add('')
$lines.Add('| area | evidence path |')
$lines.Add('|---|---|')
foreach ($record in $records) {
    $lines.Add("| $($record.area) | $($record.path) |")
}
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.8.2 evidence consolidation'
Write-Host "Report: $Report"
Write-Host "Summary: $Summary"
