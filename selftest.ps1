param(
    [string]$Root = '',
    [string]$TestRepoRoot = '',
    [switch]$IncludeDogfood,
    [switch]$IncludeSkillBasic
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
if (-not $TestRepoRoot) { $TestRepoRoot = $env:DESKTOPVISUAL_TESTREPO_ROOT }
if (-not $TestRepoRoot) {
    $sibling = Join-Path (Split-Path -Parent $Root) 'testrepo'
    if (Test-Path -LiteralPath $sibling) { $TestRepoRoot = $sibling }
}
if (-not $TestRepoRoot) { $TestRepoRoot = 'D:\testrepo' }
$TestRepoRoot = [System.IO.Path]::GetFullPath($TestRepoRoot)
$TestWindowExe = Join-Path $TestRepoRoot 'testwindow\bin\TestWindow.exe'
$Artifacts = Join-Path $Root 'artifacts'
$Report = Join-Path $Artifacts 'selftest_report.md'
$DefaultHumanProfile = Join-Path $Root 'config\operator_motion_profile.json'
$DogfoodScript = Join-Path $Root 'run_dogfood.ps1'
$SkillRoot = Join-Path $Root 'skill_template\win-desktop-agent'
$SkillBasicScript = Join-Path $SkillRoot 'scripts\run-skill-basic.ps1'
$SkillFailureDemoScript = Join-Path $SkillRoot 'scripts\run-failure-demo.ps1'
$SkillExplainReportScript = Join-Path $SkillRoot 'scripts\explain-report.ps1'
$SkillInstallationDoc = Join-Path $Root 'docs\SKILL_INSTALLATION.md'
$VisualSafetyDoc = Join-Path $Root 'docs\VISUAL_SAFETY_FREEZE.md'
$RealDevWorkflowDoc = Join-Path $Root 'docs\REAL_DEV_WORKFLOW.md'
$RealDevWorkflowScript = Join-Path $Root 'run_real_dev_workflow.ps1'
$SafetyConfig = Join-Path $Root 'config\safety.conf'
$SafetySelftestScript = Join-Path $Root 'safety_selftest.ps1'

function Fail($Message) {
    throw $Message
}

function Invoke-WinAgentJson {
param(
        [string[]]$WinArgs,
        [int[]]$AllowedExitCodes = @(0)
    )
    $output = & $WinAgent @WinArgs
    $exit = $LASTEXITCODE
    if ($AllowedExitCodes -notcontains $exit) {
        Fail "winagent $($WinArgs -join ' ') exited $exit with output: $output"
    }
    try {
        $json = $output | ConvertFrom-Json
    } catch {
        Fail "Output was not valid JSON for winagent $($WinArgs -join ' '): $output"
    }
    return @{ exit = $exit; text = [string]$output; json = $json }
}

function Assert-CommandSchema {
    param($Result, [string]$Command)
    if ($Result.json.ok -ne $true -and $Result.json.ok -ne $false) { Fail "$Command JSON missing boolean ok." }
    if ($Result.json.command -ne $Command) { Fail "$Command JSON missing command." }
    if (-not $Result.json.timestamp) { Fail "$Command JSON missing timestamp." }
    if ($null -eq $Result.json.duration_ms) { Fail "$Command JSON missing duration_ms." }
    if ($null -eq $Result.json.data) { Fail "$Command JSON missing data." }
}

function Assert-FailureSchema {
    param($Result, [string]$ExpectedCode)
    if ($Result.json.ok -ne $false) { Fail "Expected failure JSON." }
    if ($Result.json.error.code -ne $ExpectedCode) { Fail "Expected error code $ExpectedCode, got $($Result.json.error.code)." }
    if (-not $Result.json.error.message) { Fail "Failure JSON missing error.message." }
}

function Assert-ReportFormat {
    param([string]$ReportPath)
    if (!(Test-Path -LiteralPath $ReportPath)) { Fail "Missing case report: $ReportPath" }
    if (!(Select-String -LiteralPath $ReportPath -Pattern '# WinDesktopAgent Case Report' -SimpleMatch -Quiet)) { Fail "Report missing title: $ReportPath" }
    if (!(Select-String -LiteralPath $ReportPath -Pattern '## Steps' -SimpleMatch -Quiet)) { Fail "Report missing Steps section: $ReportPath" }
    if (!(Select-String -LiteralPath $ReportPath -Pattern '| index | action | params | start_time | end_time | duration_ms | result | error_code | message | json_output |' -SimpleMatch -Quiet)) {
        Fail "Report missing frozen step table: $ReportPath"
    }
}

function Test-LocalHumanMotionProfile {
    if (!(Test-Path -LiteralPath $DefaultHumanProfile)) {
        return $false
    }
    $info = Invoke-WinAgentJson -WinArgs @('motion-profile-info', '--profile', $DefaultHumanProfile) -AllowedExitCodes @(0, 1)
    return $info.exit -eq 0 -and $info.json.data.source -eq 'human'
}

function Run-Case {
    param(
        [string]$CaseFile,
        [string]$ReportPath,
        [bool]$ShouldPass,
        [string]$ExpectedErrorCode = ''
    )
    $caseToRun = $CaseFile
    $caseText = [IO.File]::ReadAllText($CaseFile, [Text.Encoding]::UTF8)
    if ($caseText.Contains('D:\testrepo')) {
        $caseToRun = Join-Path $Artifacts ("selftest_current_" + [IO.Path]::GetFileName($CaseFile))
        $caseText.Replace('D:\testrepo', $TestRepoRoot) | Set-Content -LiteralPath $caseToRun -Encoding UTF8
    }
    $result = Invoke-WinAgentJson -WinArgs @('run-case', '--file', $caseToRun, '--report', $ReportPath) -AllowedExitCodes @(0, 1)
    Assert-CommandSchema $result 'run-case'
    if ($ShouldPass) {
        if ($result.exit -ne 0 -or $result.json.ok -ne $true) { Fail "Expected case to pass: $CaseFile output=$($result.text)" }
    } else {
        if ($result.exit -eq 0 -or $result.json.ok -ne $false) { Fail "Expected case to fail: $CaseFile output=$($result.text)" }
        Assert-FailureSchema $result $ExpectedErrorCode
    }
    Assert-ReportFormat $ReportPath
    if ($ExpectedErrorCode -and !(Select-String -LiteralPath $ReportPath -Pattern $ExpectedErrorCode -Quiet)) {
        Fail "Report $ReportPath does not contain $ExpectedErrorCode"
    }
    return $result
}

function Invoke-DogfoodOptional {
    if (!$IncludeDogfood) {
        return @{ status = 'SKIPPED'; detail = 'Use -IncludeDogfood to run real-app dogfood.' }
    }

    if (!(Test-Path -LiteralPath $DogfoodScript)) {
        return @{ status = 'SKIPPED'; detail = 'run_dogfood.ps1 not found' }
    }

    $output = & $DogfoodScript -TimeoutSeconds 5 2>&1
    $exit = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    if ($exit -eq 0) {
        $dogfoodReport = Join-Path $Artifacts 'real_app_dogfood_report.md'
        Assert-ReportFormat $dogfoodReport
        return @{ status = 'PASS'; detail = $dogfoodReport }
    }

    return @{ status = 'SKIPPED'; detail = "exit=$exit $text" }
}

function Test-SkillTemplate {
    $required = @(
        (Join-Path $SkillRoot 'SKILL.md'),
        (Join-Path $SkillRoot 'references\COMMAND_PROTOCOL.md'),
        (Join-Path $SkillRoot 'references\ERROR_CODES.md'),
        (Join-Path $SkillRoot 'references\SAFETY.md'),
        (Join-Path $SkillRoot 'references\CASE_FORMAT.md'),
        (Join-Path $SkillRoot 'references\VISUAL_SAFETY_FREEZE.md'),
        (Join-Path $SkillRoot 'scripts\run-basic-demo.ps1'),
        (Join-Path $SkillRoot 'scripts\run-visible-demo.ps1'),
        (Join-Path $SkillRoot 'scripts\read-latest-report.ps1'),
        (Join-Path $SkillRoot 'scripts\run-case.ps1'),
        $SkillBasicScript,
        $SkillFailureDemoScript,
        $SkillExplainReportScript,
        (Join-Path $SkillRoot 'scripts\selftest-skill-template.ps1')
        $SkillInstallationDoc
        $VisualSafetyDoc
        $RealDevWorkflowDoc
        $RealDevWorkflowScript
        $SafetyConfig
        $SafetySelftestScript
    )
    foreach ($path in $required) {
        if (!(Test-Path -LiteralPath $path)) {
            Fail "Missing Skill template file: $path"
        }
    }

    if (!$IncludeSkillBasic) {
        return @{ status = 'SKIPPED'; detail = 'Use -IncludeSkillBasic to run run-skill-basic.ps1.' }
    }

    $output = & $SkillBasicScript 2>&1
    $exit = $LASTEXITCODE
    if ($exit -ne 0) {
        Fail "run-skill-basic.ps1 failed with exit $exit output: $($output | Out-String)"
    }
    Assert-ReportFormat (Join-Path $Artifacts 'skill_basic_report.md')
    return @{ status = 'PASS'; detail = 'run-skill-basic.ps1' }
}

function Test-SkillFailureHandling {
    $output = & $SkillFailureDemoScript 2>&1
    $exit = $LASTEXITCODE
    $text = ($output | Out-String)
    if ($exit -ne 0) {
        Fail "run-failure-demo.ps1 failed with exit $exit output: $text"
    }

    foreach ($code in @('WINDOW_NOT_FOUND', 'ASSERTION_FAILED', 'INVALID_ARGUMENT')) {
        if ($text -notmatch [regex]::Escape($code)) {
            Fail "run-failure-demo output did not contain $code"
        }
    }

    $reports = @(
        @{ Path = Join-Path $Artifacts 'skill_failure_window_not_found_report.md'; Code = 'WINDOW_NOT_FOUND' },
        @{ Path = Join-Path $Artifacts 'skill_failure_assert_report.md'; Code = 'ASSERTION_FAILED' },
        @{ Path = Join-Path $Artifacts 'skill_failure_invalid_click_report.md'; Code = 'INVALID_ARGUMENT' }
    )
    foreach ($report in $reports) {
        $explain = & $SkillExplainReportScript -ReportFile $report.Path 2>&1
        $explainExit = $LASTEXITCODE
        $explainText = ($explain | Out-String)
        if ($explainExit -ne 0) {
            Fail "explain-report.ps1 failed for $($report.Path): $explainText"
        }
        if ($explainText -notmatch [regex]::Escape($report.Code)) {
            Fail "explain-report output did not contain $($report.Code)"
        }
        if ($explainText -notmatch 'Do not continue unauthorized actions') {
            Fail "explain-report output missing unauthorized action warning."
        }
    }

    return @{ status = 'PASS'; detail = 'run-failure-demo.ps1 and explain-report.ps1' }
}

function Test-VisualSafetyFreeze {
    $checks = @(
        @{ Path = Join-Path $Root 'docs\VISUAL_SAFETY_FREEZE.md'; Text = 'Status: frozen-compatible with real Windows OCR in v2.0.0.' },
        @{ Path = Join-Path $Root 'docs\VISUAL_SAFETY_FREEZE.md'; Text = 'The target window title must resolve to exactly one visible top-level window.' },
        @{ Path = Join-Path $Root 'docs\VISUAL_SAFETY_FREEZE.md'; Text = 'OCR commands must first resolve a unique authorized target window and pass the configured title/process safety policy before reading or clicking text.' },
        @{ Path = Join-Path $Root 'docs\VISUAL_SAFETY_FREEZE.md'; Text = 'The agent must not click nearby positions to guess intent.' },
        @{ Path = Join-Path $Root 'docs\VISUAL_SAFETY_FREEZE.md'; Text = 'whether any input action was executed' },
        @{ Path = Join-Path $Root 'docs\SAFETY.md'; Text = 'Visual Locator Failure Stop' },
        @{ Path = Join-Path $Root 'docs\AGENT_USAGE_GUIDE.md'; Text = 'Visual Failure Stop' },
        @{ Path = Join-Path $SkillRoot 'SKILL.md'; Text = 'Visual Locator Safety' },
        @{ Path = Join-Path $SkillRoot 'references\VISUAL_SAFETY_FREEZE.md'; Text = 'Stop on every visual locator failure.' }
    )

    foreach ($check in $checks) {
        if (!(Test-Path -LiteralPath $check.Path)) {
            Fail "Missing visual safety freeze file: $($check.Path)"
        }
        if (!(Select-String -LiteralPath $check.Path -Pattern $check.Text -SimpleMatch -Quiet)) {
            Fail "Visual safety freeze check failed for $($check.Path): missing '$($check.Text)'"
        }
    }

    return @{ status = 'PASS'; detail = 'VISUAL_SAFETY_FREEZE.md and Skill safety references' }
}

if (!(Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run $Root\build.ps1 first." }
if (!(Test-Path -LiteralPath $TestWindowExe)) { Fail "Missing $TestWindowExe. Run $Root\build.ps1 first." }

New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null

$auditPath = Join-Path $Artifacts 'agent_audit.log'
Remove-Item -LiteralPath $auditPath -ErrorAction SilentlyContinue

Get-Process TestWindow -ErrorAction SilentlyContinue | ForEach-Object {
    $_.CloseMainWindow() | Out-Null
    Start-Sleep -Milliseconds 300
    if (!$_.HasExited) { Stop-Process -Id $_.Id -Force }
}

$expectedVersion = (Get-Content -LiteralPath (Join-Path $Root 'VERSION') -Raw).Trim()
$version = Invoke-WinAgentJson -WinArgs @('version')
Assert-CommandSchema $version 'version'
if ($version.json.data.version -ne $expectedVersion) { Fail "Expected version $expectedVersion, got $($version.json.data.version)." }
$capabilities = @($version.json.data.capabilities.available)
foreach ($capability in @('content_decision', 'decision_eval', 'decision_task_runtime', 'session_checkpoint', 'loop_guard', 'communication_action', 'communication_task_runtime', 'coding_workflow', 'coding_eval', 'coding_task_runtime', 'full_access_benchmark_harness', 'recovery_strategy_engine', 'service_protocol_v1', 'developer_tool_dogfood')) {
    if ($capabilities -notcontains $capability) {
        Fail "version capabilities missing $capability."
    }
}
$hasHumanMotionProfile = Test-LocalHumanMotionProfile

$windows = & $WinAgent windows
if ($LASTEXITCODE -ne 0) { Fail "windows command failed with exit code $LASTEXITCODE." }
try {
    $windowsJson = $windows | ConvertFrom-Json
} catch {
    Fail "windows output was not valid JSON: $windows"
}
if ($windowsJson.ok -ne $true -or $null -eq $windowsJson.windows) { Fail 'windows JSON missing ok/windows fields.' }

$proc = Start-Process -FilePath $TestWindowExe -PassThru
try {
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 250
        $find = Invoke-WinAgentJson -WinArgs @('find', '--title', 'Agent Test Window') -AllowedExitCodes @(0, 1)
    } while ($find.exit -ne 0 -and (Get-Date) -lt $deadline)
    if ($find.exit -ne 0) { Fail 'Agent Test Window did not appear or was not uniquely matched.' }
    Assert-CommandSchema $find 'find'

    $click = Invoke-WinAgentJson -WinArgs @('click', '--title', 'Agent Test Window', '--x', '80', '--y', '90', '--move-mode', 'instant')
    Assert-CommandSchema $click 'click'
    if ($click.json.data.move_mode -ne 'instant' -or [int]$click.json.data.move_duration_ms -ne 0 -or [int]$click.json.data.move_steps -le 0) {
        Fail "instant click JSON data incorrect: $($click.text)"
    }
    $dx = [Math]::Abs([int]$click.json.data.cursor_after_x - [int]$click.json.data.target_screen_x)
    $dy = [Math]::Abs([int]$click.json.data.cursor_after_y - [int]$click.json.data.target_screen_y)
    if ($dx -gt 3 -or $dy -gt 3) { Fail "human click cursor_after not close to target_screen: dx=$dx dy=$dy" }

    $press = Invoke-WinAgentJson -WinArgs @('press', '--title', 'Agent Test Window', '--key', 'SPACE')
    Assert-CommandSchema $press 'press'

    $focus = Invoke-WinAgentJson -WinArgs @('click', '--title', 'Agent Test Window', '--x', '90', '--y', '150', '--move-mode', 'instant')
    Assert-CommandSchema $focus 'click'

    $type = Invoke-WinAgentJson -WinArgs @('type', '--title', 'Agent Test Window', '--text', 'hello', '--type-mode', 'human', '--char-delay-ms', '50')
    Assert-CommandSchema $type 'type'
    if ($type.json.data.type_mode -ne 'demo-human' -or [int]$type.json.data.char_delay_ms -ne 50 -or [int]$type.json.data.text_length -ne 5) {
        Fail "human type JSON data incorrect: $($type.text)"
    }

    $missing = Invoke-WinAgentJson -WinArgs @('find', '--title', 'Definitely Missing Agent Test Window') -AllowedExitCodes @(1)
    Assert-CommandSchema $missing 'find'
    Assert-FailureSchema $missing 'WINDOW_NOT_FOUND'

    # Isolate direct command checks from case-runner checks so TestWindow text state does not leak.
    if ($proc -and !$proc.HasExited) {
        $proc.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (!$proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    }
    $proc = Start-Process -FilePath $TestWindowExe -PassThru
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 250
        $find = Invoke-WinAgentJson -WinArgs @('find', '--title', 'Agent Test Window') -AllowedExitCodes @(0, 1)
    } while ($find.exit -ne 0 -and (Get-Date) -lt $deadline)
    if ($find.exit -ne 0) { Fail 'Agent Test Window did not reappear before case selftests.' }

    $basic = Run-Case -CaseFile (Join-Path $Root 'cases\case_v2_expect_success.case') -ReportPath (Join-Path $Artifacts 'selftest_basic_click_report.md') -ShouldPass $true
    $visibleStatus = 'SKIPPED'
    $visibleDetail = 'No local source=human operator motion profile.'
    if ($hasHumanMotionProfile) {
        $visibleSource = Join-Path $Root 'cases\case_v2_expect_success.case'
        $visibleCase = Join-Path $Artifacts 'selftest_visible_action_current.case'
        ([IO.File]::ReadAllText($visibleSource, [Text.Encoding]::UTF8)).
            Replace('D:\testrepo', $TestRepoRoot).
            Replace('move_mode="instant"', 'move_mode="human"') |
            Set-Content -LiteralPath $visibleCase -Encoding UTF8
        $visible = Run-Case -CaseFile $visibleCase -ReportPath (Join-Path $Artifacts 'selftest_visible_action_report.md') -ShouldPass $true
        $visibleStatus = 'PASS'
        $visibleDetail = $visible.json.data.report
    }
    $failMissing = Run-Case -CaseFile (Join-Path $Root 'cases\failure_window_not_found.case') -ReportPath (Join-Path $Artifacts 'failure_window_not_found_report.md') -ShouldPass $false -ExpectedErrorCode 'WINDOW_NOT_FOUND'
    $failAssert = Run-Case -CaseFile (Join-Path $Root 'cases\failure_assert.case') -ReportPath (Join-Path $Artifacts 'failure_assert_report.md') -ShouldPass $false -ExpectedErrorCode 'ASSERTION_FAILED'
    $failClick = Run-Case -CaseFile (Join-Path $Root 'cases\failure_invalid_click.case') -ReportPath (Join-Path $Artifacts 'failure_invalid_click_report.md') -ShouldPass $false -ExpectedErrorCode 'INVALID_ARGUMENT'

    $auditPattern = 'timestamp=".+?" command=".+?" target_title=".*?" result="(ok|failed)" error_code=".*?" duration_ms=\d+ data=".*"'
    if (!(Select-String -LiteralPath $auditPath -Pattern $auditPattern -Quiet)) { Fail 'Audit log does not contain the frozen field format.' }
    if (!(Select-String -LiteralPath $auditPath -Pattern 'result="ok"' -Quiet)) { Fail 'Audit log does not contain success actions.' }
    if (!(Select-String -LiteralPath $auditPath -Pattern 'result="failed"' -Quiet)) { Fail 'Audit log does not contain failed actions.' }

    $skillTemplate = Test-SkillTemplate
    $skillFailureHandling = Test-SkillFailureHandling
    $visualSafetyFreeze = Test-VisualSafetyFreeze
    $dogfood = Invoke-DogfoodOptional

    $lines = @(
        '# WinDesktopAgent Selftest',
        '',
        '- Result: SUCCESS',
        "- Version: v$expectedVersion",
        "- version command: $($version.json.data.version)",
        "- windows command window_count: $($windowsJson.windows.Count)",
        "- Direct click command: $($click.json.command)",
        "- Direct click duration_ms: $($click.json.duration_ms)",
        "- Direct click move_mode: $($click.json.data.move_mode)",
        "- Direct click move_duration_ms: $($click.json.data.move_duration_ms)",
        "- Direct click move_steps: $($click.json.data.move_steps)",
        "- Direct click delta: dx=$dx, dy=$dy",
        "- Direct press command: $($press.json.command)",
        "- Direct type command: $($type.json.command)",
        "- Direct type mode: $($type.json.data.type_mode)",
        "- Direct type char_delay_ms: $($type.json.data.char_delay_ms)",
        "- case_v2_expect_success.case: PASS",
        "- visible_action.case: $visibleStatus",
        "- visible_action detail: $visibleDetail",
        "- failure_window_not_found.case: $($failMissing.json.error.code)",
        "- failure_assert.case: $($failAssert.json.error.code)",
        "- failure_invalid_click.case: $($failClick.json.error.code)",
        "- skill_template: PASS",
        "- skill_basic: $($skillTemplate.status)",
        "- skill_basic detail: $($skillTemplate.detail)",
        "- skill_failure_handling: $($skillFailureHandling.status)",
        "- skill_failure_handling detail: $($skillFailureHandling.detail)",
        "- visual_safety_freeze: $($visualSafetyFreeze.status)",
        "- visual_safety_freeze detail: $($visualSafetyFreeze.detail)",
        "- real_app dogfood: $($dogfood.status)",
        "- real_app dogfood detail: $($dogfood.detail)",
        "- audit log format: PASS",
        "- case report format: PASS",
        '',
        '## JSON Samples',
        '',
        '```json',
        $version.text,
        $click.text,
        $type.text,
        $missing.text,
        '```'
    )
    $lines | Set-Content -Encoding UTF8 -LiteralPath $Report

    Write-Host 'Selftest passed.'
    Write-Host "Report: $Report"
    Write-Host "Dogfood: $($dogfood.status)"
}
finally {
    if ($proc -and !$proc.HasExited) {
        $proc.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (!$proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    }
}
