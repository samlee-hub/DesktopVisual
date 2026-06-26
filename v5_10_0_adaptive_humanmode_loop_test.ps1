param(
    [string]$Root = '',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'

if (-not $SkipBuild) {
    & (Join-Path $Root 'build.ps1') -Root $Root
    if ($LASTEXITCODE -ne 0) { throw 'build failed' }
}

if (-not (Test-Path $WinAgent)) {
    throw "winagent.exe not found: $WinAgent"
}

function Invoke-WinAgentJson {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    $output = & $WinAgent @Args
    if ($LASTEXITCODE -ne 0) {
        throw "winagent failed ($($Args -join ' ')): $output"
    }
    try {
        return ($output | Out-String | ConvertFrom-Json)
    } catch {
        throw "invalid JSON for ($($Args -join ' ')): $output"
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Eq {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) {
        throw "$Message expected=[$Expected] actual=[$Actual]"
    }
}

$results = [ordered]@{}

$candidate = Invoke-WinAgentJson adaptive-run-step --diagnostic candidate-validation
Assert-True $candidate.ok 'candidate validation diagnostic failed'
Assert-Eq $candidate.data.good_candidate_accepted $true 'good candidate must be accepted'
foreach ($reason in @('TARGET_OFFSCREEN','WRONG_WINDOW','TARGET_IN_FORBIDDEN_REGION','TARGET_RECT_MISSING','MULTIPLE_CANDIDATES_LOW_CONFIDENCE')) {
    Assert-True ($candidate.data.rejection_reasons -contains $reason) "missing rejection reason $reason"
}
$results.candidate_validation = 'PASS'

$mapping = Invoke-WinAgentJson adaptive-run-step --diagnostic coordinate-mapping
Assert-True $mapping.ok 'coordinate mapping diagnostic failed'
Assert-Eq $mapping.data.window_relative_screen_rect.left 110 'window relative left mapping'
Assert-Eq $mapping.data.screenshot_screen_rect.left 120 'screenshot left mapping'
Assert-Eq $mapping.data.inside_rect $true 'inside rect check'
Assert-Eq $mapping.data.dpi_scale_tolerant $true 'dpi scale tolerant mapping'
$results.coordinate_mapping = 'PASS'

$explorer = Invoke-WinAgentJson adaptive-run-step --diagnostic explorer-locator
Assert-True $explorer.ok 'explorer locator diagnostic failed'
Assert-Eq $explorer.data.selected_candidate.matched_name 'testrepo' 'testrepo must be selected'
Assert-True (@($explorer.data.rejected_candidates | Where-Object { $_.matched_name -eq 'devTool' -and $_.rejection_reason -eq 'EXPECTED_NAME_MISMATCH' }).Count -ge 1) 'devTool must be rejected'
Assert-Eq $explorer.data.selected_item_missing_failure 'FAIL_SELECTED_ITEM_RECT_MISSING' 'missing selected item rect failure code'
$results.explorer_locator = 'PASS'

$browser = Invoke-WinAgentJson adaptive-run-step --diagnostic browser-form-locator
Assert-True $browser.ok 'browser locator diagnostic failed'
foreach ($field in @('Recipient','Subject','Body','Send')) {
    Assert-True ($browser.data.accepted_targets -contains $field) "$field target must be accepted"
}
Assert-True (@($browser.data.rejected_candidates | Where-Object { $_.matched_text -eq 'send real email' -and $_.rejection_reason -eq 'EXPECTED_ROLE_MISMATCH' }).Count -ge 1) 'paragraph send text must be rejected as button'
$results.browser_form_locator = 'PASS'

$click = Invoke-WinAgentJson adaptive-click --mock invalid-target
Assert-Eq $click.ok $false 'mock invalid adaptive click must fail'
Assert-True ($null -ne $click.data.human_action_result) 'adaptive click must include human_action_result'
Assert-True ($null -ne $click.data.human_action_result.verification.cursor_inside_target_rect_before_click) 'cursor_inside_target_rect_before_click missing'
Assert-True (-not [string]::IsNullOrWhiteSpace($click.error.code)) 'failed adaptive click must include error.code'
$results.human_action_result = 'PASS'

$retry = Invoke-WinAgentJson adaptive-run-step --diagnostic retry-budget
Assert-True $retry.ok 'retry budget diagnostic failed'
Assert-Eq $retry.data.stale_then_success.retry_count 1 'stale retry count'
Assert-Eq $retry.data.exhausted.error.code 'RETRY_BUDGET_EXHAUSTED' 'retry exhausted error code'
$results.retry_budget = 'PASS'

$summary = [ordered]@{
    ok = $true
    version = '5.10.1'
    checks = $results
}
$summary | ConvertTo-Json -Depth 8
