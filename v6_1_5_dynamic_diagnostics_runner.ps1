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
$RawRoot = Join-Path $ArtifactRoot 'raw\dynamic_diagnostics'
New-Item -ItemType Directory -Force -Path $RawRoot | Out-Null

$PermissionMode = 'DEVELOPER_CAPABILITY_DISCOVERY'
$BrowserProcessPattern = 'chrome\.exe|msedge\.exe'

function ConvertTo-JsonOrNull([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    try { return $Text | ConvertFrom-Json } catch { return $null }
}

function Invoke-WinAgentRaw {
    param(
        [string]$CaseId,
        [string]$StepId,
        [string[]]$WinArgs,
        [int[]]$AllowedExitCodes = @(0, 1, 2)
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

function Get-EnvelopeOk($Json) {
    if ($null -eq $Json) { return $false }
    if ($null -ne $Json.ok) { return [bool]$Json.ok }
    return $false
}

function Get-EnvelopeStopCode($Json) {
    if ($null -eq $Json) { return '' }
    if ($Json.error -and $Json.error.code) { return [string]$Json.error.code }
    if ($Json.error_code) { return [string]$Json.error_code }
    return ''
}

function Get-StepText([object[]]$Steps) {
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($step in @($Steps)) {
        if ($step.text) { $parts.Add([string]$step.text) | Out-Null }
        if ($step.stdout_path -and (Test-Path -LiteralPath $step.stdout_path)) {
            try {
                $raw = Get-Content -LiteralPath $step.stdout_path -Raw
                if ($raw.Length -gt 24000) { $raw = $raw.Substring(0, 24000) }
                $parts.Add($raw) | Out-Null
            } catch {
            }
        }
    }
    ($parts.ToArray() -join "`n")
}

function Test-ActiveProtectionText([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return $Text -match "(?i)\b(captcha|recaptcha|hcaptcha|turnstile)\b|human verification|verify you are human|bot challenge|automation detected|script detection challenge|unusual traffic|anti[- ]?cheat|lockdown browser|proctoring|script check"
}

function Test-CredentialRequiredText([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return $Text -match "(?i)login required|sign in to continue|required to sign in|username.*password|password|verification code|sms code|email code|account security|risk verification|security verification|account verification|login wall"
}

function Invoke-FailureAttribution {
    param(
        [string]$CaseId,
        [string]$StopCode,
        [string]$Reason,
        [string]$ContextText,
        [string]$TargetType
    )
    $caseDir = Join-Path $RawRoot $CaseId
    New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
    $attrPath = Join-Path $caseDir 'failure_attribution.json'
    $contextPath = Join-Path $caseDir 'failure_context.txt'
    $ContextText | Set-Content -LiteralPath $contextPath -Encoding UTF8
    $step = Invoke-WinAgentRaw $CaseId 'failure_attribution' @(
        'failure-attribution-classify',
        '--stop-code', $StopCode,
        '--failure-reason', $Reason,
        '--target-type', $TargetType,
        '--context-file', $contextPath,
        '--result-json', $attrPath
    )
    $attrJson = if (Test-Path -LiteralPath $attrPath) { Get-Content -LiteralPath $attrPath -Raw | ConvertFrom-Json } else { $step.json }
    $value = ''
    if ($attrJson -and $attrJson.data -and $attrJson.data.failure_attribution) {
        $value = [string]$attrJson.data.failure_attribution
    }
    if ([string]::IsNullOrWhiteSpace($value)) { $value = 'UNKNOWN_FAILURE' }
    [pscustomobject]@{ path = $attrPath; value = $value; step = $step }
}

function Find-PyCharmExe {
    $cmd = Get-Command pycharm64.exe -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) { return $cmd.Source }
    foreach ($root in @('C:\Program Files\JetBrains', 'C:\Program Files (x86)\JetBrains')) {
        if (Test-Path -LiteralPath $root) {
            $hit = Get-ChildItem -LiteralPath $root -Filter pycharm64.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
    }
    return ''
}

function New-DiagnosticRecord {
    param(
        [string]$CaseId,
        [string]$Category,
        [string]$TargetName,
        [string]$TargetType,
        [string]$TargetUrlOrApp,
        [object[]]$Steps,
        [bool]$ForegroundAcquired,
        [bool]$ExpectedProcessOk,
        [bool]$ExpectedTitleOk,
        [bool]$UiaReadOk,
        [bool]$OcrReadOk,
        [bool]$ScreenObserveOk,
        [bool]$BrowserSurfaceOk,
        [bool]$TargetVisible,
        [int]$TargetCandidateCount,
        [bool]$TargetUnique,
        [bool]$ScrollRegionFound,
        [bool]$ScrollProgressDetected,
        [bool]$ActionAttempted,
        [bool]$ActionExecuted,
        [bool]$ActiveProtectionDetected,
        [bool]$CredentialRequiredDetected,
        [string]$FinalStopCode,
        [string]$FailureAttribution,
        [string[]]$EvidencePaths
    )
    [pscustomobject]@{
        case_id = $CaseId
        diagnostic_category = $Category
        target_name = $TargetName
        target_type = $TargetType
        target_url_or_app = $TargetUrlOrApp
        developer_full_access = $true
        active_protection_detected = $ActiveProtectionDetected
        credential_required_detected = $CredentialRequiredDetected
        foreground_acquired = $ForegroundAcquired
        expected_process_ok = $ExpectedProcessOk
        expected_title_ok = $ExpectedTitleOk
        uia_read_ok = $UiaReadOk
        ocr_read_ok = $OcrReadOk
        screen_observe_ok = $ScreenObserveOk
        browser_surface_ok = $BrowserSurfaceOk
        target_visible = $TargetVisible
        target_candidate_count = $TargetCandidateCount
        target_unique = $TargetUnique
        target_seen_but_not_confirmed = ($TargetVisible -and (-not $ExpectedProcessOk -or -not $ExpectedTitleOk))
        scroll_region_found = $ScrollRegionFound
        scroll_progress_detected = $ScrollProgressDetected
        action_attempted = $ActionAttempted
        action_executed = $ActionExecuted
        recovery_allowed = $false
        recovery_attempted = $false
        recovery_success = $false
        final_stop_code = $FinalStopCode
        failure_attribution = $FailureAttribution
        evidence_paths = $EvidencePaths
        raw_status = 'RAW_COMPLETED_UNVERIFIED'
        runner_self_certified_pass = $false
        steps = @($Steps)
    }
}

function Invoke-WebDiagnostic {
    param(
        [string]$CaseId,
        [string]$Category,
        [string]$TargetName,
        [string]$Url,
        [string]$ExpectedMarker,
        [string]$TitlePattern,
        [string]$ProbeText
    )
    $steps = New-Object System.Collections.Generic.List[object]
    $caseDir = Join-Path $RawRoot $CaseId
    New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
    $openJson = Join-Path $caseDir 'open_url.json'
    $steps.Add((Invoke-WinAgentRaw $CaseId 'open_url_human' @(
        'browser-open-url-human',
        '--url', $Url,
        '--expected-marker', $ExpectedMarker,
        '--browser', $Browser,
        '--permission-mode', $PermissionMode,
        '--wait-ms', '15000',
        '--result-json', $openJson
    ))) | Out-Null
    Start-Sleep -Milliseconds 500
    $activeJson = Join-Path $caseDir 'active_window.json'
    $active = Invoke-WinAgentRaw $CaseId 'active_window' @('active-window', '--result-json', $activeJson)
    $steps.Add($active) | Out-Null

    $activeTitle = ''
    $activeProcess = ''
    if ($active.json -and $active.json.data) {
        $activeTitle = [string]$active.json.data.title
        $activeProcess = [string]$active.json.data.process_name
    }
    $foregroundAcquired = Get-EnvelopeOk $active.json
    $expectedProcessOk = $foregroundAcquired -and ($activeProcess -match $BrowserProcessPattern)
    $expectedTitleOk = $foregroundAcquired -and ($activeTitle -match $TitlePattern)
    $targetVisible = $expectedProcessOk -and $expectedTitleOk
    $targetCount = if ($targetVisible) { 1 } else { 0 }

    $uiaReadOk = $false
    if ($activeTitle) {
        $uia = Invoke-WinAgentRaw $CaseId 'uia_tree' @('uia-tree', '--title', $activeTitle)
        $steps.Add($uia) | Out-Null
        $uiaReadOk = Get-EnvelopeOk $uia.json
    }

    $contextText = "$TargetName`n$Url`n$activeTitle`n" + (Get-StepText @($steps.ToArray()))
    $activeProtectionDetected = Test-ActiveProtectionText $contextText
    $credentialRequiredDetected = Test-CredentialRequiredText $contextText
    $openEnvelope = if (Test-Path -LiteralPath $openJson) { Get-Content -LiteralPath $openJson -Raw | ConvertFrom-Json } else { $steps[0].json }
    $openOk = Get-EnvelopeOk $openEnvelope
    $browserSurfaceOk = $openOk -and -not $activeProtectionDetected

    $scrollRegionFound = $openOk -and $targetVisible -and -not $activeProtectionDetected -and -not $credentialRequiredDetected
    $scrollProgressDetected = $false
    $actionAttempted = $true
    $actionExecuted = $false
    if ($scrollRegionFound) {
        $find = Invoke-WinAgentRaw $CaseId 'find_box' @(
            'desktop-hotkey', '--keys', 'CTRL+F',
            '--permission-mode', $PermissionMode,
            '--expected-process-pattern', $BrowserProcessPattern,
            '--expected-title-pattern', $TitlePattern,
            '--stop-on-wrong-context', 'true',
            '--guard-result-json', (Join-Path $caseDir 'find_guard.json')
        )
        $steps.Add($find) | Out-Null
        $type = Invoke-WinAgentRaw $CaseId 'type_probe' @(
            'desktop-type', '--text', $ProbeText,
            '--permission-mode', $PermissionMode,
            '--expected-process-pattern', $BrowserProcessPattern,
            '--expected-title-pattern', $TitlePattern,
            '--stop-on-wrong-context', 'true',
            '--guard-result-json', (Join-Path $caseDir 'type_guard.json')
        )
        $steps.Add($type) | Out-Null
        $escape = Invoke-WinAgentRaw $CaseId 'escape_find' @(
            'desktop-hotkey', '--keys', 'ESC',
            '--permission-mode', $PermissionMode,
            '--expected-process-pattern', $BrowserProcessPattern,
            '--expected-title-pattern', $TitlePattern,
            '--stop-on-wrong-context', 'true',
            '--guard-result-json', (Join-Path $caseDir 'escape_guard.json')
        )
        $steps.Add($escape) | Out-Null
        $scroll = Invoke-WinAgentRaw $CaseId 'page_down_scroll' @(
            'desktop-hotkey', '--keys', 'PAGEDOWN',
            '--permission-mode', $PermissionMode,
            '--expected-process-pattern', $BrowserProcessPattern,
            '--expected-title-pattern', $TitlePattern,
            '--stop-on-wrong-context', 'true',
            '--guard-result-json', (Join-Path $caseDir 'scroll_guard.json')
        )
        $steps.Add($scroll) | Out-Null
        $actionExecuted = ($find.exit_code -eq 0 -and $type.exit_code -eq 0 -and $escape.exit_code -eq 0)
        $scrollProgressDetected = ($scroll.exit_code -eq 0)
    }

    $finalStopCode = 'OK_DIAGNOSTIC'
    $reason = 'diagnostic completed'
    if ($activeProtectionDetected) {
        $finalStopCode = 'STOP_ACTIVE_PROTECTION_OR_LOGIN_BLOCK'
        $reason = 'active protection or script detection challenge detected'
    } elseif ($credentialRequiredDetected) {
        $finalStopCode = 'STOP_CREDENTIAL_REQUIRED'
        $reason = 'credential or account verification handoff detected'
    } elseif (-not $openOk) {
        $finalStopCode = Get-EnvelopeStopCode $openEnvelope
        if ([string]::IsNullOrWhiteSpace($finalStopCode)) { $finalStopCode = 'BROWSER_SURFACE_BLOCKING' }
        $reason = 'browser open or marker verification failed'
    } elseif (-not $foregroundAcquired) {
        $finalStopCode = 'FOREGROUND_ACQUIRE_FAILED'
        $reason = 'foreground window was not acquired'
    } elseif (-not $targetVisible) {
        $finalStopCode = 'EXPECTED_CONTEXT_FAILED'
        $reason = 'expected process or title did not match before low-risk action'
    } elseif (-not $uiaReadOk) {
        $finalStopCode = 'UIA_READ_FAILED'
        $reason = 'UIA tree read failed'
    }

    if ($finalStopCode -eq 'OK_DIAGNOSTIC') {
        $failureAttribution = 'NO_FAILURE'
        $attrPath = ''
    } else {
        $attr = Invoke-FailureAttribution $CaseId $finalStopCode $reason $contextText 'web'
        $steps.Add($attr.step) | Out-Null
        $failureAttribution = $attr.value
        $attrPath = $attr.path
    }
    $evidence = @($openJson, $activeJson, (Join-Path $caseDir 'uia_tree.stdout.log'), $attrPath) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    New-DiagnosticRecord `
        -CaseId $CaseId `
        -Category $Category `
        -TargetName $TargetName `
        -TargetType 'web' `
        -TargetUrlOrApp $Url `
        -Steps @($steps.ToArray()) `
        -ForegroundAcquired $foregroundAcquired `
        -ExpectedProcessOk $expectedProcessOk `
        -ExpectedTitleOk $expectedTitleOk `
        -UiaReadOk $uiaReadOk `
        -OcrReadOk $false `
        -ScreenObserveOk $foregroundAcquired `
        -BrowserSurfaceOk $browserSurfaceOk `
        -TargetVisible $targetVisible `
        -TargetCandidateCount $targetCount `
        -TargetUnique ($targetCount -eq 1) `
        -ScrollRegionFound $scrollRegionFound `
        -ScrollProgressDetected $scrollProgressDetected `
        -ActionAttempted $actionAttempted `
        -ActionExecuted $actionExecuted `
        -ActiveProtectionDetected $activeProtectionDetected `
        -CredentialRequiredDetected $credentialRequiredDetected `
        -FinalStopCode $finalStopCode `
        -FailureAttribution $failureAttribution `
        -EvidencePaths @($evidence)
}

function Invoke-PyCharmDiagnostic {
    $caseId = 'dyn_a_pycharm_diagnostic'
    $category = 'A.PyCharm'
    $targetName = 'PyCharm diagnostic'
    $projectPath = 'D:\testrepo\pycharm_sanity'
    $steps = New-Object System.Collections.Generic.List[object]
    $exe = Find-PyCharmExe
    $contextText = "PyCharm`n$projectPath`n$exe"
    if ([string]::IsNullOrWhiteSpace($exe)) {
        $attr = Invoke-FailureAttribution $caseId 'APP_NOT_INSTALLED' 'PyCharm executable not found.' $contextText 'app'
        $steps.Add($attr.step) | Out-Null
        return New-DiagnosticRecord `
            -CaseId $caseId -Category $category -TargetName $targetName -TargetType 'app' -TargetUrlOrApp $projectPath `
            -Steps @($steps.ToArray()) -ForegroundAcquired $false -ExpectedProcessOk $false -ExpectedTitleOk $false `
            -UiaReadOk $false -OcrReadOk $false -ScreenObserveOk $false -BrowserSurfaceOk $false -TargetVisible $false `
            -TargetCandidateCount 0 -TargetUnique $false -ScrollRegionFound $false -ScrollProgressDetected $false `
            -ActionAttempted $true -ActionExecuted $false -ActiveProtectionDetected $false -CredentialRequiredDetected $false `
            -FinalStopCode 'APP_NOT_INSTALLED' -FailureAttribution $attr.value -EvidencePaths @($attr.path)
    }

    $launch = Invoke-WinAgentRaw $caseId 'launch_pycharm' @(
        'launch-app',
        '--path', $exe,
        '--target-title', 'PyCharm',
        '--process', 'pycharm64.exe',
        '--permission-mode', $PermissionMode,
        '--wait-ms', '60000'
    )
    $steps.Add($launch) | Out-Null
    Start-Sleep -Seconds 2
    $activeJson = Join-Path $RawRoot "$caseId\active_window.json"
    $active = Invoke-WinAgentRaw $caseId 'active_window' @('active-window', '--result-json', $activeJson)
    $steps.Add($active) | Out-Null

    $activeTitle = ''
    $activeProcess = ''
    if ($active.json -and $active.json.data) {
        $activeTitle = [string]$active.json.data.title
        $activeProcess = [string]$active.json.data.process_name
    }
    $foregroundAcquired = Get-EnvelopeOk $active.json
    $expectedProcessOk = $foregroundAcquired -and ($activeProcess -match 'pycharm64\.exe|pycharm\.exe')
    $expectedTitleOk = $foregroundAcquired -and ($activeTitle -match 'PyCharm|pycharm_sanity')
    $targetVisible = $expectedProcessOk -and $expectedTitleOk
    $uiaReadOk = $false
    if ($activeTitle) {
        $uia = Invoke-WinAgentRaw $caseId 'uia_tree' @('uia-tree', '--title', $activeTitle)
        $steps.Add($uia) | Out-Null
        $uiaReadOk = Get-EnvelopeOk $uia.json
    }

    $actionExecuted = $false
    if ($targetVisible) {
        $find = Invoke-WinAgentRaw $caseId 'pycharm_find_probe' @(
            'desktop-hotkey', '--keys', 'CTRL+F',
            '--permission-mode', $PermissionMode,
            '--expected-process-pattern', 'pycharm64\.exe|pycharm\.exe',
            '--expected-title-pattern', 'PyCharm|pycharm_sanity',
            '--stop-on-wrong-context', 'true'
        )
        $steps.Add($find) | Out-Null
        $type = Invoke-WinAgentRaw $caseId 'pycharm_type_probe' @(
            'desktop-type', '--text', 'sanity',
            '--permission-mode', $PermissionMode,
            '--expected-process-pattern', 'pycharm64\.exe|pycharm\.exe',
            '--expected-title-pattern', 'PyCharm|pycharm_sanity',
            '--stop-on-wrong-context', 'true'
        )
        $steps.Add($type) | Out-Null
        $esc = Invoke-WinAgentRaw $caseId 'pycharm_escape_find' @(
            'desktop-hotkey', '--keys', 'ESC',
            '--permission-mode', $PermissionMode,
            '--expected-process-pattern', 'pycharm64\.exe|pycharm\.exe',
            '--expected-title-pattern', 'PyCharm|pycharm_sanity',
            '--stop-on-wrong-context', 'true'
        )
        $steps.Add($esc) | Out-Null
        $actionExecuted = ($find.exit_code -eq 0 -and $type.exit_code -eq 0 -and $esc.exit_code -eq 0)
    }

    $contextText = "$contextText`n$activeTitle`n" + (Get-StepText @($steps.ToArray()))
    $activeProtectionDetected = Test-ActiveProtectionText $contextText
    $credentialRequiredDetected = Test-CredentialRequiredText $contextText
    $launchOk = Get-EnvelopeOk $launch.json
    $finalStopCode = 'OK_DIAGNOSTIC'
    $reason = 'diagnostic completed'
    if ($activeProtectionDetected) {
        $finalStopCode = 'STOP_ACTIVE_PROTECTION_OR_LOGIN_BLOCK'
        $reason = 'active protection detected'
    } elseif ($credentialRequiredDetected) {
        $finalStopCode = 'STOP_CREDENTIAL_REQUIRED'
        $reason = 'credential handoff detected'
    } elseif (-not $launchOk) {
        $finalStopCode = Get-EnvelopeStopCode $launch.json
        if ([string]::IsNullOrWhiteSpace($finalStopCode)) { $finalStopCode = 'APP_LAUNCH_FAILED' }
        $reason = 'PyCharm launch failed'
    } elseif (-not $foregroundAcquired) {
        $finalStopCode = 'FOREGROUND_ACQUIRE_FAILED'
        $reason = 'foreground not acquired'
    } elseif (-not $targetVisible) {
        $finalStopCode = 'EXPECTED_CONTEXT_FAILED'
        $reason = 'PyCharm expected context not confirmed'
    } elseif (-not $uiaReadOk) {
        $finalStopCode = 'UIA_READ_FAILED'
        $reason = 'PyCharm UIA read failed'
    }
    if ($finalStopCode -eq 'OK_DIAGNOSTIC') {
        $failureAttribution = 'NO_FAILURE'
        $attrPath = ''
    } else {
        $attr = Invoke-FailureAttribution $caseId $finalStopCode $reason $contextText 'app'
        $steps.Add($attr.step) | Out-Null
        $failureAttribution = $attr.value
        $attrPath = $attr.path
    }
    $evidence = @($activeJson, (Join-Path $RawRoot "$caseId\uia_tree.stdout.log"), $attrPath) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    New-DiagnosticRecord `
        -CaseId $caseId `
        -Category $category `
        -TargetName $targetName `
        -TargetType 'app' `
        -TargetUrlOrApp $projectPath `
        -Steps @($steps.ToArray()) `
        -ForegroundAcquired $foregroundAcquired `
        -ExpectedProcessOk $expectedProcessOk `
        -ExpectedTitleOk $expectedTitleOk `
        -UiaReadOk $uiaReadOk `
        -OcrReadOk $false `
        -ScreenObserveOk $foregroundAcquired `
        -BrowserSurfaceOk $false `
        -TargetVisible $targetVisible `
        -TargetCandidateCount $(if ($targetVisible) { 1 } else { 0 }) `
        -TargetUnique $targetVisible `
        -ScrollRegionFound $false `
        -ScrollProgressDetected $false `
        -ActionAttempted $true `
        -ActionExecuted $actionExecuted `
        -ActiveProtectionDetected $activeProtectionDetected `
        -CredentialRequiredDetected $credentialRequiredDetected `
        -FinalStopCode $finalStopCode `
        -FailureAttribution $failureAttribution `
        -EvidencePaths @($evidence)
}

$records = New-Object System.Collections.Generic.List[object]
$records.Add((Invoke-PyCharmDiagnostic)) | Out-Null
$records.Add((Invoke-WebDiagnostic 'dyn_c_qq_mail_diagnostic' 'C.QQMail' 'QQ Mail diagnostic' 'https://mail.qq.com/' 'QQ Mail|mail.qq.com|Inbox|Compose|Login' 'QQ|mail\.qq|Chrome|Edge' 'Compose')) | Out-Null
$records.Add((Invoke-WebDiagnostic 'dyn_d_ordinary_web_diagnostic' 'D.OrdinaryWeb' 'Example Domain ordinary web diagnostic' 'https://example.com/' 'Example Domain|This domain is for use in illustrative examples' 'Example Domain|Chrome|Edge' 'domain')) | Out-Null
$records.Add((Invoke-WebDiagnostic 'dyn_e_leetcode_oj_diagnostic' 'E.LeetCodeOJ' 'LeetCode OJ diagnostic' 'https://leetcode.com/problemset/' 'LeetCode|Problems|Problemset|Sign in|Explore' 'LeetCode|Chrome|Edge' 'Two Sum')) | Out-Null
$records.Add((Invoke-WebDiagnostic 'dyn_f_social_search_diagnostic' 'F.SocialSearch' 'YouTube public search diagnostic' 'https://www.youtube.com/results?search_query=OpenAI' 'YouTube|OpenAI|Search' 'YouTube|Chrome|Edge' 'OpenAI')) | Out-Null

$matrix = [pscustomobject]@{
    schema_version = 'v6.1.5.dynamic_diagnostics.raw'
    generated_at = (Get-Date).ToString('o')
    runner_status = 'RAW_COMPLETED_UNVERIFIED'
    runner_self_certified_pass = $false
    developer_full_access = $true
    cdp_check_status = 'UNAVAILABLE_REMOTE_DEBUGGING_NOT_USED'
    cdp_check_note = 'DesktopVisual human/browser surface diagnostics used instead of CDP.'
    diagnostic_records = @($records.ToArray())
}
$matrixPath = Join-Path $RawRoot 'dynamic_diagnostics_raw_matrix.json'
$publicMatrixPath = Join-Path $ArtifactRoot 'dynamic_diagnostics_matrix.json'
$matrix | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $matrixPath -Encoding UTF8
$matrix | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $publicMatrixPath -Encoding UTF8

Write-Host "v6.1.5 dynamic diagnostics runner completed raw evidence: $matrixPath"
exit 0
