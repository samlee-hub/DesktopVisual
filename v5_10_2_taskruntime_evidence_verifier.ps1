param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot

$ArtifactRoot = Join-Path $Root 'artifacts\dev5.10.2_real_taskruntime_final_gate'
$TaskDir = Join-Path $ArtifactRoot 'task_runtime\localhost_form_fill_submit_humanmode'
$ReportPath = Join-Path $ArtifactRoot 'taskruntime_evidence_verifier_report.md'
$TaskFile = Join-Path $Root 'tasks\localhost_form_fill_submit_humanmode.task.json'

function Read-JsonFile([string]$Path, [string]$Label, [System.Collections.Generic.List[string]]$Findings) {
    if (-not (Test-Path -LiteralPath $Path)) {
        $Findings.Add("Missing $Label`: $Path") | Out-Null
        return $null
    }
    try {
        return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
    } catch {
        $Findings.Add("Invalid JSON in $Label`: $Path :: $($_.Exception.Message)") | Out-Null
        return $null
    }
}

function Read-JsonlFile([string]$Path, [string]$Label, [System.Collections.Generic.List[string]]$Findings) {
    $items = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $Path)) {
        $Findings.Add("Missing $Label`: $Path") | Out-Null
        return $items.ToArray()
    }
    $lineNo = 0
    foreach ($line in Get-Content -LiteralPath $Path) {
        $lineNo++
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $items.Add(($line | ConvertFrom-Json)) | Out-Null
        } catch {
            $Findings.Add("Invalid JSONL in $Label at line $lineNo`: $($_.Exception.Message)") | Out-Null
        }
    }
    return $items.ToArray()
}

function Add-Finding([System.Collections.Generic.List[string]]$Findings, [string]$Message) {
    $Findings.Add($Message) | Out-Null
}

function Test-ImageLooksReal([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path
    if ($item.Length -lt 1024) { return $false }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 8) { return $false }
    $isPng = $bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47
    $isBmp = $bytes[0] -eq 0x42 -and $bytes[1] -eq 0x4D
    return ($isPng -or $isBmp)
}

function Get-FirstFailCode([string[]]$Findings) {
    $joined = ($Findings -join "`n")
    if ($joined -match 'Missing|Invalid JSON|Invalid JSONL|raw command output') { return 'FAIL_TASKRUNTIME_ARTIFACT_MISSING' }
    if ($joined -match 'synthetic|simulated|placeholder') { return 'FAIL_TASKRUNTIME_SYNTHETIC_EVIDENCE' }
    if ($joined -match 'hardcoded hwnd|hardcoded rect|target_rect missing|cursor outside') { return 'FAIL_TASKRUNTIME_HARDCODED_RECT' }
    if ($joined -match 'backend action|JS DOM|WebDriver|CDP|direct navigation|direct launch') { return 'FAIL_TASKRUNTIME_BACKEND_ACTION' }
    if ($joined -match 'Recipient|Subject|Body|field') { return 'FAIL_TASKRUNTIME_FIELD_LOCATOR' }
    if ($joined -match 'Send') { return 'FAIL_TASKRUNTIME_SEND_BUTTON' }
    if ($joined -match 'verification|Mock sent|cleared|localhost') { return 'FAIL_TASKRUNTIME_VERIFICATION' }
    return 'FAIL_TASKRUNTIME_ARTIFACT_MISSING'
}

function Count-Where($Items, [scriptblock]$Predicate) {
    @($Items | Where-Object $Predicate).Count
}

function Get-RawOutputTextByStep($RawCommands, [string]$Step) {
    $entry = @($RawCommands | Where-Object { [string]$_.step -eq $Step } | Select-Object -Last 1)
    if ($entry.Count -lt 1) { return '' }
    $path = [string]$entry[0].stdout_path
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) { return '' }
    return (Get-Content -LiteralPath $path -Raw)
}

$findings = New-Object System.Collections.Generic.List[string]
$metrics = [ordered]@{}

if (-not (Test-Path -LiteralPath $TaskDir)) {
    Add-Finding $findings "Missing TaskRuntime artifact directory: $TaskDir"
}

