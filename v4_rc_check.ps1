param(
    [string]$Root = '',
    [switch]$Help,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\v4_rc_check.ps1 [-Root <path>] [-SkipBuild]'
    Write-Host 'Runs v4.7 Hybrid Perception Release Candidate checks and writes artifacts/dev4.7.0.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$Artifacts = Join-Path $Root 'artifacts\dev4.7.0'
$LogRoot = Join-Path $Artifacts 'logs'
$ReportPath = Join-Path $Artifacts 'v4_release_candidate_report.md'
$SummaryPath = Join-Path $Artifacts 'v4_release_candidate_summary.json'
$WinAgent = Join-Path $Root 'bin\winagent.exe'

New-Item -ItemType Directory -Force -Path $Artifacts,$LogRoot | Out-Null
Remove-Item -LiteralPath $ReportPath,$SummaryPath -ErrorAction SilentlyContinue

$Results = New-Object System.Collections.Generic.List[object]

function Stop-TestWindow {
    Get-Process TestWindow -ErrorAction SilentlyContinue | ForEach-Object {
        $_.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 250
        if (!$_.HasExited) { Stop-Process -Id $_.Id -Force }
    }
}

function Get-SafeName {
    param([string]$Name)
    return ($Name -replace '[^A-Za-z0-9_.-]', '_')
}

function Invoke-RcCommand {
    param(
        [string]$Name,
        [string]$Command,
        [scriptblock]$Action,
        [scriptblock]$SkipDetector = $null
    )

    $logPath = Join-Path $LogRoot ("{0}.log" -f (Get-SafeName $Name))
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $output = @()
    $exitCode = 0
    $failed = $false
    try {
        Stop-TestWindow
        $output = & $Action 2>&1
        $exitCode = $LASTEXITCODE
        if ($null -eq $exitCode) { $exitCode = 0 }
    } catch {
        $failed = $true
        $exitCode = 1
        $output += $_.Exception.Message
    }
    $sw.Stop()
    $text = ($output | Out-String).Trim()
    @(
        "Command: $Command",
        "ExitCode: $exitCode",
        "DurationMs: $([int]$sw.ElapsedMilliseconds)",
        '',
        $text
    ) | Set-Content -Encoding UTF8 -LiteralPath $logPath

    $status = 'PASS'
    $reason = ''
    if ($SkipDetector) {
        $reason = & $SkipDetector $exitCode $text
        if ($reason) { $status = 'SKIPPED' }
    }
    if ($status -ne 'SKIPPED' -and ($failed -or $exitCode -ne 0)) {
        $status = 'FAIL'
        $reason = "exit=$exitCode"
    }

    $Results.Add([pscustomobject]@{
        name = $Name
        status = $status
        command = $Command
        duration_ms = [int]$sw.ElapsedMilliseconds
        log = $logPath
        reason = $reason
    }) | Out-Null
    if ($reason) { Write-Host "$status`: $Name - $reason" } else { Write-Host "$status`: $Name" }
}

function Invoke-JsonParseCheck {
    $jsonFiles = Get-ChildItem -LiteralPath (Join-Path $Root 'profiles') -Recurse -Filter '*.json'
    foreach ($file in $jsonFiles) {
        Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json | Out-Null
    }
    Get-Content -Raw -LiteralPath (Join-Path $Root 'config\safety_manifest.json') | ConvertFrom-Json | Out-Null
    "Parsed $($jsonFiles.Count) profile/schema JSON files and config/safety_manifest.json."
}

function Invoke-MarkdownFenceCheck {
    $mdFiles = Get-ChildItem -LiteralPath $Root -Recurse -Filter '*.md' |
        Where-Object {
            $_.FullName -notmatch '\\artifacts\\' -and
            $_.FullName -notmatch '\\bin\\' -and
            $_.FullName -notmatch '\\dist\\'
        }
    $bad = @()
    foreach ($file in $mdFiles) {
        $ticks = @(Select-String -LiteralPath $file.FullName -Pattern '^\s*```').Count
        if (($ticks % 2) -ne 0) { $bad += $file.FullName }
    }
    if ($bad.Count -gt 0) {
        throw "Unclosed Markdown fences: $($bad -join ', ')"
    }
    "Checked $($mdFiles.Count) Markdown files for closed fenced code blocks."
}

function Invoke-CommandHelpCheck {
    if (!(Test-Path -LiteralPath $WinAgent)) { throw "Missing $WinAgent. Run build first." }
    $version = & $WinAgent version | ConvertFrom-Json
    if ($version.data.version -ne '4.7.0') {
        throw "Expected runtime version 4.7.0, got $($version.data.version)."
    }
    $dogfoodHelp = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'v4_visual_dogfood.ps1') -Root $Root -Help
    $rcHelp = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'v4_rc_check.ps1') -Root $Root -Help 2>$null
    "winagent version OK. v4_visual_dogfood help lines: $(@($dogfoodHelp).Count). v4_rc_check help lines: $(@($rcHelp).Count)."
}

