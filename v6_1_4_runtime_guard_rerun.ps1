param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$ArtifactRoot = Join-Path $Root 'artifacts\dev6.1.4_runtime_guard_browser_normalization'
$RawRoot = Join-Path $ArtifactRoot 'raw\runtime_guard_rerun'
New-Item -ItemType Directory -Force -Path $RawRoot | Out-Null

function Invoke-ScriptStep {
    param(
        [string]$Name,
        [string]$Script,
        [string[]]$Arguments = @()
    )
    $log = Join-Path $RawRoot "$Name.log"
    $start = Get-Date
    $header = @(
        "COMMAND: powershell -NoProfile -ExecutionPolicy Bypass -File $Script $($Arguments -join ' ')",
        "TIMESTAMP_START: $($start.ToString('o'))"
    )
    $header | Set-Content -LiteralPath $log -Encoding UTF8
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Script @Arguments 2>&1
    $exit = $LASTEXITCODE
    $ErrorActionPreference = $previousEap
    if ($output) { $output | Add-Content -LiteralPath $log -Encoding UTF8 }
    $end = Get-Date
    @(
        "TIMESTAMP_END: $($end.ToString('o'))",
        "EXIT_CODE: $exit"
    ) | Add-Content -LiteralPath $log -Encoding UTF8
    [pscustomobject]@{
        name = $Name
        script = $Script
        arguments = $Arguments
        exit_code = $exit
        log = $log
        started_at = $start.ToString('o')
        ended_at = $end.ToString('o')
    }
}

$steps = New-Object System.Collections.Generic.List[object]
$steps.Add((Invoke-ScriptStep 'runtime_context_guard_selftest' (Join-Path $Root 'runtime_context_guard_selftest.ps1') @('-Root', $Root))) | Out-Null
$steps.Add((Invoke-ScriptStep 'browser_surface_normalization_selftest' (Join-Path $Root 'browser_surface_normalization_selftest.ps1') @('-Root', $Root))) | Out-Null
$steps.Add((Invoke-ScriptStep 'v6_1_2_real_ui_baseline_verifier' (Join-Path $Root 'v6_1_2_real_ui_baseline_verifier.ps1') @('-Root', $Root))) | Out-Null
$steps.Add((Invoke-ScriptStep 'v6_1_2_pre_v6_2_acceptance_gate' (Join-Path $Root 'v6_1_2_pre_v6_2_acceptance_gate.ps1') @('-Root', $Root))) | Out-Null
$steps.Add((Invoke-ScriptStep 'v6_1_3_wheel_scroll_verifier' (Join-Path $Root 'v6_1_3_wheel_scroll_verifier.ps1') @('-Root', $Root))) | Out-Null
$steps.Add((Invoke-ScriptStep 'v6_1_3_scroll_acceptance_gate' (Join-Path $Root 'v6_1_3_scroll_acceptance_gate.ps1') @('-Root', $Root))) | Out-Null

$allPass = @($steps | Where-Object { $_.exit_code -ne 0 }).Count -eq 0
$summary = [pscustomobject]@{
    schema_version = 'v6.1.4.runtime_guard_rerun'
    generated_at = (Get-Date).ToString('o')
    status = if ($allPass) { 'PASS' } else { 'FAIL' }
    dynamic_app_web_diagnostic_only = $true
    pycharm_wechat_qq_mail_blocking = $false
    consumes_current_v6_1_2_raw_evidence = $true
    consumes_current_v6_1_3_raw_evidence = $true
    repeated_long_runners_inside_rerun = $false
    steps = @($steps.ToArray())
}
$summaryPath = Join-Path $ArtifactRoot 'runtime_guard_rerun_summary.json'
$summary | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

@(
    '# v6.1.4 Runtime Guard Rerun',
    '',
    "- Result: $($summary.status)",
    '- Scope: Runtime context guard, browser surface normalization, v6.1.2 baseline replay, v6.1.3 scroll gate.',
    '- Dynamic App/Web cases are diagnostic-only and not blockers in this rerun.',
    '',
    '| step | exit_code | log |',
    '|---|---:|---|'
) + (@($steps.ToArray()) | ForEach-Object { "| $($_.name) | $($_.exit_code) | $($_.log) |" }) |
    Set-Content -LiteralPath (Join-Path $ArtifactRoot 'runtime_guard_rerun_report.md') -Encoding UTF8

if ($allPass) {
    exit 0
}
exit 1