$taskResultPath = Join-Path $TaskDir 'task_result.json'
$taskEventsPath = Join-Path $TaskDir 'task_events.jsonl'
$actionTracePath = Join-Path $TaskDir 'action_trace.jsonl'
$locatorTracePath = Join-Path $TaskDir 'locator_trace.jsonl'
$adaptiveLoopPath = Join-Path $TaskDir 'adaptive_loop_trace.jsonl'
$humanResultsPath = Join-Path $TaskDir 'human_action_results.jsonl'
$rawCommandLogPath = Join-Path $TaskDir 'raw_command_log.jsonl'
$screenshotsDir = Join-Path $TaskDir 'screenshots'
$overlaysDir = Join-Path $TaskDir 'overlays'

$result = Read-JsonFile $taskResultPath 'task_result.json' $findings
$events = Read-JsonlFile $taskEventsPath 'task_events.jsonl' $findings
$actions = Read-JsonlFile $actionTracePath 'action_trace.jsonl' $findings
$locators = Read-JsonlFile $locatorTracePath 'locator_trace.jsonl' $findings
$adaptive = Read-JsonlFile $adaptiveLoopPath 'adaptive_loop_trace.jsonl' $findings
$human = Read-JsonlFile $humanResultsPath 'human_action_results.jsonl' $findings
$rawCommands = Read-JsonlFile $rawCommandLogPath 'raw_command_log.jsonl' $findings

$metrics.task_event_count = @($events).Count
$metrics.action_trace_count = @($actions).Count
$metrics.locator_trace_count = @($locators).Count
$metrics.adaptive_loop_trace_count = @($adaptive).Count
$metrics.human_action_result_count = @($human).Count
$metrics.raw_command_count = @($rawCommands).Count

if ($null -eq $result) {
    Add-Finding $findings 'task_result.json could not be parsed.'
} else {
    if ($result.runtime_version -ne '5.10.2') { Add-Finding $findings "Unexpected runtime_version: $($result.runtime_version)" }
    if ($result.task_type -ne 'localhost_form_fill_submit_humanmode') { Add-Finding $findings "Unexpected task_type: $($result.task_type)" }
    if ($result.ok -ne $true -or $result.current_state -ne 'completed') { Add-Finding $findings 'TaskRuntime did not complete successfully.' }
    if ($result.actual_result -ne 'REAL_UI_EXECUTION_COMPLETED_PENDING_INDEPENDENT_VERIFIER') { Add-Finding $findings "Unexpected actual_result: $($result.actual_result)" }
    if ($result.taskruntime_self_certified_pass -ne $false) { Add-Finding $findings 'TaskRuntime self-certified PASS.' }
    if ($result.ready_for_v6_self_claim -ne $false) { Add-Finding $findings 'TaskRuntime made a ready_for_v6 self-claim.' }
    if (-not ($result.runtime_flow -contains 'TaskSession')) { Add-Finding $findings 'Runtime flow missing TaskSession.' }
    if (-not ($result.runtime_flow -contains 'StepContract')) { Add-Finding $findings 'Runtime flow missing StepContract.' }
    if (-not ($result.runtime_flow -contains 'TaskRunner')) { Add-Finding $findings 'Runtime flow missing TaskRunner.' }
    if (-not ($result.runtime_flow -contains 'AdaptiveHumanModeLoop')) { Add-Finding $findings 'Runtime flow missing AdaptiveHumanModeLoop.' }
    if (-not ($result.runtime_flow -contains 'VerificationEngineEquivalent')) { Add-Finding $findings 'Runtime flow missing verification engine equivalent.' }

    if ($result.localhost.bind_host -ne '127.0.0.1') { Add-Finding $findings "localhost bind_host is not 127.0.0.1: $($result.localhost.bind_host)" }
    if ($result.localhost.bound_all_interfaces -ne $false) { Add-Finding $findings 'localhost was bound to all interfaces.' }

    foreach ($flag in @('recipient_text_verified','subject_text_verified','body_text_verified','status_verified','fields_cleared_verified')) {
        if ($result.verification.$flag -ne $true) { Add-Finding $findings "Verification flag was not true: $flag" }
    }
    foreach ($counter in @('backend_action_count','js_dom_action_count','webdriver_count','cdp_count','uia_invoke_action_count','uia_value_action_count')) {
        if ([int]$result.integrity.$counter -ne 0) { Add-Finding $findings "$counter was nonzero: $($result.integrity.$counter)" }
    }
    if ($result.integrity.synthetic_trace -ne $false) { Add-Finding $findings 'synthetic_trace was true.' }
    if ($result.integrity.hardcoded_hwnd -ne $false) { Add-Finding $findings 'hardcoded hwnd flag was true.' }
    if ($result.integrity.hardcoded_rect -ne $false) { Add-Finding $findings 'hardcoded rect flag was true.' }
}

