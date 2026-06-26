param(
    [string]$Root = '',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.9.2_active_protection_stop_policy'
$Report = Join-Path $ArtifactDir 'p0_policy_selftest_report.md'

function Fail($Message) { throw $Message }

function Invoke-AgentJson([string[]]$CmdArgs, [switch]$AllowFailure) {
    $output = & $WinAgent @CmdArgs 2>&1
    $exit = $LASTEXITCODE
    if ($exit -ne 0 -and -not $AllowFailure) {
        Fail "winagent $($CmdArgs -join ' ') exited $exit with output: $output"
    }
    try {
        return ($output | ConvertFrom-Json)
    } catch {
        Fail "Invalid JSON from winagent $($CmdArgs -join ' '): $output"
    }
}

function Assert-Allow($Name, [string[]]$CmdArgs) {
    $result = Invoke-AgentJson -CmdArgs $CmdArgs
    if (-not $result.ok -or -not $result.data.allow) {
        Fail "$Name should be allowed. output=$($result | ConvertTo-Json -Compress -Depth 10)"
    }
    if ($result.data.permission_mode -ne 'DEVELOPER_CAPABILITY_DISCOVERY') {
        Fail "$Name expected DEVELOPER_CAPABILITY_DISCOVERY, got $($result.data.permission_mode)"
    }
    if ($result.data.permission_decision.decision -ne 'ALLOW_AUDITED' -and $result.data.permission_decision.decision -ne 'ALLOW') {
        Fail "$Name expected ALLOW_AUDITED/ALLOW, got $($result.data.permission_decision.decision)"
    }
}

function Assert-StopActiveProtection($Name, [string[]]$CmdArgs) {
    $result = Invoke-AgentJson -CmdArgs $CmdArgs -AllowFailure
    if ($result.ok -or $result.error.code -ne 'STOP_ACTIVE_PROTECTION') {
        Fail "$Name should stop with STOP_ACTIVE_PROTECTION. output=$($result | ConvertTo-Json -Compress -Depth 10)"
    }
    $decision = $result.data.decision
    if (-not $decision -and $result.data.permission_decision) {
        $decision = $result.data.permission_decision.decision
    }
    if ($decision -ne 'STOP_ACTIVE_PROTECTION') {
        Fail "$Name missing STOP_ACTIVE_PROTECTION decision."
    }
}

if (-not $SkipBuild) {
    & "$Root\build.ps1" -Root $Root
    if ($LASTEXITCODE -ne 0) { Fail 'Build failed.' }
}

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

$version = Invoke-AgentJson -CmdArgs @('version')
$ExpectedVersion = (Get-Content -LiteralPath (Join-Path $Root 'VERSION') -Raw).Trim()
if (-not $version.ok -or $version.data.version -ne $ExpectedVersion) {
    Fail "winagent version expected $ExpectedVersion, got $($version.data.version)"
}
$capabilities = @($version.data.capabilities.available)
foreach ($capability in @('desktop_move', 'desktop_click', 'desktop_double_click', 'desktop_press', 'desktop_hotkey', 'desktop_type')) {
    if ($capabilities -notcontains $capability) {
        Fail "version output missing capability $capability"
    }
}

$developerModes = @(
    'DEVELOPER_CAPABILITY_DISCOVERY',
    'developer_capability_discovery',
    'DEVELOPER_FULL_RUNTIME',
    'developer_full_runtime'
)

foreach ($mode in $developerModes) {
    Assert-Allow "developer mode alias $mode allows external_web" @(
        'policy-check', '--title', 'Ordinary Browser Window', '--process', 'chrome.exe',
        '--action', 'external_web', '--permission-mode', $mode
    )
}

$allowedActions = @(
    'mouse.move',
    'mouse.click',
    'mouse.double_click',
    'keyboard.type_text',
    'keyboard.press',
    'keyboard.hotkey',
    'window.focus',
    'window.switch',
    'app.launch',
    'third_party_app.launch',
    'explorer.open',
    'explorer.navigate',
    'file.open_local',
    'browser.open',
    'browser.address_bar_input',
    'browser.navigate',
    'local_html.interact',
    'localhost.interact',
    'external_web.navigate',
    'ordinary_form.fill',
    'ordinary_button.click',
    'mock_submit.click'
)

foreach ($action in $allowedActions) {
    Assert-Allow "developer allows $action" @(
        'policy-check', '--title', 'DesktopVisual test exam assessment quiz problem challenge mail hiring page',
        '--process', 'chrome.exe', '--action', $action,
        '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY'
    )
}

$ordinaryTitles = @(
    'test page',
    'network test page',
    'exam practice page',
    'assessment mock page',
    'quiz problem page',
    'challenge problem page',
    'coding challenge page',
    'mail mock submit',
    'localhost mail mock',
    'ordinary external web',
    'Agent Test Window',
    'Local exam fixture',
    'Hiring recruitment form'
)

foreach ($title in $ordinaryTitles) {
    Assert-Allow "developer does not block ordinary content title $title" @(
        'policy-check', '--title', $title, '--process', 'chrome.exe',
        '--action', 'browser.navigate', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY'
    )
}

$desktopTitles = @(
    @{ Title = 'Program Manager'; Process = 'explorer.exe' },
    @{ Title = 'Desktop'; Process = 'explorer.exe' },
    @{ Title = 'File Explorer'; Process = 'explorer.exe' },
    @{ Title = 'Google Chrome'; Process = 'chrome.exe' },
    @{ Title = 'Microsoft Edge'; Process = 'msedge.exe' },
    @{ Title = 'PyCharm'; Process = 'pycharm64.exe' }
)

foreach ($target in $desktopTitles) {
    Assert-Allow "developer does not block $($target.Title) by title/process whitelist" @(
        'policy-check', '--title', $target.Title, '--process', $target.Process,
        '--action', 'global_desktop', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY'
    )
}

Assert-Allow 'developer click does not require FULL_ACCESS session' @(
    'policy-check', '--title', 'Chrome test page', '--process', 'chrome.exe',
    '--action', 'mouse.double_click', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY'
)

$littleBlueBear = ([string][char]0x5C0F) + ([string][char]0x84DD) + ([string][char]0x718A)
$activeSignals = @(
    @{ Name = 'captcha signal'; Title = 'captcha'; Process = 'chrome.exe'; Action = 'mouse.click' },
    @{ Name = 'reCAPTCHA signal'; Title = 'reCAPTCHA'; Process = 'chrome.exe'; Action = 'mouse.click' },
    @{ Name = 'hCaptcha signal'; Title = 'hCaptcha'; Process = 'chrome.exe'; Action = 'mouse.click' },
    @{ Name = 'Turnstile human verification signal'; Title = 'Turnstile human verification'; Process = 'chrome.exe'; Action = 'mouse.click' },
    @{ Name = 'verify human signal'; Title = 'verify you are human'; Process = 'chrome.exe'; Action = 'mouse.click' },
    @{ Name = 'bot challenge signal'; Title = 'bot challenge'; Process = 'chrome.exe'; Action = 'mouse.click' },
    @{ Name = 'anti-bot challenge signal'; Title = 'anti-bot challenge'; Process = 'chrome.exe'; Action = 'mouse.click' },
    @{ Name = 'automation detected signal'; Title = 'automation detected'; Process = 'chrome.exe'; Action = 'mouse.click' },
    @{ Name = 'script detected signal'; Title = 'script detected'; Process = 'chrome.exe'; Action = 'mouse.click' },
    @{ Name = 'BEService signal'; Title = 'BEService.exe'; Process = 'BEService.exe'; Action = 'app.launch' },
    @{ Name = 'BattleEye service signal'; Title = 'BattleEye service'; Process = 'chrome.exe'; Action = 'app.launch' },
    @{ Name = 'EasyAntiCheat signal'; Title = 'EasyAntiCheat.exe'; Process = 'EasyAntiCheat.exe'; Action = 'app.launch' },
    @{ Name = 'EasyAntiCheat EOS signal'; Title = 'EasyAntiCheat_EOS.exe'; Process = 'EasyAntiCheat_EOS.exe'; Action = 'app.launch' },
    @{ Name = 'AntiCheatExpert signal'; Title = 'AntiCheatExpert'; Process = 'AntiCheatExpert.exe'; Action = 'app.launch' },
    @{ Name = 'ACE anti cheat signal'; Title = 'ACE anti cheat'; Process = 'ACE.exe'; Action = 'app.launch' },
    @{ Name = 'Vanguard process signal'; Title = 'vgc.exe'; Process = 'vgc.exe'; Action = 'app.launch' },
    @{ Name = 'Riot Vanguard signal'; Title = 'Riot Vanguard'; Process = 'chrome.exe'; Action = 'app.launch' },
    @{ Name = 'little blue bear signal'; Title = $littleBlueBear; Process = 'AntiCheatExpert.exe'; Action = 'app.launch' },
    @{ Name = 'lockdown browser signal'; Title = 'lockdown browser.exe'; Process = 'lockdown browser.exe'; Action = 'app.launch' },
    @{ Name = 'secure exam browser signal'; Title = 'secure exam browser.exe'; Process = 'secure exam browser.exe'; Action = 'app.launch' },
    @{ Name = 'Safe Exam Browser signal'; Title = 'Safe Exam Browser'; Process = 'chrome.exe'; Action = 'app.launch' },
    @{ Name = 'active proctoring client signal'; Title = 'active proctoring client'; Process = 'proctor.exe'; Action = 'mouse.click' }
)

foreach ($signal in $activeSignals) {
    Assert-StopActiveProtection $signal.Name @(
        'policy-check', '--title', $signal.Title, '--process', $signal.Process,
        '--action', $signal.Action, '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY'
    )
}

$ambiguousAllowedTitles = @(
    'challenge',
    'problem challenge',
    'exam',
    'assessment',
    'test',
    'mail',
    'submit',
    'login'
)

foreach ($title in $ambiguousAllowedTitles) {
    Assert-Allow "developer does not stop ambiguous ordinary word $title" @(
        'policy-check', '--title', $title, '--process', 'chrome.exe',
        '--action', 'browser.navigate', '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY'
    )
}

$bypassRequests = @(
    @{ Name = 'bypass captcha request'; Title = 'bypass captcha'; Process = 'chrome.exe'; Action = 'browser.navigate' },
    @{ Name = 'avoid bot detection request'; Title = 'avoid bot detection'; Process = 'chrome.exe'; Action = 'browser.navigate' },
    @{ Name = 'disable anti cheat request'; Title = 'disable anti cheat'; Process = 'chrome.exe'; Action = 'app.launch' },
    @{ Name = 'hook BEService request'; Title = 'hook BEService'; Process = 'BEService.exe'; Action = 'app.launch' },
    @{ Name = 'hide automation secure exam request'; Title = 'hide automation from secure exam browser'; Process = 'secure exam browser.exe'; Action = 'app.launch' },
    @{ Name = 'patch vgc request'; Title = 'patch vgc.exe'; Process = 'vgc.exe'; Action = 'app.launch' }
)

foreach ($request in $bypassRequests) {
    Assert-StopActiveProtection $request.Name @(
        'policy-check', '--title', $request.Title, '--process', $request.Process,
        '--action', $request.Action, '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY'
    )
}

$taskFixture = Join-Path $ArtifactDir 'developer_profile_task_session.task-session.json'
(@'
{
  "schema_version": "5.0.1",
  "runtime_version": "__EXPECTED_VERSION__",
  "protocol_version": "5.0",
  "task_id": "dev5_9_developer_profile",
  "task_type": "local_form_fill_submit_mock",
  "profile": "browser_local",
  "permission_profile": "DEVELOPER_CAPABILITY_DISCOVERY",
  "capability_profiles": ["developer_capability_discovery"],
  "current_state": "pending",
  "started_at": "2026-06-09T00:00:00Z",
  "updated_at": "2026-06-09T00:00:00Z",
  "artifacts": {
    "root": "artifacts/dev5.9.2_active_protection_stop_policy/developer_profile_task_session",
    "events_jsonl": "artifacts/dev5.9.2_active_protection_stop_policy/developer_profile_task_session/task_events.jsonl",
    "result_json": "artifacts/dev5.9.2_active_protection_stop_policy/developer_profile_task_session/task_result.json",
    "report_md": "artifacts/dev5.9.2_active_protection_stop_policy/developer_profile_task_session/task_report.md"
  },
  "context": {
    "runtime_mode": "STANDARD",
    "task_goal": "validate developer permission profile parsing",
    "target_title": "Local test page",
    "target_process": "chrome.exe",
    "allow_unrestricted_desktop": false
  },
  "progress": { "total_steps": 0, "completed_steps": 0, "failed_steps": 0, "current_step_id": "" },
  "states": ["pending", "running", "waiting", "verifying", "recovering", "confirmed", "completed", "failed", "stopped", "blocked"],
  "transitions": [
    { "from": "pending", "to": "running" },
    { "from": "running", "to": "completed" }
  ],
  "steps": [],
  "events": [],
  "result": {
    "task_id": "dev5_9_developer_profile",
    "state": "pending",
    "status": "pending",
    "ok": false,
    "error_code": "",
    "message": ""
  },
  "escalation": {
    "provider": "none",
    "allowed_reasons": ["semantic_unresolved"]
  }
}
'@).Replace('__EXPECTED_VERSION__', $ExpectedVersion) | Set-Content -LiteralPath $taskFixture -Encoding UTF8

$taskValidation = Invoke-AgentJson -CmdArgs @('task-session-validate', '--file', $taskFixture)
if (-not $taskValidation.ok -or $taskValidation.data.permission_profile -ne 'DEVELOPER_CAPABILITY_DISCOVERY') {
    Fail 'TaskSession did not accept DEVELOPER_CAPABILITY_DISCOVERY permission_profile.'
}

$lines = @(
    "# v$ExpectedVersion Active Protection STOP Policy Regression Selftest",
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "- Version output: $ExpectedVersion",
    '- Developer aliases accepted: DEVELOPER_CAPABILITY_DISCOVERY, developer_capability_discovery, DEVELOPER_FULL_RUNTIME, developer_full_runtime',
    '- Low-level UI primitives do not require FULL_ACCESS session in developer mode.',
    '- Program Manager / Desktop / Explorer / Chrome / Edge / PyCharm are not blocked by TestWindow-only title or process whitelist.',
    '- desktop-move, desktop-click, desktop-double-click, desktop-press, desktop-hotkey, and desktop-type command capabilities are present.',
    '- Ordinary content words test/exam/assessment/quiz/problem/challenge/mail/submit/login/hiring are allowed.',
    '- Active protection signals and processes stop with STOP_ACTIVE_PROTECTION.',
    '- Bypass requests for CAPTCHA, bot detection, anti-cheat, secure browser, and vgc.exe stop with STOP_ACTIVE_PROTECTION.',
    ('- TaskSession fixture: `{0}`' -f $taskFixture)
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host "v$ExpectedVersion active protection STOP policy selftest passed."
Write-Host "Report: $Report"
