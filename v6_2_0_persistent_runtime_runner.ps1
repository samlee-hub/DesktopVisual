param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$TestWindowExe = 'D:\testrepo\testwindow\bin\TestWindow.exe'
$StatePath = 'D:\testrepo\testwindow\runtime\state.txt'
$MailHtml = 'D:\testrepo\testwindow\desktopvisual_mail_mock.html'
$LongScrollHtml = 'D:\testrepo\testwindow\desktopvisual_long_scroll_test.html'
$WrongHtml = 'D:\testrepo\testwindow\desktopvisual_wrong_page_mock.html'
$EdgeExe = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.2.0_persistent_runtime_session_latency_gate'
$RawRoot = Join-Path $ArtifactRoot 'raw\v6_2_0_runner'
$RunnerResultPath = Join-Path $ArtifactRoot 'v6_2_0_runner_raw_result.json'
$RunnerReportPath = Join-Path $ArtifactRoot 'v6_2_0_runner_raw_report.md'
New-Item -ItemType Directory -Force -Path $RawRoot | Out-Null

function Fail([string]$Message) { throw $Message }

function Write-JsonFile {
    param([string]$Path, [object]$Value)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $Value | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-WinAgentJson {
    param(
        [string[]]$WinArgs,
        [int[]]$AllowedExitCodes = @(0),
        [string]$OutPath = ''
    )
    $output = & $WinAgent @WinArgs 2>&1
    $exit = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    if (-not [string]::IsNullOrWhiteSpace($OutPath)) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutPath) | Out-Null
        $text | Set-Content -LiteralPath $OutPath -Encoding UTF8
    }
    if ($AllowedExitCodes -notcontains $exit) {
        Fail "winagent $($WinArgs -join ' ') exited $exit with output: $text"
    }
    try { $json = $text | ConvertFrom-Json } catch { Fail "Invalid JSON for $($WinArgs -join ' '): $text" }
    [pscustomobject]@{ exit = $exit; json = $json; text = $text; args = $WinArgs }
}

function Stop-TestWindow {
    Get-Process TestWindow -ErrorAction SilentlyContinue | ForEach-Object {
        $_.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 200
        if (!$_.HasExited) { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
    }
}

function Start-TestWindow {
    Stop-TestWindow
    $proc = Start-Process -FilePath $TestWindowExe -PassThru
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 200
        $find = Invoke-WinAgentJson -WinArgs @('find', '--title', 'Agent Test Window') -AllowedExitCodes @(0, 1)
    } while ($find.exit -ne 0 -and (Get-Date) -lt $deadline)
    if ($find.exit -ne 0) { Fail 'Agent Test Window did not appear.' }
    Invoke-WinAgentJson -WinArgs @('focus', '--title', 'Agent Test Window') -AllowedExitCodes @(0, 1) | Out-Null
    Start-Sleep -Milliseconds 200
    $proc
}

