param(
    [string]$Root = '',
    [string]$Browser = 'auto'
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.1.4_runtime_guard_browser_normalization'
$RawRoot = Join-Path $ArtifactRoot 'raw\browser_surface_normalization_selftest'
New-Item -ItemType Directory -Force -Path $RawRoot | Out-Null

$MockHtml = 'D:\testrepo\testwindow\desktopvisual_mail_mock.html'
if (-not (Test-Path -LiteralPath $MockHtml)) {
    throw "Missing local mock page: $MockHtml"
}
$MockUrl = 'file:///D:/testrepo/testwindow/desktopvisual_mail_mock.html'
$WrongPageUrl = 'file:///D:/testrepo/testwindow/desktopvisual_wrong_page_mock.html'
$ActiveProtectionUrl = 'file:///D:/testrepo/testwindow/desktopvisual_active_protection_mock.html'
$ExpectedMarker = 'DesktopVisual|Recipient|Subject|Body|Compose'
$PermissionMode = 'DEVELOPER_CAPABILITY_DISCOVERY'

function Invoke-WinAgentJson {
    param(
        [string[]]$WinArgs,
        [int[]]$AllowedExitCodes = @(0, 1)
    )
    $output = & $WinAgent @WinArgs
    $exit = $LASTEXITCODE
    if ($AllowedExitCodes -notcontains $exit) {
        throw "winagent $($WinArgs -join ' ') exited $exit with output: $output"
    }
    try {
        $json = $output | ConvertFrom-Json
    } catch {
        throw "winagent $($WinArgs -join ' ') did not return JSON: $output"
    }
    [pscustomobject]@{ exit = $exit; json = $json; text = [string]$output; args = $WinArgs }
}

function Assert-Ok($Result, [string]$CaseId) {
    if ($Result.exit -ne 0 -or $Result.json.ok -ne $true) {
        throw "$CaseId expected PASS, exit=$($Result.exit), output=$($Result.text)"
    }
}

function Start-LocalhostMockServer {
    param([string]$HtmlPath)
    $html = Get-Content -LiteralPath $HtmlPath -Raw
    $port = Get-Random -Minimum 18120 -Maximum 18990
    $job = Start-Job -ScriptBlock {
        param($Port, $Html)
        $listener = [System.Net.HttpListener]::new()
        $prefix = "http://127.0.0.1:$Port/"
        $listener.Prefixes.Add($prefix)
        $listener.Start()
        try {
            while ($listener.IsListening) {
                $ctx = $listener.GetContext()
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($Html)
                $ctx.Response.ContentType = 'text/html; charset=utf-8'
                $ctx.Response.ContentLength64 = $bytes.Length
                $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                $ctx.Response.OutputStream.Close()
            }
        } finally {
            if ($listener.IsListening) { $listener.Stop() }
            $listener.Close()
        }
    } -ArgumentList $port, $html
    Start-Sleep -Milliseconds 600
    [pscustomobject]@{ Port = $port; Job = $job; Url = "http://127.0.0.1:$port/mail_mock.html" }
}

function Stop-LocalhostMockServer($Server) {
    if ($null -ne $Server -and $null -ne $Server.Job) {
        Stop-Job -Job $Server.Job -ErrorAction SilentlyContinue
        Remove-Job -Job $Server.Job -Force -ErrorAction SilentlyContinue
    }
}

$results = New-Object System.Collections.Generic.List[object]

$open1 = Invoke-WinAgentJson -WinArgs @(
    'browser-open-url-human',
    '--url', $MockUrl,
    '--expected-marker', $ExpectedMarker,
    '--browser', $Browser,
    '--permission-mode', $PermissionMode,
    '--result-json', (Join-Path $RawRoot 'open_initial.json')
) -AllowedExitCodes @(0, 1)
Assert-Ok $open1 'browser_open_initial_mock'
$results.Add([pscustomobject]@{
    case_id = 'browser_open_initial_mock'
    status = 'PASS'
    wrong_page_detected = $open1.json.data.wrong_page_detected
    marker_ok = $open1.json.data.marker_ok
}) | Out-Null

$focusAddress = Invoke-WinAgentJson -WinArgs @(
    'desktop-hotkey',
    '--keys', 'CTRL+L',
    '--permission-mode', $PermissionMode,
    '--expected-process-pattern', 'chrome\.exe|msedge\.exe',
    '--guard-result-json', (Join-Path $RawRoot 'focus_address_guard.json')
) -AllowedExitCodes @(0, 1)
Assert-Ok $focusAddress 'focus_browser_address_bar'

$typeSuggestion = Invoke-WinAgentJson -WinArgs @(
    'desktop-type',
    '--text', 'desktopvisual local mock',
    '--permission-mode', $PermissionMode,
    '--expected-process-pattern', 'chrome\.exe|msedge\.exe',
    '--guard-result-json', (Join-Path $RawRoot 'type_address_suggestion_guard.json')
) -AllowedExitCodes @(0, 1)
Assert-Ok $typeSuggestion 'type_address_suggestion_text'

$normalize = Invoke-WinAgentJson -WinArgs @(
    'browser-surface-normalize',
    '--mode', 'conservative',
    '--guard-result-json', (Join-Path $RawRoot 'browser_surface_normalize.json')
) -AllowedExitCodes @(0, 1)
Assert-Ok $normalize 'browser_surface_normalize'
$results.Add([pscustomobject]@{
    case_id = 'browser_surface_normalize'
    status = 'PASS'
    esc_sent = $normalize.json.data.browser_surface_normalization_result.esc_sent
    blocker_still_present = $normalize.json.data.browser_surface_normalization_result.blocker_still_present
}) | Out-Null

$missingBrowser = Invoke-WinAgentJson -WinArgs @(
    'browser-surface-normalize',
    '--title', '__desktopvisual_no_such_browser_window__',
    '--mode', 'conservative',
    '--guard-result-json', (Join-Path $RawRoot 'browser_surface_missing_browser.json')
) -AllowedExitCodes @(1)
if ($missingBrowser.json.ok -ne $false -or $missingBrowser.json.error.code -ne 'STOP_BROWSER_SURFACE_BLOCKING') {
    throw "browser_surface_missing_browser expected STOP_BROWSER_SURFACE_BLOCKING, output=$($missingBrowser.text)"
}
$results.Add([pscustomobject]@{
    case_id = 'browser_surface_missing_browser'
    status = 'PASS'
    stop_code = $missingBrowser.json.error.code
    blocker_still_present = $missingBrowser.json.data.browser_surface_normalization_result.blocker_still_present
}) | Out-Null

$open2 = Invoke-WinAgentJson -WinArgs @(
    'browser-open-url-human',
    '--url', $MockUrl,
    '--expected-marker', $ExpectedMarker,
    '--browser', $Browser,
    '--permission-mode', $PermissionMode,
    '--result-json', (Join-Path $RawRoot 'open_after_normalize.json')
) -AllowedExitCodes @(0, 1)
Assert-Ok $open2 'browser_open_after_normalize'
if ($open2.json.data.wrong_page_detected -ne $false) {
    throw 'browser_open_after_normalize detected wrong page.'
}
if ($open2.json.data.marker_ok -ne $true) {
    throw 'browser_open_after_normalize did not verify expected marker.'
}
$results.Add([pscustomobject]@{
    case_id = 'browser_open_after_normalize'
    status = 'PASS'
    wrong_page_detected = $open2.json.data.wrong_page_detected
    marker_ok = $open2.json.data.marker_ok
}) | Out-Null

$server = $null
try {
    $server = Start-LocalhostMockServer $MockHtml
    $localhostOpen = Invoke-WinAgentJson -WinArgs @(
        'browser-open-url-human',
        '--url', $server.Url,
        '--expected-marker', $ExpectedMarker,
        '--browser', $Browser,
        '--permission-mode', $PermissionMode,
        '--result-json', (Join-Path $RawRoot 'open_localhost.json')
    ) -AllowedExitCodes @(0, 1)
    Assert-Ok $localhostOpen 'browser_open_localhost_mock'
    $results.Add([pscustomobject]@{
        case_id = 'browser_open_localhost_mock'
        status = 'PASS'
        wrong_page_detected = $localhostOpen.json.data.wrong_page_detected
        marker_ok = $localhostOpen.json.data.marker_ok
        typed_url_ok = $localhostOpen.json.data.typed_url_ok
        clipboard_fallback_used = $localhostOpen.json.data.clipboard_fallback_used
    }) | Out-Null
} finally {
    Stop-LocalhostMockServer $server
}

$wrongPage = Invoke-WinAgentJson -WinArgs @(
    'browser-open-url-human',
    '--url', $WrongPageUrl,
    '--expected-marker', 'DesktopVisual Mail Mock Must Not Match',
    '--browser', $Browser,
    '--permission-mode', $PermissionMode,
    '--result-json', (Join-Path $RawRoot 'open_wrong_page.json')
) -AllowedExitCodes @(1)
if ($wrongPage.json.ok -ne $false -or $wrongPage.json.error.code -ne 'STOP_BROWSER_NAVIGATION_WRONG_PAGE') {
    throw "browser_open_wrong_page expected STOP_BROWSER_NAVIGATION_WRONG_PAGE, output=$($wrongPage.text)"
}
$results.Add([pscustomobject]@{
    case_id = 'browser_open_wrong_page'
    status = 'PASS'
    stop_code = $wrongPage.json.error.code
    action_continued = $false
}) | Out-Null

$activeProtection = Invoke-WinAgentJson -WinArgs @(
    'browser-open-url-human',
    '--url', $ActiveProtectionUrl,
    '--expected-marker', 'DesktopVisual Captcha Mock',
    '--browser', $Browser,
    '--permission-mode', $PermissionMode,
    '--result-json', (Join-Path $RawRoot 'open_active_protection.json')
) -AllowedExitCodes @(1)
if ($activeProtection.json.ok -ne $false -or $activeProtection.json.error.code -ne 'STOP_ACTIVE_PROTECTION_OR_LOGIN_BLOCK') {
    throw "browser_open_active_protection expected STOP_ACTIVE_PROTECTION_OR_LOGIN_BLOCK, output=$($activeProtection.text)"
}
$results.Add([pscustomobject]@{
    case_id = 'browser_open_active_protection'
    status = 'PASS'
    stop_code = $activeProtection.json.error.code
    bypass_attempted = $false
}) | Out-Null

$summary = [pscustomobject]@{
    status = 'PASS'
    browser = $Browser
    mock_url = $MockUrl
    no_google_bing_search_new_tab_error_page = $true
    active_protection_policy = 'STOP_ONLY_NOT_BYPASSED'
    overlay_policy = 'ESC_ONLY_UNKNOWN_X_NOT_CLICKED'
    cases = @($results.ToArray())
}
$summaryPath = Join-Path $ArtifactRoot 'browser_surface_normalization_selftest_summary.json'
$summary | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

$reportPath = Join-Path $ArtifactRoot 'browser_surface_normalization_report.md'
$lines = @(
    '# Browser Surface Normalization Report',
    '',
    'Result: PASS',
    '',
    "Mock URL: $MockUrl",
    '',
    '| case | status | detail |',
    '|---|---|---|'
)
foreach ($case in $results) {
    $detail = ($case | ConvertTo-Json -Compress -Depth 20)
    $lines += "| $($case.case_id) | $($case.status) | $detail |"
}
$lines += ''
$lines += 'Policy evidence: conservative normalization sends ESC for browser suggestion/overlay surfaces, refuses active protection/login/automation surfaces, and does not click unknown page body close buttons.'
$lines | Set-Content -LiteralPath $reportPath -Encoding UTF8

Write-Host "browser_surface_normalization_selftest PASS: $reportPath"