if (-not $SkipBuild) {
    Invoke-RcCommand -Name 'build' -Command (Join-Path $Root 'build.ps1') -Action {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'build.ps1') -Root $Root
    }
}

Invoke-RcCommand -Name 'script_lint' -Command (Join-Path $Root 'script_lint.ps1') -Action {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'script_lint.ps1') -Root $Root
}
Invoke-RcCommand -Name 'observe2_provider_selftest' -Command (Join-Path $Root 'observe2_provider_selftest.ps1') -Action {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'observe2_provider_selftest.ps1') -Root $Root
}
Invoke-RcCommand -Name 'observe_loop_selftest' -Command (Join-Path $Root 'observe_loop_selftest.ps1') -Action {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'observe_loop_selftest.ps1') -Root $Root
}
Invoke-RcCommand -Name 'latency_benchmark' -Command (Join-Path $Root 'latency_benchmark.ps1') -Action {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'latency_benchmark.ps1') -Root $Root
}
Invoke-RcCommand -Name 'dynamic_ui_recovery_selftest' -Command (Join-Path $Root 'dynamic_ui_recovery_selftest.ps1') -Action {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'dynamic_ui_recovery_selftest.ps1') -Root $Root
}
Invoke-RcCommand -Name 'app_profile_selftest' -Command (Join-Path $Root 'app_profile_selftest.ps1') -Action {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'app_profile_selftest.ps1') -Root $Root
}
Invoke-RcCommand -Name 'v4_visual_dogfood' -Command (Join-Path $Root 'v4_visual_dogfood.ps1') -Action {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'v4_visual_dogfood.ps1') -Root $Root -SkipBuild
}
Invoke-RcCommand -Name 'safety_manifest_selftest' -Command (Join-Path $Root 'safety_manifest_selftest.ps1') -Action {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'safety_manifest_selftest.ps1') -Root $Root -SkipBuild
}
Invoke-RcCommand -Name 'public_repo_check' -Command (Join-Path $Root 'public_repo_check.ps1') -Action {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'public_repo_check.ps1') -Root $Root
}
Invoke-RcCommand -Name 'profile_json_parse' -Command 'Parse profiles/*.json and config/safety_manifest.json' -Action {
    Invoke-JsonParseCheck
}
Invoke-RcCommand -Name 'markdown_fence_check' -Command 'Check non-generated Markdown code fences' -Action {
    Invoke-MarkdownFenceCheck
}
Invoke-RcCommand -Name 'command_help_check' -Command 'winagent version and script help checks' -Action {
    Invoke-CommandHelpCheck
}
Invoke-RcCommand -Name 'rc_check' -Command (Join-Path $Root 'rc_check.ps1') -Action {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'rc_check.ps1') -Root $Root
}

Stop-TestWindow

$failed = @($Results | Where-Object { $_.status -eq 'FAIL' })
$overall = if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }
$version = if (Test-Path -LiteralPath (Join-Path $Root 'VERSION')) { (Get-Content -Raw -LiteralPath (Join-Path $Root 'VERSION')).Trim() } else { 'unknown' }
$passCount = ($Results | Where-Object { $_.status -eq 'PASS' } | Measure-Object).Count
$failCount = ($Results | Where-Object { $_.status -eq 'FAIL' } | Measure-Object).Count
$skippedCount = ($Results | Where-Object { $_.status -eq 'SKIPPED' } | Measure-Object).Count

