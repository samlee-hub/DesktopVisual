param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$Artifacts = Join-Path $Root 'artifacts\benchmark'
$SummaryPath = Join-Path $Artifacts 'benchmark_summary.json'
$ReportPath = Join-Path $Artifacts 'benchmark_report.md'
$Checks = New-Object System.Collections.Generic.List[object]

function Add-Check([string]$Name, [bool]$Ok, [string]$Detail) {
    $script:Checks.Add([pscustomobject]@{ Name = $Name; Ok = $Ok; Detail = $Detail })
    if ($Ok) { Write-Host "PASS: $Name - $Detail" -ForegroundColor Green }
    else { Write-Host "FAIL: $Name - $Detail" -ForegroundColor Red }
}

try {
    & (Join-Path $Root 'benchmark_matrix.ps1') -Root $Root
    Add-Check 'benchmark_matrix.ps1 runs' ($LASTEXITCODE -eq 0) 'matrix exit code 0'
} catch {
    Add-Check 'benchmark_matrix.ps1 runs' $false $_.Exception.Message
}

Add-Check 'benchmark_summary.json exists' (Test-Path -LiteralPath $SummaryPath) $SummaryPath
Add-Check 'benchmark_report.md exists' (Test-Path -LiteralPath $ReportPath) $ReportPath

$summary = $null
if (Test-Path -LiteralPath $SummaryPath) {
    $summary = Get-Content -LiteralPath $SummaryPath -Raw | ConvertFrom-Json
}

if ($summary) {
    $basic = @($summary.tasks | Where-Object { $_.name -eq 'testwindow_basic' })[0]
    Add-Check 'testwindow_basic PASS' ($basic.status -eq 'PASS') "status=$($basic.status)"

    $safety = @($summary.tasks | Where-Object { $_.name -eq 'safety_denied_window' })[0]
    $developerMode = @('DEVELOPER_CAPABILITY_DISCOVERY','DEVELOPER_FULL_RUNTIME') -contains [string]$summary.permission_mode
    $safetyOk = if ($developerMode) {
        $safety.status -eq 'PASS' -and $safety.outcome_kind -eq 'developer_permission_allowed'
    } else {
        $safety.status -eq 'PASS' -and $safety.outcome_kind -eq 'expected_safe_stop'
    }
    Add-Check 'safety_denied_window permission expectation' $safetyOk "status=$($safety.status) outcome=$($safety.outcome_kind) permission_mode=$($summary.permission_mode) error=$($safety.error_code)"

    Add-Check 'failures explicit or zero' ($summary.fail -eq 0 -or @($summary.tasks | Where-Object { $_.status -eq 'FAIL' -and $_.error_code }).Count -eq $summary.fail) "fail=$($summary.fail)"
} else {
    Add-Check 'summary parse' $false 'summary unavailable'
}

try {
    & (Join-Path $Root 'export_evidence_pack.ps1') -Root $Root
    Add-Check 'export_evidence_pack.ps1 runs' ($LASTEXITCODE -eq 0) 'export exit code 0'
} catch {
    Add-Check 'export_evidence_pack.ps1 runs' $false $_.Exception.Message
}

$version = (Get-Content -LiteralPath (Join-Path $Root 'VERSION') -Raw).Trim()
$zip = Join-Path $Root "artifacts\evidence\DesktopVisual-v$version-evidence-pack.zip"
Add-Check 'evidence zip exists' (Test-Path -LiteralPath $zip) $zip

if (Test-Path -LiteralPath $zip) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
    try {
        $bad = @($archive.Entries | Where-Object { $_.FullName -match '(^|/)(bin|obj|dist|profile|edge_profile|browser_profile|Cache|GPUCache)/' })
        Add-Check 'evidence zip excludes generated/profile dirs' ($bad.Count -eq 0) "bad_entries=$($bad.Count)"
    } finally {
        $archive.Dispose()
    }
}

$failed = @($Checks | Where-Object { -not $_.Ok })
if ($failed.Count -gt 0) { exit 1 }
exit 0
