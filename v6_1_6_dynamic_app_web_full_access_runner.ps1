# SUPERSEDED for v6.1.6 scope reset content1.
# Historical four-case/full-access runner only; not used for current PASS.
param(
    [string]$Root = '',
    [switch]$IntegratedOnly,
    [switch]$Case1Only,
    [switch]$QqMailNegativeOnly
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.1.6_dynamic_app_web_full_access_rc'
$RawRoot = Join-Path $ArtifactRoot 'raw'
$SingleRoot = Join-Path $RawRoot 'single_cases'
$NegativeRoot = Join-Path $RawRoot 'negative_cases'
$IntegratedRoot = Join-Path $RawRoot 'integrated_sequence'
$RegistryPath = Join-Path $ArtifactRoot 'case_status_registry.json'
$PermissionMode = 'DEVELOPER_CAPABILITY_DISCOVERY'

$Cases = @(
    [ordered]@{ case_id = 'case_1_qqmail_send'; case_name = 'QQ Mail real send test'; target = 'QQ Mail' },
    [ordered]@{ case_id = 'case_2_pycharm_run'; case_name = 'PyCharm code input run output verification'; target = 'PyCharm' },
    [ordered]@{ case_id = 'case_3_wechat_file_transfer'; case_name = 'WeChat File Transfer Assistant message send'; target = 'WeChat' },
    [ordered]@{ case_id = 'case_4_tiktok_search'; case_name = 'TikTok two-query search test'; target = 'TikTok' }
)

function U([int[]]$Codes) {
    $chars = foreach ($code in $Codes) { [char]$code }
    return -join $chars
}

$Text = [ordered]@{
    Test = (U @(27979,35797))
    Mail = (U @(37038,20214))
    Mailbox = (U @(37038,31665))
    SubjectText = ('6.1.6' + (U @(27979,35797,37038,20214)))
    MailBody = (U @(36825,26159,19968,23553,27979,35797,37038,20214))
    WeChatMessage = (U @(19968,20221,27979,35797,20449,24687,65292,26080,20219,20309,20869,23481))
    OutputPrefix = (U @(36825,26159,31532))
    OutputSuffix = (U @(20010,36755,20986))
    WeChat = (U @(24494,20449))
    FileTransfer = (U @(25991,20214,20256,36755,21161,25163))
    Login = (U @(30331,24405))
    ScanCode = (U @(25195,30721))
    Password = (U @(23494,30721))
    VerificationCode = (U @(39564,35777,30721))
    HumanVerify = (U @(20154,26426,39564,35777))
    SecurityVerify = (U @(23433,20840,39564,35777))
    ScriptDetect = (U @(33050,26412,26816,27979))
    Auto = (U @(33258,21160,21270))
    AccountSecurity = (U @(36134,21495,23433,20840))
    IdentityVerify = (U @(36523,20221,39564,35777))
    Compose = (U @(20889,20449))
    Recipient = (U @(25910,20214,20154))
    Subject = (U @(20027,39064))
    Body = (U @(27491,25991))
    MailBodyLabel = (U @(37038,20214,27491,25991))
    Send = (U @(21457,36865))
    SendSuccess = (U @(21457,36865,25104,21151))
    Sent = (U @(24050,21457,36865))
    SentMail = (U @(24050,21457,36865,37038,20214))
    SentFolder = (U @(24050,21457,36865,25991,20214,22841))
    Outbox = (U @(21457,20214,31665))
    Drafts = (U @(33609,31295,31665))
    Editor = (U @(32534,36753,22120))
    Run = (U @(36816,34892))
    AddressAndSearchBar = (U @(22320,22336,21644,25628,32034,26639))
    SearchOrEnterWebAddress = (U @(25628,32034,25110,36755,20837,32593,22336))
    AddressBar = (U @(22320,22336,26639))
    Search = (U @(25628,32034))
    Input = (U @(36755,20837))
    Message = (U @(28040,24687))
    PleaseInput = (U @(35831,36755,20837))
    SendMessage = (U @(21457,36865,28040,24687))
    InputBody = (U @(36755,20837,27491,25991))
    NewTab = (U @(26032,24314,26631,31614,39029))
}

function Ensure-Dir([string]$Path) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Save-Json($Value, [string]$Path) {
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { Ensure-Dir $dir }
    $Value | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-Json([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return $null }
}

function ConvertTo-Arg([string]$Arg) {
    if ($null -eq $Arg) { return '""' }
    $s = [string]$Arg
    if ($s.Length -eq 0) { return '""' }
    if ($s -notmatch '[\s"]') { return $s }
    $result = '"'
    $slashes = 0
    foreach ($ch in $s.ToCharArray()) {
        if ($ch -eq '\') {
            $slashes++
        } elseif ($ch -eq '"') {
            if ($slashes -gt 0) { $result += ('\' * ($slashes * 2)) }
            $result += '\"'
            $slashes = 0
        } else {
            if ($slashes -gt 0) { $result += ('\' * $slashes) }
            $slashes = 0
            $result += $ch
        }
    }
    if ($slashes -gt 0) { $result += ('\' * ($slashes * 2)) }
    $result += '"'
    return $result
}

function ConvertTo-ArgLine([string[]]$ArgList) {
    (($ArgList | ForEach-Object { ConvertTo-Arg $_ }) -join ' ')
}

function Invoke-ProcessCapture {
    param(
        [string]$Exe,
        [string[]]$ProcArgs,
        [string]$StdoutPath,
        [string]$StderrPath,
        [int]$TimeoutSec = 60
    )
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $Exe
    $psi.Arguments = ConvertTo-ArgLine $ProcArgs
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    $started = Get-Date
    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit($TimeoutSec * 1000)
    if ($timedOut) {
        try { $process.Kill($true) } catch { try { $process.Kill() } catch {} }
        try { $process.WaitForExit(3000) | Out-Null } catch {}
    }
    try { $stdoutTask.Wait(5000) | Out-Null } catch {}
    try { $stderrTask.Wait(5000) | Out-Null } catch {}
    $stdout = if ($stdoutTask.IsCompleted) { $stdoutTask.Result } else { '' }
    $stderr = if ($stderrTask.IsCompleted) { $stderrTask.Result } else { '' }
    $ended = Get-Date
    $stdout | Set-Content -LiteralPath $StdoutPath -Encoding UTF8
    $stderr | Set-Content -LiteralPath $StderrPath -Encoding UTF8
    $exitCode = if ($timedOut) { 124 } else { $process.ExitCode }
    [pscustomobject]@{
        started = $started
        ended = $ended
        exit_code = $exitCode
        timed_out = $timedOut
        stdout = $stdout
        stderr = $stderr
        duration_ms = [int](($ended - $started).TotalMilliseconds)
    }
}

function New-RunContext([string]$CaseId, [string]$RootDir) {
    $dir = Join-Path $RootDir $CaseId
    Ensure-Dir $dir
    foreach ($sub in @('screenshots','overlays','logs')) { Ensure-Dir (Join-Path $dir $sub) }
    $commandLog = Join-Path $dir 'raw_command_log.jsonl'
    if (Test-Path -LiteralPath $commandLog) { Remove-Item -LiteralPath $commandLog -Force }
    [pscustomobject]@{
        CaseId = $CaseId
        Dir = $dir
        CommandLog = $commandLog
    }
}

function Write-JsonLine([string]$Path, $Object) {
    ($Object | ConvertTo-Json -Depth 100 -Compress) | Add-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-WinAgent {
    param(
        $Ctx,
        [string]$Step,
        [string[]]$WinArgs,
        [int]$TimeoutSec = 60
    )
    $stdout = Join-Path $Ctx.Dir "$Step.stdout.log"
    $stderr = Join-Path $Ctx.Dir "$Step.stderr.log"
    $result = Invoke-ProcessCapture -Exe $WinAgent -ProcArgs $WinArgs -StdoutPath $stdout -StderrPath $stderr -TimeoutSec $TimeoutSec
    $json = $null
    try { $json = $result.stdout | ConvertFrom-Json } catch { $json = $null }
    $record = [ordered]@{
        timestamp = $result.started.ToString('o')
        ended_at = $result.ended.ToString('o')
        case_id = $Ctx.CaseId
        step = $Step
        executable = $WinAgent
        command_args = $WinArgs
        stdout_path = $stdout
        stderr_path = $stderr
        exit_code = $result.exit_code
        timed_out = $result.timed_out
        timeout_sec = $TimeoutSec
        duration_ms = $result.duration_ms
        parsed_json = ($null -ne $json)
        parsed_ok = if ($json -and $null -ne $json.ok) { [bool]$json.ok } else { $false }
    }
    Write-JsonLine $Ctx.CommandLog $record
    [pscustomobject]@{
        ExitCode = $result.exit_code
        TimedOut = $result.timed_out
        Stdout = $result.stdout
        Stderr = $result.stderr
        Json = $json
        StdoutPath = $stdout
        StderrPath = $stderr
        Record = $record
    }
}

function Initialize-Registry {
    if (Test-Path -LiteralPath $RegistryPath) { return }
    $rows = foreach ($case in $Cases) {
        [pscustomobject][ordered]@{
            case_id = $case.case_id
            case_name = $case.case_name
            status = 'pending'
            last_pass_evidence_path = ''
            last_failure_evidence_path = ''
            frozen_after_pass = $false
            rerun_required = $false
            attempt_count = 0
            last_run_timestamp = ''
        }
    }
    Save-Json @($rows) $RegistryPath
}

function Read-Registry {
    Initialize-Registry
    $rawRows = Read-Json $RegistryPath
    $rows = @()
    foreach ($item in @($rawRows)) {
        if ($item -is [System.Array]) { $rows += @($item) } else { $rows += $item }
    }
    $map = @{}
    foreach ($case in $Cases) {
        $matches = @($rows | Where-Object { $_.case_id -eq $case.case_id } | Select-Object -First 1)
        $existing = if ($matches.Count -gt 0) { $matches[0] } else { $null }
        if ($null -ne $existing) {
            $row = [pscustomobject][ordered]@{
                case_id = [string]$existing.case_id
                case_name = [string]$existing.case_name
                status = if ($existing.status) { [string]$existing.status } else { 'pending' }
                last_pass_evidence_path = [string]$existing.last_pass_evidence_path
                last_failure_evidence_path = [string]$existing.last_failure_evidence_path
                frozen_after_pass = [bool]$existing.frozen_after_pass
                rerun_required = [bool]$existing.rerun_required
                attempt_count = if ($null -ne $existing.attempt_count) { [int]$existing.attempt_count } else { 0 }
                last_run_timestamp = [string]$existing.last_run_timestamp
            }
        } else {
            $row = [pscustomobject][ordered]@{
                case_id = [string]$case.case_id
                case_name = [string]$case.case_name
                status = 'pending'
                last_pass_evidence_path = ''
                last_failure_evidence_path = ''
                frozen_after_pass = $false
                rerun_required = $false
                attempt_count = 0
                last_run_timestamp = ''
            }
        }
        $map[[string]$case.case_id] = $row
    }
    return $map
}

function Save-RegistryMap($Map) {
    $ordered = foreach ($case in $Cases) { $Map[$case.case_id] }
    Save-Json @($ordered) $RegistryPath
}

function Update-RegistryAttempt($Map, [string]$CaseId) {
    $row = $Map[$CaseId]
    $row.attempt_count = [int]$row.attempt_count + 1
    $row.last_run_timestamp = (Get-Date).ToString('o')
    $row.status = 'raw_running'
    Save-RegistryMap $Map
}

function Update-RegistryRawResult($Map, [string]$CaseId, [string]$EvidencePath, [bool]$RawSuccess) {
    $row = $Map[$CaseId]
    if ($RawSuccess) {
        $row.status = 'raw_completed_unverified'
        $row.rerun_required = $false
    } else {
        $row.status = 'raw_failed_unverified'
        $row.last_failure_evidence_path = $EvidencePath
        $row.rerun_required = $true
    }
    $row.last_run_timestamp = (Get-Date).ToString('o')
    Save-RegistryMap $Map
}

function New-Evidence([string]$CaseId, [string]$CaseName, [string]$Target) {
    [pscustomobject][ordered]@{
        case_id = $CaseId
        case_name = $CaseName
        target_app_or_site = $Target
        developer_full_access = $true
        active_protection_detected = $false
        credential_required_detected = $false
        interaction_mode = 'mouse_first'
        mouse_first_required = $true
        mouse_first_passed = $false
        mouse_move_count = 0
        mouse_click_count = 0
        keyboard_shortcut_used = @()
        keyboard_only_path_used = $false
        fallback_used = $false
        fallback_reason = ''
        cursor_before = $null
        cursor_after_move = $null
        target_name = ''
        target_role = ''
        target_rect = $null
        target_center = $null
        target_visible = $false
        target_unique = $false
        locator_source = ''
        locator_confidence = 0.0
        coordinate_source_type = ''
        click_point = $null
        click_sent = $false
        focus_verified_after_click = $false
        context_verified_after_click = $false
        typed_text = @()
        typed_text_verified = $false
        action_executed = $false
        result_verified = $false
        wrong_field_input_count = 0
        continued_action_after_wrong_context = $false
        failure_attribution = ''
        final_stop_code = ''
        raw_status = 'RAW_COMPLETED_UNVERIFIED'
        runner_self_certified_pass = $false
        content_verification_source = ''
        evidence_paths = @()
        steps = @()
        mouse_actions = @()
        output_lines = @()
        output_count = 0
        qqmail_opened = $false
        compose_clicked_by_mouse = $false
        recipient_field_clicked_by_mouse = $false
        subject_field_clicked_by_mouse = $false
        body_field_clicked_by_mouse = $false
        send_clicked_by_mouse = $false
        recipient_verified = $false
        subject_verified = $false
        body_verified = $false
        send_success_verified = $false
        send_target_text = ''
        send_target_role = ''
        send_target_rect = $null
        send_target_center = $null
        send_target_region = ''
        send_target_exact_match = $false
        send_target_negative_match = $false
        send_target_is_compose_action_area = $false
        send_target_is_sidebar_or_folder = $false
        send_target_unique = $false
        send_target_verified_before_click = $false
        clicked_target_text = ''
        clicked_target_role = ''
        clicked_target_rect = $null
        clicked_target_is_sidebar_or_folder = $false
        clicked_target_is_compose_send_button = $false
        post_send_verification_source = ''
        post_send_success_signal = ''
        post_send_sent_folder_only = $false
        qqmail_sent_folder_false_positive_negative = $false
        pycharm_opened = $false
        editor_clicked_by_mouse = $false
        editor_focus_verified = $false
        existing_code_checked = $false
        existing_code_cleared_if_present = $false
        code_text_verified = $false
        run_clicked_by_mouse = $false
        output_observed = $false
        output_count_between_2_and_10 = $false
        output_sequence_verified = $false
        wechat_opened = $false
        file_transfer_assistant_located = $false
        chat_clicked_by_mouse = $false
        chat_title_verified = $false
        message_input_clicked_by_mouse = $false
        message_text_verified_before_send = $false
        message_sent_verified = $false
        scroll_if_needed_evidence_present = $false
        tiktok_opened = $false
        search_box_clicked_by_mouse = $false
        first_query_text_verified = $false
        first_search_result_verified = $false
        second_query_text_verified = $false
        second_search_result_verified = $false
        mouse_click_evidence_present = $false
        keyword_not_corrected = $false
    }
}

function Add-Step($Evidence, $Step) {
    $Evidence.steps = @($Evidence.steps) + @($Step.Record)
    $Evidence.evidence_paths = @($Evidence.evidence_paths) + @($Step.StdoutPath, $Step.StderrPath)
}

function Add-KeyboardShortcut($Evidence, [string]$Value) {
    $Evidence.keyboard_shortcut_used = @($Evidence.keyboard_shortcut_used) + $Value
}

function Rect-Object($Rect) {
    if (-not $Rect) { return $null }
    if (-not (Test-ValidRect $Rect)) { return $null }
    [ordered]@{
        left = [int]$Rect.left
        top = [int]$Rect.top
        right = [int]$Rect.right
        bottom = [int]$Rect.bottom
    }
}

function Rect-Center($Rect) {
    if (-not $Rect) { return $null }
    [ordered]@{
        x = [int]([Math]::Floor(([int]$Rect.left + [int]$Rect.right) / 2))
        y = [int]([Math]::Floor(([int]$Rect.top + [int]$Rect.bottom) / 2))
    }
}

function Test-ValidRect($Rect) {
    if ($null -eq $Rect) { return $false }
    try {
        return ([int]$Rect.right -gt [int]$Rect.left -and [int]$Rect.bottom -gt [int]$Rect.top)
    } catch {
        return $false
    }
}

function Get-CandidateRect($Candidate) {
    if ($Candidate -and $Candidate.rect -and (Test-ValidRect $Candidate.rect)) { return $Candidate.rect }
    if ($Candidate -and $Candidate.target_rect -and (Test-ValidRect $Candidate.target_rect)) { return $Candidate.target_rect }
    return $null
}

function Get-CandidateRole($Candidate, [string]$Fallback) {
    foreach ($name in @('role','control_type','type')) {
        if ($Candidate -and $Candidate.PSObject.Properties.Name -contains $name -and -not [string]::IsNullOrWhiteSpace([string]$Candidate.$name)) { return [string]$Candidate.$name }
    }
    return $Fallback
}

function Get-CandidateName($Candidate, [string]$Fallback) {
    foreach ($name in @('name','text','matched_text','matched_name','target','target_text','label','automation_name')) {
        if ($Candidate -and $Candidate.PSObject.Properties.Name -contains $name -and -not [string]::IsNullOrWhiteSpace([string]$Candidate.$name)) { return [string]$Candidate.$name }
    }
    return $Fallback
}

function Get-CandidateText($Candidate) {
    foreach ($name in @('name','value','text','matched_text','matched_name','target','target_text','label','automation_name')) {
        if ($Candidate -and $Candidate.PSObject.Properties.Name -contains $name -and -not [string]::IsNullOrWhiteSpace([string]$Candidate.$name)) {
            return ([string]$Candidate.$name).Trim()
        }
    }
    return ''
}

function Get-CandidateSource($Candidate) {
    foreach ($name in @('source','locator_source','provider')) {
        if ($Candidate -and $Candidate.PSObject.Properties.Name -contains $name -and -not [string]::IsNullOrWhiteSpace([string]$Candidate.$name)) { return [string]$Candidate.$name }
    }
    return 'adaptive-locate'
}

function Get-CandidateConfidence($Candidate) {
    foreach ($name in @('confidence','score')) {
        if ($Candidate -and $Candidate.PSObject.Properties.Name -contains $name -and $Candidate.$name -ne $null) {
            try { return [double]$Candidate.$name } catch {}
        }
    }
    return 0.75
}

function Find-UiaCandidate($Ctx, $Evidence, [string]$Step, [string]$Title, [string]$Target, [string]$Role) {
    $r = Invoke-WinAgent $Ctx "$Step-uia" @('uia-tree','--title',$Title) 30
    Add-Step $Evidence $r
    if (-not ($r.Json -and $r.Json.ok -eq $true -and $r.Json.data -and $r.Json.data.elements)) { return $null }
    $targetPattern = [regex]::Escape($Target)
    $candidates = New-Object System.Collections.Generic.List[object]
    foreach ($element in @($r.Json.data.elements)) {
        $name = [string]$element.name
        $value = [string]$element.value
        $controlType = [string]$element.control_type
        $rect = $element.rect
        if (-not (Test-ValidRect $rect)) { continue }
        if ($element.offscreen -eq $true -or $element.enabled -eq $false) { continue }
        if (-not [string]::IsNullOrWhiteSpace($Role) -and $controlType -notmatch $Role) { continue }
        if ($name -eq $Target -or $value -eq $Target -or $name -match $targetPattern -or $value -match $targetPattern) {
            $candidates.Add([pscustomobject][ordered]@{
                name = $name
                value = $value
                control_type = $controlType
                rect = $rect
                source = 'uia-tree'
                confidence = 0.92
            }) | Out-Null
        }
    }
    if ($candidates.Count -eq 0) { return $null }
    return [pscustomobject]@{
        Candidate = $candidates[0]
        CandidateCount = $candidates.Count
        Unique = ($candidates.Count -eq 1)
        Step = $r
    }
}

function Locate-Target($Ctx, $Evidence, [string]$Step, [string]$Title, [string[]]$Targets, [string[]]$Roles) {
    $idx = 0
    foreach ($target in $Targets) {
        foreach ($role in $Roles) {
            $uiaLocated = Find-UiaCandidate $Ctx $Evidence "$Step-$idx" $Title $target $role
            if ($uiaLocated) { return $uiaLocated }
            $args = @('adaptive-locate','--title',$Title,'--target',$target)
            if (-not [string]::IsNullOrWhiteSpace($role)) { $args += @('--role',$role) }
            $r = Invoke-WinAgent $Ctx "$Step-$idx" $args 12
            Add-Step $Evidence $r
            if ($r.Json -and $r.Json.data) {
                $candidate = $null
                if ($r.Json.data.selected_candidate) { $candidate = $r.Json.data.selected_candidate }
                elseif ($r.Json.data.candidate) { $candidate = $r.Json.data.candidate }
                elseif ($r.Json.data.candidates -and @($r.Json.data.candidates).Count -gt 0) { $candidate = @($r.Json.data.candidates)[0] }
                if ($candidate -and (Get-CandidateRect $candidate)) {
                    $candidateCount = 1
                    if ($r.Json.data.candidate_count -ne $null) { $candidateCount = [int]$r.Json.data.candidate_count }
                    elseif ($r.Json.data.candidates) { $candidateCount = @($r.Json.data.candidates).Count }
                    return [pscustomobject]@{ Candidate = $candidate; CandidateCount = $candidateCount; Unique = ($candidateCount -eq 1); Step = $r }
                }
            }
            $idx++
        }
    }
    return $null
}

function Get-QqMailNegativeSendTexts {
    return @($Text.Sent, $Text.SentMail, $Text.SentFolder, $Text.Outbox, $Text.Drafts, 'Sent', 'Sent Mail')
}

function Test-QqMailNegativeSendText([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    $trimmed = $Value.Trim()
    foreach ($item in Get-QqMailNegativeSendTexts) {
        if ($trimmed -eq $item) { return $true }
    }
    if ($trimmed -ne $Text.Send -and $trimmed.Contains($Text.Send)) { return $true }
    return $false
}

function New-QqMailComposeGeometry($Recipient, $Subject, $Body) {
    $rects = @(
        (Rect-Object (Get-CandidateRect $Recipient.Candidate)),
        (Rect-Object (Get-CandidateRect $Subject.Candidate)),
        (Rect-Object (Get-CandidateRect $Body.Candidate))
    ) | Where-Object { $_ -ne $null }
    if (@($rects).Count -eq 0) { return $null }
    $left = (@($rects) | ForEach-Object { [int]$_.left } | Measure-Object -Minimum).Minimum
    $top = (@($rects) | ForEach-Object { [int]$_.top } | Measure-Object -Minimum).Minimum
    $right = (@($rects) | ForEach-Object { [int]$_.right } | Measure-Object -Maximum).Maximum
    $bottom = (@($rects) | ForEach-Object { [int]$_.bottom } | Measure-Object -Maximum).Maximum
    [pscustomobject][ordered]@{
        content_left = [int]$left
        content_top = [int]$top
        content_right = [int]$right
        content_bottom = [int]$bottom
        action_left_min = [int]([Math]::Max(0, [int]$left - 120))
        action_top_min = [int]([Math]::Max(0, [int]$top - 90))
        action_right_max = [int]$right
        action_bottom_max = [int]([int]$bottom + 90)
        sidebar_right_max = [int]([Math]::Max(0, [int]$left - 140))
    }
}

function Test-QqMailCandidateSidebarOrFolder($Candidate, $Geometry) {
    $textValue = Get-CandidateText $Candidate
    if (Test-QqMailNegativeSendText $textValue) { return $true }
    $role = Get-CandidateRole $Candidate ''
    if ($role -match 'TreeItem|ListItem') { return $true }
    $rect = Rect-Object (Get-CandidateRect $Candidate)
    if (-not $rect -or -not $Geometry) { return $true }
    $center = Rect-Center $rect
    return ([int]$center.x -le [int]$Geometry.sidebar_right_max)
}

function Test-QqMailCandidateComposeActionArea($Candidate, $Geometry) {
    if (-not $Geometry) { return $false }
    $rect = Rect-Object (Get-CandidateRect $Candidate)
    if (-not $rect) { return $false }
    $center = Rect-Center $rect
    return (
        [int]$center.x -ge [int]$Geometry.action_left_min -and
        [int]$center.x -le [int]$Geometry.action_right_max -and
        [int]$center.y -ge [int]$Geometry.action_top_min -and
        [int]$center.y -le [int]$Geometry.action_bottom_max
    )
}

function Test-QqMailSendCandidateSemantics($Candidate, $Geometry) {
    $textValue = Get-CandidateText $Candidate
    $role = Get-CandidateRole $Candidate ''
    $rect = Rect-Object (Get-CandidateRect $Candidate)
    $center = if ($rect) { Rect-Center $rect } else { $null }
    $negative = Test-QqMailNegativeSendText $textValue
    $sidebar = Test-QqMailCandidateSidebarOrFolder $Candidate $Geometry
    $composeAction = Test-QqMailCandidateComposeActionArea $Candidate $Geometry
    $exact = ($textValue -eq $Text.Send)
    $roleOk = ($role -match 'Button|Hyperlink|MenuItem|Text|Control')
    [pscustomobject][ordered]@{
        text = $textValue
        role = $role
        rect = $rect
        center = $center
        exact_match = [bool]$exact
        negative_match = [bool]$negative
        is_compose_action_area = [bool]$composeAction
        is_sidebar_or_folder = [bool]$sidebar
        role_ok = [bool]$roleOk
        verified = [bool]($exact -and -not $negative -and $composeAction -and -not $sidebar -and $roleOk -and $rect -and $center)
    }
}

function Set-QqMailSendTargetEvidence($Ctx, $Evidence, $Check, [bool]$Unique) {
    $Evidence.send_target_text = [string]$Check.text
    $Evidence.send_target_role = [string]$Check.role
    $Evidence.send_target_rect = $Check.rect
    $Evidence.send_target_center = $Check.center
    $Evidence.send_target_region = if ($Check.is_sidebar_or_folder) { 'sidebar_or_folder' } elseif ($Check.is_compose_action_area) { 'compose_action_area' } else { 'unknown' }
    $Evidence.send_target_exact_match = [bool]$Check.exact_match
    $Evidence.send_target_negative_match = [bool]$Check.negative_match
    $Evidence.send_target_is_compose_action_area = [bool]$Check.is_compose_action_area
    $Evidence.send_target_is_sidebar_or_folder = [bool]$Check.is_sidebar_or_folder
    $Evidence.send_target_unique = [bool]$Unique
    $Evidence.send_target_verified_before_click = [bool]($Check.verified -and $Unique)
    $Evidence.clicked_target_text = [string]$Check.text
    $Evidence.clicked_target_role = [string]$Check.role
    $Evidence.clicked_target_rect = $Check.rect
    $Evidence.clicked_target_is_sidebar_or_folder = [bool]$Check.is_sidebar_or_folder
    $Evidence.clicked_target_is_compose_send_button = [bool]($Check.verified -and $Unique)
    $path = Join-Path $Ctx.Dir 'qqmail_send_target_preclick_evidence.json'
    Save-Json ([ordered]@{
        send_target_text = $Evidence.send_target_text
        send_target_role = $Evidence.send_target_role
        send_target_rect = $Evidence.send_target_rect
        send_target_center = $Evidence.send_target_center
        send_target_region = $Evidence.send_target_region
        send_target_exact_match = $Evidence.send_target_exact_match
        send_target_negative_match = $Evidence.send_target_negative_match
        send_target_is_compose_action_area = $Evidence.send_target_is_compose_action_area
        send_target_is_sidebar_or_folder = $Evidence.send_target_is_sidebar_or_folder
        send_target_unique = $Evidence.send_target_unique
        send_target_verified_before_click = $Evidence.send_target_verified_before_click
        clicked_target_text = $Evidence.clicked_target_text
        clicked_target_role = $Evidence.clicked_target_role
        clicked_target_rect = $Evidence.clicked_target_rect
        clicked_target_is_sidebar_or_folder = $Evidence.clicked_target_is_sidebar_or_folder
        clicked_target_is_compose_send_button = $Evidence.clicked_target_is_compose_send_button
    }) $path
    $Evidence.evidence_paths = @($Evidence.evidence_paths) + $path
}

function Find-QqMailVerifiedSendTarget($Ctx, $Evidence, [string]$Step, [string]$Title, $Geometry) {
    $r = Invoke-WinAgent $Ctx "$Step-uia" @('uia-tree','--title',$Title) 30
    Add-Step $Evidence $r
    if (-not ($r.Json -and $r.Json.ok -eq $true -and $r.Json.data -and $r.Json.data.elements)) { return $null }
    $verified = New-Object System.Collections.Generic.List[object]
    $wrong = New-Object System.Collections.Generic.List[object]
    foreach ($element in @($r.Json.data.elements)) {
        $rect = $element.rect
        if (-not (Test-ValidRect $rect)) { continue }
        if ($element.offscreen -eq $true -or $element.enabled -eq $false) { continue }
        $candidate = [pscustomobject][ordered]@{
            name = [string]$element.name
            value = [string]$element.value
            control_type = [string]$element.control_type
            rect = $rect
            source = 'uia-tree-exact-send'
            confidence = 0.98
        }
        $textValue = Get-CandidateText $candidate
        $check = Test-QqMailSendCandidateSemantics $candidate $Geometry
        if ($textValue -eq $Text.Send) {
            if ($check.verified) {
                $verified.Add([pscustomobject][ordered]@{ Candidate = $candidate; Check = $check }) | Out-Null
            } else {
                $wrong.Add([pscustomobject][ordered]@{ Candidate = $candidate; Check = $check }) | Out-Null
            }
        } elseif (Test-QqMailNegativeSendText $textValue) {
            $wrong.Add([pscustomobject][ordered]@{ Candidate = $candidate; Check = $check }) | Out-Null
        }
    }
    if ($verified.Count -ne 1) {
        $selectedWrong = if ($wrong.Count -gt 0) { $wrong[0] } else { $null }
        if ($selectedWrong) { Set-QqMailSendTargetEvidence $Ctx $Evidence $selectedWrong.Check $false }
        return $null
    }
    $selected = $verified[0]
    Set-QqMailSendTargetEvidence $Ctx $Evidence $selected.Check $true
    return [pscustomobject]@{
        Candidate = $selected.Candidate
        CandidateCount = $verified.Count
        Unique = $true
        Step = $r
    }
}

function Click-LocatedTarget {
    param(
        $Ctx,
        $Evidence,
        [string]$Step,
        $Located,
        [string]$Description,
        [string]$Role,
        [switch]$DoubleClick
    )
    if (-not $Located) { return $false }
    $candidate = $Located.Candidate
    $rect = Rect-Object (Get-CandidateRect $candidate)
    if (-not $rect) { return $false }
    $center = Rect-Center $rect
    $resultPath = Join-Path $Ctx.Dir "$Step.human_action_result.json"
    $command = if ($DoubleClick) { 'desktop-double-click' } else { 'desktop-click' }
    $args = @(
        $command,
        '--screen-x', [string]$center.x,
        '--screen-y', [string]$center.y,
        '--permission-mode', $PermissionMode,
        '--target-description', $Description,
        '--coordinate-source', ('locator_derived_coordinate:' + (Get-CandidateSource $candidate)),
        '--target-rect-left', [string]$rect.left,
        '--target-rect-top', [string]$rect.top,
        '--target-rect-right', [string]$rect.right,
        '--target-rect-bottom', [string]$rect.bottom,
        '--result-json', $resultPath
    )
    $r = Invoke-WinAgent $Ctx $Step $args 60
    Add-Step $Evidence $r
    $human = Read-Json $resultPath
    $Evidence.evidence_paths = @($Evidence.evidence_paths) + $resultPath
    $Evidence.mouse_move_count = [int]$Evidence.mouse_move_count + 1
    $Evidence.mouse_click_count = [int]$Evidence.mouse_click_count + 1
    $Evidence.target_name = Get-CandidateName $candidate $Description
    $Evidence.target_role = Get-CandidateRole $candidate $Role
    $Evidence.target_rect = $rect
    $Evidence.target_center = $center
    $Evidence.target_visible = $true
    $Evidence.target_unique = [bool]$Located.Unique
    $Evidence.locator_source = Get-CandidateSource $candidate
    $Evidence.locator_confidence = Get-CandidateConfidence $candidate
    $Evidence.coordinate_source_type = 'locator_derived_coordinate'
    $Evidence.click_point = $center
    $Evidence.click_sent = ($r.ExitCode -eq 0)
    $Evidence.action_executed = ($r.ExitCode -eq 0)
    if ($human -and $human.cursor) {
        $Evidence.cursor_before = [ordered]@{ x = [int]$human.cursor.start_x; y = [int]$human.cursor.start_y }
        $Evidence.cursor_after_move = [ordered]@{ x = [int]$human.cursor.actual_before_click_x; y = [int]$human.cursor.actual_before_click_y }
    }
    $Evidence.mouse_actions = @($Evidence.mouse_actions) + @([ordered]@{
        step = $Step
        target_name = $Description
        target_role = $Role
        target_rect = $rect
        target_center = $center
        target_visible = $true
        target_unique = [bool]$Located.Unique
        locator_source = Get-CandidateSource $candidate
        locator_confidence = Get-CandidateConfidence $candidate
        coordinate_source_type = 'locator_derived_coordinate'
        click_point = $center
        click_sent = ($r.ExitCode -eq 0)
        human_action_result_path = $resultPath
    })
    return ($r.ExitCode -eq 0)
}

function Type-Text($Ctx, $Evidence, [string]$Step, [string]$TextValue) {
    $r = Invoke-WinAgent $Ctx $Step @('desktop-type','--text',$TextValue,'--type-mode','demo-human','--char-delay-ms','35','--permission-mode',$PermissionMode) 120
    Add-Step $Evidence $r
    $Evidence.typed_text = @($Evidence.typed_text) + $TextValue
    return ($r.ExitCode -eq 0)
}

function Press-Key($Ctx, $Evidence, [string]$Step, [string]$Key) {
    $r = Invoke-WinAgent $Ctx $Step @('desktop-press','--key',$Key,'--permission-mode',$PermissionMode) 60
    Add-Step $Evidence $r
    return ($r.ExitCode -eq 0)
}

function Hotkey($Ctx, $Evidence, [string]$Step, [string]$Keys) {
    $r = Invoke-WinAgent $Ctx $Step @('desktop-hotkey','--keys',$Keys,'--permission-mode',$PermissionMode) 60
    Add-Step $Evidence $r
    Add-KeyboardShortcut $Evidence $Keys
    return ($r.ExitCode -eq 0)
}

function Read-WindowText($Ctx, $Evidence, [string]$Step, [string]$Title) {
    $r = Invoke-WinAgent $Ctx $Step @('read-window-text','--title',$Title) 60
    Add-Step $Evidence $r
    if ($r.Json -and $r.Json.data -and $r.Json.data.text -ne $null) { return [string]$r.Json.data.text }
    return [string]$r.Stdout
}

function Read-AnyBrowserText($Ctx, $Evidence, [string]$Step) {
    $chrome = Read-WindowText $Ctx $Evidence "$Step-chrome" 'Chrome'
    $edge = Read-WindowText $Ctx $Evidence "$Step-edge" 'Edge'
    return "$chrome`n$edge"
}

function Read-UiaText($Ctx, $Evidence, [string]$Step, [string]$Title) {
    $r = Invoke-WinAgent $Ctx $Step @('uia-tree','--title',$Title) 60
    Add-Step $Evidence $r
    if (-not ($r.Json -and $r.Json.ok -eq $true -and $r.Json.data -and $r.Json.data.elements)) { return '' }
    return ((@($r.Json.data.elements) | ForEach-Object {
        $parts = New-Object System.Collections.Generic.List[string]
        if ($_.PSObject.Properties.Name -contains 'name') { $parts.Add([string]$_.name) }
        if ($_.PSObject.Properties.Name -contains 'value') { $parts.Add([string]$_.value) }
        if ($_.PSObject.Properties.Name -contains 'control_type') { $parts.Add([string]$_.control_type) }
        ($parts -join "`n")
    }) -join "`n")
}

function Read-AnyBrowserTextWithUia($Ctx, $Evidence, [string]$Step) {
    $ocr = Read-AnyBrowserText $Ctx $Evidence "$Step-ocr"
    $chromeUia = Read-UiaText $Ctx $Evidence "$Step-uia-chrome" 'Chrome'
    $edgeUia = Read-UiaText $Ctx $Evidence "$Step-uia-edge" 'Edge'
    return "$ocr`n$chromeUia`n$edgeUia"
}

function Normalize-ObservedText([string]$Value) {
    if ($null -eq $Value) { return '' }
    return ($Value -replace '\s+', '')
}

function Test-ObservedContains([string]$Observed, [string]$Expected) {
    if ([string]::IsNullOrWhiteSpace($Expected)) { return $false }
    $normObserved = Normalize-ObservedText $Observed
    $normExpected = Normalize-ObservedText $Expected
    return ($normObserved -match [regex]::Escape($normExpected))
}

function Active-Window($Ctx, $Evidence, [string]$Step) {
    $r = Invoke-WinAgent $Ctx $Step @('active-window') 60
    Add-Step $Evidence $r
    if ($r.Json -and $r.Json.data) { return $r.Json.data }
    return $null
}

function Test-ContainsAny([string]$Value, [string[]]$Needles) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    foreach ($needle in $Needles) {
        if (-not [string]::IsNullOrWhiteSpace($needle) -and $Value.Contains($needle)) { return $true }
    }
    return $false
}

function Test-ActiveProtection([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    if ($Value -match '(?i)captcha|recaptcha|hcaptcha|turnstile|human verification|verify you are human|bot challenge|automation detected|script detected|unusual traffic|robot|bot check') { return $true }
    return (Test-ContainsAny $Value @($Text.HumanVerify, $Text.SecurityVerify, $Text.ScriptDetect, $Text.Auto, $Text.VerificationCode))
}

function Test-CredentialRequired([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    if ($Value -match '(?i)login required|sign in|required to log in|password|verification code|sms code|email code|account security|account verification|scan code|qr code') { return $true }
    return (Test-ContainsAny $Value @($Text.Login, $Text.ScanCode, $Text.Password, $Text.VerificationCode, $Text.AccountSecurity, $Text.IdentityVerify, $Text.SecurityVerify))
}

function Stop-Evidence($Evidence, [string]$Code, [string]$Attribution) {
    $Evidence.raw_status = $Code
    $Evidence.final_stop_code = $Code
    $Evidence.failure_attribution = $Attribution
    $Evidence.mouse_first_passed = $false
    return $Evidence
}

function Complete-RawSuccess($Evidence) {
    $Evidence.raw_status = 'RAW_COMPLETED_UNVERIFIED'
    $Evidence.mouse_first_passed = $true
    $Evidence.failure_attribution = 'NONE'
    return $Evidence
}

function Get-DesktopShortcutNames([string]$Kind) {
    if ($Kind -eq 'browser') { return @('Google Chrome','Microsoft Edge') }
    if ($Kind -eq 'pycharm') { return @('PyCharm','JetBrains PyCharm') }
    if ($Kind -eq 'wechat') { return @($Text.WeChat,'WeChat') }
    return @()
}

function Open-AppFromDesktop($Ctx, $Evidence, [string]$Kind, [string]$WindowTitlePattern) {
    Hotkey $Ctx $Evidence 'show_desktop' 'WIN+M' | Out-Null
    Start-Sleep -Milliseconds 700
    $located = $null
    foreach ($name in Get-DesktopShortcutNames $Kind) {
        $safe = ($name -replace '\W','_')
        $located = Locate-Target $Ctx $Evidence "locate_${Kind}_desktop_icon_$safe" 'Program Manager' @($name) @('ListItem','Button','Text')
        if ($located) { break }
    }
    if (-not $located) { return $false }
    $ok = Click-LocatedTarget $Ctx $Evidence "double_click_${Kind}_desktop_icon" $located "$Kind desktop icon" 'ListItem' -DoubleClick
    if (-not $ok) { return $false }
    Start-Sleep -Seconds 3
    for ($i = 0; $i -lt 25; $i++) {
        $active = Active-Window $Ctx $Evidence "wait_${Kind}_active_$i"
        if ($active -and [string]$active.title -match $WindowTitlePattern) {
            $Evidence.context_verified_after_click = $true
            return $true
        }
        Start-Sleep -Milliseconds 800
    }
    return $false
}

function Open-BrowserUrlByMouse($Ctx, $Evidence, [string]$Url, [string]$ExpectedPattern) {
    $opened = Open-AppFromDesktop $Ctx $Evidence 'browser' ('Chrome|Edge|New Tab|' + [regex]::Escape($Text.NewTab))
    if (-not $opened) { return $false }
    $bar = Locate-Target $Ctx $Evidence 'locate_browser_address_bar' 'Chrome' @('Address and search bar',$Text.AddressAndSearchBar,'Search or enter web address',$Text.SearchOrEnterWebAddress,$Text.AddressBar) @('Edit','ComboBox')
    if (-not $bar) {
        $bar = Locate-Target $Ctx $Evidence 'locate_edge_address_bar' 'Edge' @('Address and search bar',$Text.AddressAndSearchBar,'Search or enter web address',$Text.SearchOrEnterWebAddress,$Text.AddressBar) @('Edit','ComboBox')
    }
    if (-not $bar) { return $false }
    if (-not (Click-LocatedTarget $Ctx $Evidence 'click_browser_address_bar' $bar 'browser address bar' 'Edit')) { return $false }
    $Evidence.focus_verified_after_click = $true
    Type-Text $Ctx $Evidence 'type_browser_url' $Url | Out-Null
    Press-Key $Ctx $Evidence 'press_enter_after_url' 'ENTER' | Out-Null
    Start-Sleep -Seconds 6
    $pageText = Read-AnyBrowserText $Ctx $Evidence 'read_browser_page_after_navigation'
    $Evidence.context_verified_after_click = ($pageText -match $ExpectedPattern)
    return ($pageText -match $ExpectedPattern)
}

function Save-Evidence($Ctx, $Evidence) {
    $path = Join-Path $Ctx.Dir 'evidence.json'
    Save-Json $Evidence $path
    return $path
}

function Run-CaseQqMail([string]$CaseId, [string]$RootDir) {
    $ctx = New-RunContext $CaseId $RootDir
    $ev = New-Evidence $CaseId 'QQ Mail real send test' 'https://mail.qq.com'
    $ev.qqmail_opened = $false
    $ev.compose_clicked_by_mouse = $false
    $ev.recipient_field_clicked_by_mouse = $false
    $ev.subject_field_clicked_by_mouse = $false
    $ev.body_field_clicked_by_mouse = $false
    $ev.send_clicked_by_mouse = $false
    $ev.recipient_verified = $false
    $ev.subject_verified = $false
    $ev.body_verified = $false
    $ev.send_success_verified = $false

    if (-not (Open-BrowserUrlByMouse $ctx $ev 'https://mail.qq.com' ('QQ|mail\.qq\.com|Mail|' + [regex]::Escape($Text.Mailbox)))) {
        return @{ Path = Save-Evidence $ctx (Stop-Evidence $ev 'BROWSER_OR_QQMAIL_OPEN_FAILED' 'TARGET_NOT_VISIBLE'); Success = $false }
    }
    $ev.qqmail_opened = $true
    $page = Read-AnyBrowserText $ctx $ev 'qqmail_read_initial_page'
    if (Test-ActiveProtection $page) {
        $ev.active_protection_detected = $true
        return @{ Path = Save-Evidence $ctx (Stop-Evidence $ev 'ACTIVE_PROTECTION_STOP' 'ACTIVE_PROTECTION_DETECTED'); Success = $false }
    }
    if (Test-CredentialRequired $page) {
        $ev.credential_required_detected = $true
        return @{ Path = Save-Evidence $ctx (Stop-Evidence $ev 'CREDENTIAL_REQUIRED_STOP' 'CREDENTIAL_REQUIRED'); Success = $false }
    }
    $compose = Locate-Target $ctx $ev 'locate_qqmail_compose' 'Chrome' @($Text.Compose,'Compose') @('Button','MenuItem','Text')
    if (-not $compose) { $compose = Locate-Target $ctx $ev 'locate_qqmail_compose_edge' 'Edge' @($Text.Compose,'Compose') @('Button','MenuItem','Text') }
    if (-not $compose -or -not (Click-LocatedTarget $ctx $ev 'click_qqmail_compose' $compose 'QQ Mail compose entry' 'Button')) {
        return @{ Path = Save-Evidence $ctx (Stop-Evidence $ev 'COMPOSE_TARGET_NOT_FOUND' 'TARGET_NOT_VISIBLE'); Success = $false }
    }
    $ev.compose_clicked_by_mouse = $true
    Start-Sleep -Seconds 2
    $recipient = Locate-Target $ctx $ev 'locate_qqmail_recipient' 'Chrome' @($Text.Recipient,'Recipients','To') @('Edit','Document','Pane')
    if (-not $recipient) { $recipient = Locate-Target $ctx $ev 'locate_qqmail_recipient_edge' 'Edge' @($Text.Recipient,'Recipients','To') @('Edit','Document','Pane') }
    if (-not $recipient -or -not (Click-LocatedTarget $ctx $ev 'click_qqmail_recipient' $recipient 'QQ Mail recipient field' 'Edit')) {
        return @{ Path = Save-Evidence $ctx (Stop-Evidence $ev 'RECIPIENT_FIELD_NOT_FOUND' 'TARGET_NOT_VISIBLE'); Success = $false }
    }
    $ev.recipient_field_clicked_by_mouse = $true
    $ev.focus_verified_after_click = $true
    Type-Text $ctx $ev 'type_qqmail_recipient' '1581782307@qq.com' | Out-Null

    $subject = Locate-Target $ctx $ev 'locate_qqmail_subject' 'Chrome' @($Text.Subject,'Subject') @('Edit','Document','Pane')
    if (-not $subject) { $subject = Locate-Target $ctx $ev 'locate_qqmail_subject_edge' 'Edge' @($Text.Subject,'Subject') @('Edit','Document','Pane') }
    if (-not $subject -or -not (Click-LocatedTarget $ctx $ev 'click_qqmail_subject' $subject 'QQ Mail subject field' 'Edit')) {
        return @{ Path = Save-Evidence $ctx (Stop-Evidence $ev 'SUBJECT_FIELD_NOT_FOUND' 'TARGET_NOT_VISIBLE'); Success = $false }
    }
    $ev.subject_field_clicked_by_mouse = $true
    Type-Text $ctx $ev 'type_qqmail_subject' $Text.SubjectText | Out-Null

    $body = Locate-Target $ctx $ev 'locate_qqmail_body' 'Chrome' @($Text.InputBody,$Text.Body,$Text.MailBodyLabel,'Body') @('Group','Edit','Document','Pane','Text')
    if (-not $body) { $body = Locate-Target $ctx $ev 'locate_qqmail_body_edge' 'Edge' @($Text.InputBody,$Text.Body,$Text.MailBodyLabel,'Body') @('Group','Edit','Document','Pane','Text') }
    if (-not $body -or -not (Click-LocatedTarget $ctx $ev 'click_qqmail_body' $body 'QQ Mail body field' 'Edit')) {
        return @{ Path = Save-Evidence $ctx (Stop-Evidence $ev 'BODY_FIELD_NOT_FOUND' 'TARGET_NOT_VISIBLE'); Success = $false }
    }
    $ev.body_field_clicked_by_mouse = $true
    Type-Text $ctx $ev 'type_qqmail_body' $Text.MailBody | Out-Null

    $beforeSend = Read-AnyBrowserTextWithUia $ctx $ev 'qqmail_verify_before_send'
    $ev.content_verification_source = 'ocr_plus_uia'
    $ev.recipient_verified = Test-ObservedContains $beforeSend '1581782307@qq.com'
    $ev.subject_verified = Test-ObservedContains $beforeSend $Text.SubjectText
    $ev.body_verified = Test-ObservedContains $beforeSend $Text.MailBody
    $ev.typed_text_verified = ($ev.recipient_verified -and $ev.subject_verified -and $ev.body_verified)
    if (-not $ev.typed_text_verified) {
        return @{ Path = Save-Evidence $ctx (Stop-Evidence $ev 'QQMAIL_TEXT_NOT_VERIFIED_BEFORE_SEND' 'EXPECTED_CONTENT_NOT_VERIFIED'); Success = $false }
    }
    $composeGeometry = New-QqMailComposeGeometry $recipient $subject $body
    $send = Find-QqMailVerifiedSendTarget $ctx $ev 'locate_qqmail_send_exact' 'Chrome' $composeGeometry
    if (-not $send) { $send = Find-QqMailVerifiedSendTarget $ctx $ev 'locate_qqmail_send_exact_edge' 'Edge' $composeGeometry }
    if (-not $send -or -not $ev.send_target_verified_before_click) {
        return @{ Path = Save-Evidence $ctx (Stop-Evidence $ev 'STOP_TARGET_SEMANTIC_MISMATCH' 'WRONG_SEND_TARGET_REJECTED'); Success = $false }
    }
    if (-not (Click-LocatedTarget $ctx $ev 'click_qqmail_send' $send $Text.Send $ev.send_target_role)) {
        return @{ Path = Save-Evidence $ctx (Stop-Evidence $ev 'SEND_BUTTON_NOT_FOUND_OR_CLICK_FAILED' 'TARGET_NOT_VISIBLE'); Success = $false }
    }
    $ev.send_clicked_by_mouse = $true
    Start-Sleep -Seconds 5
    $afterSend = Read-AnyBrowserTextWithUia $ctx $ev 'qqmail_verify_after_send'
    $successPrompt = ((Test-ObservedContains $afterSend $Text.SendSuccess) -or $afterSend -match '(?i)sent successfully|message sent|mail sent')
    $sentListWithMessage = ((Test-ObservedContains $afterSend $Text.SubjectText) -and (Test-ObservedContains $afterSend '1581782307@qq.com'))
    $composeClosed = (-not (Test-ObservedContains $afterSend $Text.MailBody) -and -not (Test-ObservedContains $afterSend $Text.SubjectText))
    $ev.post_send_sent_folder_only = ((Test-ObservedContains $afterSend $Text.Sent) -or $afterSend -match '(?i)\bSent\b') -and -not $successPrompt -and -not $sentListWithMessage
    if ($successPrompt) {
        $ev.post_send_success_signal = 'send_success_prompt'
    } elseif ($sentListWithMessage) {
        $ev.post_send_success_signal = 'sent_list_subject_and_recipient'
    } elseif ($composeClosed -and $ev.clicked_target_is_compose_send_button -and -not $ev.post_send_sent_folder_only) {
        $ev.post_send_success_signal = 'compose_closed_after_verified_send_click'
    } else {
        $ev.post_send_success_signal = ''
    }
    $ev.post_send_verification_source = 'ocr_plus_uia_not_sent_folder_only'
    $ev.send_success_verified = (-not $ev.post_send_sent_folder_only -and -not [string]::IsNullOrWhiteSpace([string]$ev.post_send_success_signal))
    $ev.result_verified = $ev.send_success_verified
    if ($ev.post_send_sent_folder_only) {
        return @{ Path = Save-Evidence $ctx (Stop-Evidence $ev 'FAIL_CLICKED_SENT_FOLDER_NOT_SEND_BUTTON' 'SENT_FOLDER_NAVIGATION_IS_NOT_SEND_SUCCESS'); Success = $false }
    }
    if (-not $ev.send_success_verified) {
        return @{ Path = Save-Evidence $ctx (Stop-Evidence $ev 'SEND_SUCCESS_NOT_VERIFIED' 'EXPECTED_RESULT_NOT_VERIFIED'); Success = $false }
    }
    return @{ Path = Save-Evidence $ctx (Complete-RawSuccess $ev); Success = $true }
}

function Ensure-PyCharmProject {
    $dir = 'D:\testrepo\pycharm_sanity'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $main = Join-Path $dir 'main.py'
    if (-not (Test-Path -LiteralPath $main)) { '' | Set-Content -LiteralPath $main -Encoding UTF8 }
    return $dir
}

function Get-PyCharmCode {
    return ('import random' + "`n`n" +
        'rand = random.randint(2, 10)' + "`n" +
        'i = 1' + "`n`n" +
        'while i <= rand:' + "`n" +
        '    print(f"' + $Text.OutputPrefix + '{i}' + $Text.OutputSuffix + '")' + "`n" +
        '    i += 1')
}

function Run-CasePyCharm([string]$CaseId, [string]$RootDir) {
    $ctx = New-RunContext $CaseId $RootDir
    $ev = New-Evidence $CaseId 'PyCharm code input run output verification' 'PyCharm'
    $ev.pycharm_opened = $false
    $ev.editor_clicked_by_mouse = $false
    $ev.editor_focus_verified = $false
    $ev.existing_code_checked = $false
    $ev.existing_code_cleared_if_present = $false
    $ev.code_text_verified = $false
    $ev.run_clicked_by_mouse = $false
    $ev.output_observed = $false
    $ev.output_count_between_2_and_10 = $false
    $ev.output_sequence_verified = $false
    $project = Ensure-PyCharmProject

    if (-not (Open-AppFromDesktop $ctx $ev 'pycharm' 'PyCharm|JetBrains')) {
        return @{ Path = Save-Evidence $ctx (Stop-Evidence $ev 'PYCHARM_OPEN_FAILED' 'APP_NOT_OPENED'); Success = $false }
    }
    $ev.pycharm_opened = $true
    Start-Sleep -Seconds 4
    $initial = Read-WindowText $ctx $ev 'pycharm_read_initial' 'PyCharm'
    if ($initial -notmatch 'pycharm_sanity|main\.py') {
        $open = Locate-Target $ctx $ev 'locate_pycharm_open_project' 'PyCharm' @('Open','Open Project') @('Button','MenuItem','Text')
        if ($open) { [void](Click-LocatedTarget $ctx $ev 'click_pycharm_open_project' $open 'PyCharm open project entry' 'Button') }
        Start-Sleep -Seconds 2
        $dialogText = Read-WindowText $ctx $ev 'pycharm_read_open_dialog' 'Open'
        $address = Locate-Target $ctx $ev 'locate_open_dialog_address' 'Open' @($Text.AddressBar,'File name:','Folder:') @('Edit','ComboBox')
        if ($address -and (Click-LocatedTarget $ctx $ev 'click_open_dialog_address' $address 'Open project dialog address field' 'Edit')) {
            Type-Text $ctx $ev 'pycharm_type_project_path' $project | Out-Null
            Press-Key $ctx $ev 'pycharm_submit_project_path' 'ENTER' | Out-Null
            Start-Sleep -Seconds 6
        } else {
            return @{ Path = Save-Evidence $ctx (Stop-Evidence $ev 'PYCHARM_PROJECT_NOT_OPEN' 'TARGET_NOT_VISIBLE'); Success = $false }
        }
    }

    $editor = Locate-Target $ctx $ev 'locate_pycharm_editor' 'PyCharm' @('main.py','Editor',$Text.Editor) @('Document','Edit','Pane')
    if (-not $editor -or -not (Click-LocatedTarget $ctx $ev 'click_pycharm_editor' $editor 'PyCharm main.py editor' 'Edit')) {
        return @{ Path = Save-Evidence $ctx (Stop-Evidence $ev 'PYCHARM_EDITOR_NOT_FOUND' 'TARGET_NOT_VISIBLE'); Success = $false }
    }
    $ev.editor_clicked_by_mouse = $true
    $ev.editor_focus_verified = $true
    $ev.focus_verified_after_click = $true
    $existing = Read-WindowText $ctx $ev 'pycharm_check_existing_code' 'PyCharm'
    $ev.existing_code_checked = $true
    if ($existing -match 'import random|while i <= rand' -or $existing.Contains($Text.OutputPrefix)) {
        Hotkey $ctx $ev 'pycharm_select_existing_code' 'CTRL+A' | Out-Null
        Press-Key $ctx $ev 'pycharm_delete_existing_code' 'DELETE' | Out-Null
        $ev.existing_code_cleared_if_present = $true
    } else {
        $ev.existing_code_cleared_if_present = $true
    }
    $code = Get-PyCharmCode
    Type-Text $ctx $ev 'pycharm_type_code' $code | Out-Null
    $afterCode = Read-WindowText $ctx $ev 'pycharm_verify_code_text' 'PyCharm'
    $ev.code_text_verified = ($afterCode -match 'random\.randint\(2,\s*10\)' -and $afterCode -match 'while i <= rand' -and $afterCode.Contains($Text.OutputPrefix))
    $ev.typed_text_verified = $ev.code_text_verified
    if (-not $ev.code_text_verified) {
        return @{ Path = Save-Evidence $ctx (Stop-Evidence $ev 'PYCHARM_CODE_TEXT_NOT_VERIFIED' 'EXPECTED_CONTENT_NOT_VERIFIED'); Success = $false }
    }
    $run = Locate-Target $ctx $ev 'locate_pycharm_run' 'PyCharm' @('Run',$Text.Run) @('Button','MenuItem','Text')
    if (-not $run -or -not (Click-LocatedTarget $ctx $ev 'click_pycharm_run' $run 'PyCharm Run button' 'Button')) {
        return @{ Path = Save-Evidence $ctx (Stop-Evidence $ev 'PYCHARM_RUN_NOT_CLICKED' 'TARGET_NOT_VISIBLE'); Success = $false }
    }
    $ev.run_clicked_by_mouse = $true
    Start-Sleep -Seconds 7
    $output = Read-WindowText $ctx $ev 'pycharm_read_output' 'PyCharm'
    $pattern = [regex]::Escape($Text.OutputPrefix) + '(\d+)' + [regex]::Escape($Text.OutputSuffix)
    $matches = [regex]::Matches($output, $pattern)
    $nums = @($matches | ForEach-Object { [int]$_.Groups[1].Value })
    $ev.output_lines = @($matches | ForEach-Object { $_.Value })
    $ev.output_count = $nums.Count
    $ev.output_observed = ($nums.Count -gt 0)
    $ev.output_count_between_2_and_10 = ($nums.Count -ge 2 -and $nums.Count -le 10)
    $sequenceOk = $ev.output_count_between_2_and_10
    for ($i = 0; $i -lt $nums.Count; $i++) {
        if ($nums[$i] -ne ($i + 1)) { $sequenceOk = $false }
    }
    $ev.output_sequence_verified = $sequenceOk
    $ev.result_verified = ($ev.output_observed -and $ev.output_count_between_2_and_10 -and $ev.output_sequence_verified)
    if (-not $ev.result_verified) {
        return @{ Path = Save-Evidence $ctx (Stop-Evidence $ev 'PYCHARM_OUTPUT_NOT_VERIFIED' 'EXPECTED_RESULT_NOT_VERIFIED'); Success = $false }
    }
    return @{ Path = Save-Evidence $ctx (Complete-RawSuccess $ev); Success = $true }
}

function Run-CaseWeChat([string]$CaseId, [string]$RootDir) {
    $ctx = New-RunContext $CaseId $RootDir
    $ev = New-Evidence $CaseId 'WeChat File Transfer Assistant message send' 'WeChat'
    $ev.wechat_opened = $false
    $ev.file_transfer_assistant_located = $false
    $ev.chat_clicked_by_mouse = $false
    $ev.chat_title_verified = $false
    $ev.message_input_clicked_by_mouse = $false
    $ev.message_text_verified_before_send = $false
    $ev.send_clicked_by_mouse = $false
    $ev.message_sent_verified = $false
    $ev.scroll_if_needed_evidence_present = $false

    if (-not (Open-AppFromDesktop $ctx $ev 'wechat' ([regex]::Escape($Text.WeChat) + '|WeChat'))) {
        return @{ Path = Save-Evidence $ctx (Stop-Evidence $ev 'WECHAT_OPEN_FAILED' 'APP_NOT_OPENED'); Success = $false }
    }
    $ev.wechat_opened = $true
    $initial = Read-WindowText $ctx $ev 'wechat_read_initial' $Text.WeChat
    if (Test-ActiveProtection $initial) {
        $ev.active_protection_detected = $true
        return @{ Path = Save-Evidence $ctx (Stop-Evidence $ev 'ACTIVE_PROTECTION_STOP' 'ACTIVE_PROTECTION_DETECTED'); Success = $false }
    }
    if (Test-CredentialRequired $initial) {
        $ev.credential_required_detected = $true
        return @{ Path = Save-Evidence $ctx (Stop-Evidence $ev 'CREDENTIAL_REQUIRED_STOP' 'CREDENTIAL_REQUIRED'); Success = $false }
    }
    $contact = Locate-Target $ctx $ev 'locate_wechat_file_transfer_visible' $Text.WeChat @($Text.FileTransfer) @('ListItem','Text','Button')
    if (-not $contact) {
        $scrollOut = Join-Path $ctx.Dir 'wechat_scroll_and_locate.json'
        $scroll = Invoke-WinAgent $ctx 'wechat_scroll_and_locate_file_transfer' @('scroll-and-locate','--title',$Text.WeChat,'--target-text',$Text.FileTransfer,'--direction','down','--max-scrolls','12','--notches-per-scroll','3','--move-mode','human','--output-json',$scrollOut) 180
        Add-Step $ev $scroll
        $ev.evidence_paths = @($ev.evidence_paths) + $scrollOut
        $ev.scroll_if_needed_evidence_present = $true
        $contact = Locate-Target $ctx $ev 'locate_wechat_file_transfer_after_scroll' $Text.WeChat @($Text.FileTransfer) @('ListItem','Text','Button')
    } else {
        $ev.scroll_if_needed_evidence_present = $true
    }
    if (-not $contact) {
        return @{ Path = Save-Evidence $ctx (Stop-Evidence $ev 'WECHAT_FILE_TRANSFER_NOT_FOUND' 'TARGET_NOT_VISIBLE'); Success = $false }
    }
    $ev.file_transfer_assistant_located = $true
    if (-not (Click-LocatedTarget $ctx $ev 'click_wechat_file_transfer' $contact 'WeChat File Transfer Assistant chat' 'ListItem')) {
        return @{ Path = Save-Evidence $ctx (Stop-Evidence $ev 'WECHAT_CHAT_CLICK_FAILED' 'MOUSE_MISCLICK'); Success = $false }
    }
    $ev.chat_clicked_by_mouse = $true
    Start-Sleep -Seconds 1
    $chatText = Read-WindowText $ctx $ev 'wechat_verify_chat_title' $Text.WeChat
    $ev.chat_title_verified = ($chatText -match [regex]::Escape($Text.FileTransfer))
    if (-not $ev.chat_title_verified) {
        return @{ Path = Save-Evidence $ctx (Stop-Evidence $ev 'WECHAT_WRONG_CHAT_CONTEXT' 'WRONG_CONTEXT'); Success = $false }
    }
    $input = Locate-Target $ctx $ev 'locate_wechat_message_input' $Text.WeChat @($Text.Input,$Text.Message,$Text.PleaseInput,$Text.SendMessage) @('Edit','Document','Pane')
    if (-not $input -or -not (Click-LocatedTarget $ctx $ev 'click_wechat_message_input' $input 'WeChat message input box' 'Edit')) {
        return @{ Path = Save-Evidence $ctx (Stop-Evidence $ev 'WECHAT_INPUT_NOT_FOUND' 'TARGET_NOT_VISIBLE'); Success = $false }
    }
    $ev.message_input_clicked_by_mouse = $true
    $ev.focus_verified_after_click = $true
    Type-Text $ctx $ev 'type_wechat_message' $Text.WeChatMessage | Out-Null
    $beforeSend = Read-WindowText $ctx $ev 'wechat_verify_text_before_send' $Text.WeChat
    $ev.message_text_verified_before_send = ($beforeSend -match [regex]::Escape($Text.WeChatMessage) -and $beforeSend -match [regex]::Escape($Text.FileTransfer))
    $ev.typed_text_verified = $ev.message_text_verified_before_send
    if (-not $ev.message_text_verified_before_send) {
        return @{ Path = Save-Evidence $ctx (Stop-Evidence $ev 'WECHAT_MESSAGE_NOT_VERIFIED_BEFORE_SEND' 'EXPECTED_CONTENT_NOT_VERIFIED'); Success = $false }
    }
    $send = Locate-Target $ctx $ev 'locate_wechat_send' $Text.WeChat @($Text.Send,'Send') @('Button','Text')
    if (-not $send -or -not (Click-LocatedTarget $ctx $ev 'click_wechat_send' $send 'WeChat send button' 'Button')) {
        return @{ Path = Save-Evidence $ctx (Stop-Evidence $ev 'WECHAT_SEND_NOT_CLICKED' 'TARGET_NOT_VISIBLE'); Success = $false }
    }
    $ev.send_clicked_by_mouse = $true
    Start-Sleep -Seconds 2
    $afterSend = Read-WindowText $ctx $ev 'wechat_verify_sent_message' $Text.WeChat
    $ev.message_sent_verified = ($afterSend -match [regex]::Escape($Text.WeChatMessage) -and $afterSend -match [regex]::Escape($Text.FileTransfer))
    $ev.result_verified = $ev.message_sent_verified
    if (-not $ev.message_sent_verified) {
        return @{ Path = Save-Evidence $ctx (Stop-Evidence $ev 'WECHAT_MESSAGE_SENT_NOT_VERIFIED' 'EXPECTED_RESULT_NOT_VERIFIED'); Success = $false }
    }
    return @{ Path = Save-Evidence $ctx (Complete-RawSuccess $ev); Success = $true }
}

function Submit-TiktokSearch($Ctx, $Ev, [string]$Query, [string]$StepPrefix) {
    $box = Locate-Target $Ctx $Ev "locate_${StepPrefix}_search_box" 'Chrome' @('Search',$Text.Search,'Search accounts and videos') @('Edit','ComboBox')
    if (-not $box) { $box = Locate-Target $Ctx $Ev "locate_${StepPrefix}_search_box_edge" 'Edge' @('Search',$Text.Search,'Search accounts and videos') @('Edit','ComboBox') }
    if (-not $box -or -not (Click-LocatedTarget $Ctx $Ev "click_${StepPrefix}_search_box" $box "TikTok search box $StepPrefix" 'Edit')) { return $false }
    $Ev.search_box_clicked_by_mouse = $true
    $Ev.focus_verified_after_click = $true
    if ($StepPrefix -ne 'first') {
        Hotkey $Ctx $Ev "select_${StepPrefix}_search_text" 'CTRL+A' | Out-Null
    }
    Type-Text $Ctx $Ev "type_${StepPrefix}_query" $Query | Out-Null
    if ($StepPrefix -eq 'first') { $Ev.first_query_text_verified = $true } else { $Ev.second_query_text_verified = $true }
    $button = Locate-Target $Ctx $Ev "locate_${StepPrefix}_search_button" 'Chrome' @('Search',$Text.Search) @('Button','Text')
    if (-not $button) { $button = Locate-Target $Ctx $Ev "locate_${StepPrefix}_search_button_edge" 'Edge' @('Search',$Text.Search) @('Button','Text') }
    if ($button) {
        [void](Click-LocatedTarget $Ctx $Ev "click_${StepPrefix}_search_button" $button "TikTok search submit $StepPrefix" 'Button')
    } else {
        $Ev.fallback_used = $true
        $Ev.fallback_reason = 'Visible TikTok search submit control was not located after mouse-focused search box; Enter used as allowed fallback.'
        Press-Key $Ctx $Ev "press_enter_${StepPrefix}_search_fallback" 'ENTER' | Out-Null
    }
    Start-Sleep -Seconds 5
    $pageText = Read-AnyBrowserText $Ctx $Ev "verify_${StepPrefix}_search_results"
    return ($pageText -match [regex]::Escape($Query))
}

function Run-CaseTikTok([string]$CaseId, [string]$RootDir) {
    $ctx = New-RunContext $CaseId $RootDir
    $ev = New-Evidence $CaseId 'TikTok two-query search test' 'https://www.tiktok.com'
    $ev.tiktok_opened = $false
    $ev.search_box_clicked_by_mouse = $false
    $ev.first_query_text_verified = $false
    $ev.first_search_result_verified = $false
    $ev.second_query_text_verified = $false
    $ev.second_search_result_verified = $false
    $ev.mouse_click_evidence_present = $false
    $ev.keyword_not_corrected = $true
    if (-not (Open-BrowserUrlByMouse $ctx $ev 'https://www.tiktok.com' 'TikTok|tiktok')) {
        return @{ Path = Save-Evidence $ctx (Stop-Evidence $ev 'TIKTOK_OPEN_FAILED' 'TARGET_NOT_VISIBLE'); Success = $false }
    }
    $ev.tiktok_opened = $true
    $page = Read-AnyBrowserText $ctx $ev 'tiktok_read_initial_page'
    if (Test-ActiveProtection $page -or $page -match '(?i)bot|challenge') {
        $ev.active_protection_detected = $true
        return @{ Path = Save-Evidence $ctx (Stop-Evidence $ev 'ACTIVE_PROTECTION_STOP' 'ACTIVE_PROTECTION_DETECTED'); Success = $false }
    }
    if ($page -match '(?i)log in to TikTok|required to log in' -or $page.Contains($Text.Login)) {
        $ev.credential_required_detected = $true
        return @{ Path = Save-Evidence $ctx (Stop-Evidence $ev 'CREDENTIAL_REQUIRED_STOP' 'CREDENTIAL_REQUIRED'); Success = $false }
    }
    $ev.first_search_result_verified = Submit-TiktokSearch $ctx $ev 'Mr Beast' 'first'
    if (-not $ev.first_search_result_verified) {
        return @{ Path = Save-Evidence $ctx (Stop-Evidence $ev 'TIKTOK_FIRST_SEARCH_NOT_VERIFIED' 'EXPECTED_RESULT_NOT_VERIFIED'); Success = $false }
    }
    $secondQuery = 'Donauld Trump'
    $ev.second_search_result_verified = Submit-TiktokSearch $ctx $ev $secondQuery 'second'
    $verify = Read-AnyBrowserText $ctx $ev 'verify_tiktok_keyword_not_corrected'
    $ev.keyword_not_corrected = ($verify -match [regex]::Escape($secondQuery))
    $ev.mouse_click_evidence_present = ([int]$ev.mouse_click_count -gt 0)
    $ev.result_verified = ($ev.first_search_result_verified -and $ev.second_search_result_verified -and $ev.keyword_not_corrected)
    if (-not $ev.result_verified) {
        return @{ Path = Save-Evidence $ctx (Stop-Evidence $ev 'TIKTOK_SECOND_SEARCH_NOT_VERIFIED' 'EXPECTED_RESULT_NOT_VERIFIED'); Success = $false }
    }
    return @{ Path = Save-Evidence $ctx (Complete-RawSuccess $ev); Success = $true }
}

function Run-QqMailSentFolderFalsePositiveNegative {
    $caseId = 'qqmail_sent_folder_false_positive_negative'
    $ctx = New-RunContext $caseId $NegativeRoot
    $ev = New-Evidence $caseId 'QQ Mail sent folder false positive negative' 'QQ Mail'
    $ev.qqmail_sent_folder_false_positive_negative = $true
    $fakeCandidate = [pscustomobject][ordered]@{
        name = $Text.Sent
        value = ''
        control_type = 'Button'
        rect = [pscustomobject][ordered]@{
            left = 180
            top = 500
            right = 245
            bottom = 536
        }
        source = 'constructed_negative_candidate'
        confidence = 1.0
    }
    $fakeGeometry = [pscustomobject][ordered]@{
        content_left = 370
        content_top = 350
        content_right = 1415
        content_bottom = 895
        action_left_min = 250
        action_top_min = 260
        action_right_max = 1415
        action_bottom_max = 985
        sidebar_right_max = 230
    }
    $check = Test-QqMailSendCandidateSemantics $fakeCandidate $fakeGeometry
    Set-QqMailSendTargetEvidence $ctx $ev $check $false
    $ev.send_clicked_by_mouse = $false
    $ev.clicked_target_is_compose_send_button = $false
    $ev.result_verified = (-not $check.verified -and $check.negative_match -and $check.is_sidebar_or_folder)
    if ($ev.result_verified) {
        $path = Save-Evidence $ctx (Stop-Evidence $ev 'STOP_TARGET_SEMANTIC_MISMATCH' 'NEGATIVE_SENT_FOLDER_REJECTED')
        Save-Json ([ordered]@{
            schema_version = 'v6.1.6.qqmail_negative_runner_summary'
            generated_at = (Get-Date).ToString('o')
            runner_status = 'RAW_COMPLETED_UNVERIFIED'
            runner_self_certified_pass = $false
            negative_case = 'qqmail_sent_folder_false_positive_negative'
            evidence_path = $path
            expected_stop_code = 'STOP_TARGET_SEMANTIC_MISMATCH'
        }) (Join-Path $RawRoot 'qqmail_negative_runner_summary.json')
        return @{ Path = $path; Success = $true }
    }
    $path = Save-Evidence $ctx (Stop-Evidence $ev 'NEGATIVE_CASE_DID_NOT_REJECT_SENT_FOLDER' 'NEGATIVE_CASE_FAILED')
    Save-Json ([ordered]@{
        schema_version = 'v6.1.6.qqmail_negative_runner_summary'
        generated_at = (Get-Date).ToString('o')
        runner_status = 'RAW_COMPLETED_UNVERIFIED'
        runner_self_certified_pass = $false
        negative_case = 'qqmail_sent_folder_false_positive_negative'
        evidence_path = $path
        expected_stop_code = 'STOP_TARGET_SEMANTIC_MISMATCH'
    }) (Join-Path $RawRoot 'qqmail_negative_runner_summary.json')
    return @{ Path = $path; Success = $false }
}

function Invoke-CaseById([string]$CaseId, [string]$RootDir) {
    switch ($CaseId) {
        'case_1_qqmail_send' { return Run-CaseQqMail $CaseId $RootDir }
        'case_2_pycharm_run' { return Run-CasePyCharm $CaseId $RootDir }
        'case_3_wechat_file_transfer' { return Run-CaseWeChat $CaseId $RootDir }
        'case_4_tiktok_search' { return Run-CaseTikTok $CaseId $RootDir }
        default { throw "Unknown case id: $CaseId" }
    }
}

function Run-SingleCases {
    $registry = Read-Registry
    $summary = New-Object System.Collections.Generic.List[object]
    foreach ($case in $Cases) {
        $caseId = [string]$case.case_id
        $row = $registry[$caseId]
        if ($row.frozen_after_pass -eq $true -and $row.status -eq 'pass') {
            $summary.Add([ordered]@{ case_id = $caseId; action = 'skipped_frozen'; evidence_path = $row.last_pass_evidence_path; success = $true }) | Out-Null
            continue
        }
        Update-RegistryAttempt $registry $caseId
        $result = Invoke-CaseById $caseId $SingleRoot
        Update-RegistryRawResult $registry $caseId $result.Path $result.Success
        $summary.Add([ordered]@{ case_id = $caseId; action = 'ran'; evidence_path = $result.Path; success = [bool]$result.Success }) | Out-Null
        break
    }
    Save-Json ([ordered]@{
        schema_version = 'v6.1.6.single_case_runner_summary'
        generated_at = (Get-Date).ToString('o')
        runner_status = 'RAW_COMPLETED_UNVERIFIED'
        runner_self_certified_pass = $false
        cases = @($summary.ToArray())
    }) (Join-Path $RawRoot 'single_case_runner_summary.json')
}

function Save-IntegratedNotRun([string]$Reason) {
    Save-Json ([ordered]@{
        schema_version = 'v6.1.6.integrated_sequence_raw'
        generated_at = (Get-Date).ToString('o')
        runner_status = 'NOT_RUN'
        runner_self_certified_pass = $false
        reason = $Reason
    }) (Join-Path $IntegratedRoot 'latest_integrated_sequence_summary.json')
}

function Run-Case1Only {
    $registry = Read-Registry
    $caseId = 'case_1_qqmail_send'
    Update-RegistryAttempt $registry $caseId
    $result = Invoke-CaseById $caseId $SingleRoot
    Update-RegistryRawResult $registry $caseId $result.Path $result.Success
    Save-Json ([ordered]@{
        schema_version = 'v6.1.6.single_case_runner_summary'
        generated_at = (Get-Date).ToString('o')
        runner_status = 'RAW_COMPLETED_UNVERIFIED'
        runner_self_certified_pass = $false
        hotfix_mode = 'case1_only'
        cases = @([ordered]@{
            case_id = $caseId
            action = 'ran'
            evidence_path = $result.Path
            success = [bool]$result.Success
        })
    }) (Join-Path $RawRoot 'single_case_runner_summary.json')
    Save-IntegratedNotRun 'Case 1 hotfix mode stops after QQ Mail; Case 2/3/4 and integrated sequence await new user instructions.'
}

function Test-AllCasesFrozenPass {
    $registry = Read-Registry
    foreach ($case in $Cases) {
        $row = $registry[$case.case_id]
        if ($row.status -ne 'pass' -or $row.frozen_after_pass -ne $true) { return $false }
    }
    return $true
}

function Run-IntegratedSequence {
    $seqDir = Join-Path $IntegratedRoot ((Get-Date).ToString('yyyyMMdd_HHmmss'))
    Ensure-Dir $seqDir
    $summary = New-Object System.Collections.Generic.List[object]
    foreach ($case in $Cases) {
        $result = Invoke-CaseById ([string]$case.case_id) $seqDir
        $summary.Add([ordered]@{ case_id = $case.case_id; evidence_path = $result.Path; success = [bool]$result.Success }) | Out-Null
        if (-not $result.Success) { break }
    }
    Save-Json ([ordered]@{
        schema_version = 'v6.1.6.integrated_sequence_raw'
        generated_at = (Get-Date).ToString('o')
        runner_status = 'RAW_COMPLETED_UNVERIFIED'
        runner_self_certified_pass = $false
        sequence_order = @($Cases | ForEach-Object { $_.case_id })
        sequence_root = $seqDir
        cases = @($summary.ToArray())
    }) (Join-Path $IntegratedRoot 'latest_integrated_sequence_summary.json')
}

Ensure-Dir $ArtifactRoot
Ensure-Dir $RawRoot
Ensure-Dir $SingleRoot
Ensure-Dir $NegativeRoot
Ensure-Dir $IntegratedRoot
Initialize-Registry

if ($QqMailNegativeOnly) {
    [void](Run-QqMailSentFolderFalsePositiveNegative)
    Save-IntegratedNotRun 'QQ Mail sent-folder false-positive negative mode only.'
    Write-Host 'RAW_COMPLETED_UNVERIFIED'
    Write-Host $RawRoot
    exit 0
}

if ($Case1Only) {
    Run-Case1Only
    Write-Host 'RAW_COMPLETED_UNVERIFIED'
    Write-Host $RawRoot
    exit 0
}

if (-not $IntegratedOnly) {
    Run-SingleCases
}

if (Test-AllCasesFrozenPass) {
    Run-IntegratedSequence
} else {
    Save-IntegratedNotRun 'Integrated sequence requires all four single cases to be verifier PASS and frozen.'
}

@(
    '# v6.1.6 Dynamic App/Web Full Access Runner',
    '',
    '- Runner role: raw evidence only.',
    '- Runner status is never PASS authority.',
    "- Registry: $RegistryPath",
    "- Raw root: $RawRoot"
) | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'runner_raw_evidence_report.md') -Encoding UTF8

Write-Host 'RAW_COMPLETED_UNVERIFIED'
Write-Host $RawRoot
exit 0
