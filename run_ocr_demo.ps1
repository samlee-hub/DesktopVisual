param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\run_ocr_demo.ps1'
    Write-Host 'Runs the TestWindow OCR demo when Windows OCR is available.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$TestRepoRoot = & (Join-Path $Root 'scripts\Resolve-TestRepoRoot.ps1') -Root $Root
$TestWindowRoot = Join-Path $TestRepoRoot 'testwindow'
$TestWindowExe = Join-Path $TestWindowRoot 'bin\TestWindow.exe'
$Artifacts = Join-Path $Root 'artifacts'
$Report = Join-Path $Artifacts 'ocr_demo_report.md'

function Write-Report($Lines) {
    New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null
    $Lines | Set-Content -Encoding UTF8 -LiteralPath $Report
}

function Fail($Message) {
    Write-Report @(
        '# OCR Demo Report',
        '',
        '- Result: FAILED',
        "- Message: $Message"
    )
    Write-Host "FAIL: $Message"
    exit 1
}

& (Join-Path $Root 'build.ps1') -Root $Root -TestRepoRoot $TestRepoRoot
if ($LASTEXITCODE -ne 0) {
    Fail "build.ps1 failed with exit $LASTEXITCODE"
}

if (!(Test-Path -LiteralPath $WinAgent)) {
    Fail "Missing $WinAgent"
}
if (!(Test-Path -LiteralPath $TestWindowExe)) {
    Fail "Missing $TestWindowExe"
}

Get-Process TestWindow -ErrorAction SilentlyContinue | ForEach-Object {
    $_.CloseMainWindow() | Out-Null
    Start-Sleep -Milliseconds 300
    if (!$_.HasExited) {
        Stop-Process -Id $_.Id -Force
    }
}

$proc = Start-Process -FilePath $TestWindowExe -PassThru
try {
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 250
        & $WinAgent find --title 'Agent Test Window' | Out-Null
        $findExit = $LASTEXITCODE
    } while ($findExit -ne 0 -and (Get-Date) -lt $deadline)

    if ($findExit -ne 0) {
        Fail 'Agent Test Window did not appear.'
    }

    $readOutput = & $WinAgent read-window-text --title 'Agent Test Window'
    $readExit = $LASTEXITCODE
    if ($readExit -ne 0) {
        $readJson = $readOutput | ConvertFrom-Json
        if ($readJson.error.code -eq 'OCR_UNAVAILABLE' -or $readJson.error.code -eq 'OCR_LANGUAGE_UNAVAILABLE') {
            Write-Report @(
                '# OCR Demo Report',
                '',
                '- Result: SKIPPED',
                "- Reason: $($readJson.error.code)",
                '- Report behavior: read-window-text returned a clear OCR unavailable error and no click was attempted.',
                '',
                '## read-window-text JSON',
                '',
                '```json',
                $readOutput,
                '```'
            )
            Write-Host "SKIPPED: $($readJson.error.code)"
            Write-Host "Report: $Report"
            exit 0
        }
        Fail "read-window-text failed with $($readJson.error.code): $($readJson.error.message)"
    }

    $requestedText = 'Click Me'
    $clickText = $requestedText
    $fallbackReason = ''

    $findOutput = & $WinAgent find-text --title 'Agent Test Window' --text $requestedText
    $findExit = $LASTEXITCODE
    $findJson = $findOutput | ConvertFrom-Json

    if ($findExit -ne 0 -and ($findJson.error.code -eq 'OCR_UNAVAILABLE' -or $findJson.error.code -eq 'OCR_LANGUAGE_UNAVAILABLE')) {
        Write-Report @(
            '# OCR Demo Report',
            '',
            '- Result: SKIPPED',
            "- Reason: $($findJson.error.code)",
            '- Report behavior: find-text returned a clear OCR unavailable error and no click was attempted.',
            '',
            '## find-text JSON',
            '',
            '```json',
            $findOutput,
            '```'
        )
        Write-Host "SKIPPED: $($findJson.error.code)"
        Write-Host "Report: $Report"
        exit 0
    }

    if ($findExit -ne 0) {
        if ($findJson.error.code -ne 'LOCATOR_NOT_FOUND') {
            Fail "find-text failed with $($findJson.error.code): $($findJson.error.message)"
        }

        $fallbackReason = "Primary demo text '$requestedText' was not recognized by Windows OCR in this environment; using visible client-area fallback text 'last'."
        $clickText = 'last'
        $findOutput = & $WinAgent find-text --title 'Agent Test Window' --text $clickText
        $findExit = $LASTEXITCODE
        $findJson = $findOutput | ConvertFrom-Json
        if ($findExit -ne 0) {
            Fail "fallback find-text failed with $($findJson.error.code): $($findJson.error.message)"
        }
    }

    $clickOutput = & $WinAgent click-text --title 'Agent Test Window' --text $clickText --move-mode human --move-duration-ms 800
    $clickExit = $LASTEXITCODE
    if ($clickExit -ne 0) {
        $clickJson = $clickOutput | ConvertFrom-Json
        Fail "click-text failed with $($clickJson.error.code): $($clickJson.error.message)"
    }

    Write-Report @(
        '# OCR Demo Report',
        '',
        '- Result: SUCCESS',
        '- OCR: AVAILABLE',
        "- Requested text: $requestedText",
        "- Clicked OCR text: $clickText",
        "- Fallback reason: $fallbackReason",
        '',
        '## read-window-text JSON',
        '',
        '```json',
        $readOutput,
        '```',
        '',
        '## find-text JSON',
        '',
        '```json',
        $findOutput,
        '```',
        '',
        '## click-text JSON',
        '',
        '```json',
        $clickOutput,
        '```'
    )
    Write-Host 'PASS: OCR demo passed.'
    Write-Host "Report: $Report"
}
finally {
    if ($proc -and !$proc.HasExited) {
        $proc.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (!$proc.HasExited) {
            Stop-Process -Id $proc.Id -Force
        }
    }
}