$requiredEvents = @(
    'start_localhost_http_server',
    'open_browser_humanmode_address_bar_navigation',
    'locate_recipient',
    'click_recipient',
    'type_recipient',
    'verify_recipient_text',
    'locate_subject',
    'click_subject',
    'type_subject',
    'verify_subject_text',
    'locate_body',
    'click_body',
    'type_body',
    'verify_body_text',
    'locate_send',
    'click_send',
    'verify_mock_sent_successfully',
    'verify_fields_cleared',
    'stop_localhost_http_server'
)
foreach ($step in $requiredEvents) {
    $match = @($events | Where-Object { [string]$_.step_id -eq $step -and $_.ok -eq $true -and [string]$_.state -eq 'completed' })
    if ($match.Count -lt 1) { Add-Finding $findings "Missing completed event step: $step" }
}

if (@($rawCommands).Count -lt 20) { Add-Finding $findings 'Too few raw winagent command outputs for real UI flow.' }
foreach ($entry in $rawCommands) {
    if ($entry.ok -ne $true -or [int]$entry.exit_code -ne 0) {
        Add-Finding $findings "Raw command failed: sequence=$($entry.sequence) step=$($entry.step) command=$($entry.command)"
    }
    if ([string]::IsNullOrWhiteSpace([string]$entry.stdout_path) -or -not (Test-Path -LiteralPath ([string]$entry.stdout_path))) {
        Add-Finding $findings "Missing raw command output for sequence=$($entry.sequence) step=$($entry.step)"
    } else {
        [void](Read-JsonFile ([string]$entry.stdout_path) "raw command output $($entry.sequence)" $findings)
    }
}

$commands = @($rawCommands | ForEach-Object { [string]$_.command })
foreach ($requiredCommand in @('observe','adaptive-locate','desktop-move','desktop-click','desktop-type','desktop-hotkey','desktop-press','screenshot','read-window-text')) {
    if (-not ($commands -contains $requiredCommand)) { Add-Finding $findings "Missing raw command type: $requiredCommand" }
}
foreach ($bannedCommand in @('uia-click','uia-type','browser-nav','external-web-navigation','launch-app','webdriver','cdp')) {
    if ($commands -contains $bannedCommand) { Add-Finding $findings "Banned backend/direct command was used: $bannedCommand" }
}

$fieldLocators = @{
    locate_recipient = @{ target = 'Recipient'; role = 'Edit' }
    locate_subject = @{ target = 'Subject'; role = 'Edit' }
    locate_body = @{ target = 'Body'; role = 'Edit' }
    locate_send = @{ target = 'Send'; role = 'Button' }
}
foreach ($step in $fieldLocators.Keys) {
    $item = @($locators | Where-Object { [string]$_.step -eq $step } | Select-Object -Last 1)
    if ($item.Count -lt 1) {
        Add-Finding $findings "Missing locator trace for $step"
        continue
    }
    $candidate = $item[0].selected_candidate
    if ($candidate.source -ne 'uia' -and $candidate.source -ne 'uia_address_bar') { Add-Finding $findings "Locator source was not UIA-derived for $step`: $($candidate.source)" }
    if ($candidate.target_id -ne $fieldLocators[$step].target) { Add-Finding $findings "Locator target mismatch for $step`: $($candidate.target_id)" }
    if ($candidate.role -ne $fieldLocators[$step].role) { Add-Finding $findings "Locator role mismatch for $step`: $($candidate.role)" }
    if ($null -eq $candidate.rect -or [int]$candidate.rect.right -le [int]$candidate.rect.left -or [int]$candidate.rect.bottom -le [int]$candidate.rect.top) {
        Add-Finding $findings "Locator target_rect missing or invalid for $step"
    }
}

