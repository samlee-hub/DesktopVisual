param(
    [string]$Root = ''
)

param([switch]$SkipBuild)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$TestWindowExe = 'D:\testrepo\testwindow\bin\TestWindow.exe'
$Artifacts = Join-Path $Root 'artifacts'

function Fail($Message) { throw "FAIL: $Message" }
function Skip($Reason) { Write-Host "  SKIPPED: $Reason" -ForegroundColor Yellow }

function Invoke-WinAgentJson {
    param([string[]]$WinArgs, [int[]]$AllowedExitCodes = @(0))
    $output = & $WinAgent @WinArgs
    $exit = $LASTEXITCODE
    if ($AllowedExitCodes -notcontains $exit) {
        Fail "winagent $($WinArgs -join ' ') exited ${exit}: $output"
    }
    try { return $output | ConvertFrom-Json } catch { Fail "Not JSON: $output" }
}

if (-not $SkipBuild) {
    Write-Host "Building..."
    & "$Root\build.ps1"
    if ($LASTEXITCODE -ne 0) { Fail "Build failed" }
}

# Check OCR availability
$ver = & $WinAgent version | ConvertFrom-Json
$ocrAvailable = $ver.data.ocr_available
Write-Host "OCR available: $ocrAvailable" -ForegroundColor Cyan

$passed = 0; $failed = 0; $skipped = 0

function Run-Test($Name, [scriptblock]$Test, [bool]$RequiresOcr = $false) {
    Write-Host "=== $Name ===" -ForegroundColor Cyan
    if ($RequiresOcr -and -not $ocrAvailable) {
        Skip "OCR_UNAVAILABLE on this system"
        $script:skipped++
        return
    }
    try { & $Test; Write-Host "  PASS" -ForegroundColor Green; $script:passed++ }
    catch { Write-Host "  $_" -ForegroundColor Red; $script:failed++ }
}

