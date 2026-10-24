param(
    [string]$OutPath = ""
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root

$artifactDir = Join-Path $Root "artifacts\dev1.1.8_workspace_hygiene_field_test_readiness"
New-Item -ItemType Directory -Force -Path $artifactDir | Out-Null

if ([string]::IsNullOrWhiteSpace($OutPath)) {
    $OutPath = Join-Path $artifactDir "latency_baseline_v1_1_8.json"
}

$exe = Join-Path $Root "bin\winagent.exe"
if (-not (Test-Path -LiteralPath $exe)) {
    Write-Host "Latency baseline runner FAIL: bin\winagent.exe is missing; run .\build.ps1 first"
    exit 1
}

if (Test-Path -LiteralPath $OutPath) {
    Remove-Item -LiteralPath $OutPath -Force
}

$stdoutPath = Join-Path $artifactDir "latency_baseline_runner_stdout.json"
$output = & $exe latency-baseline --out $OutPath 2>&1
$exit = $LASTEXITCODE
$output | Out-File -LiteralPath $stdoutPath -Encoding UTF8

if ($exit -ne 0) {
    Write-Host "Latency baseline runner FAIL: winagent.exe latency-baseline exited $exit"
    exit $exit
}

if (-not (Test-Path -LiteralPath $OutPath)) {
    Write-Host "Latency baseline runner FAIL: baseline artifact was not written"
    exit 1
}

$summary = Get-Content -Raw -LiteralPath $OutPath | ConvertFrom-Json
if ($summary.version -ne "1.1.8" -or $null -eq $summary.scenarios -or $summary.scenarios.Count -lt 5 -or $summary.vlm_probe_attempted -ne $false -or $null -eq $summary.state_wait_total_ms -or $null -eq $summary.wait_timeout_count -or $null -eq $summary.workflow_wait_total_ms -or $null -eq $summary.workflow_wait_timeout_count) {
    Write-Host "Latency baseline runner FAIL: baseline artifact does not contain v1.1.8 no-probe, core wait, and workflow wait scenarios"
    exit 1
}

Write-Host "Latency baseline runner PASS: $OutPath"
exit 0
