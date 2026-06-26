param(
    [string]$Root = '',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

function Fail([string]$Message) {
    Write-Error $Message
    exit 1
}

if (-not $SkipBuild) {
    & (Join-Path $Root 'build.ps1') -Root $Root
    if ($LASTEXITCODE -ne 0) { Fail 'build.ps1 failed.' }
}

$matrix = Join-Path $Root 'dogfood_matrix.ps1'
& $matrix -Root $Root -SkipBuild
if ($LASTEXITCODE -ne 0) { Fail 'dogfood_matrix.ps1 failed.' }

$report = Join-Path $Root 'artifacts\dogfood\dogfood_report.md'
$summaryPath = Join-Path $Root 'artifacts\dogfood\dogfood_summary.json'
if (-not (Test-Path -LiteralPath $report)) { Fail "Missing dogfood report: $report" }
if (-not (Test-Path -LiteralPath $summaryPath)) { Fail "Missing dogfood summary: $summaryPath" }

$summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
$tasks = @($summary.tasks)
$required = @('notepad', 'calculator', 'explorer', 'local_html', 'powershell', 'vscode')
foreach ($taskId in $required) {
    $task = @($tasks | Where-Object { $_.task_id -eq $taskId }) | Select-Object -First 1
    if (-not $task) { Fail "Missing dogfood task in summary: $taskId" }
    foreach ($field in @('status', 'safety_boundary', 'expected_result', 'skipped_condition')) {
        if (-not $task.$field) { Fail "Task $taskId missing $field." }
    }
    if (@('PASS', 'FAIL', 'SKIPPED') -notcontains $task.status) {
        Fail "Task $taskId has invalid status $($task.status)."
    }
}

$pass = @($tasks | Where-Object { $_.status -eq 'PASS' }).Count
$fail = @($tasks | Where-Object { $_.status -eq 'FAIL' }).Count
$skipped = @($tasks | Where-Object { $_.status -eq 'SKIPPED' }).Count
if ($summary.total -ne $tasks.Count) { Fail 'Summary total does not match task count.' }
if ($summary.pass -ne $pass -or $summary.fail -ne $fail -or $summary.skipped -ne $skipped) {
    Fail 'Summary PASS/FAIL/SKIPPED counts do not match tasks.'
}
if ($fail -gt 0) { Fail 'Dogfood summary contains FAIL entries.' }

$reportText = Get-Content -LiteralPath $report -Raw
foreach ($needle in @('Safety Boundary', 'Expected Result', 'SKIPPED Condition', 'bounded confidence')) {
    if ($reportText -notmatch [regex]::Escape($needle)) {
        Fail "Dogfood report missing required text: $needle"
    }
}

Write-Host 'Dogfood selftest passed.'
