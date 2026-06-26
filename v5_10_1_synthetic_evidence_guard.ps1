param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot

$ArtifactRoot = Join-Path $Root 'artifacts\dev5.10.1_real_ui_adaptive_cases'
$Runner = Join-Path $Root 'v5_10_1_real_ui_adaptive_cases_runner.ps1'
$VerifiedCases = Join-Path $ArtifactRoot 'verified\cases'
$Report = Join-Path $ArtifactRoot 'synthetic_evidence_guard_report.md'

$errors = New-Object System.Collections.Generic.List[string]

function Add-Finding([string]$Message) {
    $errors.Add($Message) | Out-Null
}

if (-not (Test-Path -LiteralPath $Runner)) {
    Add-Finding "Missing runner: $Runner"
} else {
    $runnerText = Get-Content -LiteralPath $Runner -Raw
    $runnerBanned = @(
        'Save-PlaceholderPng',
        'Add-AdaptiveStep',
        'actual_result\s*=\s*STRICT_',
        'actual_result"\s*:\s*"STRICT_',
        'ready_for_v6\s*=\s*\$?true',
        'ready_for_v6"\s*:\s*true',
        'backend_action_count\s*=\s*0',
        'cursor_inside_target_rect_before_click\s*=\s*\$?true'
    )
    foreach ($pattern in $runnerBanned) {
        if ($runnerText -match $pattern) {
            Add-Finding "Runner contains banned self-evidence pattern: $pattern"
        }
    }
    if ($runnerText -match '\bStart-Process\b') {
        Add-Finding 'Runner contains Start-Process.'
    }
    if ($runnerText -match '\bInvoke-Item\b') {
        Add-Finding 'Runner contains Invoke-Item.'
    }
    if ($runnerText -match 'UseShellExecute\s*=\s*\$?true' -or $runnerText -match '\bShellExecute\s*\(') {
        Add-Finding 'Runner contains ShellExecute action.'
    }
}

if (Test-Path -LiteralPath $VerifiedCases) {
    $taskResults = Get-ChildItem -LiteralPath $VerifiedCases -Recurse -Filter task_result.json -File
    foreach ($file in $taskResults) {
        try {
            $json = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        } catch {
            Add-Finding "Invalid task_result JSON: $($file.FullName): $($_.Exception.Message)"
            continue
        }
        if ($json.synthetic_evidence_detected -eq $true) { Add-Finding "Synthetic evidence detected in $($file.FullName)" }
        if ($json.placeholder_screenshot_detected -eq $true) { Add-Finding "Invalid screenshot detected in $($file.FullName)" }
        if ($json.hardcoded_rect_detected -eq $true) { Add-Finding "Hardcoded rect detected in $($file.FullName)" }
        if ($json.hardcoded_hwnd_detected -eq $true) { Add-Finding "Hardcoded hwnd detected in $($file.FullName)" }
        if ([int]$json.backend_action_count -gt 0) { Add-Finding "Backend actions detected in $($file.FullName)" }
        if ([int]$json.direct_launch_count -gt 0) { Add-Finding "Direct launch detected in $($file.FullName)" }
        if ([int]$json.js_dom_action_count -gt 0) { Add-Finding "JS/DOM action detected in $($file.FullName)" }
        if ([int]$json.webdriver_count -gt 0) { Add-Finding "WebDriver action detected in $($file.FullName)" }
        if ([int]$json.cdp_count -gt 0) { Add-Finding "CDP action detected in $($file.FullName)" }
        if ([int]$json.uia_invoke_action_count -gt 0) { Add-Finding "UIA InvokePattern action detected in $($file.FullName)" }
        if ([int]$json.uia_value_action_count -gt 0) { Add-Finding "UIA ValuePattern action detected in $($file.FullName)" }
        if ([int]$json.vlm_call_count -gt 0) { Add-Finding "VLM calls detected in $($file.FullName)" }
        if ([int]$json.active_protection_bypass_attempt_count -gt 0) { Add-Finding "Active protection bypass attempt detected in $($file.FullName)" }
    }
} else {
    Add-Finding "Verified cases directory missing: $VerifiedCases"
}

$status = if ($errors.Count -eq 0) { 'PASS' } else { 'FAIL' }
@(
    '# v5.10.1 Synthetic Evidence Guard',
    '',
    "- Result: $status",
    "- Checked runner: $Runner",
    "- Checked verified cases: $VerifiedCases",
    '',
    '## Findings',
    '',
    $(if ($errors.Count -eq 0) { '- None' } else { $errors | ForEach-Object { "- $_" } })
) | Set-Content -LiteralPath $Report -Encoding UTF8

if ($errors.Count -gt 0) {
    Write-Host "Synthetic evidence guard FAIL. Report: $Report"
    exit 1
}

Write-Host "Synthetic evidence guard PASS. Report: $Report"
exit 0
