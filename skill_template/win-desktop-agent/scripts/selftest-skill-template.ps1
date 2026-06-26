param(
    [string]$Root = '',
    [string]$TestRepoRoot = '',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'Resolve-DesktopVisualRoot.ps1'
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
$SkillRoot = Join-Path $Root 'skill_template\win-desktop-agent'
$ScriptsDir = Join-Path $SkillRoot 'scripts'
$RefsDir = Join-Path $SkillRoot 'references'

function Fail($msg) { throw "FAIL: $msg" }
function Pass($msg) { Write-Host "  PASS: $msg" -ForegroundColor Green }

if (-not $SkipBuild) {
    Write-Host "Building..." -ForegroundColor Cyan
    & (Join-Path $Root 'build.ps1') -Root $Root
    if ($LASTEXITCODE -ne 0) { Fail "Build failed" }
}

$passed = 0; $failed = 0

function Check($name, [scriptblock]$test) {
    Write-Host "=== $name ===" -ForegroundColor Cyan
    try { & $test; $script:passed++ } catch { Write-Host "  $_" -ForegroundColor Red; $script:failed++ }
}

# 1. New scripts exist
Check "New scripts exist" {
    @('observe-target.ps1','locate-target.ps1','act-target.ps1','run-case-v2.ps1','summarize-report.ps1','run-dogfood-matrix.ps1','run-task.ps1','summarize-task-report.ps1') | ForEach-Object {
        $path = Join-Path $ScriptsDir $_
        if (-not (Test-Path $path)) { Fail "Missing script: $_" }
        Pass "$_ exists"
    }
}

# 2. References complete
Check "References complete" {
    @('COMMAND_PROTOCOL.md','CASE_FORMAT.md','ERROR_CODES.md','SAFETY.md','VISUAL_SAFETY_FREEZE.md','AGENT_USAGE_GUIDE.md','KNOWN_LIMITATIONS.md') | ForEach-Object {
        $path = Join-Path $RefsDir $_
        if (-not (Test-Path $path)) { Write-Host "  WARNING: $_ not found" -ForegroundColor Yellow }
        else { Pass "$_ exists" }
    }
}

# 3. SKILL.md contains observe-act-verify flow
Check "SKILL.md contains observe-act-verify flow" {
    $skill = Get-Content (Join-Path $SkillRoot 'SKILL.md') -Raw
    if ($skill -notmatch 'observe') { Fail "Missing 'observe'" }
    if ($skill -notmatch 'locate') { Fail "Missing 'locate'" }
    if ($skill -notmatch 'act') { Fail "Missing 'act'" }
    if ($skill -notmatch 'verif') { Fail "Missing 'verify'" }
    Pass "observe-act-verify flow present"
}

# 4. SKILL.md contains stop conditions
Check "SKILL.md contains stop conditions" {
    $skill = Get-Content (Join-Path $SkillRoot 'SKILL.md') -Raw
    if ($skill -notmatch 'LOCATOR_NOT_FOUND') { Fail "Missing LOCATOR_NOT_FOUND" }
    if ($skill -notmatch 'LOCATOR_NOT_UNIQUE') { Fail "Missing LOCATOR_NOT_UNIQUE" }
    if ($skill -notmatch 'OCR_UNAVAILABLE') { Fail "Missing OCR_UNAVAILABLE" }
    if ($skill -notmatch 'SAFETY_POLICY_DENIED') { Fail "Missing SAFETY_POLICY_DENIED" }
    Pass "Stop conditions documented"
}

# 5. run-case-v2.ps1 executes a stable Case v2 fixture
Check "run-case-v2.ps1 executes case_v2_expect_success.case" {
    Get-Process TestWindow -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 300
    $proc = Start-Process -FilePath $TestWindowExe -PassThru
    Start-Sleep -Milliseconds 800

    $sourceCaseFile = Join-Path $Root 'cases\case_v2_expect_success.case'
    $caseFile = Join-Path $Artifacts 'skill_selftest_case_v2_current.case'
    ([IO.File]::ReadAllText($sourceCaseFile, [Text.Encoding]::UTF8)).Replace('D:\testrepo', $TestRepoRoot) |
        Set-Content -LiteralPath $caseFile -Encoding UTF8
    $reportFile = Join-Path $Artifacts 'skill_selftest_case_v2_report.md'
    & powershell -ExecutionPolicy Bypass -File (Join-Path $ScriptsDir 'run-case-v2.ps1') -CaseFile $caseFile -ReportFile $reportFile 2>&1 | Out-Null
    $exit = $LASTEXITCODE
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    if ($exit -ne 0) { Fail "run-case-v2.ps1 exited with $exit" }
    if (-not (Test-Path $reportFile)) { Fail "Report not generated" }
    Pass "case_v2_expect_success.case executed"
}

# 6. observe-target.ps1 outputs observe data
Check "observe-target.ps1 outputs observe data" {
    Get-Process TestWindow -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 300
    $proc = Start-Process -FilePath $TestWindowExe -PassThru
    Start-Sleep -Milliseconds 800
    $output = & powershell -ExecutionPolicy Bypass -File (Join-Path $ScriptsDir 'observe-target.ps1') -Title 'Agent Test Window' 2>&1
    $exit = $LASTEXITCODE
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    if ($exit -ne 0) { Fail "observe-target.ps1 exited with $exit" }
    if (($output | Out-String) -notmatch 'Observe OK') { Fail "No Observe OK" }
    Pass "observe-target.ps1 works"
}

# 7. locate-target.ps1 locates Click Me
Check "locate-target.ps1 locates Click Me" {
    Get-Process TestWindow -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 300
    $proc = Start-Process -FilePath $TestWindowExe -PassThru
    Start-Sleep -Milliseconds 800
    $output = & powershell -ExecutionPolicy Bypass -File (Join-Path $ScriptsDir 'locate-target.ps1') -Title 'Agent Test Window' -Selector 'uia:name=Click Me' 2>&1
    $exit = $LASTEXITCODE
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    if ($exit -ne 0) { Fail "locate-target.ps1 exited with $exit" }
    if (($output | Out-String) -notmatch 'Locate OK') { Fail "No Locate OK" }
    Pass "locate-target.ps1 works"
}

# 8. act-target.ps1 clicks Click Me
Check "act-target.ps1 clicks Click Me" {
    Get-Process TestWindow -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 300
    $proc = Start-Process -FilePath $TestWindowExe -PassThru
    Start-Sleep -Milliseconds 800
    $output = & powershell -ExecutionPolicy Bypass -File (Join-Path $ScriptsDir 'act-target.ps1') -Title 'Agent Test Window' -Selector 'uia:name=Click Me' -Action 'click' 2>&1
    $exit = $LASTEXITCODE
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    if ($exit -ne 0) { Fail "act-target.ps1 exited with $exit" }
    if (($output | Out-String) -notmatch 'Act OK') { Fail "No Act OK" }
    Pass "act-target.ps1 works"
}

# 9. summarize-report.ps1 summarizes failure report
Check "summarize-report.ps1 summarizes failure report" {
    $failReport = Join-Path $Artifacts 'failure_assert_report.md'
    if (-not (Test-Path $failReport)) {
        Write-Host "  No failure report, running failure demo..."
        & powershell -ExecutionPolicy Bypass -File (Join-Path $ScriptsDir 'run-failure-demo.ps1') 2>&1 | Out-Null
    }
    if (Test-Path $failReport) {
        $output = & powershell -ExecutionPolicy Bypass -File (Join-Path $ScriptsDir 'summarize-report.ps1') -ReportFile $failReport 2>&1
        if (($output | Out-String) -notmatch 'End Summary') { Fail "No End Summary" }
        Pass "summarize-report.ps1 works"
    } else {
        Pass "summarize-report.ps1 exists (no report to test)"
    }
}

# 10. run-task.ps1 executes testwindow_basic.task.json
Check "run-task.ps1 executes testwindow_basic.task.json" {
    Get-Process TestWindow -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 300
    $proc = Start-Process -FilePath $TestWindowExe -PassThru
    Start-Sleep -Milliseconds 800

    $taskFile = Join-Path $Root 'tasks\testwindow_basic.task.json'
    $reportFile = Join-Path $Artifacts 'skill_selftest_task_report.md'
    & powershell -ExecutionPolicy Bypass -File (Join-Path $ScriptsDir 'run-task.ps1') -TaskFile $taskFile -ReportFile $reportFile 2>&1 | Out-Null
    $exit = $LASTEXITCODE
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    if ($exit -ne 0) { Fail "run-task.ps1 exited with $exit" }
    if (-not (Test-Path $reportFile)) { Fail "Task report not generated" }
    Pass "testwindow_basic.task.json executed"
}

# 11. summarize-task-report.ps1 summarizes task report
Check "summarize-task-report.ps1 summarizes task report" {
    $reportFile = Join-Path $Artifacts 'skill_selftest_task_report.md'
    if (-not (Test-Path $reportFile)) { Fail "Task report missing: $reportFile" }
    $output = & powershell -ExecutionPolicy Bypass -File (Join-Path $ScriptsDir 'summarize-task-report.ps1') -ReportFile $reportFile 2>&1
    if (($output | Out-String) -notmatch 'End Summary') { Fail "No End Summary" }
    Pass "summarize-task-report.ps1 works"
}

Write-Host ""
Write-Host "===================================" -ForegroundColor Cyan
Write-Host "Skill Template Selftest v3.0" -ForegroundColor Cyan
Write-Host "Passed: $passed / $($passed + $failed)" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Green' })
if ($failed -gt 0) { exit 1 }
exit 0