$evidence = [ordered]@{
    v4_1_provider = 'artifacts/dev4.1.0/observe2_provider_selftest_report.md'
    v4_2_observe_loop = 'artifacts/dev4.2.0/observe_loop_selftest_report.md'
    v4_3_latency = 'artifacts/dev4.3.0/latency/latency_summary.md'
    v4_4_dynamic_recovery = 'artifacts/dev4.4.0/dynamic_ui_recovery_selftest_report.md'
    v4_5_app_profiles = 'artifacts/dev4.5.0/app_profile_selftest_report.md'
    v4_6_visual_dogfood = 'artifacts/dev4.6.0/dogfood_report.md'
    v4_7_rc_report = 'artifacts/dev4.7.0/v4_release_candidate_report.md'
}

$summary = [pscustomobject][ordered]@{
    version = $version
    generated_at = (Get-Date).ToString('s')
    overall = $overall
    pass = $passCount
    fail = $failCount
    skipped = $skippedCount
    results = @($Results.ToArray())
    evidence = [pscustomobject]$evidence
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $SummaryPath

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# DesktopVisual v4.7.0 Hybrid Perception Release Candidate Report')
$lines.Add('')
$lines.Add("- Overall result: $overall")
$lines.Add("- Version: $version")
$lines.Add("- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$lines.Add("- Summary JSON: $SummaryPath")
$lines.Add('')
$lines.Add('## Positioning')
$lines.Add('')
$lines.Add('- v4.x is a Hybrid Screen Perception Runtime.')
$lines.Add('- v4.x provides ScreenFrame, ElementGraph, LocatorCandidate, SceneState, ChangeEvent, observe2, Screen Delta, ROI OCR, Perception Cache, provider-ready visual sources, Dynamic UI Recovery, App Profiles, latency evidence, and local visual dogfood evidence.')
$lines.Add('- v4.x is not a complete autonomous Agent and does not claim complete understanding of arbitrary screens.')
$lines.Add('- v5 is the intended task-level continuous execution phase. v6 is the intended Runtime plus VLM/Agent semantic desktop intelligence phase.')
$lines.Add('')
$lines.Add('## RC Steps')
$lines.Add('')
$lines.Add('| step | status | duration_ms | reason | log |')
$lines.Add('|---|---|---:|---|---|')
foreach ($result in $Results) {
    $reason = ([string]$result.reason) -replace '\|','/'
    $log = ([string]$result.log) -replace '\|','/'
    $lines.Add("| $($result.name) | $($result.status) | $($result.duration_ms) | $reason | ``$log`` |")
}
$lines.Add('')
$lines.Add('## Evidence Pack')
$lines.Add('')
foreach ($key in $evidence.Keys) {
    $path = Join-Path $Root $evidence[$key]
    $state = if ($key -eq 'v4_7_rc_report') { 'present' } elseif (Test-Path -LiteralPath $path) { 'present' } else { 'missing' }
    $lines.Add("- ${key}: $($evidence[$key]) [$state]")
}
$lines.Add('')
$lines.Add('## Safety Closure')
$lines.Add('')
$lines.Add('- Provider/Profile outputs remain candidates and metadata; they do not execute actions directly.')
$lines.Add('- Visual-only unresolved candidates are verified by selftests to stop with ACTION_BLOCKED_SEMANTIC_UNRESOLVED.')
$lines.Add('- Blocked Dynamic UI state is verified by selftests to route STOP and not VLM bypass.')
$lines.Add('- Public release preparation remains separate from D:\desktopvisual and must use D:\desktopvisual-release with restricted public permissions.')
$lines.Add('- Real exams, hiring assessments, certifications, proctored pages, rated contests, game cheating, captcha/anti-cheat bypass, payments, credentials, and account-security bypass remain outside public release permission.')
$lines.Add('')
$lines.Add('## Release Hygiene')
$lines.Add('')
$lines.Add('- `public_repo_check.ps1` verifies required docs, `.gitignore` coverage, release-tree wording, and public-release positioning.')
$lines.Add('- Release packaging is not run unless explicitly requested with release packaging flags.')
$lines.Add('- Model weights, browser profiles, build outputs, and large generated artifacts are not part of the default public package path.')
$lines | Set-Content -Encoding UTF8 -LiteralPath $ReportPath

Write-Host "v4 release candidate report: $ReportPath"
Write-Host "v4 release candidate summary: $SummaryPath"
Write-Host "Overall result: $overall"

if ($failed.Count -gt 0) { exit 1 }
exit 0
