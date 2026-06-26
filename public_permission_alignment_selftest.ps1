param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ManifestPath = Join-Path $Root 'config\safety_manifest.json'
$SafetyConfPath = Join-Path $Root 'config\safety.conf'
$OutDir = Join-Path $Root 'artifacts\dev1.1.0_public_permission_agent_efficiency'
$ReportPath = Join-Path $OutDir 'public_permission_alignment_selftest_report.md'

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Fail($Message) { throw $Message }

function Add-Line {
    param([System.Collections.Generic.List[string]]$Lines, [string]$Text)
    $Lines.Add($Text) | Out-Null
}

function Invoke-AgentJson {
    param(
        [string[]]$CmdArgs,
        [switch]$AllowFailure
    )
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

function Assert-Allowed {
    param(
        [string]$Name,
        [string]$Title,
        [string]$Process,
        [string]$Action
    )
    $result = Invoke-AgentJson -CmdArgs @(
        'policy-check',
        '--title', $Title,
        '--process', $Process,
        '--action', $Action,
        '--permission-mode', 'PUBLIC_DEFAULT'
    )
    if (-not $result.ok -or -not $result.data.allow) {
        Fail "$Name should be allowed by PUBLIC_DEFAULT."
    }
}

function Assert-Stopped {
    param(
        [string]$Name,
        [string]$Title,
        [string]$Process,
        [string]$Action
    )
    $result = Invoke-AgentJson -CmdArgs @(
        'policy-check',
        '--title', $Title,
        '--process', $Process,
        '--action', $Action,
        '--permission-mode', 'PUBLIC_DEFAULT'
    ) -AllowFailure
    if ($result.ok -or ($result.error.code -notin @('STOP_ACTIVE_PROTECTION','SAFETY_POLICY_DENIED','CREDENTIAL_INPUT_DETECTED'))) {
        Fail "$Name should stop with an active protection or security boundary code."
    }
}

if (-not (Test-Path -LiteralPath $WinAgent)) { Fail "winagent.exe missing: $WinAgent" }
$manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
$safetyConf = Get-Content -Raw -LiteralPath $SafetyConfPath

if ($manifest.default_permission_mode -ne 'DEVELOPER_CAPABILITY_DISCOVERY') {
    Fail 'default_permission_mode must remain DEVELOPER_CAPABILITY_DISCOVERY.'
}
if ($safetyConf -notmatch '(?m)^allow_absolute_screen_click=true\r?$') {
    Fail 'allow_absolute_screen_click must remain true.'
}

$requiredCapabilities = @(
    'third_party_apps',
    'external_web',
    'communication',
    'content_decision',
    'cross_window',
    'global_desktop',
    'browser',
    'explorer',
    'local_file_open',
    'localhost'
)

foreach ($capability in $requiredCapabilities) {
    if ($manifest.permission_modes.PUBLIC_DEFAULT.$capability -ne $true) {
        Fail "PUBLIC_DEFAULT must allow $capability."
    }
    if ($manifest.permission_modes.DEVELOPER_CAPABILITY_DISCOVERY.$capability -ne $true) {
        Fail "DEVELOPER_CAPABILITY_DISCOVERY must still allow $capability."
    }
    if ($manifest.permission_modes.DEVELOPER_FULL_RUNTIME.$capability -ne $true) {
        Fail "DEVELOPER_FULL_RUNTIME must still allow $capability."
    }
}
if ($manifest.permission_modes.PUBLIC_DEFAULT.requires_full_access_session -ne $false) {
    Fail 'PUBLIC_DEFAULT must not require a FULL_ACCESS session for ordinary visible operations.'
}

Assert-Allowed 'ordinary visible desktop action' 'Ordinary Visible Desktop App' 'notepad.exe' 'global_desktop'
Assert-Allowed 'ordinary third party app' 'Ordinary Third Party App' 'ThirdParty.exe' 'third_party_apps'
Assert-Allowed 'browser https page' 'HTTPS Documentation Page' 'msedge.exe' 'browser_navigate'
Assert-Allowed 'localhost page' 'Localhost Fixture' 'chrome.exe' 'localhost_interact'
Assert-Allowed 'Explorer workflow' 'File Explorer' 'explorer.exe' 'explorer_navigate'
Assert-Allowed 'validated absolute screen coordinate action' 'Visible Local App' 'notepad.exe' 'desktop-click'
Assert-Allowed 'ordinary keyword page' 'test exam challenge submit assessment practice page' 'chrome.exe' 'browser_navigate'

Assert-Stopped 'real lockdown exam' 'secure exam browser active' 'Safe Exam Browser.exe' 'browser_navigate'
Assert-Stopped 'captcha human verification' 'captcha human verification' 'chrome.exe' 'mouse.click'
Assert-Stopped 'anti-cheat' 'protected game client' 'EasyAntiCheat.exe' 'mouse.click'
Assert-Stopped 'UAC protected desktop' 'User Account Control protected desktop' 'Consent.exe' 'mouse.click'

$developerKeyword = Invoke-AgentJson -CmdArgs @(
    'policy-check',
    '--title', 'test exam challenge submit assessment practice page',
    '--process', 'chrome.exe',
    '--action', 'browser_navigate',
    '--permission-mode', 'DEVELOPER_CAPABILITY_DISCOVERY'
)
if (-not $developerKeyword.ok -or -not $developerKeyword.data.allow) {
    Fail 'Developer profile was tightened for ordinary keyword content.'
}

$lines = New-Object System.Collections.Generic.List[string]
Add-Line $lines '# Public Permission Alignment Selftest'
Add-Line $lines ''
Add-Line $lines '- Result: PASS'
Add-Line $lines "- Root: $Root"
Add-Line $lines '- PUBLIC_DEFAULT ordinary visible desktop capabilities: aligned'
Add-Line $lines '- PUBLIC_DEFAULT STOP triggers: preserved'
Add-Line $lines '- Developer profile: not tightened'
Add-Line $lines '- allow_absolute_screen_click: true'
$lines | Set-Content -LiteralPath $ReportPath -Encoding UTF8

Write-Host 'public_permission_alignment_selftest PASS'
Write-Host "Report: $ReportPath"
