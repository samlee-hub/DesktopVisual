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
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.2.0_persistent_runtime_session_latency_gate'
$RawRoot = Join-Path $ArtifactRoot 'raw\runtime_session_latency_benchmark'
$LatencyJson = Join-Path $ArtifactRoot 'latency_report.json'
$LatencyMd = Join-Path $ArtifactRoot 'latency_report.md'
New-Item -ItemType Directory -Force -Path $RawRoot | Out-Null

function Fail([string]$Message) { throw $Message }

function Invoke-WinAgentJsonTimed {
    param(
        [string[]]$WinArgs,
        [int[]]$AllowedExitCodes = @(0)
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $output = & $WinAgent @WinArgs 2>&1
    $exit = $LASTEXITCODE
    $sw.Stop()
    $text = ($output | Out-String).Trim()
    if ($AllowedExitCodes -notcontains $exit) {
        Fail "winagent $($WinArgs -join ' ') exited $exit with output: $text"
    }
    try { $json = $text | ConvertFrom-Json } catch { Fail "Invalid JSON: $text" }
    [pscustomobject]@{ exit = $exit; json = $json; text = $text; args = $WinArgs; elapsed_ms = [int64]$sw.ElapsedMilliseconds }
}

function Percentile([int64[]]$Values, [double]$P) {
    if ($Values.Count -eq 0) { return 0 }
    $sorted = @($Values | Sort-Object)
    if ($sorted.Count -eq 1) { return [int64]$sorted[0] }
    $index = [int][Math]::Round(($sorted.Count - 1) * $P)
    if ($index -lt 0) { $index = 0 }
    if ($index -ge $sorted.Count) { $index = $sorted.Count - 1 }
    [int64]$sorted[$index]
}

function Summarize-Latency([string]$Mode, [object[]]$Steps, [int]$ProcessRestartCount, [bool]$SessionReuseEnabled) {
    $durations = @($Steps | ForEach-Object { [int64]$_.elapsed_ms })
    $total = [int64](($durations | Measure-Object -Sum).Sum)
    $avg = if ($durations.Count -gt 0) { [int64][Math]::Round($total / $durations.Count) } else { 0 }
    $slowest = $Steps | Sort-Object elapsed_ms -Descending | Select-Object -First 1
    [ordered]@{
        mode = $Mode
        step_count = $Steps.Count
        total_sequence_ms = $total
        average_step_ms = $avg
        p50_step_ms = (Percentile $durations 0.50)
        p95_step_ms = (Percentile $durations 0.95)
        process_restart_count = $ProcessRestartCount
        session_reuse_enabled = $SessionReuseEnabled
        slowest_step = if ($slowest) { [string]$slowest.name } else { '' }
        slowest_step_reason = if ($slowest) { [string]$slowest.command } else { '' }
        steps = @($Steps)
    }
}

function Invoke-OneShotSimpleStep {
    param(
        [System.Collections.Generic.List[object]]$Steps,
        [string]$Name,
        [string[]]$WinArgs
    )
    $r = Invoke-WinAgentJsonTimed -WinArgs $WinArgs
    $script:oneShotProcessCount += 1
    $Steps.Add([ordered]@{
        name = $Name
        command = ($WinArgs -join ' ')
        elapsed_ms = $r.elapsed_ms
        duration_ms = [int64]$r.json.duration_ms
        ok = [bool]$r.json.ok
    }) | Out-Null
}

function Invoke-OneShotLocateClickStep {
    param(
        [System.Collections.Generic.List[object]]$Steps,
        [string]$Name,
        [string]$Selector
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $locateArgs = @('locate','--title','Agent Test Window','--selector',$Selector)
    $locate = Invoke-WinAgentJsonTimed -WinArgs $locateArgs
    $script:oneShotProcessCount += 1
    if (-not [bool]$locate.json.ok) {
        Fail "one-shot locate failed for $Selector"
    }
    $x = [string][int]$locate.json.data.client_point.x
    $y = [string][int]$locate.json.data.client_point.y
    $clickArgs = @('click','--title','Agent Test Window','--x',$x,'--y',$y,'--move-mode','instant')
    $click = Invoke-WinAgentJsonTimed -WinArgs $clickArgs
    $script:oneShotProcessCount += 1
    $sw.Stop()
    $Steps.Add([ordered]@{
        name = $Name
        command = (($locateArgs -join ' ') + ' && ' + ($clickArgs -join ' '))
        elapsed_ms = [int64]$sw.ElapsedMilliseconds
        duration_ms = [int64]($locate.json.duration_ms + $click.json.duration_ms)
        ok = ([bool]$locate.json.ok -and [bool]$click.json.ok)
    }) | Out-Null
}

function Invoke-OneShotStateWaitStep {
    param(
        [System.Collections.Generic.List[object]]$Steps,
        [string]$Name,
        [string]$ExpectedText,
        [int]$TimeoutMs = 3000
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    $attempts = 0
    $lastText = ''
    do {
        $r = Invoke-WinAgentJsonTimed -WinArgs @('read-file','--path',$StatePath) -AllowedExitCodes @(0, 1)
        $script:oneShotProcessCount += 1
        $attempts += 1
        $lastText = $r.text
        if ($r.exit -eq 0) {
            $content = [string]$r.json.data.content
            if ([string]::IsNullOrWhiteSpace($ExpectedText) -or $content.Contains($ExpectedText)) {
                $sw.Stop()
                $Steps.Add([ordered]@{
                    name = $Name
                    command = "read-file --path $StatePath wait_contains=$ExpectedText attempts=$attempts"
                    elapsed_ms = [int64]$sw.ElapsedMilliseconds
                    duration_ms = [int64]$r.json.duration_ms
                    ok = [bool]$r.json.ok
                }) | Out-Null
                return
            }
        }
        Start-Sleep -Milliseconds 50
    } while ((Get-Date) -lt $deadline)

    Fail "state wait failed for '$ExpectedText' after $attempts attempts. Last output: $lastText"
}

if (!(Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run build.ps1 first." }
if (!(Test-Path -LiteralPath $TestWindowExe)) { Fail "Missing $TestWindowExe. Run build.ps1 first." }

Get-Process TestWindow -ErrorAction SilentlyContinue | ForEach-Object {
    $_.CloseMainWindow() | Out-Null
    Start-Sleep -Milliseconds 200
    if (!$_.HasExited) { Stop-Process -Id $_.Id -Force }
}

$proc = Start-Process -FilePath $TestWindowExe -PassThru
try {
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 200
        $find = Invoke-WinAgentJsonTimed -WinArgs @('find', '--title', 'Agent Test Window') -AllowedExitCodes @(0, 1)
    } while ($find.exit -ne 0 -and (Get-Date) -lt $deadline)
    if ($find.exit -ne 0) { Fail 'Agent Test Window did not appear.' }

    $baselineSteps = New-Object System.Collections.Generic.List[object]
    $script:oneShotProcessCount = 0
    Invoke-OneShotSimpleStep -Steps $baselineSteps -Name 'observe' -WinArgs @('observe','--title','Agent Test Window','--screenshot','false','--uia','true')
    Invoke-OneShotLocateClickStep -Steps $baselineSteps -Name 'click_field' -Selector 'uia:type=Edit'
    Invoke-OneShotSimpleStep -Steps $baselineSteps -Name 'type_text1' -WinArgs @('type','--title','Agent Test Window','--text','DV62_TEXT1','--type-mode','instant')
    Invoke-OneShotStateWaitStep -Steps $baselineSteps -Name 'verify_text1' -ExpectedText 'last_text=DV62_TEXT1'
    Invoke-OneShotLocateClickStep -Steps $baselineSteps -Name 'click_button1' -Selector 'uia:name=Click Me,type=Button'
    Invoke-OneShotStateWaitStep -Steps $baselineSteps -Name 'verify_click1' -ExpectedText 'clicks=1'
    Invoke-OneShotLocateClickStep -Steps $baselineSteps -Name 'click_field_again' -Selector 'uia:type=Edit'
    Invoke-OneShotSimpleStep -Steps $baselineSteps -Name 'type_text2' -WinArgs @('type','--title','Agent Test Window','--text','DV62TEXT2','--type-mode','instant')
    Invoke-OneShotStateWaitStep -Steps $baselineSteps -Name 'verify_text2' -ExpectedText 'DV62TEXT2'
    Invoke-OneShotLocateClickStep -Steps $baselineSteps -Name 'click_button2' -Selector 'uia:name=Click Me,type=Button'
    $baseline = Summarize-Latency -Mode 'one_shot_baseline' -Steps @($baselineSteps.ToArray()) -ProcessRestartCount $script:oneShotProcessCount -SessionReuseEnabled $false

    if ($proc -and !$proc.HasExited) {
        $proc.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (!$proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    }
    $proc = Start-Process -FilePath $TestWindowExe -PassThru
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 200
        $find = Invoke-WinAgentJsonTimed -WinArgs @('find', '--title', 'Agent Test Window') -AllowedExitCodes @(0, 1)
    } while ($find.exit -ne 0 -and (Get-Date) -lt $deadline)
    if ($find.exit -ne 0) { Fail 'Agent Test Window did not reappear.' }

    $start = Invoke-WinAgentJsonTimed -WinArgs @('runtime-session-start', '--title', 'Agent Test Window', '--process', 'TestWindow.exe')
    $sessionId = [string]$start.json.session_id
    $stepsPath = Join-Path $RawRoot 'persistent_10_step_workflow.steps.json'
    $dispatchResultPath = Join-Path $RawRoot 'persistent_10_step_workflow.result.json'
    $steps = [ordered]@{
        steps = @(
            [ordered]@{ step_id='s01_observe'; action='observe'; cache_policy='force_reobserve' },
            [ordered]@{ step_id='s02_click_field1'; action='click'; target='uia:type=Edit'; move_mode='instant' },
            [ordered]@{ step_id='s03_type_text1'; action='type'; target='uia:type=Edit'; text='DV62_TEXT1'; type_mode='instant'; move_mode='instant'; force_reobserve=$true },
            [ordered]@{ step_id='s04_verify_field1'; action='verify'; verification_hint='state_contains:last_text=DV62_TEXT1' },
            [ordered]@{ step_id='s05_click_submit1'; action='click'; target='uia:name=Click Me,type=Button'; move_mode='instant'; force_reobserve=$true; verification_hint='state_contains:clicks=1' },
            [ordered]@{ step_id='s06_click_field2'; action='click'; target='uia:type=Edit'; move_mode='instant'; force_reobserve=$true },
            [ordered]@{ step_id='s07_type_text2'; action='type'; target='uia:type=Edit'; text='DV62TEXT2'; type_mode='instant'; move_mode='instant'; force_reobserve=$true },
            [ordered]@{ step_id='s08_verify_field2'; action='verify'; verification_hint='state_contains:TEXT2' },
            [ordered]@{ step_id='s09_observe_after_actions'; action='observe'; force_reobserve=$true },
            [ordered]@{ step_id='s10_click_submit2'; action='click'; target='uia:name=Click Me,type=Button'; move_mode='instant'; force_reobserve=$true; verification_hint='state_contains:clicks=2' }
        )
    }
    $steps | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $stepsPath -Encoding UTF8
    $dispatch = Invoke-WinAgentJsonTimed -WinArgs @('runtime-session-dispatch','--session-id',$sessionId,'--steps-json',$stepsPath,'--result-json',$dispatchResultPath)
    $close = Invoke-WinAgentJsonTimed -WinArgs @('runtime-session-close', '--session-id', $sessionId)

    $persistentInternal = $dispatch.json.data.latency_summary
    $persistentSteps = @($dispatch.json.data.step_results | ForEach-Object {
        [ordered]@{
            name = [string]$_.step_id
            command = [string]$_.action
            elapsed_ms = [int64]$_.latency.total_step_ms
            duration_ms = [int64]$_.latency.total_step_ms
            ok = [bool]$_.ok
        }
    })
    $persistent = Summarize-Latency -Mode 'persistent_session' -Steps $persistentSteps -ProcessRestartCount 1 -SessionReuseEnabled $true
    $persistent.total_sequence_ms = [int64]$persistentInternal.total_sequence_ms
    $persistent.average_step_ms = [int64]$persistentInternal.average_step_ms
    $persistent.p50_step_ms = [int64]$persistentInternal.p50_step_ms
    $persistent.p95_step_ms = [int64]$persistentInternal.p95_step_ms
    $persistent.process_restart_count = [int]$persistentInternal.process_restart_count

    $processReduced = [int]$persistent.process_restart_count -lt [int]$baseline.process_restart_count
    $avgImproved = [int64]$persistent.average_step_ms -lt [int64]$baseline.average_step_ms
    $p95Reported = [int64]$persistent.p95_step_ms -ge 0 -and [int64]$baseline.p95_step_ms -ge 0
    $latencyGateMet = $processReduced -and $avgImproved -and $p95Reported
    $improvementPct = if ([int64]$baseline.average_step_ms -gt 0) {
        [Math]::Round((([double]$baseline.average_step_ms - [double]$persistent.average_step_ms) / [double]$baseline.average_step_ms) * 100.0, 2)
    } else { 0 }

    $report = [ordered]@{
        schema_version = 'v6.2.0.latency_report'
        generated_at = (Get-Date).ToString('o')
        status = if ($latencyGateMet) { 'PASS' } else { 'BLOCKED_LATENCY_GATE_NOT_MET' }
        workflow = 'TestWindow 10-step field/type/verify/button workflow'
        one_shot_latency_reported = $true
        persistent_latency_reported = $true
        process_restart_count_reduced = $processReduced
        average_step_latency_reported = $true
        p95_step_latency_reported = $p95Reported
        persistent_session_improvement_explained = $latencyGateMet
        average_step_improvement_percent = $improvementPct
        one_shot_baseline = $baseline
        persistent_session = $persistent
        persistent_dispatch_result = $dispatchResultPath
        steps_json = $stepsPath
    }
    $report | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $LatencyJson -Encoding UTF8

    @(
        '# v6.2.0 Latency Report',
        '',
        "- Status: $($report.status)",
        '- Workflow: TestWindow 10-step field/type/verify/button workflow',
        "- one-shot total_sequence_ms: $($baseline.total_sequence_ms)",
        "- one-shot average_step_ms: $($baseline.average_step_ms)",
        "- one-shot p50_step_ms: $($baseline.p50_step_ms)",
        "- one-shot p95_step_ms: $($baseline.p95_step_ms)",
        "- one-shot process_restart_count: $($baseline.process_restart_count)",
        "- persistent total_sequence_ms: $($persistent.total_sequence_ms)",
        "- persistent average_step_ms: $($persistent.average_step_ms)",
        "- persistent p50_step_ms: $($persistent.p50_step_ms)",
        "- persistent p95_step_ms: $($persistent.p95_step_ms)",
        "- persistent process_restart_count: $($persistent.process_restart_count)",
        "- process_restart_count_reduced: $processReduced",
        "- average_step_improvement_percent: $improvementPct",
        "- persistent_session_improvement_explained: $latencyGateMet",
        '',
        'The comparison uses the same controlled local TestWindow workflow. The persistent path keeps the sequence inside one Runtime process and reuses session/window binding, observe state, and locator cache policy where valid. HumanMode behavior is not changed; the benchmark uses explicit instant diagnostic movement in both modes to isolate process/session overhead.'
    ) | Set-Content -LiteralPath $LatencyMd -Encoding UTF8

    if (-not $latencyGateMet) {
        throw 'BLOCKED_LATENCY_GATE_NOT_MET'
    }

    Write-Output 'RUNTIME_SESSION_LATENCY_BENCHMARK_PASS'
}
finally {
    if ($proc -and !$proc.HasExited) {
        $proc.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (!$proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    }
}
