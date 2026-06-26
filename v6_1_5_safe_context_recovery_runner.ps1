param(
    [string]$Root = '',
    [string]$Browser = 'auto'
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.1.5_safe_context_recovery_dynamic_diagnostics'
$RawRoot = Join-Path $ArtifactRoot 'raw\safe_context_recovery'
New-Item -ItemType Directory -Force -Path $RawRoot | Out-Null

$TestRoot = 'D:\testrepo\testwindow'
$MailHtml = Join-Path $TestRoot 'desktopvisual_mail_mock.html'
$WrongHtml = Join-Path $TestRoot 'desktopvisual_wrong_page_mock.html'
$ActiveHtml = Join-Path $TestRoot 'desktopvisual_active_protection_mock.html'
$CredentialHtml = Join-Path $TestRoot 'desktopvisual_credential_required_mock.html'
$KeywordHtml = Join-Path $TestRoot 'desktopvisual_keyword_nonblock_mock.html'
$MailUrl = 'file:///D:/testrepo/testwindow/desktopvisual_mail_mock.html'
$WrongUrl = 'file:///D:/testrepo/testwindow/desktopvisual_wrong_page_mock.html'
$KeywordUrl = 'file:///D:/testrepo/testwindow/desktopvisual_keyword_nonblock_mock.html'
$ExpectedMailMarker = 'DesktopVisual Local Mail Mock|Recipient|Subject|Body'
$PermissionMode = 'DEVELOPER_CAPABILITY_DISCOVERY'

foreach ($required in @($MailHtml, $WrongHtml, $ActiveHtml, $CredentialHtml, $KeywordHtml)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Missing required v6.1.5 fixture: $required"
    }
}

