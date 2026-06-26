param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.1.4_runtime_guard_browser_normalization'
$RawRoot = Join-Path $ArtifactRoot 'raw\runtime_context_guard_selftest'
New-Item -ItemType Directory -Force -Path $RawRoot | Out-Null

function Fail([string]$Message) {
    throw $Message
}

function Invoke-WinAgentJson {
    param(
        [string[]]$WinArgs,
        [int[]]$AllowedExitCodes = @(0, 1)
    )
    $output = & $WinAgent @WinArgs
    $exit = $LASTEXITCODE
    if ($AllowedExitCodes -notcontains $exit) {
        Fail "winagent $($WinArgs -join ' ') exited $exit with output: $output"
    }
    try {
        $json = $output | ConvertFrom-Json
    } catch {
        Fail "winagent $($WinArgs -join ' ') did not return JSON: $output"
    }
    [pscustomobject]@{ exit = $exit; json = $json; text = [string]$output; args = $WinArgs }
}

function Assert-GuardStop {
    param(
        $Result,
        [string]$CaseId,
        [string]$ExpectedStop,
        [string]$ActionFlag,
        [object]$ExpectedActionFlagValue
    )
    if ($Result.exit -eq 0) { Fail "$CaseId expected non-zero exit." }
    if ($Result.json.ok -ne $false) { Fail "$CaseId expected ok=false." }
    if ($Result.json.error.code -ne $ExpectedStop) {
        Fail "$CaseId expected $ExpectedStop, got $($Result.json.error.code)."
    }
    if ($Result.json.data.context_guard_enabled -ne $true) { Fail "$CaseId missing context_guard_enabled=true." }
    if ($Result.json.data.context_guard_result.ok -ne $false) { Fail "$CaseId missing guard ok=false." }
    if ($Result.json.data.context_guard_result.stop_code -ne $ExpectedStop) {
        Fail "$CaseId guard stop_code mismatch: $($Result.json.data.context_guard_result.stop_code)."
    }
    if ($Result.json.data.action_executed -ne $false) { Fail "$CaseId expected action_executed=false." }
    if ($Result.json.data.continued_action_after_wrong_context -ne $false) { Fail "$CaseId expected continued_action_after_wrong_context=false." }
    if ($ActionFlag) {
        $prop = $Result.json.data.PSObject.Properties[$ActionFlag]
        if ($null -eq $prop) { Fail "$CaseId missing $ActionFlag." }
        if ($prop.Value -ne $ExpectedActionFlagValue) { Fail "$CaseId expected $ActionFlag=$ExpectedActionFlagValue, got $($prop.Value)." }
    }
}

$showDesktop = Invoke-WinAgentJson -WinArgs @('desktop-hotkey','--keys','WIN+D','--permission-mode','DEVELOPER_CAPABILITY_DISCOVERY') -AllowedExitCodes @(0, 1)
Start-Sleep -Milliseconds 300

$active = Invoke-WinAgentJson -WinArgs @('active-window') -AllowedExitCodes @(0)
$activeTitle = [string]$active.json.data.title
$activeHwnd = [string]$active.json.data.hwnd
if ([string]::IsNullOrWhiteSpace($activeTitle)) {
    Fail 'Active window title is required for scroll-and-locate guard selftest.'
}
if ([string]::IsNullOrWhiteSpace($activeHwnd)) {
    Fail 'Active window hwnd is required for scroll-and-locate guard selftest.'
}

$cases = New-Object System.Collections.Generic.List[object]

function Add-CaseResult([string]$CaseId, [string]$ExpectedStop, $Result) {
    $cases.Add([pscustomobject]@{
        case_id = $CaseId
        expected_stop = $ExpectedStop
        exit_code = $Result.exit
        actual_stop = $Result.json.error.code
        action_executed = $Result.json.data.action_executed
        continued_action_after_wrong_context = $Result.json.data.continued_action_after_wrong_context
        command = ($Result.args -join ' ')
    }) | Out-Null
}

$r = Invoke-WinAgentJson -WinArgs @('desktop-click','--screen-x','1','--screen-y','1','--expected-process-pattern','__definitely_not_current_process__','--guard-result-json',(Join-Path $RawRoot 'desktop_click_wrong_process.json'))
Assert-GuardStop $r 'desktop_click_wrong_process' 'STOP_FOREGROUND_CHANGED' 'click_sent' $false
Add-CaseResult 'desktop_click_wrong_process' 'STOP_FOREGROUND_CHANGED' $r

$r = Invoke-WinAgentJson -WinArgs @('desktop-type','--text','SHOULD_NOT_TYPE','--permission-mode','DEVELOPER_CAPABILITY_DISCOVERY','--expected-title-pattern','__definitely_not_current_title__','--guard-result-json',(Join-Path $RawRoot 'desktop_type_wrong_title.json'))
Assert-GuardStop $r 'desktop_type_wrong_title' 'STOP_FOREGROUND_CHANGED' 'typing_started' $false
Add-CaseResult 'desktop_type_wrong_title' 'STOP_FOREGROUND_CHANGED' $r

$r = Invoke-WinAgentJson -WinArgs @('desktop-type','--text','SHOULD_NOT_TYPE','--permission-mode','DEVELOPER_CAPABILITY_DISCOVERY','--expected-focus-marker','__missing_focus_marker__','--guard-result-json',(Join-Path $RawRoot 'desktop_type_wrong_focus.json'))
Assert-GuardStop $r 'desktop_type_wrong_focus' 'STOP_WRONG_FIELD_FOCUS' 'typing_started' $false
Add-CaseResult 'desktop_type_wrong_focus' 'STOP_WRONG_FIELD_FOCUS' $r

