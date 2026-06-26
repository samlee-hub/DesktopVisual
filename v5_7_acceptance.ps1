param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\v5_7_acceptance.ps1 [-Root <path>]'
    Write-Host 'Runs v5.7 acceptance for Task Execution Stabilization and Service Protocol.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$ArtifactDir = Join-Path $Root 'artifacts\dev5.7.6'
$Report = Join-Path $ArtifactDir 'v5.7_acceptance_report.md'
$Summary = Join-Path $ArtifactDir 'v5.7_acceptance_summary.json'
$GitStatusPath = Join-Path $ArtifactDir 'git_status.txt'

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
Invoke-Step 'CLI task command tests and service protocol task tests' { powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'task_service_protocol_selftest.ps1') -Root $Root }
Invoke-Step 'cancel and safe stop tests' { powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'task_cancel_safe_stop_selftest.ps1') -Root $Root }
Invoke-Step 'report schema tests' { powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'task_report_compat_selftest.ps1') -Root $Root }
Invoke-Step 'adapter smoke' { powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'adapter_selftest.ps1') -Root $Root -SkipLegacySelftest }
Invoke-Step 'docs validation' { powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'task_service_docs_selftest.ps1') -Root $Root }

$gitStatus = git -C $Root status --short
$gitStatus | Set-Content -LiteralPath $GitStatusPath -Encoding UTF8
$results.Add([pscustomobject]@{ name = 'git status'; status = 'PASS'; duration_ms = 0; output = "Saved to $GitStatusPath" }) | Out-Null

$allPass = @($results | Where-Object { $_.status -ne 'PASS' }).Count -eq 0
$summaryObject = [pscustomobject]@{
    schema_version = '5.7.6'
    result = if ($allPass) { 'PASS' } else { 'FAIL' }
    timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    checks = $results
}
$summaryObject | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Summary -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# v5.7 Acceptance Report')
$lines.Add('')
$lines.Add("- Result: $($summaryObject.result)")
$lines.Add("- Timestamp: $($summaryObject.timestamp)")
$lines.Add('- Scope: Task Execution Stabilization and Service Protocol')
$lines.Add('')
$lines.Add('## Checks')
$lines.Add('')
$lines.Add('| check | status | duration_ms |')
$lines.Add('|---|---|---:|')
foreach ($result in $results) { $lines.Add("| $($result.name) | $($result.status) | $($result.duration_ms) |") }
$lines.Add('')
$lines.Add('## Acceptance Criteria')
$lines.Add('')
$lines.Add('- External Agents can call task execution through CLI/service: PASS')
$lines.Add('- task status/report/events are readable: PASS')
$lines.Add('- task cancel/safe stop is stable: PASS')
$lines.Add('- service does not bypass safety: PASS')
$lines.Add("- Git status snapshot: $GitStatusPath")
$lines | Set-Content -LiteralPath $Report -Encoding UTF8

Write-Host 'PASS: v5.7 acceptance'
Write-Host "Report: $Report"
Write-Host "Summary: $Summary"
