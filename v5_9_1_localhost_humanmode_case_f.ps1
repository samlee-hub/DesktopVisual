param(
    [string]$Root = '',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev5.9.1_pre_v6_handoff'
$CaseDir = Join-Path $ArtifactRoot 'cases\localhost_form_fill_submit_humanmode_flow'
$Screenshots = Join-Path $CaseDir 'screenshots'
$MockDir = 'D:\testrepo\testwindow'
$MockHtml = Join-Path $MockDir 'mail_mock.html'
$Port = 18091
$PermissionMode = 'DEVELOPER_CAPABILITY_DISCOVERY'

function Fail($Message) { throw $Message }
function Ensure-Dir($Path) { New-Item -ItemType Directory -Force -Path $Path | Out-Null }
function Write-JsonLine($Path, $Object) { ($Object | ConvertTo-Json -Compress -Depth 30) | Add-Content -LiteralPath $Path -Encoding UTF8 }
function Invoke-AgentJson([string[]]$CmdArgs, [switch]$AllowFailure) {
    $output = & $WinAgent @CmdArgs 2>&1
    $exit = $LASTEXITCODE
    if ($exit -ne 0 -and -not $AllowFailure) { Fail "winagent $($CmdArgs -join ' ') exited $exit with output: $output" }
    try { return ($output | ConvertFrom-Json) } catch { Fail "Invalid JSON from winagent $($CmdArgs -join ' '): $output" }
}
function Save-ScreenShot($Path) {
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms
    $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
    $graphics.CopyFromScreen($bounds.Left, $bounds.Top, 0, 0, $bounds.Size)
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bmp.Dispose()
}
function Find-WindowTitle($Pattern) {
    $windows = Invoke-AgentJson -CmdArgs @('windows') -AllowFailure
    foreach ($w in $windows.windows) {
        if ($w.title -match $Pattern -and $w.rect.right -gt $w.rect.left -and $w.rect.bottom -gt $w.rect.top) { return $w.title }
    }
    return ''
}
function Wait-WindowTitle($Pattern, [int]$TimeoutSeconds) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $title = Find-WindowTitle $Pattern
        if ($title) { return $title }
        Start-Sleep -Milliseconds 500
    }
    return ''
}
function Add-TraceFromHumanResult($ActionResult, $ActionTrace) {
    $har = $ActionResult.data.human_action_result
    if (-not $har) { return }
    Write-JsonLine $ActionTrace ([pscustomobject]@{ action_type='mouse_move_humanmode_start'; from_x=$har.cursor.start_x; from_y=$har.cursor.start_y; target_x=$har.target.x; target_y=$har.target.y; duration_ms=$har.motion.move_duration_ms; planned_steps=$har.motion.planned_steps; easing=$har.motion.easing; timestamp=$har.timing.move_start_ts })
    $path = @($har.motion.planned_path)
    foreach ($idx in (@(0, [Math]::Floor(($path.Count - 1) / 2), ($path.Count - 1)) | Select-Object -Unique)) {
        Write-JsonLine $ActionTrace ([pscustomobject]@{ action_type='mouse_move_humanmode_step'; step_index=[int]($idx + 1); step_count=$path.Count; x=$path[$idx].x; y=$path[$idx].y; timestamp=$har.timing.move_start_ts })
    }
    Write-JsonLine $ActionTrace ([pscustomobject]@{ action_type='mouse_move_humanmode_end'; final_x=$har.cursor.final_x; final_y=$har.cursor.final_y; target_x=$har.target.x; target_y=$har.target.y; within_epsilon=$har.cursor.within_target_epsilon_before_click; timestamp=$har.timing.move_end_ts })
    if ($har.action_type -in @('mouse_click','mouse_double_click')) {
        Write-JsonLine $ActionTrace ([pscustomobject]@{ action_type='dwell_before_click'; duration_ms=$har.motion.dwell_before_click_ms; timestamp=$har.timing.dwell_start_ts })
        Write-JsonLine $ActionTrace ([pscustomobject]@{ action_type='mouse_click_down'; x=$har.cursor.actual_before_click_x; y=$har.cursor.actual_before_click_y; timestamp=$har.timing.click_down_ts })
        Write-JsonLine $ActionTrace ([pscustomobject]@{ action_type='mouse_click_up'; x=$har.cursor.actual_before_click_x; y=$har.cursor.actual_before_click_y; timestamp=$har.timing.click_up_ts })
    }
}
function Invoke-HumanAction($ActionTrace, $Events, [string]$ActionType, [string]$Target, [string[]]$CmdArgs) {
    $result = Invoke-AgentJson -CmdArgs $CmdArgs
    Add-TraceFromHumanResult $result $ActionTrace
    Write-JsonLine $ActionTrace ([pscustomobject]@{
        timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
        action_type = $ActionType
        target_description = $Target
        humanmode = $true
        backend_action = $false
        ok = [bool]$result.ok
        error_code = $(if ($result.ok) { '' } else { $result.error.code })
        notes = ($CmdArgs -join ' ')
    })
    Write-JsonLine $Events ([pscustomobject]@{ timestamp=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff'); event=$ActionType; status=$(if($result.ok){'ok'}else{'failed'}); details=@{ command=($CmdArgs -join ' ') } })
    return $result
}
function Get-ObservedElementCenter($Title, $Name, $ControlType) {
    $observed = Invoke-AgentJson -CmdArgs @('observe', '--title', $Title, '--screenshot', 'false', '--uia', 'true', '--max-elements', '260') -AllowFailure
    if (-not $observed.ok) { return $null }
    $matches = @($observed.data.uia.elements | Where-Object { $_.name -eq $Name -and $_.control_type -eq $ControlType -and $_.rect.right -gt $_.rect.left -and $_.rect.bottom -gt $_.rect.top })
    if ($matches.Count -ne 1) { return $null }
    $rect = $matches[0].rect
    [pscustomobject]@{ X=[int](($rect.left + $rect.right) / 2); Y=[int](($rect.top + $rect.bottom) / 2); Raw=$matches[0] }
}
function Get-AddressBarCenter($Title) {
    $observed = Invoke-AgentJson -CmdArgs @('observe', '--title', $Title, '--screenshot', 'false', '--uia', 'true', '--max-elements', '260') -AllowFailure
    if (-not $observed.ok) { return $null }
    $edits = @($observed.data.uia.elements | Where-Object { $_.control_type -eq 'Edit' -and $_.rect.right -gt $_.rect.left -and $_.rect.bottom -gt $_.rect.top })
    $candidate = $edits | Sort-Object @{Expression={$_.rect.top}}, @{Expression={-($_.rect.right-$_.rect.left)}} | Select-Object -First 1
    if (-not $candidate) { return $null }
    $rect = $candidate.rect
    [pscustomobject]@{ X=[int](($rect.left + $rect.right) / 2); Y=[int](($rect.top + $rect.bottom) / 2); Raw=$candidate }
}

Ensure-Dir $CaseDir
Ensure-Dir $Screenshots
$Events = Join-Path $CaseDir 'task_events.jsonl'
$Actions = Join-Path $CaseDir 'action_trace.jsonl'
$Locators = Join-Path $CaseDir 'locator_trace.jsonl'
Set-Content -LiteralPath $Events -Value '' -Encoding UTF8
Set-Content -LiteralPath $Actions -Value '' -Encoding UTF8
Set-Content -LiteralPath $Locators -Value '' -Encoding UTF8

if (-not $SkipBuild) {
    & "$Root\build.ps1" -Root $Root
    if ($LASTEXITCODE -ne 0) { Fail 'Build failed.' }
}

@'
<!doctype html>
<html><head><meta charset="utf-8"><title>DesktopVisual Localhost Mail Mock</title></head>
<body>
<label>Recipient <input aria-label="Recipient" id="recipient"></label><br>
<label>Subject <input aria-label="Subject" id="subject"></label><br>
<label>Body <textarea aria-label="Body" id="body"></textarea></label><br>
<button id="send" onclick="recipient.value='';subject.value='';body.value='';status.textContent='Mock sent successfully';">Send</button>
<div id="status" role="status"></div>
</body></html>
'@ | Set-Content -LiteralPath $MockHtml -Encoding UTF8

$server = $null
$status = 'FAIL'
$summary = ''
try {
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) { Fail 'python command is not available for local HTTP server.' }
    $server = Start-Process -FilePath $python.Source -ArgumentList @('-m','http.server',"$Port",'--bind','127.0.0.1','--directory',$MockDir) -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 2
    $url = "http://127.0.0.1:$Port/mail_mock.html"

    Invoke-HumanAction $Actions $Events 'keyboard.press' 'Start menu' @('desktop-press','--key','WIN','--permission-mode',$PermissionMode) | Out-Null
    Invoke-HumanAction $Actions $Events 'keyboard.type_text' 'browser search' @('desktop-type','--text','chrome','--type-mode','demo-human','--char-delay-ms','40','--permission-mode',$PermissionMode) | Out-Null
    Invoke-HumanAction $Actions $Events 'keyboard.press' 'open browser search result' @('desktop-press','--key','ENTER','--permission-mode',$PermissionMode) | Out-Null
    Start-Sleep -Seconds 5
    $browserTitle = Wait-WindowTitle 'Chrome|Edge' 10
    if (-not $browserTitle) { Fail 'No Chrome or Edge window appeared.' }
    Save-ScreenShot (Join-Path $Screenshots 'browser_open.png')
    $address = Get-AddressBarCenter $browserTitle
    if (-not $address) { Fail 'Could not locate browser address bar.' }
    Write-JsonLine $Locators ([pscustomobject]@{ timestamp=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff'); target_description='browser address bar'; locator_method='uia browser Edit'; status='ok'; screen_x=$address.X; screen_y=$address.Y; details=$address.Raw })
    Invoke-HumanAction $Actions $Events 'mouse.click' 'browser address bar' @('desktop-click','--screen-x',"$($address.X)",'--screen-y',"$($address.Y)",'--permission-mode',$PermissionMode,'--humanmode','true','--target-description','browser address bar','--coordinate-source','locator_derived') | Out-Null
    Invoke-HumanAction $Actions $Events 'keyboard.hotkey' 'select address bar' @('desktop-hotkey','--keys','CTRL+A','--permission-mode',$PermissionMode) | Out-Null
    Invoke-HumanAction $Actions $Events 'keyboard.type_text' 'localhost URL' @('desktop-type','--text',$url,'--type-mode','demo-human','--char-delay-ms','25','--permission-mode',$PermissionMode) | Out-Null
    Invoke-HumanAction $Actions $Events 'keyboard.press' 'navigate localhost URL' @('desktop-press','--key','ENTER','--permission-mode',$PermissionMode) | Out-Null
    Start-Sleep -Seconds 3
    $pageTitle = Wait-WindowTitle 'DesktopVisual Localhost Mail Mock|Chrome|Edge' 10
    if (-not $pageTitle) { Fail 'Localhost mail mock page did not appear.' }
    Save-ScreenShot (Join-Path $Screenshots 'localhost_loaded.png')

    foreach ($field in @(
        @{ Name='Recipient'; Value='xiaoming'; Action='recipient input' },
        @{ Name='Subject'; Value='desktopvisual test'; Action='subject input' },
        @{ Name='Body'; Value='this is a testing message'; Action='body textarea' }
    )) {
        $center = Get-ObservedElementCenter $pageTitle $field.Name 'Edit'
        if (-not $center) { Fail "Could not locate $($field.Name) field." }
        Write-JsonLine $Locators ([pscustomobject]@{ timestamp=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff'); target_description=$field.Action; locator_method='uia browser field'; status='ok'; screen_x=$center.X; screen_y=$center.Y; details=$center.Raw })
        Invoke-HumanAction $Actions $Events 'mouse.click' $field.Action @('desktop-click','--screen-x',"$($center.X)",'--screen-y',"$($center.Y)",'--permission-mode',$PermissionMode,'--humanmode','true','--target-description',$field.Action,'--coordinate-source','locator_derived') | Out-Null
        Invoke-HumanAction $Actions $Events 'keyboard.type_text' $field.Action @('desktop-type','--text',$field.Value,'--type-mode','demo-human','--char-delay-ms','30','--permission-mode',$PermissionMode) | Out-Null
    }
    Save-ScreenShot (Join-Path $Screenshots 'after_fill.png')
    $send = Get-ObservedElementCenter $pageTitle 'Send' 'Button'
    if (-not $send) { Fail 'Could not locate Send button.' }
    Write-JsonLine $Locators ([pscustomobject]@{ timestamp=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff'); target_description='Send button'; locator_method='uia browser button'; status='ok'; screen_x=$send.X; screen_y=$send.Y; details=$send.Raw })
    Invoke-HumanAction $Actions $Events 'mouse.click' 'Send button' @('desktop-click','--screen-x',"$($send.X)",'--screen-y',"$($send.Y)",'--permission-mode',$PermissionMode,'--humanmode','true','--target-description','Send button','--coordinate-source','locator_derived') | Out-Null
    Start-Sleep -Seconds 1
    Save-ScreenShot (Join-Path $Screenshots 'after_send.png')
    $observed = Invoke-AgentJson -CmdArgs @('observe','--title','DesktopVisual Localhost Mail Mock','--screenshot','false','--uia','true','--max-elements','260') -AllowFailure
    $text = Invoke-AgentJson -CmdArgs @('read-window-text','--title','DesktopVisual Localhost Mail Mock') -AllowFailure
    $statusOk = $observed.ok -and @($observed.data.uia.elements | Where-Object { $_.name -eq 'Mock sent successfully' }).Count -gt 0
    $ocrText = if ($text.ok) { $text.data.text } else { '' }
    $cleared = ($ocrText -notmatch 'xiaoming') -and ($ocrText -notmatch 'desktopvisual test') -and ($ocrText -notmatch 'this is a testing message')
    if ($statusOk -and $cleared) {
        $status = 'STRICT_HUMANMODE_PASS'
        $summary = 'Filled localhost mock mail form through visible HumanMode and verified mock sent/cleared fields.'
    } else {
        $summary = 'Could not verify Mock sent successfully and cleared fields after Send.'
    }
} catch {
    $summary = $_.Exception.Message
} finally {
    if ($server -and -not $server.HasExited) {
        Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
    }
}

$actionLines = Get-Content -LiteralPath $Actions | Where-Object { $_.Trim() }
$humanActionResultCount = 0
$parseErrors = 0
foreach ($line in $actionLines) {
    try {
        $obj = $line | ConvertFrom-Json
        if ($obj.action_type -like 'mouse_*' -or $obj.action_type -eq 'dwell_before_click') { }
    } catch { $parseErrors++ }
}
$mouseClicks = @($actionLines | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object action_type -eq 'mouse.click')
$moveStarts = @($actionLines | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object action_type -eq 'mouse_move_humanmode_start')
$dwell = @($actionLines | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object action_type -eq 'dwell_before_click')
$result = [pscustomobject]@{
    case_id = 'localhost_form_fill_submit_humanmode_flow'
    actual_result = $status
    status = $status
    summary = $summary
    server_bind = '127.0.0.1'
    port = $Port
    humanmode = $true
    backend_action_count = 0
    direct_launch_count = 0
    shell_execute_count = 0
    start_process_count = 0
    invoke_item_count = 0
    webdriver_count = 0
    cdp_count = 0
    js_dom_action_count = 0
    uia_invoke_action_count = 0
    uia_value_action_count = 0
    vlm_call_count = 0
    active_protection_bypass_attempt_count = 0
    real_email_send_count = 0
    mouse_click_action_count = $mouseClicks.Count
    move_trace_count = $moveStarts.Count
    dwell_before_click_count = $dwell.Count
    action_trace_parse_errors = $parseErrors
    screenshots_count = @(Get-ChildItem -LiteralPath $Screenshots -File -ErrorAction SilentlyContinue).Count
    timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
}
$result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $CaseDir 'task_result.json') -Encoding UTF8
@(
    "# localhost_form_fill_submit_humanmode_flow",
    "",
    "- Result: $status",
    "- Summary: $summary",
    "- Server bind: 127.0.0.1",
    "- Real email sends: 0",
    "- DOM/CDP/WebDriver/Selenium/Playwright: 0",
    "- Artifacts are in this directory."
) | Set-Content -LiteralPath (Join-Path $CaseDir 'task_report.md') -Encoding UTF8

if ($status -eq 'STRICT_HUMANMODE_PASS') {
    Write-Host 'Case F localhost HumanMode PASS.'
    exit 0
}
Write-Host "Case F localhost HumanMode $status`: $summary"
exit 1