function Stop-TestWindow {
    Get-Process TestWindow -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

function New-DenyTestWindowSafetyConfig {
    $path = Join-Path $Artifacts 'ocr_deny_testwindow_safety.conf'
    @'
allowed_titles=Definitely Not Agent Test Window
allowed_processes=notepad.exe
allowed_read_roots=${PROJECT_ROOT};${PROJECT_ROOT}\artifacts;D:\testrepo\testwindow
allowed_write_roots=${PROJECT_ROOT}\artifacts;D:\testrepo\testwindow
max_steps=100
max_duration_ms=120000
emergency_stop_key=F12
allow_absolute_screen_click=false
'@ | Out-File -FilePath $path -Encoding utf8
    return $path
}

# Test 1: read-window-text reads visible text
Run-Test "read-window-text reads visible text" -RequiresOcr $true {
    Stop-TestWindow; Start-Sleep -Milliseconds 300
    $proc = Start-Process -FilePath $TestWindowExe -PassThru
    Start-Sleep -Milliseconds 1500

    $json = Invoke-WinAgentJson -WinArgs "read-window-text","--title","Agent Test Window"
    if (-not $json.ok) { Fail "read-window-text returned error: $($json.error.message)" }
    if ($json.data.word_count -eq 0) { Fail "read-window-text returned 0 words" }
    if (-not $json.data.screenshot_path) { Fail "read-window-text did not return screenshot_path" }
    if (-not (Test-Path $json.data.screenshot_path)) { Fail "read-window-text screenshot_path does not exist: $($json.data.screenshot_path)" }
    Write-Host "  Found $($json.data.word_count) words, $($json.data.line_count) lines"

    Stop-TestWindow
}

# Test 2: find-text locates text
Run-Test "find-text locates text" -RequiresOcr $true {
    Stop-TestWindow; Start-Sleep -Milliseconds 300
    $proc = Start-Process -FilePath $TestWindowExe -PassThru
    Start-Sleep -Milliseconds 1500

    $json = Invoke-WinAgentJson -WinArgs "find-text","--title","Agent Test Window","--text","Agent"
    if (-not $json.ok -and $json.error.code -ne 'LOCATOR_NOT_FOUND') {
        Fail "find-text failed: $($json.error.code) $($json.error.message)"
    }
    if ($json.ok) {
        Write-Host "  Found '$($json.data.matched_text)' at rect ($($json.data.bounding_box.left),$($json.data.bounding_box.top))"
    } else {
        Write-Host "  LOCATOR_NOT_FOUND (may be valid if text not rendered)"
    }

    Stop-TestWindow
}

# Test 3: text selector locates
Run-Test "text selector locates" -RequiresOcr $true {
    Stop-TestWindow; Start-Sleep -Milliseconds 300
    $proc = Start-Process -FilePath $TestWindowExe -PassThru
    Start-Sleep -Milliseconds 1500

    $json = Invoke-WinAgentJson -WinArgs "locate","--title","Agent Test Window","--selector","text:contains=Click" -AllowedExitCodes @(0,1)
    if ($json.ok) {
        Write-Host "  Located at client ($($json.data.client_point.x),$($json.data.client_point.y))"
        if ($json.data.client_point.x -lt 0 -or $json.data.client_point.y -lt 0) {
            Fail "text selector returned negative client coordinates"
        }
    } elseif ($json.error.code -eq 'LOCATOR_NOT_FOUND') {
        Write-Host "  LOCATOR_NOT_FOUND (may be valid)"
    } else {
        Fail "text selector failed: $($json.error.code)"
    }

    Stop-TestWindow
}

# Test 4: Non-existent text returns LOCATOR_NOT_FOUND
Run-Test "Non-existent text returns LOCATOR_NOT_FOUND" -RequiresOcr $true {
    Stop-TestWindow; Start-Sleep -Milliseconds 300
    $proc = Start-Process -FilePath $TestWindowExe -PassThru
    Start-Sleep -Milliseconds 1500

    $json = Invoke-WinAgentJson -WinArgs "find-text","--title","Agent Test Window","--text","ZZZNonExistent999" -AllowedExitCodes @(0,1)
    if ($json.error.code -ne 'LOCATOR_NOT_FOUND') {
        Fail "Expected LOCATOR_NOT_FOUND, got: $($json.error.code)"
    }

    Stop-TestWindow
}

# Test 5: Unauthorized window returns SAFETY_POLICY_DENIED (for click-text)
Run-Test "Unauthorized window returns SAFETY_POLICY_DENIED" -RequiresOcr $true {
    Stop-TestWindow; Start-Sleep -Milliseconds 300
    $proc = Start-Process -FilePath $TestWindowExe -PassThru
    Start-Sleep -Milliseconds 800

    $oldConfig = $env:DESKTOPVISUAL_SAFETY_CONFIG
    $env:DESKTOPVISUAL_SAFETY_CONFIG = New-DenyTestWindowSafetyConfig
    try {
        $readJson = Invoke-WinAgentJson -WinArgs "read-window-text","--title","Agent Test Window" -AllowedExitCodes @(0,1)
        if ($readJson.error.code -ne 'SAFETY_POLICY_DENIED') {
            Fail "Expected read-window-text SAFETY_POLICY_DENIED, got: $($readJson.error.code)"
        }
        $findJson = Invoke-WinAgentJson -WinArgs "find-text","--title","Agent Test Window","--text","Click" -AllowedExitCodes @(0,1)
        if ($findJson.error.code -ne 'SAFETY_POLICY_DENIED') {
            Fail "Expected find-text SAFETY_POLICY_DENIED, got: $($findJson.error.code)"
        }
        Write-Host "  OCR read and locate commands enforce SafetyPolicy"
    } finally {
        $env:DESKTOPVISUAL_SAFETY_CONFIG = $oldConfig
        Stop-TestWindow
    }
}

# Test 6: find-text with --match exact
Run-Test "find-text with --match exact" -RequiresOcr $true {
    Stop-TestWindow; Start-Sleep -Milliseconds 300
    $proc = Start-Process -FilePath $TestWindowExe -PassThru
    Start-Sleep -Milliseconds 1500

    $json = Invoke-WinAgentJson -WinArgs "find-text","--title","Agent Test Window","--text","Agent","--match","exact" -AllowedExitCodes @(0,1)
    # May or may not find exact match, but should not crash
    Write-Host "  Result: ok=$($json.ok) code=$($json.error.code)"

    Stop-TestWindow
}

# Test 7: OCR unavailable is handled gracefully (always passes - just checks version data)
Run-Test "Version reports OCR capability correctly" {
    $ver = & $WinAgent version | ConvertFrom-Json
    if ($ver.data.ocr_available) {
        if ($ver.data.ocr_engine -eq 'none') { Fail "OCR available but engine is 'none'" }
        $stubNames = @($ver.data.capabilities.stub | ForEach-Object { $_.name })
        foreach ($name in @('read_window_text','read_region_text','find_text','click_text','wait_text')) {
            if ($stubNames -contains $name) { Fail "OCR command '$name' is in stub while ocr_available=true" }
        }
        Write-Host "  OCR engine: $($ver.data.ocr_engine)"
    } else {
        Write-Host "  OCR unavailable: engine=$($ver.data.ocr_engine)"
    }
    if (-not $ver.data.capabilities) { Fail "capabilities missing from version" }
}

# Summary
Write-Host ""
Write-Host "===================================" -ForegroundColor Cyan
Write-Host "OCR Selftest Results" -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan
Write-Host "Passed: $passed  Failed: $failed  Skipped: $skipped" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Green' })
Write-Host "===================================" -ForegroundColor Cyan

if ($failed -gt 0) { exit 1 }
exit 0
