param(
    [string]$Root = '',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.1.3_mouse_wheel_scroll_and_scroll_locate'
$RawRoot = Join-Path $ArtifactRoot 'raw'
$RawCasesRoot = Join-Path $RawRoot 'cases'
$FixtureRoot = 'D:\testrepo\testwindow'
$LongHtml = Join-Path $FixtureRoot 'desktopvisual_long_scroll_test.html'
$FriendHtml = Join-Path $FixtureRoot 'desktopvisual_mock_friend_list.html'
$NoScrollHtml = Join-Path $FixtureRoot 'desktopvisual_no_scroll_test.html'
$ExplorerFixture = Join-Path $FixtureRoot 'scroll_many_files'

function Ensure-Dir([string]$Path) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Clear-CaseDir([string]$Path, [string]$AllowedRoot) {
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullAllowed = [System.IO.Path]::GetFullPath($AllowedRoot)
    if (-not $fullPath.StartsWith($fullAllowed, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clear evidence path outside raw cases root: $fullPath"
    }
    if (Test-Path -LiteralPath $Path) {
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        } catch {
            $empty = Join-Path $AllowedRoot '_empty_delete_source'
            New-Item -ItemType Directory -Force -Path $empty | Out-Null
            & robocopy $empty $Path /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            Remove-Item -LiteralPath $empty -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Ensure-Dir $Path
}

function Write-JsonLine([string]$Path, $Object) {
    ($Object | ConvertTo-Json -Depth 100 -Compress) | Add-Content -LiteralPath $Path -Encoding UTF8
}

function New-RawCase([string]$CaseId) {
    $dir = Join-Path $RawCasesRoot $CaseId
    Clear-CaseDir $dir $RawCasesRoot
    foreach ($name in @('screenshots','overlays','crops')) {
        Ensure-Dir (Join-Path $dir $name)
    }
    foreach ($file in @('raw_command_log.jsonl','raw_stdout.jsonl','preliminary_observations.jsonl')) {
        Set-Content -LiteralPath (Join-Path $dir $file) -Value '' -Encoding UTF8
    }
    Set-Content -LiteralPath (Join-Path $dir 'raw_stderr.log') -Value '' -Encoding UTF8
    [pscustomobject]@{
        CaseId = $CaseId
        Dir = $dir
        CommandLog = Join-Path $dir 'raw_command_log.jsonl'
        StdoutLog = Join-Path $dir 'raw_stdout.jsonl'
        StderrLog = Join-Path $dir 'raw_stderr.log'
        ScreenshotDir = Join-Path $dir 'screenshots'
    }
}

function Add-Preliminary($Ctx, [string]$Kind, $Details) {
    Write-JsonLine (Join-Path $Ctx.Dir 'preliminary_observations.jsonl') ([pscustomobject]@{
        timestamp = (Get-Date).ToString('o')
        case_id = $Ctx.CaseId
        kind = $Kind
        details = $Details
        verified_by_runner = $false
    })
}

function Invoke-WinAgentRaw($Ctx, [string]$Step, [string[]]$CommandArgs, [switch]$AllowFailure) {
    $stdout = Join-Path $Ctx.Dir ("$Step.stdout.log")
    $stderr = Join-Path $Ctx.Dir ("$Step.stderr.log")
    $outputJson = $null
    for ($i = 0; $i -lt $CommandArgs.Count - 1; $i++) {
        if ($CommandArgs[$i] -eq '--output-json' -or $CommandArgs[$i] -eq '--result-json') {
            $outputJson = $CommandArgs[$i + 1]
        }
    }
    $started = Get-Date
    & $WinAgent @CommandArgs > $stdout 2> $stderr
    $exit = $LASTEXITCODE
    $ended = Get-Date
    $stdoutText = if (Test-Path -LiteralPath $stdout) { Get-Content -LiteralPath $stdout -Raw } else { '' }
    $stderrText = if (Test-Path -LiteralPath $stderr) { Get-Content -LiteralPath $stderr -Raw } else { '' }
    Write-JsonLine $Ctx.CommandLog ([pscustomobject]@{
        timestamp = $started.ToString('o')
        ended_at = $ended.ToString('o')
        case_id = $Ctx.CaseId
        step = $Step
        executable = $WinAgent
        command_args = $CommandArgs
        stdout_path = $stdout
        stderr_path = $stderr
        output_json_path = $outputJson
        exit_code = $exit
    })
    $parsed = $null
    try { $parsed = $stdoutText | ConvertFrom-Json } catch { $parsed = $null }
    Write-JsonLine $Ctx.StdoutLog ([pscustomobject]@{
        timestamp = $ended.ToString('o')
        case_id = $Ctx.CaseId
        step = $Step
        exit_code = $exit
        stdout_path = $stdout
        stderr_path = $stderr
        stdout_length = $stdoutText.Length
        stderr_length = $stderrText.Length
        parsed_ok = ($null -ne $parsed)
        parsed_command = if ($parsed -and $parsed.command) { $parsed.command } else { '' }
        parsed_ok_field = if ($parsed -and $null -ne $parsed.ok) { [bool]$parsed.ok } else { $false }
    })
    if ($exit -ne 0 -and -not $AllowFailure) {
        Add-Preliminary $Ctx 'command_unverified_failure' @{ step = $Step; exit_code = $exit; stdout = $stdoutText; stderr = $stderrText }
    }
    [pscustomobject]@{ ExitCode = $exit; Stdout = $stdoutText; Stderr = $stderrText; OutputJsonPath = $outputJson; Parsed = $parsed }
}

function Write-TestHtmlFiles {
    Ensure-Dir $FixtureRoot
    $items = 1..100 | ForEach-Object {
        $label = if ($_ -eq 72) { 'DesktopVisual Target Item 72' } else { ('DesktopVisual List Item {0:000}' -f $_) }
        "<li>$label</li>"
    }
    @"
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>DesktopVisual Long Scroll Test</title>
  <style>
    body { font-family: Segoe UI, Arial, sans-serif; margin: 0; background: #f7f7f4; color: #17202a; }
    header { position: sticky; top: 0; background: #ffffff; border-bottom: 1px solid #9aa0a6; padding: 14px 28px; font-size: 22px; }
    main { padding: 20px 44px 900px 44px; }
    li { list-style: none; margin: 14px 0; padding: 16px 18px; border: 1px solid #c6c8cc; background: #ffffff; min-height: 28px; }
  </style>
</head>
<body>
  <header>DesktopVisual Long Scroll Test</header>
  <main><ol>$($items -join "`n")</ol></main>
</body>
</html>
"@ | Set-Content -LiteralPath $LongHtml -Encoding UTF8

    $friends = 1..110 | ForEach-Object {
        $name = if ($_ -eq 88) { 'Friend Target 088' } else { ('Friend Contact {0:000}' -f $_) }
        "<div class=""friend-row"">$name</div>"
    }
    @"
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>DesktopVisual Mock Friend List</title>
  <style>
    body { font-family: Segoe UI, Arial, sans-serif; margin: 0; background: #eef2f3; color: #18212a; }
    .shell { display: grid; grid-template-columns: 220px minmax(360px, 720px); gap: 18px; padding: 24px; }
    .side { background: #25313b; color: white; padding: 18px; min-height: 620px; }
    .friend-list { height: 560px; overflow-y: auto; background: #ffffff; border: 1px solid #8d99a6; scrollbar-width: thin; }
    .friend-row { min-height: 44px; border-bottom: 1px solid #dde2e6; padding: 14px 18px; font-size: 18px; }
  </style>
</head>
<body>
  <section class="shell">
    <aside class="side">Contacts</aside>
    <main class="friend-list">$($friends -join "`n")</main>
  </section>
</body>
</html>
"@ | Set-Content -LiteralPath $FriendHtml -Encoding UTF8

    @"
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>DesktopVisual No Scroll Test</title>
  <style>body { font-family: Segoe UI, Arial, sans-serif; margin: 30px; background: #ffffff; color: #202124; }</style>
</head>
<body>
  <h1>DesktopVisual No Scroll Test</h1>
  <p>This page is intentionally short so wheel input should not change visible content.</p>
</body>
</html>
"@ | Set-Content -LiteralPath $NoScrollHtml -Encoding UTF8
}

function Ensure-ExplorerFixture {
    Ensure-Dir $ExplorerFixture
    1..120 | ForEach-Object {
        $path = Join-Path $ExplorerFixture ('item_{0:000}.txt' -f $_)
        if (-not (Test-Path -LiteralPath $path)) {
            Set-Content -LiteralPath $path -Value "DesktopVisual scroll fixture item $_" -Encoding UTF8
        }
    }
}

function Get-BrowserCommand {
    foreach ($name in @('msedge.exe','chrome.exe')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    return ''
}

function Open-BrowserFixture($Ctx, [string]$HtmlPath, [string]$TitlePattern, [string]$Step) {
    $uri = ([System.Uri]$HtmlPath).AbsoluteUri + '?run=' + [uri]::EscapeDataString((Get-Date).ToString('yyyyMMddHHmmssfff'))
    $openResult = Join-Path $Ctx.Dir "$Step-browser-open-url-human.json"
    $open = Invoke-WinAgentRaw $Ctx "$Step-browser-open-url-human" @(
        'browser-open-url-human',
        '--url', $uri,
        '--expected-marker', $TitlePattern,
        '--browser', 'auto',
        '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY',
        '--result-json', $openResult
    ) -AllowFailure
    Add-Preliminary $Ctx 'fixture_browser_open_requested' @{ html = $HtmlPath; uri = $uri; title_pattern = $TitlePattern; runtime_open_url_human = $true; result_json = $openResult; exit_code = $open.ExitCode }
    if ($open.ExitCode -ne 0 -or -not ($open.Parsed -and $open.Parsed.ok -eq $true)) {
        Add-Preliminary $Ctx 'case_unverified_failure' @{ reason = 'browser-open-url-human failed'; title_pattern = $TitlePattern; result_json = $openResult }
        return $null
    }
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 500
        $windows = Invoke-WinAgentRaw $Ctx "$Step-windows-$i" @('windows') -AllowFailure
        if ($windows.Parsed -and $windows.Parsed.windows) {
            $match = @($windows.Parsed.windows | Where-Object { $_.title -like "*$TitlePattern*" } | Select-Object -First 1)
            if ($match.Count -gt 0) {
                Add-Preliminary $Ctx 'fixture_window_found' @{ title = $match[0].title; hwnd = $match[0].hwnd; pattern = $TitlePattern }
                return $match[0]
            }
        }
    }
    Add-Preliminary $Ctx 'case_unverified_failure' @{ reason = 'fixture browser window not found'; title_pattern = $TitlePattern }
    return $null
}

function Open-ExplorerFixture($Ctx) {
    $desktopGuard = Join-Path $Ctx.Dir 'show_desktop_before_explorer_context_guard.json'
    Invoke-WinAgentRaw $Ctx 'show-desktop-before-explorer' @(
        'desktop-hotkey','--keys','WIN+D','--permission-mode','DEVELOPER_CAPABILITY_DISCOVERY',
        '--expected-process-pattern','chrome\.exe|msedge\.exe|explorer\.exe|powershell\.exe',
        '--expected-title-pattern','DesktopVisual|Chrome|Edge|Program Manager|system32|PowerShell|scroll_many_files',
        '--guard-result-json',$desktopGuard
    ) -AllowFailure | Out-Null
    Start-Sleep -Milliseconds 600
    Start-Process -FilePath 'explorer.exe' -ArgumentList $ExplorerFixture | Out-Null
    Add-Preliminary $Ctx 'fixture_explorer_open_requested' @{ directory = $ExplorerFixture }
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 500
        $windows = Invoke-WinAgentRaw $Ctx "explorer-windows-$i" @('windows') -AllowFailure
        if ($windows.Parsed -and $windows.Parsed.windows) {
            $match = @($windows.Parsed.windows | Where-Object { $_.title -like '*scroll_many_files*' } | Select-Object -First 1)
            if ($match.Count -gt 0) {
                Add-Preliminary $Ctx 'fixture_window_found' @{ title = $match[0].title; hwnd = $match[0].hwnd; pattern = 'scroll_many_files' }
                $focusGuard = Join-Path $Ctx.Dir 'focus_explorer_fixture_context_guard.json'
                $focus = Invoke-WinAgentRaw $Ctx 'focus-explorer-fixture' @(
                    'focus','--title','scroll_many_files',
                    '--expected-process-pattern','explorer\.exe',
                    '--expected-title-pattern','Program Manager|scroll_many_files',
                    '--guard-result-json',$focusGuard
                ) -AllowFailure
                Add-Preliminary $Ctx 'fixture_window_focus_requested' @{
                    title = $match[0].title
                    hwnd = $match[0].hwnd
                    exit_code = $focus.ExitCode
                    guard_result_json = $focusGuard
                    runtime_focus_guarded = $true
                }
                if ($focus.ExitCode -ne 0 -or -not ($focus.Parsed -and $focus.Parsed.ok -eq $true)) {
                    Add-Preliminary $Ctx 'case_unverified_failure' @{ reason = 'Explorer fixture focus failed before guarded scroll'; title = $match[0].title; guard_result_json = $focusGuard }
                    return $null
                }
                Start-Sleep -Milliseconds 500
                return $match[0]
            }
        }
    }
    Add-Preliminary $Ctx 'case_unverified_failure' @{ reason = 'Explorer fixture window not found'; directory = $ExplorerFixture }
    return $null
}

function Case-A {
    $ctx = New-RawCase 'v6_1_3_mouse_wheel_primitive_real_input'
    Add-Preliminary $ctx 'case_started' @{ output = 'raw evidence only' }
    $window = Open-BrowserFixture $ctx $LongHtml 'DesktopVisual Long Scroll Test' 'case-a'
    if (-not $window) { return }
    $out = Join-Path $ctx.Dir 'adaptive_scroll_output.json'
    $guard = Join-Path $ctx.Dir 'adaptive_scroll_context_guard.json'
    Invoke-WinAgentRaw $ctx 'adaptive-scroll-wheel' @(
        'adaptive-scroll','--title','DesktopVisual Long Scroll Test','--direction','down','--notches','5',
        '--move-mode','human','--verify-content-change','true','--output-json',$out,'--screenshot-dir',$ctx.ScreenshotDir
        '--expected-title-pattern','DesktopVisual Long Scroll Test','--required-marker','DesktopVisual Long Scroll Test','--guard-result-json',$guard
    ) -AllowFailure
    Add-Preliminary $ctx 'case_unverified_complete' @{ case_id = $ctx.CaseId; output_json = $out }
}

function Case-B {
    $ctx = New-RawCase 'v6_1_3_browser_long_page_scroll_and_locate'
    Add-Preliminary $ctx 'case_started' @{ output = 'raw evidence only'; target = 'DesktopVisual Target Item 72' }
    $window = Open-BrowserFixture $ctx $LongHtml 'DesktopVisual Long Scroll Test' 'case-b'
    if (-not $window) { return }
    $out = Join-Path $ctx.Dir 'scroll_and_locate_output.json'
    $guard = Join-Path $ctx.Dir 'scroll_and_locate_context_guard.json'
    Invoke-WinAgentRaw $ctx 'scroll-and-locate-target' @(
        'scroll-and-locate','--title','DesktopVisual Long Scroll Test','--target-text','DesktopVisual Target Item 72',
        '--direction','down','--max-scrolls','20','--notches-per-scroll','3','--move-mode','human',
        '--locator','hybrid','--output-json',$out,'--screenshot-dir',$ctx.ScreenshotDir
        '--expected-title-pattern','DesktopVisual Long Scroll Test','--required-marker','DesktopVisual Long Scroll Test','--guard-result-json',$guard
    ) -AllowFailure
    Add-Preliminary $ctx 'case_unverified_complete' @{ case_id = $ctx.CaseId; output_json = $out }
}

function Case-C {
    $ctx = New-RawCase 'v6_1_3_mock_friend_list_scroll_and_locate'
    Add-Preliminary $ctx 'case_started' @{ output = 'raw evidence only'; target = 'Friend Target 088' }
    $window = Open-BrowserFixture $ctx $FriendHtml 'DesktopVisual Mock Friend List' 'case-c'
    if (-not $window) { return }
    $out = Join-Path $ctx.Dir 'scroll_and_locate_output.json'
    $guard = Join-Path $ctx.Dir 'scroll_and_locate_context_guard.json'
    Invoke-WinAgentRaw $ctx 'scroll-and-locate-friend' @(
        'scroll-and-locate','--title','DesktopVisual Mock Friend List','--target-text','Friend Target 088',
        '--region','list','--direction','down','--max-scrolls','20','--notches-per-scroll','3','--move-mode','human',
        '--locator','hybrid','--output-json',$out,'--screenshot-dir',$ctx.ScreenshotDir
        '--expected-title-pattern','DesktopVisual Mock Friend List','--required-marker','DesktopVisual Mock Friend List','--guard-result-json',$guard
    ) -AllowFailure
    Add-Preliminary $ctx 'case_unverified_complete' @{ case_id = $ctx.CaseId; output_json = $out }
}

function Case-D {
    $ctx = New-RawCase 'v6_1_3_explorer_list_wheel_scroll_and_locate'
    Add-Preliminary $ctx 'case_started' @{ output = 'raw evidence only'; target = 'item_105.txt' }
    $window = Open-ExplorerFixture $ctx
    if (-not $window) { return }
    $out = Join-Path $ctx.Dir 'scroll_and_locate_output.json'
    $guard = Join-Path $ctx.Dir 'scroll_and_locate_context_guard.json'
    Invoke-WinAgentRaw $ctx 'scroll-and-locate-explorer-item' @(
        'scroll-and-locate','--title','scroll_many_files','--target-text','item_105.txt',
        '--region','list','--direction','down','--max-scrolls','30','--notches-per-scroll','3','--move-mode','human',
        '--locator','hybrid','--output-json',$out,'--screenshot-dir',$ctx.ScreenshotDir
        '--expected-title-pattern','scroll_many_files','--guard-result-json',$guard
    ) -AllowFailure
    Add-Preliminary $ctx 'case_unverified_complete' @{ case_id = $ctx.CaseId; output_json = $out }
}

function Case-E {
    $ctx = New-RawCase 'v6_1_3_wheel_no_progress_detection'
    Add-Preliminary $ctx 'case_started' @{ output = 'raw evidence only'; target = 'no progress' }
    $window = Open-BrowserFixture $ctx $NoScrollHtml 'DesktopVisual No Scroll Test' 'case-e'
    if (-not $window) { return }
    $out = Join-Path $ctx.Dir 'adaptive_scroll_no_progress_output.json'
    $guard = Join-Path $ctx.Dir 'adaptive_scroll_no_progress_context_guard.json'
    Invoke-WinAgentRaw $ctx 'adaptive-scroll-no-progress' @(
        'adaptive-scroll','--title','DesktopVisual No Scroll Test','--direction','down','--notches','3',
        '--move-mode','human','--verify-content-change','true','--output-json',$out,'--screenshot-dir',$ctx.ScreenshotDir
        '--expected-title-pattern','DesktopVisual No Scroll Test','--required-marker','DesktopVisual No Scroll Test','--guard-result-json',$guard
    ) -AllowFailure
    Add-Preliminary $ctx 'case_unverified_complete' @{ case_id = $ctx.CaseId; output_json = $out; expected_command_error = 'WHEEL_NO_CONTENT_CHANGE' }
}

function Case-F {
    $ctx = New-RawCase 'v6_1_3_v6_1_2_baseline_regression_replay'
    Add-Preliminary $ctx 'case_started' @{ output = 'raw evidence only'; baseline = 'v6.1.2 replay' }
    $baselineRunnerLog = Join-Path $ctx.Dir 'v6_1_2_real_ui_baseline_runner_replay.log'
    $baselineVerifierLog = Join-Path $ctx.Dir 'v6_1_2_real_ui_baseline_verifier_replay.log'
    $runnerStart = Get-Date
    & powershell -ExecutionPolicy Bypass -File (Join-Path $Root 'v6_1_2_real_ui_baseline_runner.ps1') -Root $Root -SkipBuild -Rounds 2 > $baselineRunnerLog 2>&1
    $runnerExit = $LASTEXITCODE
    $runnerEnd = Get-Date
    Write-JsonLine $ctx.CommandLog ([pscustomobject]@{
        timestamp = $runnerStart.ToString('o')
        ended_at = $runnerEnd.ToString('o')
        case_id = $ctx.CaseId
        step = 'v6_1_2_real_ui_baseline_runner_replay'
        executable = 'powershell'
        command_args = @('-ExecutionPolicy','Bypass','-File',(Join-Path $Root 'v6_1_2_real_ui_baseline_runner.ps1'),'-Root',$Root,'-SkipBuild','-Rounds','2')
        stdout_path = $baselineRunnerLog
        stderr_path = ''
        output_json_path = ''
        exit_code = $runnerExit
    })
    $verifierStart = Get-Date
    & powershell -ExecutionPolicy Bypass -File (Join-Path $Root 'v6_1_2_real_ui_baseline_verifier.ps1') -Root $Root > $baselineVerifierLog 2>&1
    $verifierExit = $LASTEXITCODE
    $verifierEnd = Get-Date
    Write-JsonLine $ctx.CommandLog ([pscustomobject]@{
        timestamp = $verifierStart.ToString('o')
        ended_at = $verifierEnd.ToString('o')
        case_id = $ctx.CaseId
        step = 'v6_1_2_real_ui_baseline_verifier_replay'
        executable = 'powershell'
        command_args = @('-ExecutionPolicy','Bypass','-File',(Join-Path $Root 'v6_1_2_real_ui_baseline_verifier.ps1'),'-Root',$Root)
        stdout_path = $baselineVerifierLog
        stderr_path = ''
        output_json_path = ''
        exit_code = $verifierExit
    })
    Add-Preliminary $ctx 'baseline_replay_invoked' @{ runner_exit_code = $runnerExit; verifier_exit_code = $verifierExit; runner_log = $baselineRunnerLog; verifier_log = $baselineVerifierLog }
    $source = Join-Path $Root 'artifacts\dev6.1.2_real_ui_baseline_sanity_pre_v6_2_gate'
    $copyRoot = Join-Path $ctx.Dir 'fresh_v6_1_2_replay_copy'
    if (Test-Path -LiteralPath $copyRoot) { Remove-Item -LiteralPath $copyRoot -Recurse -Force }
    Ensure-Dir $copyRoot
    $robocopyLog = Join-Path $ctx.Dir 'v6_1_2_replay_copy_robocopy.log'
    & robocopy $source $copyRoot /E /NFL /NDL /NJH /NJS /NP > $robocopyLog 2>&1
    $copyExit = $LASTEXITCODE
    if ($copyExit -gt 7) {
        Add-Preliminary $ctx 'baseline_replay_copy_failed' @{ source = $source; copied_current_replay = $copyRoot; robocopy_exit_code = $copyExit; robocopy_log = $robocopyLog }
        return
    }
    Add-Preliminary $ctx 'case_unverified_complete' @{ case_id = $ctx.CaseId; copied_current_replay = $copyRoot; robocopy_exit_code = $copyExit; robocopy_log = $robocopyLog }
}

Ensure-Dir $ArtifactRoot
Ensure-Dir $RawRoot
Ensure-Dir $RawCasesRoot
git -C $Root status --short | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'git_status_initial.txt') -Encoding UTF8

if (-not $SkipBuild) {
    & (Join-Path $Root 'build.ps1') -Root $Root > (Join-Path $RawRoot 'build.log') 2>&1
}

Write-TestHtmlFiles
Ensure-ExplorerFixture

Case-A
Case-B
Case-C
Case-D
Case-E
Case-F

[pscustomobject]@{
    schema_version = 'v6.1.3.runner.raw'
    generated_at = (Get-Date).ToString('o')
    runner_role = 'collect_raw_evidence_only'
    artifact_root = $ArtifactRoot
    raw_root = $RawRoot
    fixture_root = $FixtureRoot
    runner_does_not_decide_pass = $true
} | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $RawRoot 'runner_summary.json') -Encoding UTF8

@(
    '# v6.1.3 Wheel Scroll Runner Raw Evidence Report',
    '',
    '- Runner role: collect raw evidence only.',
    '- PASS/FAIL authority: v6_1_3_wheel_scroll_verifier.ps1 and v6_1_3_scroll_acceptance_gate.ps1.',
    "- Artifact root: $ArtifactRoot",
    "- Fixture root: $FixtureRoot",
    '- Real wheel commands used: adaptive-scroll and scroll-and-locate.'
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'runner_raw_evidence_report.md') -Encoding UTF8

Write-Host 'v6.1.3 wheel scroll raw runner complete.'
