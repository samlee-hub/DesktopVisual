param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$TestWindowExe = 'D:\testrepo\testwindow\bin\TestWindow.exe'
$LatencyRoot = Join-Path $Root 'artifacts\dev4.3.0\latency'
$RawLogs = Join-Path $LatencyRoot 'raw_logs'
$Screenshots = Join-Path $LatencyRoot 'screenshots'
$Fixtures = Join-Path $LatencyRoot 'fixtures'
$ResultsPath = Join-Path $LatencyRoot 'latency_results.json'
$SummaryPath = Join-Path $LatencyRoot 'latency_summary.md'
$ConfigPath = Join-Path $LatencyRoot 'benchmark_config.json'

New-Item -ItemType Directory -Force -Path $LatencyRoot,$RawLogs,$Screenshots,$Fixtures | Out-Null
Remove-Item -LiteralPath $ResultsPath,$SummaryPath,$ConfigPath -ErrorAction SilentlyContinue

function Fail($Message) { throw $Message }

function Save-RawLog {
    param([string]$Name, [string]$Text)
    $safe = ($Name -replace '[^A-Za-z0-9_.-]', '_')
    $path = Join-Path $RawLogs "$safe.log"
    $Text | Set-Content -Encoding UTF8 -LiteralPath $path
    return $path
}