function ConvertTo-JsonOrNull([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    try { return $Text | ConvertFrom-Json } catch { return $null }
}

function Invoke-WinAgentRaw {
    param(
        [string]$CaseId,
        [string]$StepId,
        [string[]]$WinArgs,
        [int[]]$AllowedExitCodes = @(0, 1)
    )
    $caseDir = Join-Path $RawRoot $CaseId
    New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
    $stdoutPath = Join-Path $caseDir "$StepId.stdout.log"
    $stderrPath = Join-Path $caseDir "$StepId.stderr.log"
    $metaPath = Join-Path $caseDir "$StepId.meta.json"
    $start = Get-Date
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & $WinAgent @WinArgs 2>&1
    $exit = $LASTEXITCODE
    $ErrorActionPreference = $previousEap
    $text = ($output | Out-String).Trim()
    $text | Set-Content -LiteralPath $stdoutPath -Encoding UTF8
    '' | Set-Content -LiteralPath $stderrPath -Encoding UTF8
    $json = ConvertTo-JsonOrNull $text
    $meta = [pscustomobject]@{
        case_id = $CaseId
        step_id = $StepId
        command = "winagent.exe $($WinArgs -join ' ')"
        started_at = $start.ToString('o')
        ended_at = (Get-Date).ToString('o')
        exit_code = $exit
        exit_code_allowed = ($AllowedExitCodes -contains $exit)
        stdout_path = $stdoutPath
        stderr_path = $stderrPath
        parsed_json = ($null -ne $json)
    }
    $meta | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $metaPath -Encoding UTF8
    [pscustomobject]@{
        case_id = $CaseId
        step_id = $StepId
        exit_code = $exit
        allowed = ($AllowedExitCodes -contains $exit)
        stdout_path = $stdoutPath
        stderr_path = $stderrPath
        meta_path = $metaPath
        json = $json
        text = $text
    }
}

function Start-LocalhostRecoveryServer {
    $mail = Get-Content -LiteralPath $MailHtml -Raw
    $wrong = Get-Content -LiteralPath $WrongHtml -Raw
    $port = Get-Random -Minimum 19120 -Maximum 19980
    $job = Start-Job -ScriptBlock {
        param($Port, $Mail, $Wrong)
        $listener = [System.Net.HttpListener]::new()
        $listener.Prefixes.Add("http://127.0.0.1:$Port/")
        $listener.Start()
        try {
            while ($listener.IsListening) {
                $ctx = $listener.GetContext()
                $path = $ctx.Request.Url.AbsolutePath
                $html = if ($path -like '*wrong*') { $Wrong } else { $Mail }
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
                $ctx.Response.ContentType = 'text/html; charset=utf-8'
                $ctx.Response.ContentLength64 = $bytes.Length
                $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                $ctx.Response.OutputStream.Close()
            }
        } finally {
            if ($listener.IsListening) { $listener.Stop() }
            $listener.Close()
        }
    } -ArgumentList $port, $mail, $wrong
    Start-Sleep -Milliseconds 600
    [pscustomobject]@{
        Port = $port
        Job = $job
        MailUrl = "http://127.0.0.1:$port/mail_mock.html"
        WrongUrl = "http://127.0.0.1:$port/wrong.html"
    }
}

function Stop-LocalhostRecoveryServer($Server) {
    if ($null -ne $Server -and $null -ne $Server.Job) {
        Stop-Job -Job $Server.Job -ErrorAction SilentlyContinue
        Remove-Job -Job $Server.Job -Force -ErrorAction SilentlyContinue
    }
}

$cases = New-Object System.Collections.Generic.List[object]

function Add-Case {
    param(
        [string]$CaseId,
        [string]$Expected,
        [object[]]$Steps,
        [string]$PrimaryResultJson = '',
        [string]$CheckpointJson = '',
        [string]$FailureAttributionJson = ''
    )
    $cases.Add([pscustomobject]@{
        case_id = $CaseId
        expected = $Expected
        raw_status = 'RAW_COMPLETED_UNVERIFIED'
        primary_result_json = $PrimaryResultJson
        checkpoint_json = $CheckpointJson
        failure_attribution_json = $FailureAttributionJson
        steps = @($Steps)
    }) | Out-Null
}

@(
    '# v6.1.5 Safe Context Recovery Design',
    '',
    '- Runtime command: `safe-context-recovery` owns recovery allow/deny, active-protection STOP, credential STOP, target allowlist, reobserve marker verification, and resume gating inputs.',
    '- Runtime command: `task-checkpoint-evaluate` owns checkpoint/resume/replay decisions after recovery.',
    '- Runtime command: `failure-attribution-classify` owns unified diagnostic failure attribution.',
    '- Runner output is raw and unverified. Verifier and gate own PASS authority.',
    '- v6.1.5 scope is Safe Recovery plus Dynamic Diagnostics only. v6.1.6 is reserved for full Dynamic App/Web Developer FULL_ACCESS Automation RC.'
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'safe_context_recovery_design.md') -Encoding UTF8

$caseId = 'safe_context_recovery_selftest'
$selfResult = Join-Path $RawRoot "$caseId\safe_context_recovery.json"
$steps = @()
$steps += Invoke-WinAgentRaw $caseId 'safe_context_recovery' @(
    'safe-context-recovery',
    '--recovery-enabled', 'true',
    '--recovery-action', 'none',
    '--recovery-url', $MailUrl,
    '--context-text', 'DesktopVisual Local Mail Mock Recipient Subject Body',
    '--recovery-expected-marker', 'Recipient',
    '--dry-run', 'true',
    '--result-json', $selfResult
)
Add-Case $caseId 'SafeContextRecovery selftest allows local mock context and verifies marker.' $steps $selfResult

$caseId = 'case_1_local_mock_wrong_page_recovery'
$caseDir = Join-Path $RawRoot $caseId
$safeResult = Join-Path $caseDir 'safe_context_recovery.json'
$checkpointResult = Join-Path $caseDir 'checkpoint_resume.json'
$steps = @()
$steps += Invoke-WinAgentRaw $caseId 'open_wrong_local_page' @(
    'browser-open-url-human', '--url', $WrongUrl, '--expected-marker', 'Google Search',
    '--browser', $Browser, '--permission-mode', $PermissionMode,
    '--result-json', (Join-Path $caseDir 'open_wrong_local_page.json')
)
$steps += Invoke-WinAgentRaw $caseId 'safe_context_recovery' @(
    'safe-context-recovery',
    '--recovery-enabled', 'true',
    '--recovery-scope', 'local_file_mock',
    '--recovery-action', 'browser_open_url_human',
    '--recovery-url', $MailUrl,
    '--recovery-expected-marker', $ExpectedMailMarker,
    '--resume-policy', 'replay_from_checkpoint',
    '--checkpoint-required', 'true',
    '--checkpoint-available', 'true',
    '--context-text', 'Google Search wrong page context',
    '--result-json', $safeResult
)
$steps += Invoke-WinAgentRaw $caseId 'checkpoint_resume' @(
    'task-checkpoint-evaluate',
    '--task-id', 'v6_1_5_safe_recovery',
    '--case-id', $caseId,
    '--step-index', '2',
    '--step-name', 'after_recovery_reobserve',
    '--verified-context', 'DesktopVisual Local Mail Mock',
    '--verified-marker', 'Recipient',
    '--verified-window-title', 'DesktopVisual Local Mail Mock',
    '--verified-process', 'browser',
    '--input-state-hash', 'before-recovery-input',
    '--page-state-hash', 'mail-mock-page',
    '--safe-to-resume', 'true',
    '--resume-from-step', '3',
    '--replay-from-step', '1',
    '--current-context', 'DesktopVisual Local Mail Mock',
    '--current-window-title', 'DesktopVisual Local Mail Mock',
    '--current-process', 'browser',
    '--current-input-state-hash', 'after-recovery-input',
    '--current-page-state-hash', 'mail-mock-page',
    '--state-loss-risk', 'medium',
    '--recovery-just-executed', 'true',
    '--reobserve-performed', 'true',
    '--expected-context-reverified', 'true',
    '--result-json', $checkpointResult
)
Add-Case $caseId 'Wrong local file page recovers to mail mock and requires replay from safe checkpoint when input state may be lost.' $steps $safeResult $checkpointResult

$server = $null
try {
    $server = Start-LocalhostRecoveryServer
    $caseId = 'case_2_localhost_wrong_page_recovery'
    $caseDir = Join-Path $RawRoot $caseId
    $safeResult = Join-Path $caseDir 'safe_context_recovery.json'
    $checkpointResult = Join-Path $caseDir 'checkpoint_resume.json'
    $steps = @()
    $steps += Invoke-WinAgentRaw $caseId 'open_wrong_localhost_page' @(
        'browser-open-url-human', '--url', $server.WrongUrl, '--expected-marker', 'Google Search',
        '--browser', $Browser, '--permission-mode', $PermissionMode,
        '--result-json', (Join-Path $caseDir 'open_wrong_localhost_page.json')
    )
    $steps += Invoke-WinAgentRaw $caseId 'safe_context_recovery' @(
        'safe-context-recovery',
        '--recovery-enabled', 'true',
        '--recovery-scope', 'localhost_mock',
        '--recovery-action', 'browser_open_url_human',
        '--recovery-url', $server.MailUrl,
        '--recovery-expected-marker', $ExpectedMailMarker,
        '--resume-policy', 'checkpoint',
        '--checkpoint-required', 'true',
        '--checkpoint-available', 'true',
        '--context-text', 'Google Search wrong localhost page context',
        '--result-json', $safeResult
    )
    $steps += Invoke-WinAgentRaw $caseId 'checkpoint_resume' @(
        'task-checkpoint-evaluate',
        '--task-id', 'v6_1_5_safe_recovery',
        '--case-id', $caseId,
        '--step-index', '2',
        '--step-name', 'after_localhost_recovery',
        '--verified-context', 'DesktopVisual Local Mail Mock',
        '--verified-marker', 'Recipient',
        '--verified-window-title', 'DesktopVisual Local Mail Mock',
        '--verified-process', 'browser',
        '--input-state-hash', 'same',
        '--page-state-hash', 'mail-localhost-page',
        '--safe-to-resume', 'true',
        '--resume-from-step', '3',
        '--replay-from-step', '1',
        '--current-context', 'DesktopVisual Local Mail Mock',
        '--current-window-title', 'DesktopVisual Local Mail Mock',
        '--current-process', 'browser',
        '--current-input-state-hash', 'same',
        '--current-page-state-hash', 'mail-localhost-page',
        '--recovery-just-executed', 'true',
        '--reobserve-performed', 'true',
        '--expected-context-reverified', 'true',
        '--result-json', $checkpointResult
    )
    Add-Case $caseId 'Wrong localhost page recovers to localhost mail mock with marker verification.' $steps $safeResult $checkpointResult
} finally {
    Stop-LocalhostRecoveryServer $server
}

$caseId = 'case_3_explorer_wrong_folder_recovery'
$caseDir = Join-Path $RawRoot $caseId
$safeResult = Join-Path $caseDir 'safe_context_recovery.json'
$steps = @()
$steps += Invoke-WinAgentRaw $caseId 'safe_context_recovery' @(
    'safe-context-recovery',
    '--recovery-enabled', 'true',
    '--recovery-scope', 'explorer_test_directory',
    '--recovery-action', 'explorer_open_path',
    '--recovery-path', $TestRoot,
    '--recovery-expected-marker', 'desktopvisual_mail_mock.html|testwindow',
    '--resume-policy', 'checkpoint',
    '--checkpoint-required', 'false',
    '--context-text', 'Explorer current folder C:\Windows\System32 does not match D:\testrepo\testwindow',
    '--result-json', $safeResult
)
Add-Case $caseId 'Explorer wrong-folder context recovers to D:\testrepo\testwindow and verifies directory marker.' $steps $safeResult

$caseId = 'case_4_browser_surface_wrong_page_recovery'
$caseDir = Join-Path $RawRoot $caseId
$safeResult = Join-Path $caseDir 'safe_context_recovery.json'
$steps = @()
$steps += Invoke-WinAgentRaw $caseId 'open_browser_wrong_page' @(
    'browser-open-url-human', '--url', $WrongUrl, '--expected-marker', 'Google Search',
    '--browser', $Browser, '--permission-mode', $PermissionMode,
    '--result-json', (Join-Path $caseDir 'open_browser_wrong_page.json')
)
$steps += Invoke-WinAgentRaw $caseId 'safe_context_recovery' @(
    'safe-context-recovery',
    '--recovery-enabled', 'true',
    '--recovery-scope', 'browser_open_url_human',
    '--recovery-action', 'browser_open_url_human',
    '--recovery-url', $MailUrl,
    '--recovery-expected-marker', $ExpectedMailMarker,
    '--resume-policy', 'checkpoint',
    '--checkpoint-required', 'false',
    '--context-text', 'Browser surface is on Google Search wrong page',
    '--result-json', $safeResult
)
Add-Case $caseId 'Browser wrong page recovers through browser-open-url-human to target file URL.' $steps $safeResult

$caseId = 'case_5_active_protection_hard_stop'
$caseDir = Join-Path $RawRoot $caseId
$safeResult = Join-Path $caseDir 'safe_context_recovery.json'
$attrResult = Join-Path $caseDir 'failure_attribution.json'
$steps = @()
$steps += Invoke-WinAgentRaw $caseId 'safe_context_recovery' @(
    'safe-context-recovery',
    '--recovery-enabled', 'true',
    '--recovery-action', 'browser_open_url_human',
    '--recovery-url', $MailUrl,
    '--context-file', $ActiveHtml,
    '--result-json', $safeResult
) @(1)
$steps += Invoke-WinAgentRaw $caseId 'failure_attribution' @(
    'failure-attribution-classify',
    '--stop-code', 'STOP_ACTIVE_PROTECTION_OR_LOGIN_BLOCK',
    '--context-file', $ActiveHtml,
    '--result-json', $attrResult
)
Add-Case $caseId 'Active protection mock must hard STOP with no recovery attempt.' $steps $safeResult '' $attrResult

$caseId = 'case_6_credential_required_hard_stop'
$caseDir = Join-Path $RawRoot $caseId
$safeResult = Join-Path $caseDir 'safe_context_recovery.json'
$attrResult = Join-Path $caseDir 'failure_attribution.json'
$steps = @()
$steps += Invoke-WinAgentRaw $caseId 'safe_context_recovery' @(
    'safe-context-recovery',
    '--recovery-enabled', 'true',
    '--recovery-action', 'browser_open_url_human',
    '--recovery-url', $MailUrl,
    '--context-file', $CredentialHtml,
    '--result-json', $safeResult
) @(1)
$steps += Invoke-WinAgentRaw $caseId 'failure_attribution' @(
    'failure-attribution-classify',
    '--stop-code', 'STOP_CREDENTIAL_REQUIRED',
    '--context-file', $CredentialHtml,
    '--result-json', $attrResult
)
Add-Case $caseId 'Credential-required mock must hard STOP without typing credentials.' $steps $safeResult '' $attrResult

$caseId = 'case_7_keyword_nonblock_regression'
$caseDir = Join-Path $RawRoot $caseId
$safeResult = Join-Path $caseDir 'safe_context_recovery.json'
$steps = @()
$steps += Invoke-WinAgentRaw $caseId 'open_keyword_page' @(
    'browser-open-url-human', '--url', $KeywordUrl, '--expected-marker', 'Keyword Nonblock|test|exam|OJ|submit|race',
    '--browser', $Browser, '--permission-mode', $PermissionMode,
    '--result-json', (Join-Path $caseDir 'open_keyword_page.json')
)
$steps += Invoke-WinAgentRaw $caseId 'safe_context_recovery' @(
    'safe-context-recovery',
    '--recovery-enabled', 'true',
    '--recovery-action', 'none',
    '--recovery-url', $KeywordUrl,
    '--context-file', $KeywordHtml,
    '--recovery-expected-marker', 'test.*exam.*contest.*interview.*challenge.*assessment.*OJ.*submit.*code.*race',
    '--dry-run', 'true',
    '--result-json', $safeResult
)
$steps += Invoke-WinAgentRaw $caseId 'keyword_find_box' @(
    'desktop-hotkey', '--keys', 'CTRL+F', '--permission-mode', $PermissionMode,
    '--expected-process-pattern', 'chrome\.exe|msedge\.exe'
)
$steps += Invoke-WinAgentRaw $caseId 'keyword_type_probe' @(
    'desktop-type', '--text', 'race', '--permission-mode', $PermissionMode,
    '--expected-process-pattern', 'chrome\.exe|msedge\.exe'
)
$steps += Invoke-WinAgentRaw $caseId 'keyword_escape_find' @(
    'desktop-hotkey', '--keys', 'ESC', '--permission-mode', $PermissionMode,
    '--expected-process-pattern', 'chrome\.exe|msedge\.exe'
)
Add-Case $caseId 'Ordinary keywords do not create STOP conditions and low-risk observe/type actions can run.' $steps $safeResult

$matrix = [pscustomobject]@{
    schema_version = 'v6.1.5.safe_context_recovery.raw'
    generated_at = (Get-Date).ToString('o')
    runner_status = 'RAW_COMPLETED_UNVERIFIED'
    runner_self_certified_pass = $false
    cases = @($cases.ToArray())
}
$matrixPath = Join-Path $RawRoot 'safe_recovery_raw_matrix.json'
$matrix | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $matrixPath -Encoding UTF8

$caseRows = @($cases.ToArray()) | ForEach-Object {
    '| {0} | {1} | {2} |' -f $_.case_id, $_.raw_status, $_.primary_result_json
}
$reportLines = @(
    '# v6.1.5 Safe Context Recovery Runner Raw Evidence',
    '',
    '- Runner status: RAW_COMPLETED_UNVERIFIED',
    '- Runner self-certified PASS: false',
    ('- Raw matrix: {0}' -f $matrixPath),
    '',
    '| case | raw_status | primary_result_json |',
    '|---|---|---|'
) + @($caseRows)
$reportLines | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'safe_recovery_cases_report.md') -Encoding UTF8

Write-Host "v6.1.5 safe context recovery runner completed raw evidence: $matrixPath"
exit 0