foreach ($step in @('click_address_bar_click','click_recipient_click','click_subject_click','click_body_click','click_send_click')) {
    $item = @($human | Where-Object { [string]$_.step -eq $step } | Select-Object -Last 1)
    if ($item.Count -lt 1) {
        Add-Finding $findings "Missing human click evidence for $step"
        continue
    }
    $har = $item[0].human_action_result
    if ($har.humanmode -ne $true) { Add-Finding $findings "Click was not HumanMode: $step" }
    if ($har.backend_action -ne $false) { Add-Finding $findings "Click used backend action: $step" }
    if ($har.actual_click_sent -ne $true) { Add-Finding $findings "Click did not send real click: $step" }
    if ($har.verification.cursor_inside_target_rect_before_click -ne $true) { Add-Finding $findings "cursor outside target before click: $step" }
    if ($har.verification.click_after_move_end -ne $true) { Add-Finding $findings "click_after_move_end false: $step" }
    if ($har.verification.dwell_completed_before_click -ne $true) { Add-Finding $findings "dwell_completed_before_click false: $step" }
    if ([string]$har.target.coordinate_source -notmatch '^locator_derived:') { Add-Finding $findings "Click coordinate source was not locator-derived: $step" }
}

foreach ($step in @('type_localhost_url','type_recipient','type_subject','type_body')) {
    $item = @($human | Where-Object { [string]$_.step -eq $step } | Select-Object -Last 1)
    if ($item.Count -lt 1) {
        Add-Finding $findings "Missing human typing evidence for $step"
        continue
    }
    $har = $item[0].human_action_result
    if ($har.humanmode -ne $true) { Add-Finding $findings "Typing was not HumanMode: $step" }
    if ($har.backend_action -ne $false) { Add-Finding $findings "Typing used backend action: $step" }
    if ($har.actual_key_sent -ne $true) { Add-Finding $findings "Typing did not send real key input: $step" }
}

foreach ($entry in $human) {
    $har = $entry.human_action_result
    if ($har.backend_action -eq $true) { Add-Finding $findings "backend action detected in human result: $($entry.step)" }
    if ($har.direct_launch -eq $true) { Add-Finding $findings "direct launch detected in human result: $($entry.step)" }
    if ([string]$har.target.coordinate_source -match 'hardcoded|simulated|synthetic') { Add-Finding $findings "synthetic coordinate source detected: $($entry.step)" }
}

$rawText = ''
foreach ($path in @($taskEventsPath,$actionTracePath,$locatorTracePath,$adaptiveLoopPath,$humanResultsPath,$rawCommandLogPath,$taskResultPath)) {
    if (Test-Path -LiteralPath $path) { $rawText += "`n" + (Get-Content -LiteralPath $path -Raw) }
}
if ($rawText -match 'simulated_candidate|synthetic action_trace|synthetic_trace"\s*:\s*true|placeholder screenshot|no-open mock') {
    Add-Finding $findings 'synthetic or placeholder evidence marker detected.'
}
if ($rawText -match '"command"\s*:\s*"(browser-nav|external-web-navigation|uia-click|uia-type|webdriver|cdp)"|Runtime\.evaluate|document\.querySelector|XMLHttpRequest\(') {
    Add-Finding $findings 'JS DOM/WebDriver/CDP/UIA action marker detected.'
}

$recipientText = Get-RawOutputTextByStep $rawCommands 'verify_recipient_text'
$subjectText = Get-RawOutputTextByStep $rawCommands 'verify_subject_text'
$bodyText = Get-RawOutputTextByStep $rawCommands 'verify_body_text'
$afterText = Get-RawOutputTextByStep $rawCommands 'verify_after_send_observe'
if ($recipientText -notmatch '"name"\s*:\s*"Recipient"\s*,\s*"value"\s*:\s*"xiaoming"') { Add-Finding $findings 'Recipient value was not verified from raw observe output.' }
if ($subjectText -notmatch '"name"\s*:\s*"Subject"\s*,\s*"value"\s*:\s*"desktopvisual test"') { Add-Finding $findings 'Subject value was not verified from raw observe output.' }
if ($bodyText -notmatch '"name"\s*:\s*"Body"\s*,\s*"value"\s*:\s*"this is a testing message"') { Add-Finding $findings 'Body value was not verified from raw observe output.' }
if ($afterText -notmatch 'Mock sent successfully') { Add-Finding $findings 'Mock sent successfully status missing from after-send observe output.' }
foreach ($field in @('Recipient','Subject','Body')) {
    if ($afterText -notmatch ('"name"\s*:\s*"' + [regex]::Escape($field) + '"\s*,\s*"value"\s*:\s*""')) {
        Add-Finding $findings "$field was not verified cleared from after-send observe output."
    }
}