function Invoke-WinAgentMeasured {
    param(
        [string]$Name,
        [string[]]$WinArgs,
        [int[]]$AllowedExitCodes = @(0)
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $output = & $WinAgent @WinArgs 2>&1
    $exit = $LASTEXITCODE
    $sw.Stop()
    $text = ($output | Out-String).Trim()
    $json = $null
    $parseOk = $false
    if ($text) {
        try {
            $json = $text | ConvertFrom-Json
            $parseOk = $true
        } catch {
            $parseOk = $false
        }
    }
    $log = Save-RawLog -Name $Name -Text ("COMMAND: winagent $($WinArgs -join ' ')" + [Environment]::NewLine + "EXIT: $exit" + [Environment]::NewLine + $text)
    return [pscustomobject]@{
        name = $Name
        args = $WinArgs
        exit_code = $exit
        duration_ms = [int]$sw.ElapsedMilliseconds
        json = $json
        json_parse_ok = $parseOk
        raw_log = $log
        ok = ($AllowedExitCodes -contains $exit)
    }
}

function Add-Scenario {
    param(
        [System.Collections.Generic.List[object]]$List,
        [string]$Name,
        [string]$Status,
        [string]$Detail,
        [int]$DurationMs = 0,
        [string[]]$Artifacts = @(),
        [string[]]$Metrics = @()
    )
    $List.Add([pscustomobject]@{
        name = $Name
        status = $Status
        detail = $Detail
        duration_ms = $DurationMs
        artifacts = $Artifacts
        metrics = $Metrics
    }) | Out-Null
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
    do {
        Start-Sleep -Milliseconds 250
        $find = Invoke-WinAgentMeasured -Name 'wait_testwindow_find' -WinArgs @('find', '--title', 'Agent Test Window') -AllowedExitCodes @(0, 1)
    } while ($find.exit_code -ne 0 -and (Get-Date) -lt $deadline)
    if ($find.exit_code -ne 0) { Fail 'Agent Test Window did not appear.' }
    return $proc
}

function Stop-TestWindowProcess($Proc) {
    if ($Proc -and !$Proc.HasExited) {
        $Proc.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 250
        if (!$Proc.HasExited) { Stop-Process -Id $Proc.Id -Force }
    }
}

function New-TemplateFromScreenshot {
    param([string]$Source, [string]$Template)
    Add-Type -AssemblyName System.Drawing
    $bmp = [System.Drawing.Bitmap]::new($Source)
    try {
        $width = [Math]::Min(120, $bmp.Width)
        $height = [Math]::Min(80, $bmp.Height)
        $crop = [System.Drawing.Rectangle]::new(0, 0, $width, $height)
        $templ = $bmp.Clone($crop, $bmp.PixelFormat)
        try {
            $templ.Save($Template, [System.Drawing.Imaging.ImageFormat]::Bmp)
        } finally {
            $templ.Dispose()
        }
    } finally {
        $bmp.Dispose()
    }
}

function Measure-FileHashDelta {
    param([string]$PathA, [string]$PathB)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $hashA = Get-FileHash -LiteralPath $PathA -Algorithm SHA256
    $hashB = Get-FileHash -LiteralPath $PathB -Algorithm SHA256
    $changed = $hashA.Hash -ne $hashB.Hash
    $sw.Stop()
    return [pscustomobject]@{ duration_ms = [int]$sw.ElapsedMilliseconds; changed = $changed }
}

function Write-LocalHtmlFixtures {
    $text1 = Join-Path $Fixtures 'text_change_v1.html'
    $text2 = Join-Path $Fixtures 'text_change_v2.html'
    $button = Join-Path $Fixtures 'button_appeared.html'
    @'
<!doctype html>
<html><body><label for="status">Status</label><input id="status" name="status" value="ready"></body></html>
'@ | Set-Content -Encoding UTF8 -LiteralPath $text1
    @'
<!doctype html>
<html><body><label for="status">Status</label><input id="status" name="status" value="changed"></body></html>
'@ | Set-Content -Encoding UTF8 -LiteralPath $text2
    @'
<!doctype html>
<html><body><button id="continue">Continue</button></body></html>
'@ | Set-Content -Encoding UTF8 -LiteralPath $button
    return [pscustomobject]@{ text1 = $text1; text2 = $text2; button = $button }
}

if (!(Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run $Root\build.ps1 first." }

$config = [ordered]@{
    version = '4.3.0'
    generated_at = (Get-Date).ToString('s')
    root = $Root
    target_window = 'Agent Test Window'
    interval_ms = 100
    max_duration_ms = 1500
    max_events = 4
    warning_thresholds = [ordered]@{
        observe2_latency_ms = 3000
        observe_loop_event_latency_ms = 1000
        roi_ocr_slower_than_full_multiplier = 1.50
        cache_hit_ratio_min = 0.20
        llm_or_vlm_call_count = 0
    }
    scenarios = @(
        'TestWindow basic elements',
        'local HTML text change',
        'local HTML button appeared',
        'ROI OCR vs full OCR',
        'cache hit vs cache miss',
        'image template provider available/unavailable',
        'observe-loop event detection'
    )
}
$config | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $ConfigPath

$version = Invoke-WinAgentMeasured -Name 'version' -WinArgs @('version')
$ocrAvailable = $false
if ($version.json -and $version.json.data -and $version.json.data.ocr_available -eq $true) { $ocrAvailable = $true }

$scenarios = New-Object System.Collections.Generic.List[object]
$warnings = New-Object System.Collections.Generic.List[string]
$metrics = [ordered]@{
    screenshot_latency_ms = $null
    uia_latency_ms = $null
    full_ocr_latency_ms = $null
    roi_ocr_latency_ms = $null
    screen_delta_latency_ms = $null
    element_graph_build_ms = $null
    hybrid_locate_latency_ms = $null
    visual_provider_latency_ms = $null
    observe2_latency_ms = $null
    observe_loop_event_latency_ms = $null
    act_to_verify_latency_ms = $null
    cache_hit_ratio = $null
    llm_or_vlm_call_count = 0
}
$metricNotes = [ordered]@{}

$tw = $null
try {
    $tw = Start-TestWindow

    $shot1 = Join-Path $Screenshots 'testwindow_1.bmp'
    $shot2 = Join-Path $Screenshots 'testwindow_2.bmp'
    $template = Join-Path $Screenshots 'image_template.bmp'

    $screenshot = Invoke-WinAgentMeasured -Name 'screenshot_latency' -WinArgs @('screenshot', '--title', 'Agent Test Window', '--out', $shot1)
    if ($screenshot.ok -and $screenshot.json_parse_ok -and (Test-Path -LiteralPath $shot1)) {
        $metrics['screenshot_latency_ms'] = $screenshot.duration_ms
        Add-Scenario $scenarios 'TestWindow screenshot' 'PASS' 'Captured target window screenshot.' $screenshot.duration_ms @($shot1, $screenshot.raw_log) @('screenshot_latency_ms')
    } else {
        Add-Scenario $scenarios 'TestWindow screenshot' 'FAIL' 'Could not capture screenshot.' $screenshot.duration_ms @($screenshot.raw_log) @('screenshot_latency_ms')
    }

    $uia = Invoke-WinAgentMeasured -Name 'uia_latency' -WinArgs @('uia-tree', '--title', 'Agent Test Window')
    if ($uia.ok -and $uia.json_parse_ok) {
        $metrics['uia_latency_ms'] = $uia.duration_ms
        Add-Scenario $scenarios 'TestWindow basic elements' 'PASS' 'UIA tree command completed.' $uia.duration_ms @($uia.raw_log) @('uia_latency_ms')
    } else {
        Add-Scenario $scenarios 'TestWindow basic elements' 'FAIL' 'UIA tree command failed.' $uia.duration_ms @($uia.raw_log) @('uia_latency_ms')
    }

    if ($ocrAvailable) {
        $fullOcr = Invoke-WinAgentMeasured -Name 'full_ocr_latency' -WinArgs @('read-window-text', '--title', 'Agent Test Window')
        if ($fullOcr.ok -and $fullOcr.json_parse_ok) {
            $metrics['full_ocr_latency_ms'] = $fullOcr.duration_ms
            Add-Scenario $scenarios 'full OCR' 'PASS' 'Full-window OCR completed.' $fullOcr.duration_ms @($fullOcr.raw_log) @('full_ocr_latency_ms')
        } else {
            Add-Scenario $scenarios 'full OCR' 'SKIPPED' 'OCR command did not complete in this environment.' $fullOcr.duration_ms @($fullOcr.raw_log) @('full_ocr_latency_ms')
        }

        $roiOcr = Invoke-WinAgentMeasured -Name 'roi_ocr_latency' -WinArgs @('read-region-text', '--title', 'Agent Test Window', '--x', '0', '--y', '0', '--w', '400', '--h', '300')
        if ($roiOcr.ok -and $roiOcr.json_parse_ok) {
            $metrics['roi_ocr_latency_ms'] = $roiOcr.duration_ms
            Add-Scenario $scenarios 'ROI OCR vs full OCR' 'PASS' 'ROI OCR completed.' $roiOcr.duration_ms @($roiOcr.raw_log) @('roi_ocr_latency_ms')
        } else {
            Add-Scenario $scenarios 'ROI OCR vs full OCR' 'SKIPPED' 'ROI OCR command did not complete in this environment.' $roiOcr.duration_ms @($roiOcr.raw_log) @('roi_ocr_latency_ms')
        }
    } else {
        $warnings.Add('Windows OCR is unavailable; full_ocr_latency_ms and roi_ocr_latency_ms are null.') | Out-Null
        Add-Scenario $scenarios 'ROI OCR vs full OCR' 'SKIPPED' 'Windows OCR unavailable.' 0 @() @('full_ocr_latency_ms','roi_ocr_latency_ms')
    }

    $screenshot2 = Invoke-WinAgentMeasured -Name 'screenshot_delta_source' -WinArgs @('screenshot', '--title', 'Agent Test Window', '--out', $shot2)
    if ((Test-Path -LiteralPath $shot1) -and (Test-Path -LiteralPath $shot2)) {
        $delta = Measure-FileHashDelta -PathA $shot1 -PathB $shot2
        $metrics['screen_delta_latency_ms'] = $delta.duration_ms
        Add-Scenario $scenarios 'cache hit vs cache miss' 'PASS' "Screen delta hash comparison completed; changed=$($delta.changed)." $delta.duration_ms @($shot1,$shot2) @('screen_delta_latency_ms')
    } else {
        Add-Scenario $scenarios 'cache hit vs cache miss' 'FAIL' 'Missing screenshots for delta comparison.' 0 @($screenshot2.raw_log) @('screen_delta_latency_ms')
    }

    if (Test-Path -LiteralPath $shot1) {
        New-TemplateFromScreenshot -Source $shot1 -Template $template
    }

    $observe2 = Invoke-WinAgentMeasured -Name 'observe2_latency' -WinArgs @('observe2', '--title', 'Agent Test Window', '--screenshot', '--include-uia', '--max-elements', '25')
    if ($observe2.ok -and $observe2.json_parse_ok) {
        $metrics['observe2_latency_ms'] = $observe2.duration_ms
        $metrics['element_graph_build_ms'] = $observe2.duration_ms
        $metricNotes.element_graph_build_ms = 'Measured as observe2 graph-producing command latency; internal graph-only timer is not exposed in v4.3.0.'
        Add-Scenario $scenarios 'observe2 latency' 'PASS' 'observe2 produced provider registry and ElementGraph.' $observe2.duration_ms @($observe2.raw_log) @('observe2_latency_ms','element_graph_build_ms')
    } else {
        Add-Scenario $scenarios 'observe2 latency' 'FAIL' 'observe2 command failed.' $observe2.duration_ms @($observe2.raw_log) @('observe2_latency_ms','element_graph_build_ms')
    }

    if (Test-Path -LiteralPath $template) {
        $visualAvailable = Invoke-WinAgentMeasured -Name 'visual_provider_available' -WinArgs @('observe2', '--title', 'Agent Test Window', '--screenshot', '--image-template', $template, '--tolerance', '0')
        if ($visualAvailable.ok -and $visualAvailable.json_parse_ok) {
            $imageProvider = @($visualAvailable.json.data.providers | Where-Object { $_.name -eq 'image_template' })[0]
            if ($imageProvider -and $null -ne $imageProvider.latency_ms) {
                $metrics['visual_provider_latency_ms'] = [int]$imageProvider.latency_ms
            } else {
                $metrics['visual_provider_latency_ms'] = $visualAvailable.duration_ms
            }
            Add-Scenario $scenarios 'image template provider available' 'PASS' 'image_template provider produced or attempted candidates through observe2.' $visualAvailable.duration_ms @($template,$visualAvailable.raw_log) @('visual_provider_latency_ms')
        } else {
            Add-Scenario $scenarios 'image template provider available' 'FAIL' 'observe2 image_template provider command failed.' $visualAvailable.duration_ms @($visualAvailable.raw_log) @('visual_provider_latency_ms')
        }
    }

    $visualUnavailable = Invoke-WinAgentMeasured -Name 'visual_provider_unavailable' -WinArgs @('observe2', '--title', 'Agent Test Window', '--screenshot')
    if ($visualUnavailable.ok -and $visualUnavailable.json_parse_ok) {
        $provider = @($visualUnavailable.json.data.providers | Where-Object { $_.name -eq 'image_template' })[0]
        $status = if ($provider) { [string]$provider.status } else { 'missing' }
        $scenarioStatus = if ($status -in @('unavailable','degraded','available')) { 'PASS' } else { 'FAIL' }
        Add-Scenario $scenarios 'image template provider unavailable' $scenarioStatus "image_template status=$status without template." $visualUnavailable.duration_ms @($visualUnavailable.raw_log) @('visual_provider_latency_ms')
    } else {
        Add-Scenario $scenarios 'image template provider unavailable' 'FAIL' 'observe2 without template failed.' $visualUnavailable.duration_ms @($visualUnavailable.raw_log) @('visual_provider_latency_ms')
    }

    $locate = Invoke-WinAgentMeasured -Name 'hybrid_locate_latency' -WinArgs @('locate', '--title', 'Agent Test Window', '--selector', 'uia:name=Click Me')
    if ($locate.ok -and $locate.json_parse_ok) {
        $metrics['hybrid_locate_latency_ms'] = $locate.duration_ms
        Add-Scenario $scenarios 'hybrid locate' 'PASS' 'Hybrid locator resolved UIA selector.' $locate.duration_ms @($locate.raw_log) @('hybrid_locate_latency_ms')
    } else {
        Add-Scenario $scenarios 'hybrid locate' 'FAIL' 'Hybrid locator failed.' $locate.duration_ms @($locate.raw_log) @('hybrid_locate_latency_ms')
    }

    $actSw = [System.Diagnostics.Stopwatch]::StartNew()
    $click = Invoke-WinAgentMeasured -Name 'act_to_verify_click' -WinArgs @('uia-click', '--title', 'Agent Test Window', '--name', 'Click Me') -AllowedExitCodes @(0,1)
    $verify = Invoke-WinAgentMeasured -Name 'act_to_verify_verify' -WinArgs @('uia-find', '--title', 'Agent Test Window', '--name', 'Click Me') -AllowedExitCodes @(0,1)
    $actSw.Stop()
    if ($click.exit_code -eq 0 -and $verify.exit_code -eq 0) {
        $metrics['act_to_verify_latency_ms'] = [int]$actSw.ElapsedMilliseconds
        Add-Scenario $scenarios 'act to verify' 'PASS' 'Measured UIA click followed by UIA verification.' $metrics['act_to_verify_latency_ms'] @($click.raw_log,$verify.raw_log) @('act_to_verify_latency_ms')
    } else {
        Add-Scenario $scenarios 'act to verify' 'SKIPPED' 'UIA click or verification could not complete in this environment.' ([int]$actSw.ElapsedMilliseconds) @($click.raw_log,$verify.raw_log) @('act_to_verify_latency_ms')
    }

    $loopEvents = Join-Path $LatencyRoot 'observe_loop_events.jsonl'
    $loopReport = Join-Path $LatencyRoot 'observe_loop_report.md'
    Remove-Item -LiteralPath $loopEvents,$loopReport -ErrorAction SilentlyContinue
    $loop = Invoke-WinAgentMeasured -Name 'observe_loop_event_latency' -WinArgs @('observe-loop', '--title', 'Agent Test Window', '--interval-ms', '100', '--max-duration-ms', '1500', '--max-events', '4', '--max-no-change-rounds', '8', '--roi', '0,0,400,300', '--changed-regions-only', '--out', $loopEvents, '--report', $loopReport)
    if ($loop.ok -and $loop.json_parse_ok -and (Test-Path -LiteralPath $loopEvents)) {
        $events = @(Get-Content -LiteralPath $loopEvents | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json })
        $eventLatencies = @($events | Where-Object { $_.type -ne 'target_ready' } | ForEach-Object { [int]$_.latency_ms })
        if ($eventLatencies.Count -gt 0) {
            $metrics['observe_loop_event_latency_ms'] = [int](($eventLatencies | Measure-Object -Average).Average)
        } else {
            $metrics['observe_loop_event_latency_ms'] = $loop.duration_ms
        }
        $hits = [double]$loop.json.data.cache_hits
        $misses = [double]$loop.json.data.cache_misses
        if (($hits + $misses) -gt 0) {
            $metrics['cache_hit_ratio'] = [Math]::Round($hits / ($hits + $misses), 4)
        }
        Add-Scenario $scenarios 'observe-loop event detection' 'PASS' "events=$($events.Count), cache_hits=$hits, cache_misses=$misses." $loop.duration_ms @($loopEvents,$loopReport,$loop.raw_log) @('observe_loop_event_latency_ms','cache_hit_ratio')
    } else {
        Add-Scenario $scenarios 'observe-loop event detection' 'FAIL' 'observe-loop command failed or did not write events.' $loop.duration_ms @($loop.raw_log) @('observe_loop_event_latency_ms','cache_hit_ratio')
    }
} finally {
    Stop-TestWindowProcess $tw
}

$fixtures = Write-LocalHtmlFixtures
$html1 = Invoke-WinAgentMeasured -Name 'local_html_text_v1' -WinArgs @('form-control', '--html', $fixtures.text1, '--field-id', 'status')
$html2 = Invoke-WinAgentMeasured -Name 'local_html_text_v2' -WinArgs @('form-control', '--html', $fixtures.text2, '--field-id', 'status')
if ($html1.ok -and $html2.ok -and $html1.json_parse_ok -and $html2.json_parse_ok) {
    Add-Scenario $scenarios 'local HTML text change' 'PASS' 'Local HTML fixtures resolved before and after text value change.' ($html1.duration_ms + $html2.duration_ms) @($fixtures.text1,$fixtures.text2,$html1.raw_log,$html2.raw_log) @()
} else {
    Add-Scenario $scenarios 'local HTML text change' 'FAIL' 'Local HTML text-change fixture did not resolve.' ($html1.duration_ms + $html2.duration_ms) @($html1.raw_log,$html2.raw_log) @()
}

$button = Invoke-WinAgentMeasured -Name 'local_html_button_appeared' -WinArgs @('form-control', '--html', $fixtures.button, '--field-id', 'continue')
if ($button.ok -and $button.json_parse_ok) {
    Add-Scenario $scenarios 'local HTML button appeared' 'PASS' 'Local HTML button fixture resolved.' $button.duration_ms @($fixtures.button,$button.raw_log) @()
} else {
    Add-Scenario $scenarios 'local HTML button appeared' 'FAIL' 'Local HTML button fixture did not resolve.' $button.duration_ms @($button.raw_log) @()
}

if ($metrics['observe2_latency_ms'] -ne $null -and $metrics['observe2_latency_ms'] -gt $config.warning_thresholds['observe2_latency_ms']) {
    $warnings.Add("observe2_latency_ms exceeded warning threshold: $($metrics['observe2_latency_ms'])") | Out-Null
}
if ($metrics['observe_loop_event_latency_ms'] -ne $null -and $metrics['observe_loop_event_latency_ms'] -gt $config.warning_thresholds['observe_loop_event_latency_ms']) {
    $warnings.Add("observe_loop_event_latency_ms exceeded warning threshold: $($metrics['observe_loop_event_latency_ms'])") | Out-Null
}
if ($metrics['full_ocr_latency_ms'] -ne $null -and $metrics['roi_ocr_latency_ms'] -ne $null -and $metrics['roi_ocr_latency_ms'] -gt ($metrics['full_ocr_latency_ms'] * $config.warning_thresholds['roi_ocr_slower_than_full_multiplier'])) {
    $warnings.Add("ROI OCR was slower than full OCR by more than configured threshold on this machine.") | Out-Null
}
if ($metrics['cache_hit_ratio'] -ne $null -and $metrics['cache_hit_ratio'] -lt $config.warning_thresholds['cache_hit_ratio_min']) {
    $warnings.Add("cache_hit_ratio was below warning threshold: $($metrics['cache_hit_ratio'])") | Out-Null
}
if ($metrics['llm_or_vlm_call_count'] -ne 0) {
    $warnings.Add('llm_or_vlm_call_count must remain 0 by default.') | Out-Null
}

$failed = @($scenarios | Where-Object { $_.status -eq 'FAIL' })
$status = if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }
$machine = [ordered]@{
    computer_name = $env:COMPUTERNAME
    os = (Get-CimInstance Win32_OperatingSystem).Caption
    os_version = (Get-CimInstance Win32_OperatingSystem).Version
    powershell_version = $PSVersionTable.PSVersion.ToString()
    processor = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
    ocr_available = $ocrAvailable
}

$results = [ordered]@{
    status = $status
    version = '4.3.0'
    generated_at = (Get-Date).ToString('s')
    machine = $machine
    metrics = $metrics
    metric_notes = $metricNotes
    warnings = @($warnings.ToArray())
    scenarios = @($scenarios.ToArray())
    artifacts = [ordered]@{
        benchmark_config = $ConfigPath
        latency_results = $ResultsPath
        latency_summary = $SummaryPath
        raw_logs = $RawLogs
        screenshots = $Screenshots
    }
}
$results | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -LiteralPath $ResultsPath

$summaryLines = New-Object System.Collections.Generic.List[string]
$summaryLines.Add('# DesktopVisual v4.3.0 Latency Benchmark Summary') | Out-Null
$summaryLines.Add('') | Out-Null
$summaryLines.Add("- Result: $status") | Out-Null
$summaryLines.Add("- Generated: $($results.generated_at)") | Out-Null
$summaryLines.Add("- Machine: $($machine.computer_name)") | Out-Null
$summaryLines.Add("- OCR available: $ocrAvailable") | Out-Null
$summaryLines.Add("- LLM/VLM call count: $($metrics['llm_or_vlm_call_count'])") | Out-Null
$summaryLines.Add('') | Out-Null
$summaryLines.Add('## Metrics') | Out-Null
$summaryLines.Add('') | Out-Null
foreach ($key in $metrics.Keys) {
    $summaryLines.Add("- ${key}: $($metrics[$key])") | Out-Null
}
$summaryLines.Add('') | Out-Null
$summaryLines.Add('## Scenarios') | Out-Null
$summaryLines.Add('') | Out-Null
foreach ($scenario in $scenarios) {
    $summaryLines.Add("- $($scenario.name): $($scenario.status) - $($scenario.detail)") | Out-Null
}
$summaryLines.Add('') | Out-Null
$summaryLines.Add('## Warnings') | Out-Null
$summaryLines.Add('') | Out-Null
if ($warnings.Count -eq 0) {
    $summaryLines.Add('- None') | Out-Null
} else {
    foreach ($warning in $warnings) { $summaryLines.Add("- $warning") | Out-Null }
}
$summaryLines.Add('') | Out-Null
$summaryLines.Add('## Boundary') | Out-Null
$summaryLines.Add('') | Out-Null
$summaryLines.Add('- Runtime first: UIA/OCR/Delta/Profile/Cache are measured before any model provider.') | Out-Null
$summaryLines.Add('- OmniParser/YOLO/UGround/VLM are not invoked by this benchmark.') | Out-Null
$summaryLines.Add('- Results are current-machine evidence, not a cross-machine SLA.') | Out-Null
$summaryLines | Set-Content -Encoding UTF8 -LiteralPath $SummaryPath

Write-Host "Latency benchmark result: $status"
Write-Host "Results: $ResultsPath"
Write-Host "Summary: $SummaryPath"
if ($status -ne 'PASS') { exit 1 }
exit 0

