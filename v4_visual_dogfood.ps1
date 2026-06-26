param(
    [string]$Root = '',
    [switch]$Help,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\v4_visual_dogfood.ps1 [-Root <path>] [-SkipBuild]'
    Write-Host 'Runs v4.6 visual dogfood on bounded local developer workflow fixtures.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$TestRepoRoot = & (Join-Path $Root 'scripts\Resolve-TestRepoRoot.ps1') -Root $Root
$TestWindowRoot = Join-Path $TestRepoRoot 'testwindow'
$TestWindowExe = Join-Path $TestWindowRoot 'bin\TestWindow.exe'
$Artifacts = Join-Path $Root 'artifacts\dev4.6.0'
$Fixtures = Join-Path $Artifacts 'fixtures'
$DogfoodReport = Join-Path $Artifacts 'dogfood_report.md'
$SummaryJson = Join-Path $Artifacts 'dogfood_summary.json'

function Fail($Message) { throw $Message }

function Write-Utf8 {
    param([string]$Path, [string]$Value)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

function New-Case {
    param([string]$Name, [string]$ProfileName = '')
    return [ordered]@{
        name = $Name
        status = 'PASS'
        reason = ''
        profile = $ProfileName
        commands = New-Object System.Collections.Generic.List[object]
        artifacts = New-Object System.Collections.Generic.List[string]
        screenshots = New-Object System.Collections.Generic.List[string]
        observed_events = New-Object System.Collections.Generic.List[string]
        locator_methods = New-Object System.Collections.Generic.List[string]
        perception = [ordered]@{}
        latency_ms = 0
        safety = 'bounded_local_fixture'
    }
}

function Add-Artifact {
    param([hashtable]$Case, [string]$Path)
    if ($Path -and (Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue)) {
        $Case.artifacts.Add($Path) | Out-Null
    }
}

function Invoke-AgentJson {
    param(
        [hashtable]$Case,
        [string[]]$WinArgs,
        [int[]]$AllowedExitCodes = @(0)
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $output = & $WinAgent @WinArgs 2>&1
    $exit = $LASTEXITCODE
    $sw.Stop()
    $text = ($output | Out-String).Trim()
    $record = [ordered]@{
        command = "winagent $($WinArgs -join ' ')"
        exit_code = $exit
        duration_ms = [int]$sw.ElapsedMilliseconds
        ok_exit = ($AllowedExitCodes -contains $exit)
    }
    $Case.commands.Add($record) | Out-Null
    $Case.latency_ms += [int]$sw.ElapsedMilliseconds
    if ($AllowedExitCodes -notcontains $exit) {
        Fail "winagent $($WinArgs -join ' ') exited $exit with output: $text"
    }
    try {
        $json = $text | ConvertFrom-Json
    } catch {
        Fail "Invalid JSON from winagent $($WinArgs -join ' '): $text"
    }
    return @{ exit = $exit; text = $text; json = $json }
}

function Start-TestWindow {
    if (!(Test-Path -LiteralPath $TestWindowExe)) { Fail "Missing TestWindow.exe: $TestWindowExe" }
    Get-Process TestWindow -ErrorAction SilentlyContinue | ForEach-Object {
        $_.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 250
        if (!$_.HasExited) { Stop-Process -Id $_.Id -Force }
    }
    $proc = Start-Process -FilePath $TestWindowExe -PassThru
    $deadline = (Get-Date).AddSeconds(10)
    $probe = New-Case -Name 'wait_testwindow'
    do {
        Start-Sleep -Milliseconds 250
        $find = Invoke-AgentJson -Case $probe -WinArgs @('find', '--title', 'Agent Test Window') -AllowedExitCodes @(0, 1)
    } while ($find.exit -ne 0 -and (Get-Date) -lt $deadline)
    if ($find.exit -ne 0) { Fail 'Agent Test Window did not appear.' }
    return $proc
}

function Stop-TestWindowProcess($Proc) {
    if ($Proc -and !$Proc.HasExited) {
        $Proc.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 250
        if (!$Proc.HasExited) { Stop-Process -Id $Proc.Id -Force }
    }
}

function Invoke-V4PerceptionProbe {
    param(
        [hashtable]$Case,
        [string]$ProfileName = ''
    )
    $caseDir = Join-Path $Artifacts ($Case.name -replace '[^A-Za-z0-9_.-]', '_')
    New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
    $eventsPath = Join-Path $caseDir 'events.jsonl'
    $loopReport = Join-Path $caseDir 'observe_loop_report.md'
    Remove-Item -LiteralPath $eventsPath,$loopReport -ErrorAction SilentlyContinue

    $observe2 = Invoke-AgentJson -Case $Case -WinArgs @('observe2', '--title', 'Agent Test Window', '--screenshot', '--include-uia', '--max-elements', '30')
    if ($observe2.json.ok -ne $true) { Fail "observe2 failed for $($Case.name)" }
    $data = $observe2.json.data
    foreach ($field in @('screen_frame', 'element_graph', 'locator_candidates', 'scene_state', 'change_events', 'providers')) {
        if ($null -eq $data.$field) { Fail "observe2 missing $field for $($Case.name)" }
    }
    $candidateCount = @($data.locator_candidates).Count
    $nodeCount = @($data.element_graph.nodes).Count
    if ($candidateCount -lt 1 -or $nodeCount -lt 1) {
        Fail "observe2 did not produce ElementGraph/LocatorCandidate evidence for $($Case.name)"
    }
    $Case.perception['observe2_schema_version'] = [string]$data.schema_version
    $Case.perception['element_graph_nodes'] = $nodeCount
    $Case.perception['locator_candidates'] = $candidateCount
    $Case.perception['scene_state'] = [string]$data.scene_state.status
    $Case.perception['provider_count'] = @($data.providers).Count
    $Case.locator_methods.Add('observe2:ElementGraph') | Out-Null
    $Case.locator_methods.Add('observe2:LocatorCandidate') | Out-Null
    $Case.locator_methods.Add('SceneState:' + [string]$data.scene_state.status) | Out-Null
    foreach ($event in @($data.change_events)) {
        if ($event.type) { $Case.observed_events.Add([string]$event.type) | Out-Null }
    }
    if ($data.screen_frame.artifact_path) {
        $Case.screenshots.Add([string]$data.screen_frame.artifact_path) | Out-Null
    }
    $screenPath = Join-Path $caseDir 'screen.bmp'
    $screenshot = Invoke-AgentJson -Case $Case -WinArgs @('screenshot', '--title', 'Agent Test Window', '--out', $screenPath)
    if ($screenshot.json.ok -ne $true -or !(Test-Path -LiteralPath $screenPath)) {
        Fail "screenshot artifact was not written for $($Case.name)"
    }
    $Case.screenshots.Add($screenPath) | Out-Null

    $profile = Invoke-AgentJson -Case $Case -WinArgs @('profile-report')
    if ($profile.json.data.loaded_count -lt 1) { Fail 'profile-report did not load profiles.' }
    if ($ProfileName) {
        $matched = @($profile.json.data.profiles | Where-Object { $_.profile_name -eq $ProfileName })
        if ($matched.Count -lt 1) { Fail "profile $ProfileName was not loaded." }
        $Case.locator_methods.Add("AppProfile:$ProfileName") | Out-Null
    }
    $locate = Invoke-AgentJson -Case $Case -WinArgs @('locate', '--title', 'Agent Test Window', '--profile', 'testwindow', '--profile-locator', 'click_button')
    if ($locate.json.ok -ne $true -or $locate.json.data.profile_candidate.source -ne 'app_profile') {
        Fail "profile locator did not produce app_profile metadata for $($Case.name)"
    }
    $Case.locator_methods.Add('AppProfile:testwindow.click_button') | Out-Null

    $loop = Invoke-AgentJson -Case $Case -WinArgs @(
        'observe-loop',
        '--title', 'Agent Test Window',
        '--interval-ms', '100',
        '--max-duration-ms', '900',
        '--max-events', '3',
        '--max-no-change-rounds', '4',
        '--roi', '0,0,400,300',
        '--changed-regions-only',
        '--out', $eventsPath,
        '--report', $loopReport
    )
    if ($loop.json.ok -ne $true -or !(Test-Path -LiteralPath $eventsPath)) {
        Fail "observe-loop did not write events for $($Case.name)"
    }
    Add-Artifact -Case $Case -Path $eventsPath
    Add-Artifact -Case $Case -Path $loopReport
    $parsed = @(Get-Content -LiteralPath $eventsPath | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
    foreach ($event in $parsed) {
        if ($event.type) { $Case.observed_events.Add([string]$event.type) | Out-Null }
    }
    $Case.perception['observe_loop_events'] = $parsed.Count
    $Case.perception['cache_hits'] = $loop.json.data.cache_hits
    $Case.perception['cache_misses'] = $loop.json.data.cache_misses
    $Case.locator_methods.Add('Delta:observe-loop changed-regions-only roi=0,0,400,300') | Out-Null
}

function Complete-Case {
    param([hashtable]$Case)
    $Case['commands'] = @($Case.commands.ToArray())
    $Case['observed_events'] = @($Case.observed_events | Select-Object -Unique)
    $Case['locator_methods'] = @($Case.locator_methods | Select-Object -Unique)
    $Case['artifacts'] = @($Case.artifacts | Select-Object -Unique)
    $Case['screenshots'] = @($Case.screenshots | Select-Object -Unique)
    return [pscustomobject]$Case
}

function Invoke-CaseBody {
    param([hashtable]$Case, [scriptblock]$Body)
    try {
        & $Body
    } catch {
        $Case.status = 'FAIL'
        $Case.reason = [string]$_
    }
    if (-not $Case.reason) { $Case.reason = 'completed' }
    return Complete-Case -Case $Case
}

if (-not $SkipBuild) {
    & (Join-Path $Root 'build.ps1') -Root $Root
    if ($LASTEXITCODE -ne 0) { Fail 'build.ps1 failed.' }
}
if (!(Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run build.ps1 first." }

New-Item -ItemType Directory -Force -Path $Artifacts,$Fixtures | Out-Null
Remove-Item -LiteralPath $DogfoodReport,$SummaryJson -ErrorAction SilentlyContinue

$version = (& $WinAgent version | ConvertFrom-Json).data.version
$cases = New-Object System.Collections.Generic.List[object]
$tw = $null
$tw = Start-TestWindow
try {
    $case = New-Case -Name 'local_html_form_flow' -ProfileName 'browser_local'
    $cases.Add((Invoke-CaseBody -Case $case -Body {
        $html = Join-Path $Fixtures 'local_html_form_flow.html'
        Write-Utf8 $html @'
<!doctype html>
<html><body data-state="normal">
<label for="name">Name</label><input id="name" data-label="Name" type="text" value="">
<label for="terms">Terms</label><input id="terms" data-label="Terms" type="checkbox">
<button id="submit" data-ready="true" data-label="Submit">Submit</button>
</body></html>
'@
        Add-Artifact -Case $case -Path $html
        Invoke-V4PerceptionProbe -Case $case -ProfileName 'browser_local'
        foreach ($field in @('name', 'terms', 'submit')) {
            $fc = Invoke-AgentJson -Case $case -WinArgs @('form-control', '--html', $html, '--field-id', $field)
            if ($fc.json.ok -ne $true) { Fail "form-control failed for $field" }
            $case.locator_methods.Add('form-control:' + $field) | Out-Null
        }
        $du = Invoke-AgentJson -Case $case -WinArgs @('dynamic-ui-recovery', '--html', $html, '--candidate-id', 'submit', '--semantic-status', 'resolved', '--risk-status', 'normal')
        if ($du.json.data.scene_state.status -notin @('normal', 'success')) { Fail 'Unexpected form scene state.' }
        foreach ($event in @($du.json.data.change_events)) { if ($event.type) { $case.observed_events.Add([string]$event.type) | Out-Null } }
        $case.safety = 'local_html_fixture_no_external_web'
    })) | Out-Null

    $case = New-Case -Name 'local_problem_page_run_and_read_result' -ProfileName 'local_problem_page'
    $cases.Add((Invoke-CaseBody -Case $case -Body {
        $loading = Join-Path $Fixtures 'local_problem_loading.html'
        $ready = Join-Path $Fixtures 'local_problem_ready.html'
        Write-Utf8 $loading @'
<html><body data-state="loading"><h1>Mock Practice Problem</h1><div>Loading...</div><button id="run" disabled>Run Code</button></body></html>
'@
        Write-Utf8 $ready @'
<html data-problem-title="Mock Practice Problem"><body data-state="success">
<h1>Mock Practice Problem</h1>
<section id="problem_statement">Development benchmark only. Add two local integers.</section>
<textarea id="code" data-control-type="code_editor" data-label="Code Editor"></textarea>
<button id="run" data-ready="true">Run Code</button>
<div id="result" data-result="sample_pass">Sample Pass</div>
</body></html>
'@
        Add-Artifact -Case $case -Path $loading
        Add-Artifact -Case $case -Path $ready
        Invoke-V4PerceptionProbe -Case $case -ProfileName 'local_problem_page'
        $du = Invoke-AgentJson -Case $case -WinArgs @('dynamic-ui-recovery', '--html', $ready, '--previous-html', $loading, '--candidate-id', 'run', '--semantic-status', 'resolved', '--risk-status', 'normal')
        foreach ($event in @($du.json.data.change_events)) { if ($event.type) { $case.observed_events.Add([string]$event.type) | Out-Null } }
        if (@($du.json.data.change_events | Where-Object { $_.type -eq 'loading_finished' }).Count -lt 1) { Fail 'Problem page did not emit loading_finished.' }
        $eval = Invoke-AgentJson -Case $case -WinArgs @('coding-eval', '--html', $ready, '--user-goal', 'development benchmark mock problem; not exam or assessment', '--action', 'run_code', '--language', 'cpp', '--code', 'int add(int a,int b){return a+b;}')
        if ($eval.json.data.coding_workflow_context.result_state -ne 'SAMPLE_PASS') { Fail 'Mock OJ result was not SAMPLE_PASS.' }
        $case.locator_methods.Add('coding-eval:local_mock_problem') | Out-Null
        $case.safety = 'local_mock_problem_development_benchmark_not_exam'
    })) | Out-Null

    $case = New-Case -Name 'local_mail_mock_compose_attach_verify_no_real_send' -ProfileName 'local_mail_mock'
    $cases.Add((Invoke-CaseBody -Case $case -Body {
        $attach = Join-Path $Fixtures 'mail_mock_attachment.txt'
        $draft = Join-Path $Fixtures 'mail_mock_draft.html'
        $sent = Join-Path $Fixtures 'mail_mock_sent.html'
        Write-Utf8 $attach 'mock attachment payload; local only'
        Write-Utf8 $draft @'
<html><body data-state="loading">
<button id="compose" data-label="Compose">Compose</button>
<input id="to" data-label="To" value="mock@example.local">
<input id="subject" data-label="Subject" value="Mock only">
<input id="attachment" data-label="Attachment" value="uploading">
<button id="send_mock" disabled data-label="Send Mock">Send Mock</button>
<div id="progress">Upload progress 50%</div>
</body></html>
'@
        Write-Utf8 $sent @'
<html><body data-state="success">
<button id="compose" data-label="Compose">Compose</button>
<input id="to" data-label="To" value="mock@example.local">
<input id="subject" data-label="Subject" value="Mock only">
<input id="attachment" data-label="Attachment" value="upload complete">
<button id="send_mock" data-ready="true" data-label="Send Mock">Send Mock</button>
<div id="progress">Upload complete</div>
<div id="sent_state">Sent state mock verified; no real send performed</div>
</body></html>
'@
        Add-Artifact -Case $case -Path $attach
        Add-Artifact -Case $case -Path $draft
        Add-Artifact -Case $case -Path $sent
        Invoke-V4PerceptionProbe -Case $case -ProfileName 'local_mail_mock'
        foreach ($field in @('compose', 'to', 'subject', 'attachment', 'send_mock')) {
            $fc = Invoke-AgentJson -Case $case -WinArgs @('form-control', '--html', $sent, '--field-id', $field)
            if ($fc.json.ok -ne $true) { Fail "mail mock control failed for $field" }
        }
        $du = Invoke-AgentJson -Case $case -WinArgs @('dynamic-ui-recovery', '--html', $sent, '--previous-html', $draft, '--candidate-id', 'send_mock', '--semantic-status', 'resolved', '--risk-status', 'normal')
        foreach ($event in @($du.json.data.change_events)) { if ($event.type) { $case.observed_events.Add([string]$event.type) | Out-Null } }
        $htmlText = Get-Content -LiteralPath $sent -Raw
        if ($htmlText -notmatch 'Upload complete' -or $htmlText -notmatch 'no real send performed') { Fail 'Mail mock did not prove upload completion and mock sent state.' }
        $case.locator_methods.Add('AppProfile:local_mail_mock.roi_definitions') | Out-Null
        $case.safety = 'local_mail_mock_no_real_send_no_account'
    })) | Out-Null

    $case = New-Case -Name 'explorer_temp_file_select_flow' -ProfileName 'explorer'
    $cases.Add((Invoke-CaseBody -Case $case -Body {
        $dir = Join-Path $Fixtures 'explorer_temp_file_select_flow'
        $file = Join-Path $dir 'selected_file.txt'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Write-Utf8 $file 'selected file marker for Explorer temp dogfood'
        Add-Artifact -Case $case -Path $file
        Invoke-V4PerceptionProbe -Case $case -ProfileName 'explorer'
        $read = Invoke-AgentJson -Case $case -WinArgs @('read-file', '--path', $file)
        if ($read.json.data.content -notmatch 'selected file marker') { Fail 'Explorer temp selected file content was not verified.' }
        $case.locator_methods.Add('AppProfile:explorer.address_bar') | Out-Null
        $case.locator_methods.Add('filesystem:selected_file_under_artifacts') | Out-Null
        $case.safety = 'explorer_temp_directory_under_artifacts_only'
    })) | Out-Null

    $case = New-Case -Name 'notepad_text_edit_verify' -ProfileName 'notepad'
    $cases.Add((Invoke-CaseBody -Case $case -Body {
        $existing = @(Get-Process notepad -ErrorAction SilentlyContinue)
        if ($existing.Count -gt 0) {
            $case.status = 'SKIPPED'
            $case.reason = 'Existing Notepad process found; skipped to avoid user session.'
            return
        }
        $dir = Join-Path $Fixtures 'notepad'
        $file = Join-Path $dir 'notepad_v46.txt'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Write-Utf8 $file ''
        $proc = Start-Process notepad.exe -ArgumentList ('"{0}"' -f $file) -PassThru
        try {
            Start-Sleep -Milliseconds 900
            $title = Split-Path -Leaf $file
            $find = Invoke-AgentJson -Case $case -WinArgs @('find', '--title', $title) -AllowedExitCodes @(0, 1)
            if ($find.exit -ne 0) {
                $case.status = 'SKIPPED'
                $case.reason = 'Notepad temp file window was not found.'
                return
            }
            $obs = Invoke-AgentJson -Case $case -WinArgs @('observe2', '--title', $title, '--screenshot', '--include-uia', '--max-elements', '30')
            if ($obs.json.ok -ne $true) { Fail 'Notepad observe2 failed.' }
            $case.locator_methods.Add('observe2:notepad') | Out-Null
            if ($obs.json.data.screen_frame.artifact_path) { $case.screenshots.Add([string]$obs.json.data.screen_frame.artifact_path) | Out-Null }
            $marker = 'DV_V46_NOTEPAD_' + [Guid]::NewGuid().ToString('N')
            $typed = Invoke-AgentJson -Case $case -WinArgs @('type', '--title', $title, '--text', $marker) -AllowedExitCodes @(0, 1)
            if ($typed.exit -ne 0) {
                $case.status = 'SKIPPED'
                $case.reason = 'Notepad type path unavailable: ' + $typed.json.error.code
                return
            }
            Invoke-AgentJson -Case $case -WinArgs @('hotkey', '--title', $title, '--keys', 'CTRL+S') | Out-Null
            Start-Sleep -Milliseconds 500
            $content = Get-Content -LiteralPath $file -Raw
            if ($content -notmatch [regex]::Escape($marker)) { Fail 'Notepad saved file did not contain marker.' }
            Add-Artifact -Case $case -Path $file
            $case.locator_methods.Add('AppProfile:notepad.edit_area') | Out-Null
            $case.safety = 'clean_notepad_temp_file_under_artifacts'
        } finally {
            if ($proc -and !$proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
        }
    })) | Out-Null

    $case = New-Case -Name 'powershell_command_result_read' -ProfileName ''
    $cases.Add((Invoke-CaseBody -Case $case -Body {
        $dir = Join-Path $Fixtures 'powershell'
        $out = Join-Path $dir 'command_result.txt'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $value = 'DV_V46_POWERSHELL_' + [Guid]::NewGuid().ToString('N')
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Set-Content -LiteralPath '$out' -Encoding UTF8 -Value '$value'"
        if ($LASTEXITCODE -ne 0) { Fail 'Local PowerShell command failed.' }
        Add-Artifact -Case $case -Path $out
        Invoke-V4PerceptionProbe -Case $case
        $read = Invoke-AgentJson -Case $case -WinArgs @('read-file', '--path', $out)
        if ($read.json.data.content -notmatch [regex]::Escape($value)) { Fail 'PowerShell result file did not match expected marker.' }
        $case.locator_methods.Add('read-file:allowed_artifact_result') | Out-Null
        $case.safety = 'local_non_admin_powershell_output_under_artifacts'
    })) | Out-Null
} finally {
    Stop-TestWindowProcess $tw
}

$caseList = @($cases.ToArray())
$pass = @($caseList | Where-Object { $_.status -eq 'PASS' }).Count
$fail = @($caseList | Where-Object { $_.status -eq 'FAIL' }).Count
$skip = @($caseList | Where-Object { $_.status -eq 'SKIPPED' }).Count
$mail = @($caseList | Where-Object { $_.name -eq 'local_mail_mock_compose_attach_verify_no_real_send' })[0]
$overall = if ($pass -ge 4 -and $fail -eq 0 -and $mail.status -eq 'PASS') { 'PASS' } else { 'FAIL' }

$summary = [ordered]@{
    version = $version
    generated_at = (Get-Date).ToString('s')
    overall = $overall
    pass = $pass
    fail = $fail
    skipped = $skip
    cases = $caseList
    notes = @(
        'v4.6 dogfood uses local fixtures and bounded normal-user windows only.',
        'local_mail_mock verifies upload completion and sent mock state without real send.',
        'local_problem_page is a development benchmark, not exam or assessment automation.'
    )
}
$summary | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -LiteralPath $SummaryJson

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# DesktopVisual v4.6.0 Visual Dogfood Report') | Out-Null
$lines.Add('') | Out-Null
$lines.Add("- Result: $overall") | Out-Null
$lines.Add("- Version: $version") | Out-Null
$lines.Add("- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')") | Out-Null
$lines.Add("- PASS: $pass") | Out-Null
$lines.Add("- FAIL: $fail") | Out-Null
$lines.Add("- SKIPPED: $skip") | Out-Null
$lines.Add("- Summary JSON: $SummaryJson") | Out-Null
$lines.Add('') | Out-Null
$lines.Add('## Cases') | Out-Null
$lines.Add('') | Out-Null
$lines.Add('| case name | status | safety | locator methods used | observed events | artifacts | screenshots | latency ms | failure reason |') | Out-Null
$lines.Add('|---|---|---|---|---|---:|---:|---:|---|') | Out-Null
foreach ($caseItem in $caseList) {
    $methods = (@($caseItem.locator_methods) -join ', ') -replace '\|', '/'
    $events = (@($caseItem.observed_events) -join ', ') -replace '\|', '/'
    $reason = ([string]$caseItem.reason) -replace '\|', '/'
    $safety = ([string]$caseItem.safety) -replace '\|', '/'
    $lines.Add("| $($caseItem.name) | $($caseItem.status) | $safety | $methods | $events | $(@($caseItem.artifacts).Count) | $(@($caseItem.screenshots).Count) | $($caseItem.latency_ms) | $reason |") | Out-Null
}
$lines.Add('') | Out-Null
$lines.Add('## Commands Run') | Out-Null
$lines.Add('') | Out-Null
foreach ($caseItem in $caseList) {
    $lines.Add("### $($caseItem.name)") | Out-Null
    foreach ($cmd in @($caseItem.commands)) {
        $lines.Add("- $($cmd.command) -> exit $($cmd.exit_code), $($cmd.duration_ms)ms") | Out-Null
    }
    $lines.Add('') | Out-Null
}
$lines.Add('## Artifacts') | Out-Null
$lines.Add('') | Out-Null
foreach ($caseItem in $caseList) {
    $lines.Add("### $($caseItem.name)") | Out-Null
    $allArtifacts = @($caseItem.artifacts) + @($caseItem.screenshots)
    foreach ($artifact in @($allArtifacts | Select-Object -Unique)) {
        $lines.Add("- $artifact") | Out-Null
    }
    $lines.Add('') | Out-Null
}
$lines.Add('## Safety Notes') | Out-Null
$lines.Add('') | Out-Null
$lines.Add('- No real email, external account, captcha, anti-cheat, payment, or credential workflow is used.') | Out-Null
$lines.Add('- The mail case uses generated local HTML and proves only mock upload/sent-state detection.') | Out-Null
$lines.Add('- The problem case is a development benchmark fixture, not real exam or assessment automation.') | Out-Null
$lines.Add('- v4 visual providers and App Profiles produce candidates/metadata only; action safety remains Runtime-owned.') | Out-Null
$lines | Set-Content -Encoding UTF8 -LiteralPath $DogfoodReport

Write-Host "v4 visual dogfood result: $overall"
Write-Host "Report: $DogfoodReport"
Write-Host "Summary: $SummaryJson"
if ($overall -ne 'PASS') { exit 1 }
exit 0