if (-not (Test-Path -LiteralPath $screenshotsDir)) {
    Add-Finding $findings "Missing screenshots directory: $screenshotsDir"
} else {
    foreach ($name in @('before_fill.bmp','after_fill.bmp','after_send.bmp')) {
        $image = Join-Path $screenshotsDir $name
        if (-not (Test-ImageLooksReal $image)) { Add-Finding $findings "Missing or placeholder screenshot: $image" }
    }
}
if (-not (Test-Path -LiteralPath $overlaysDir)) {
    Add-Finding $findings "Missing overlays directory: $overlaysDir"
}

if (Test-Path -LiteralPath $TaskFile) {
    $taskText = Get-Content -LiteralPath $TaskFile -Raw
    if ($taskText -match 'not_implemented_real_humanmode_taskruntime_flow|simulated PASS|hardcoded hwnd|hardcoded window rect|hardcoded content rect|hardcoded Recipient|hardcoded Subject|hardcoded Body|hardcoded Send') {
        Add-Finding $findings 'Task file contains banned invalidated/simulated/hardcoded marker.'
    }
    if ($taskText -notmatch '127\.0\.0\.1') { Add-Finding $findings 'Task file does not use 127.0.0.1 localhost URL.' }
    if ($taskText -match '"server_bind_host"\s*:\s*"0\.0\.0\.0"' -or $taskText -match '"localhost_url"\s*:\s*"http://0\.0\.0\.0') {
        Add-Finding $findings 'Task file binds or navigates to 0.0.0.0.'
    }
} else {
    Add-Finding $findings "Missing task file: $TaskFile"
}

$metrics.backend_action_count = Count-Where $human { $_.human_action_result.backend_action -eq $true }
$metrics.js_dom_action_count = 0
$metrics.webdriver_count = 0
$metrics.cdp_count = 0
$metrics.uia_invoke_action_count = Count-Where $rawCommands { [string]$_.command -eq 'uia-click' }
$metrics.uia_value_action_count = Count-Where $rawCommands { [string]$_.command -eq 'uia-type' }
$metrics.localhost_bound_to_127001_only = ($null -ne $result -and $result.localhost.bind_host -eq '127.0.0.1' -and $result.localhost.bound_all_interfaces -eq $false)
$metrics.fields_verified = ($null -ne $result -and $result.verification.recipient_text_verified -eq $true -and $result.verification.subject_text_verified -eq $true -and $result.verification.body_text_verified -eq $true)
$metrics.status_verified = ($null -ne $result -and $result.verification.status_verified -eq $true)
$metrics.fields_cleared_verified = ($null -ne $result -and $result.verification.fields_cleared_verified -eq $true)

$verdict = if ($findings.Count -eq 0) { 'REAL_TASKRUNTIME_HUMANMODE_PASS' } else { Get-FirstFailCode $findings.ToArray() }

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# v5.10.2 TaskRuntime Evidence Verifier') | Out-Null
$lines.Add('') | Out-Null
$lines.Add("- Verdict: $verdict") | Out-Null
$lines.Add("- TaskRuntime artifact directory: $TaskDir") | Out-Null
$lines.Add("- Task file: $TaskFile") | Out-Null
$lines.Add("- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')") | Out-Null
$lines.Add('') | Out-Null
$lines.Add('## Metrics') | Out-Null
$lines.Add('') | Out-Null
foreach ($key in $metrics.Keys) {
    $lines.Add("- $key`: $($metrics[$key])") | Out-Null
}
$lines.Add('') | Out-Null
$lines.Add('## Findings') | Out-Null
$lines.Add('') | Out-Null
if ($findings.Count -eq 0) {
    $lines.Add('- None') | Out-Null
} else {
    foreach ($finding in $findings) { $lines.Add("- $finding") | Out-Null }
}

New-Item -ItemType Directory -Force -Path $ArtifactRoot | Out-Null
$lines | Set-Content -LiteralPath $ReportPath -Encoding UTF8

if ($verdict -ne 'REAL_TASKRUNTIME_HUMANMODE_PASS') {
    Write-Host "$verdict. Report: $ReportPath"
    exit 1
}

Write-Host "REAL_TASKRUNTIME_HUMANMODE_PASS. Report: $ReportPath"
exit 0