function Stop-EdgeProfile([string]$ProfilePath) {
    if ([string]::IsNullOrWhiteSpace($ProfilePath)) { return }
    Get-CimInstance Win32_Process -Filter "name = 'msedge.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*$ProfilePath*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

function Start-EdgeLocalPage {
    param(
        [string]$Title,
        [string]$HtmlPath,
        [string]$ProfileName
    )
    if (!(Test-Path -LiteralPath $EdgeExe)) { Fail "Missing Edge executable at $EdgeExe" }
    $profile = Join-Path $RawRoot $ProfileName
    Stop-EdgeProfile $profile
    $url = 'file:///' + $HtmlPath.Replace('\', '/')
    $args = '--new-window --no-first-run --disable-features=Translate --user-data-dir="{0}" "{1}"' -f $profile, $url
    Start-Process -FilePath $EdgeExe -ArgumentList $args | Out-Null
    $deadline = (Get-Date).AddSeconds(45)
    do {
        Start-Sleep -Milliseconds 500
        $find = Invoke-WinAgentJson -WinArgs @('find', '--title', $Title) -AllowedExitCodes @(0, 1)
    } while ($find.exit -ne 0 -and (Get-Date) -lt $deadline)
    if ($find.exit -ne 0) { Fail "Edge page did not appear for $Title" }
    Invoke-WinAgentJson -WinArgs @('focus', '--title', $Title) -AllowedExitCodes @(0, 1) | Out-Null
    Start-Sleep -Milliseconds 300
    [pscustomobject]@{ profile = $profile; find = $find.json }
}

function Close-SessionIfAny([string]$SessionId) {
    if (-not [string]::IsNullOrWhiteSpace($SessionId)) {
        Invoke-WinAgentJson -WinArgs @('runtime-session-close', '--session-id', $SessionId) -AllowedExitCodes @(0, 1) | Out-Null
    }
}

function New-TestWindowContext {
    [ordered]@{ expected_title_pattern = 'Agent Test Window'; expected_process_pattern = 'TestWindow.exe' }
}

function New-EdgeContext([string]$Title) {
    [ordered]@{ expected_title_pattern = $Title; expected_process_pattern = 'msedge.exe' }
}

function Run-Dispatch {
    param(
        [string]$CaseDir,
        [string]$SessionId,
        [object]$Steps,
        [string]$Name
    )
    $stepsPath = Join-Path $CaseDir "$Name.steps.json"
    $resultPath = Join-Path $CaseDir "$Name.result.json"
    Write-JsonFile -Path $stepsPath -Value ([ordered]@{ steps = $Steps })
    $dispatch = Invoke-WinAgentJson -WinArgs @('runtime-session-dispatch', '--session-id', $SessionId, '--steps-json', $stepsPath, '--result-json', $resultPath) -AllowedExitCodes @(0, 1) -OutPath (Join-Path $CaseDir "$Name.stdout.json")
    [ordered]@{ steps_json = $stepsPath; result_json = $resultPath; stdout_json = (Join-Path $CaseDir "$Name.stdout.json"); command_exit = $dispatch.exit; command = $dispatch.json }
}

if (!(Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run build.ps1 first." }
if (!(Test-Path -LiteralPath $TestWindowExe)) { Fail "Missing $TestWindowExe. Run build.ps1 first." }

$cases = [ordered]@{}

# Case 1: Session lifecycle.
$caseDir = Join-Path $RawRoot 'case_1_session_lifecycle'
New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
$proc = Start-TestWindow
$sessionId = ''
try {
    $start = Invoke-WinAgentJson -WinArgs @('runtime-session-start', '--title', 'Agent Test Window', '--process', 'TestWindow.exe') -OutPath (Join-Path $caseDir '01_start.json')
    $sessionId = [string]$start.json.session_id
    $status = Invoke-WinAgentJson -WinArgs @('runtime-session-status', '--session-id', $sessionId) -OutPath (Join-Path $caseDir '02_status.json')
    $observe = Invoke-WinAgentJson -WinArgs @('runtime-session-observe', '--session-id', $sessionId, '--screenshot', 'false', '--uia', 'true') -OutPath (Join-Path $caseDir '03_observe.json')
    $close = Invoke-WinAgentJson -WinArgs @('runtime-session-close', '--session-id', $sessionId) -OutPath (Join-Path $caseDir '04_close.json')
    $closed = Invoke-WinAgentJson -WinArgs @('runtime-session-command', '--session-id', $sessionId, '--action', 'observe') -AllowedExitCodes @(1) -OutPath (Join-Path $caseDir '05_closed_reject.json')
    $cases.case_1_session_lifecycle = [ordered]@{
        raw_status = 'RAW_COMPLETED_UNVERIFIED'
        start = $start.json
        status = $status.json
        observe = $observe.json
        close = $close.json
        closed_reject = $closed.json
    }
}
finally {
    Close-SessionIfAny $sessionId
    if ($proc -and !$proc.HasExited) { $proc.CloseMainWindow() | Out-Null; Start-Sleep -Milliseconds 300; if (!$proc.HasExited) { Stop-Process -Id $proc.Id -Force } }
}

# Case 2: One-shot compatibility with no session id.
$caseDir = Join-Path $RawRoot 'case_2_one_shot_compatibility'
New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
$proc = Start-TestWindow
try {
    $legacy = @()
    $legacy += Invoke-WinAgentJson -WinArgs @('observe','--title','Agent Test Window','--screenshot','false','--uia','true') -OutPath (Join-Path $caseDir '01_observe.json')
    $legacy += Invoke-WinAgentJson -WinArgs @('click','--title','Agent Test Window','--x','90','--y','150','--move-mode','instant') -OutPath (Join-Path $caseDir '02_click.json')
    $legacy += Invoke-WinAgentJson -WinArgs @('type','--title','Agent Test Window','--text','abc','--type-mode','human') -OutPath (Join-Path $caseDir '03_type.json')
    $legacy += Invoke-WinAgentJson -WinArgs @('read-file','--path',$StatePath) -OutPath (Join-Path $caseDir '04_read_file.json')
    $legacy += Invoke-WinAgentJson -WinArgs @('scroll','--title','Agent Test Window','--x','120','--y','120','--delta','-120','--move-mode','instant') -OutPath (Join-Path $caseDir '05_scroll.json')
    $cases.case_2_one_shot_compatibility = [ordered]@{
        raw_status = 'RAW_COMPLETED_UNVERIFIED'
        commands = @($legacy | ForEach-Object { [ordered]@{ args = $_.args; exit = $_.exit; json = $_.json } })
    }
}
finally {
    if ($proc -and !$proc.HasExited) { $proc.CloseMainWindow() | Out-Null; Start-Sleep -Milliseconds 300; if (!$proc.HasExited) { Stop-Process -Id $proc.Id -Force } }
}

# Case 3: 10-step session workflow.
$caseDir = Join-Path $RawRoot 'case_3_10_step_session_workflow'
New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
$proc = Start-TestWindow
$sessionId = ''
try {
    $ctx = New-TestWindowContext
    $start = Invoke-WinAgentJson -WinArgs @('runtime-session-start', '--title', 'Agent Test Window', '--process', 'TestWindow.exe') -OutPath (Join-Path $caseDir '00_start.json')
    $sessionId = [string]$start.json.session_id
    $steps = @(
        [ordered]@{ step_id='s01_observe'; action='observe'; cache_policy='force_reobserve' },
        [ordered]@{ step_id='s02_click_field1'; action='click'; target='uia:type=Edit'; move_mode='instant'; expected_context=$ctx },
        [ordered]@{ step_id='s03_type_text1'; action='type'; text='DV62_TEXT1'; type_mode='instant'; verification_hint='state_contains:last_text=DV62_TEXT1'; expected_context=$ctx },
        [ordered]@{ step_id='s04_verify_field1'; action='verify'; verification_hint='state_contains:last_text=DV62_TEXT1' },
        [ordered]@{ step_id='s05_click_field2'; action='click'; target='uia:type=Edit'; move_mode='instant'; force_reobserve=$true; expected_context=$ctx },
        [ordered]@{ step_id='s06_type_text2'; action='type'; text='_DV62_TEXT2'; type_mode='instant'; verification_hint='state_contains:last_text=DV62_TEXT1_DV62_TEXT2'; expected_context=$ctx },
        [ordered]@{ step_id='s07_verify_field2'; action='verify'; verification_hint='state_contains:last_text=DV62_TEXT1_DV62_TEXT2' },
        [ordered]@{ step_id='s08_scroll'; action='scroll'; delta='-120'; move_mode='instant'; expected_context=$ctx },
        [ordered]@{ step_id='s09_click_submit'; action='click'; target='uia:name=Click Me,type=Button'; move_mode='instant'; force_reobserve=$true; verification_hint='state_contains:clicks=1'; expected_context=$ctx },
        [ordered]@{ step_id='s10_verify_result'; action='verify'; verification_hint='state_contains:clicks=1' }
    )
    $dispatch = Run-Dispatch -CaseDir $caseDir -SessionId $sessionId -Steps $steps -Name 'ten_step'
    $close = Invoke-WinAgentJson -WinArgs @('runtime-session-close', '--session-id', $sessionId) -OutPath (Join-Path $caseDir '99_close.json')
    $cases.case_3_10_step_session_workflow = [ordered]@{ raw_status='RAW_COMPLETED_UNVERIFIED'; start=$start.json; dispatch=$dispatch; close=$close.json }
}
finally {
    Close-SessionIfAny $sessionId
    if ($proc -and !$proc.HasExited) { $proc.CloseMainWindow() | Out-Null; Start-Sleep -Milliseconds 300; if (!$proc.HasExited) { Stop-Process -Id $proc.Id -Force } }
}

# Case 4: Browser form session workflow on local mail mock.
$caseDir = Join-Path $RawRoot 'case_4_browser_form_session_workflow'
New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
$edge = $null
$sessionId = ''
try {
    $edge = Start-EdgeLocalPage -Title 'DesktopVisual Local Mail Mock' -HtmlPath $MailHtml -ProfileName 'edge_mail_profile'
    $ctx = New-EdgeContext 'DesktopVisual Local Mail Mock'
    $start = Invoke-WinAgentJson -WinArgs @('runtime-session-start', '--title', 'DesktopVisual Local Mail Mock', '--process', 'msedge.exe') -OutPath (Join-Path $caseDir '00_start.json')
    $sessionId = [string]$start.json.session_id
    $steps = @(
        [ordered]@{ step_id='b01_observe'; action='observe'; cache_policy='force_reobserve' },
        [ordered]@{ step_id='b02_click_recipient'; action='click'; target='uia:automation_id=recipient'; move_mode='instant'; expected_context=$ctx },
        [ordered]@{ step_id='b03_type_recipient'; action='type'; text='dv62@example.test'; type_mode='instant'; verification_hint='uia_contains:dv62@example.test'; expected_context=$ctx },
        [ordered]@{ step_id='b04_click_subject'; action='click'; target='uia:automation_id=subject'; move_mode='instant'; force_reobserve=$true; expected_context=$ctx },
        [ordered]@{ step_id='b05_type_subject'; action='type'; text='DV62 Subject'; type_mode='instant'; verification_hint='uia_contains:DV62 Subject'; expected_context=$ctx },
        [ordered]@{ step_id='b06_click_body'; action='click'; target='uia:automation_id=body'; move_mode='instant'; force_reobserve=$true; expected_context=$ctx },
        [ordered]@{ step_id='b07_type_body'; action='type'; text='DV62 Body'; type_mode='instant'; verification_hint='uia_contains:DV62 Body'; expected_context=$ctx },
        [ordered]@{ step_id='b08_click_send'; action='click'; target='uia:automation_id=sendButton'; move_mode='instant'; force_reobserve=$true; verification_hint='uia_contains:Mock sent successfully'; expected_context=$ctx },
        [ordered]@{ step_id='b09_verify_result'; action='verify'; verification_hint='uia_contains:Mock sent successfully' }
    )
    $dispatch = Run-Dispatch -CaseDir $caseDir -SessionId $sessionId -Steps $steps -Name 'browser_form'
    $close = Invoke-WinAgentJson -WinArgs @('runtime-session-close', '--session-id', $sessionId) -OutPath (Join-Path $caseDir '99_close.json')
    $cases.case_4_browser_form_session_workflow = [ordered]@{ raw_status='RAW_COMPLETED_UNVERIFIED'; edge_profile=$edge.profile; start=$start.json; dispatch=$dispatch; close=$close.json }
}
finally {
    Close-SessionIfAny $sessionId
    if ($edge) { Stop-EdgeProfile $edge.profile }
}

# Case 5: Scroll-and-locate session workflow on local long page.
$caseDir = Join-Path $RawRoot 'case_5_scroll_and_locate_session_workflow'
New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
$edge = $null
$sessionId = ''
try {
    $edge = Start-EdgeLocalPage -Title 'DesktopVisual Long Scroll Test' -HtmlPath $LongScrollHtml -ProfileName 'edge_scroll_profile'
    $ctx = New-EdgeContext 'DesktopVisual Long Scroll Test'
    $start = Invoke-WinAgentJson -WinArgs @('runtime-session-start', '--title', 'DesktopVisual Long Scroll Test', '--process', 'msedge.exe') -OutPath (Join-Path $caseDir '00_start.json')
    $sessionId = [string]$start.json.session_id
    $steps = @(
        [ordered]@{ step_id='c01_observe'; action='observe'; cache_policy='force_reobserve' },
        [ordered]@{ step_id='c02_scroll'; action='scroll'; delta='-120'; move_mode='instant'; expected_context=$ctx },
        [ordered]@{ step_id='c03_reobserve'; action='observe'; force_reobserve=$true },
        [ordered]@{ step_id='c04_locate_target'; action='scroll_and_locate'; delta='-120'; target='uia:name=DesktopVisual List Item 010,type=ListItem'; force_reobserve=$true; move_mode='instant'; expected_context=$ctx },
        [ordered]@{ step_id='c05_click_target'; action='click'; target='uia:name=DesktopVisual List Item 010,type=ListItem'; move_mode='instant'; force_reobserve=$true; expected_context=$ctx }
    )
    $dispatch = Run-Dispatch -CaseDir $caseDir -SessionId $sessionId -Steps $steps -Name 'scroll_and_locate'
    $close = Invoke-WinAgentJson -WinArgs @('runtime-session-close', '--session-id', $sessionId) -OutPath (Join-Path $caseDir '99_close.json')
    $cases.case_5_scroll_and_locate_session_workflow = [ordered]@{ raw_status='RAW_COMPLETED_UNVERIFIED'; edge_profile=$edge.profile; start=$start.json; dispatch=$dispatch; close=$close.json }
}
finally {
    Close-SessionIfAny $sessionId
    if ($edge) { Stop-EdgeProfile $edge.profile }
}

# Case 6: Wrong context inside session.
$caseDir = Join-Path $RawRoot 'case_6_wrong_context_inside_session'
New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
$proc = Start-TestWindow
$edge = $null
$sessionId = ''
try {
    $start = Invoke-WinAgentJson -WinArgs @('runtime-session-start', '--title', 'Agent Test Window', '--process', 'TestWindow.exe') -OutPath (Join-Path $caseDir '00_start.json')
    $sessionId = [string]$start.json.session_id
    $edge = Start-EdgeLocalPage -Title 'Google Search' -HtmlPath $WrongHtml -ProfileName 'edge_wrong_context_profile'
    $ctx = New-TestWindowContext
    $steps = @(
        [ordered]@{ step_id='w01_attempt_click_wrong_foreground'; action='click'; target='uia:name=Click Me,type=Button'; move_mode='instant'; expected_context=$ctx },
        [ordered]@{ step_id='w02_must_not_continue_type'; action='type'; text='UNSAFE_CONTINUATION'; type_mode='instant'; expected_context=$ctx }
    )
    $dispatch = Run-Dispatch -CaseDir $caseDir -SessionId $sessionId -Steps $steps -Name 'wrong_context'
    $close = Invoke-WinAgentJson -WinArgs @('runtime-session-close', '--session-id', $sessionId) -AllowedExitCodes @(0, 1) -OutPath (Join-Path $caseDir '99_close.json')
    $cases.case_6_wrong_context_inside_session = [ordered]@{ raw_status='RAW_COMPLETED_UNVERIFIED'; edge_profile=$edge.profile; start=$start.json; dispatch=$dispatch; close=$close.json }
}
finally {
    Close-SessionIfAny $sessionId
    if ($edge) { Stop-EdgeProfile $edge.profile }
    if ($proc -and !$proc.HasExited) { $proc.CloseMainWindow() | Out-Null; Start-Sleep -Milliseconds 300; if (!$proc.HasExited) { Stop-Process -Id $proc.Id -Force } }
}

# Case 7: Cache invalidation is delegated to the dedicated raw cache selftest evidence.
$cases.case_7_cache_invalidation = [ordered]@{
    raw_status = 'RAW_COMPLETED_UNVERIFIED'
    evidence = (Join-Path $ArtifactRoot 'runtime_session_cache_selftest_result.json')
}

# Case 8: Latency comparison is delegated to the dedicated latency benchmark evidence.
$cases.case_8_latency_comparison = [ordered]@{
    raw_status = 'RAW_COMPLETED_UNVERIFIED'
    evidence = (Join-Path $ArtifactRoot 'latency_report.json')
}

$runner = [ordered]@{
    schema_version = 'v6.2.0.persistent_runtime.runner.raw'
    generated_at = (Get-Date).ToString('o')
    status = 'RAW_COMPLETED_UNVERIFIED'
    raw_completed_unverified = $true
    root = $Root
    artifact_root = $ArtifactRoot
    raw_root = $RawRoot
    cases = $cases
}
Write-JsonFile -Path $RunnerResultPath -Value $runner

@(
    '# v6.2.0 Persistent Runtime Runner Raw Report',
    '',
    '- Status: RAW_COMPLETED_UNVERIFIED',
    '- This runner does not declare PASS.',
    "- Raw result: $RunnerResultPath",
    "- Raw root: $RawRoot",
    '',
    '## Cases',
    '- Case 1: session lifecycle',
    '- Case 2: one-shot compatibility',
    '- Case 3: 10-step session workflow',
    '- Case 4: local Edge mail mock browser form workflow',
    '- Case 5: local long page scroll-and-locate workflow',
    '- Case 6: wrong context inside session',
    '- Case 7: cache invalidation evidence pointer',
    '- Case 8: latency comparison evidence pointer'
) | Set-Content -LiteralPath $RunnerReportPath -Encoding UTF8

Write-Output 'RAW_COMPLETED_UNVERIFIED'