$r = Invoke-WinAgentJson -WinArgs @('desktop-click','--screen-x','1','--screen-y','1','--required-marker','__missing_required_marker__','--guard-result-json',(Join-Path $RawRoot 'desktop_click_missing_marker.json'))
Assert-GuardStop $r 'desktop_click_missing_marker' 'STOP_WRONG_CONTEXT' 'click_sent' $false
Add-CaseResult 'desktop_click_missing_marker' 'STOP_WRONG_CONTEXT' $r

$r = Invoke-WinAgentJson -WinArgs @('scroll-and-locate','--hwnd',$activeHwnd,'--target-text','__target_not_needed__','--required-marker','__missing_scroll_page_marker__','--guard-result-json',(Join-Path $RawRoot 'scroll_and_locate_wrong_page_before_wheel.json'))
Assert-GuardStop $r 'scroll_and_locate_wrong_page_before_wheel' 'STOP_WRONG_CONTEXT' 'wheel_event_count' 0
Add-CaseResult 'scroll_and_locate_wrong_page_before_wheel' 'STOP_WRONG_CONTEXT' $r

$r = Invoke-WinAgentJson -WinArgs @('adaptive-click','--target','anything','--require-target-current','true','--target-from-current-observe','false','--guard-result-json',(Join-Path $RawRoot 'adaptive_click_stale_target.json'))
Assert-GuardStop $r 'adaptive_click_stale_target' 'STOP_TARGET_STALE' 'click_sent' $false
Add-CaseResult 'adaptive_click_stale_target' 'STOP_TARGET_STALE' $r

$r = Invoke-WinAgentJson -WinArgs @('adaptive-click','--target','anything','--require-target-unique','true','--target-unique','false','--guard-result-json',(Join-Path $RawRoot 'adaptive_click_ambiguous.json'))
Assert-GuardStop $r 'adaptive_click_ambiguous' 'STOP_TARGET_NOT_UNIQUE' 'click_sent' $false
Add-CaseResult 'adaptive_click_ambiguous' 'STOP_TARGET_NOT_UNIQUE' $r

$r = Invoke-WinAgentJson -WinArgs @('adaptive-click','--target','anything','--require-target-inside-viewport','true','--target-inside-viewport','false','--guard-result-json',(Join-Path $RawRoot 'adaptive_click_outside_viewport.json'))
Assert-GuardStop $r 'adaptive_click_outside_viewport' 'STOP_TARGET_OUTSIDE_VIEWPORT' 'click_sent' $false
Add-CaseResult 'adaptive_click_outside_viewport' 'STOP_TARGET_OUTSIDE_VIEWPORT' $r

$r = Invoke-WinAgentJson -WinArgs @('desktop-click','--screen-x','1','--screen-y','1','--wrong-page-pattern','.','--guard-result-json',(Join-Path $RawRoot 'wrong_page_pattern.json'))
Assert-GuardStop $r 'wrong_page_pattern' 'STOP_WRONG_PAGE' 'click_sent' $false
Add-CaseResult 'wrong_page_pattern' 'STOP_WRONG_PAGE' $r

$r = Invoke-WinAgentJson -WinArgs @('desktop-click','--screen-x','1','--screen-y','1','--active-protection-pattern','.','--guard-result-json',(Join-Path $RawRoot 'active_protection_pattern.json'))
Assert-GuardStop $r 'active_protection_pattern' 'STOP_ACTIVE_PROTECTION_OR_LOGIN_BLOCK' 'click_sent' $false
Add-CaseResult 'active_protection_pattern' 'STOP_ACTIVE_PROTECTION_OR_LOGIN_BLOCK' $r

$r = Invoke-WinAgentJson -WinArgs @('desktop-click','--screen-x','1','--screen-y','1','--automation-pattern','.','--guard-result-json',(Join-Path $RawRoot 'automation_pattern.json'))
Assert-GuardStop $r 'automation_pattern' 'STOP_AUTOMATION_DETECTED' 'click_sent' $false
Add-CaseResult 'automation_pattern' 'STOP_AUTOMATION_DETECTED' $r

$r = Invoke-WinAgentJson -WinArgs @('desktop-click','--screen-x','1','--screen-y','1','--loading-overlay-pattern','.','--guard-result-json',(Join-Path $RawRoot 'loading_overlay_pattern.json'))
Assert-GuardStop $r 'loading_overlay_pattern' 'STOP_LOADING_OR_OVERLAY_BLOCKING' 'click_sent' $false
Add-CaseResult 'loading_overlay_pattern' 'STOP_LOADING_OR_OVERLAY_BLOCKING' $r

$summary = [pscustomobject]@{
    status = 'PASS'
    case_count = $cases.Count
    cases = @($cases.ToArray())
}
$summaryPath = Join-Path $ArtifactRoot 'runtime_context_guard_selftest_summary.json'
$summary | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

$reportPath = Join-Path $ArtifactRoot 'runtime_context_guard_selftest_report.md'
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# Runtime Context Guard Selftest') | Out-Null
$lines.Add('') | Out-Null
$lines.Add('Result: PASS') | Out-Null
$lines.Add('') | Out-Null
$lines.Add('| case | expected_stop | actual_stop | action_executed | continued_action_after_wrong_context |') | Out-Null
$lines.Add('|---|---|---|---:|---:|') | Out-Null
foreach ($case in $cases) {
    $lines.Add("| $($case.case_id) | $($case.expected_stop) | $($case.actual_stop) | $($case.action_executed) | $($case.continued_action_after_wrong_context) |") | Out-Null
}
$lines | Set-Content -LiteralPath $reportPath -Encoding UTF8

Write-Host "runtime_context_guard_selftest PASS: $reportPath"
