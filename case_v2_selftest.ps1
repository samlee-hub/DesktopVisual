param(
    [string]$Root = '',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$TestWindowExe = 'D:\testrepo\testwindow\bin\TestWindow.exe'
$Artifacts = Join-Path $Root 'artifacts'
$Report = Join-Path $Artifacts 'case_v2_selftest_report.md'

function Fail($Message) {
    throw "FAIL: $Message"
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
        return $json
    } catch {
        Fail "Could not parse JSON from: $output"
    }
}

function Assert-True($Condition, $Message) {
    if (-not $Condition) { Fail $Message }
}

function Assert-Equal($Expected, $Actual, $Message) {
    if ($Expected -ne $Actual) { Fail "$Message 闂?expected $Expected, got $Actual" }
}

function Stop-TestWindow {
    Get-Process TestWindow -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

# === Build ===
if (-not $SkipBuild) {
    Write-Host "Building..."
    & (Join-Path $Root 'build.ps1') -Root $Root
    if ($LASTEXITCODE -ne 0) { Fail "Build failed" }
}

# === Clean before tests ===
Stop-TestWindow
Start-Sleep -Milliseconds 300

$results = @()
$passed = 0
$failed = 0

function Run-Test($Name, [scriptblock]$Test) {
    Write-Host "=== $Name ===" -ForegroundColor Cyan
    try {
        & $Test
        Write-Host "  PASS" -ForegroundColor Green
        $script:passed++
    } catch {
        Write-Host "  FAIL: $_" -ForegroundColor Red
        $script:failed++
    }
}

# =============================================
# Test 1: Old v1 case still passes
# =============================================
Run-Test "Old v1 case (basic_click.case) still passes" {
    Stop-TestWindow
    Start-Sleep -Milliseconds 200
    $proc = Start-Process -FilePath $TestWindowExe -PassThru
    Start-Sleep -Milliseconds 800

    $report = Join-Path $Artifacts 'selftest_v1_compat.md'
    $json = Invoke-WinAgentJson -WinArgs "run-case","--file","$Root\cases\basic_click.case","--report",$report
    Assert-True $json.ok "v1 basic_click case should pass"
    Assert-Equal "basic_click.case" $json.data.case_file.Split('\')[-1] "Case name mismatch"

    Stop-TestWindow
}

# =============================================
# Test 2: case_version=2 basic case passes
# =============================================
Run-Test "Case v2 basic (case_v2_basic.case) passes" {
    Stop-TestWindow
    Start-Sleep -Milliseconds 200
    $proc = Start-Process -FilePath $TestWindowExe -PassThru
    Start-Sleep -Milliseconds 800

    $report = Join-Path $Artifacts 'case_v2_basic_report.md'
    $json = Invoke-WinAgentJson -WinArgs "run-case","--file","$Root\cases\case_v2_basic.case","--report",$report
    Assert-True $json.ok "v2 basic case should pass"

    Stop-TestWindow
}

# =============================================
# Test 3: Variable substitution
# =============================================
Run-Test "Variable substitution" {
    Stop-TestWindow
    Start-Sleep -Milliseconds 200
    $proc = Start-Process -FilePath $TestWindowExe -PassThru
    Start-Sleep -Milliseconds 800

    # Create a temp v2 case with variables
    $varCase = Join-Path $Artifacts 'case_v2_var_test.case'
    @"
case_version=2
set name="my_title" value="Agent Test Window"
set name="my_x" value="80"
set name="my_y" value="90"
target_title="`${my_title}"
wait ms=300
click x="`${my_x}" y="`${my_y}" move_mode="instant"
wait ms=300
"@ | Out-File -FilePath $varCase -Encoding utf8

    $report = Join-Path $Artifacts 'case_v2_var_report.md'
    $json = Invoke-WinAgentJson -WinArgs "run-case","--file",$varCase,"--report",$report
    Assert-True $json.ok "Variable substitution case should pass"

    Stop-TestWindow
}

# =============================================
# Test 4: wait_until selector passes
# =============================================
Run-Test "wait_until selector passes" {
    Stop-TestWindow
    Start-Sleep -Milliseconds 200
    $proc = Start-Process -FilePath $TestWindowExe -PassThru
    Start-Sleep -Milliseconds 800

    $report = Join-Path $Artifacts 'case_v2_wait_until_report.md'
    $json = Invoke-WinAgentJson -WinArgs "run-case","--file","$Root\cases\case_v2_wait_until.case","--report",$report
    Assert-True $json.ok "wait_until case should pass"
    Assert-True ((Get-Content $report -Raw) -match 'Wait Results') "Report should have Wait Results section"

    Stop-TestWindow
}

# =============================================
# Test 5: expect success passes
# =============================================
Run-Test "expect success passes" {
    Stop-TestWindow
    Start-Sleep -Milliseconds 200
    $proc = Start-Process -FilePath $TestWindowExe -PassThru
    Start-Sleep -Milliseconds 800

    $report = Join-Path $Artifacts 'case_v2_expect_success_report.md'
    $json = Invoke-WinAgentJson -WinArgs "run-case","--file","$Root\cases\case_v2_expect_success.case","--report",$report
    Assert-True $json.ok "expect success case should pass"
    Assert-True ((Get-Content $report -Raw) -match 'Expect Results') "Report should have Expect Results section"

    Stop-TestWindow
}

# =============================================
# Test 6: expect failure returns ASSERTION_FAILED
# =============================================
Run-Test "expect failure returns ASSERTION_FAILED" {
    Stop-TestWindow
    Start-Sleep -Milliseconds 200
    $proc = Start-Process -FilePath $TestWindowExe -PassThru
    Start-Sleep -Milliseconds 800

    $report = Join-Path $Artifacts 'case_v2_expect_failure_report.md'
    $json = Invoke-WinAgentJson -WinArgs "run-case","--file","$Root\cases\case_v2_expect_failure.case","--report",$report -AllowedExitCodes @(0,1)
    Assert-True (-not $json.ok) "expect failure case should NOT pass"
    Assert-Equal "ASSERTION_FAILED" $json.error.code "Error code should be ASSERTION_FAILED"

    Stop-TestWindow
}

# =============================================
# Test 7: Bad quotes returns CASE_PARSE_FAILED
# =============================================
Run-Test "Bad quotes returns CASE_PARSE_FAILED" {
    Stop-TestWindow
    Start-Sleep -Milliseconds 200
    $proc = Start-Process -FilePath $TestWindowExe -PassThru
    Start-Sleep -Milliseconds 800

    $badCase = Join-Path $Artifacts 'case_v2_bad_quotes.case'
    @"
case_version=2
target_title="unclosed quote
"@ | Out-File -FilePath $badCase -Encoding utf8

    $report = Join-Path $Artifacts 'case_v2_bad_quotes_report.md'
    $json = Invoke-WinAgentJson -WinArgs "run-case","--file",$badCase,"--report",$report -AllowedExitCodes @(0,1,2)
    Assert-True (-not $json.ok) "Bad quotes case should NOT pass"
    Assert-Equal "CASE_PARSE_FAILED" $json.error.code "Error code should be CASE_PARSE_FAILED"

    Stop-TestWindow
}

# =============================================
# Test 8: locate failure stops subsequent input
# =============================================
Run-Test "locate failure stops subsequent input" {
    Stop-TestWindow
    Start-Sleep -Milliseconds 200
    $proc = Start-Process -FilePath $TestWindowExe -PassThru
    Start-Sleep -Milliseconds 800

    $locFailCase = Join-Path $Artifacts 'case_v2_locate_fail.case'
    @"
case_version=2
target_title="Agent Test Window"
# This selector should fail
locate selector="uia:name=DoesNotExist999"
# This click should NEVER execute because locate failed
click x=80 y=90
"@ | Out-File -FilePath $locFailCase -Encoding utf8

    $report = Join-Path $Artifacts 'case_v2_locate_fail_report.md'
    $json = Invoke-WinAgentJson -WinArgs "run-case","--file",$locFailCase,"--report",$report -AllowedExitCodes @(0,1)
    Assert-True (-not $json.ok) "locate failure case should NOT pass"
    Assert-Equal 2 $json.data.failed_step_index "Should fail on step 2 (locate), not step 3 (click)"
    Assert-Equal 1 $json.data.passed_step_count "Only target_title should pass before locate fails"

    Stop-TestWindow
}

# =============================================
# Test 9: act with expect post-action verification
# =============================================
Run-Test "act with post-action expect verification" {
    Stop-TestWindow
    Start-Sleep -Milliseconds 200
    $proc = Start-Process -FilePath $TestWindowExe -PassThru
    Start-Sleep -Milliseconds 800

    $actExpectCase = Join-Path $Artifacts 'case_v2_act_expect.case'
    @"
case_version=2
target_title="Agent Test Window"
# Click button then verify state file was updated
act selector="uia:name=Click Me" action="click" expect_file_contains_path="D:\testrepo\testwindow\runtime\state.txt" expect_file_contains_text="clicks="
"@ | Out-File -FilePath $actExpectCase -Encoding utf8

    $report = Join-Path $Artifacts 'case_v2_act_expect_report.md'
    $json = Invoke-WinAgentJson -WinArgs "run-case","--file",$actExpectCase,"--report",$report -AllowedExitCodes @(0,1)
    Assert-True $json.ok "act with post-action expect should pass"
    Assert-True ((Get-Content $report -Raw) -match 'Expect Results') "Report should have Expect Results"

    Stop-TestWindow
}

# =============================================
# Test 10: Case v2 report has case_version field
# =============================================
Run-Test "Case v2 report includes case_version" {
    $report = Join-Path $Artifacts 'case_v2_basic_report.md'
    if (-not (Test-Path $report)) {
        Fail "Report file not found: $report"
    }
    $content = Get-Content $report -Raw
    Assert-True ($content -match 'Case version: 2') "Report should show case_version 2"
}

# =============================================
# Summary
# =============================================
Write-Host ""
Write-Host "===================================" -ForegroundColor Cyan
Write-Host "Case v2 Selftest Results" -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan
Write-Host "Passed: $passed / $($passed + $failed)" -ForegroundColor Green
if ($failed -gt 0) {
    Write-Host "Failed: $failed" -ForegroundColor Red
}
Write-Host "===================================" -ForegroundColor Cyan

if ($failed -gt 0) {
    exit 1
}
exit 0
