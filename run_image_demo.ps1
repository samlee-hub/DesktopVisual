param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\run_image_demo.ps1'
    Write-Host 'Runs the TestWindow BMP image-location demo.'
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
$Assets = Join-Path $Root 'assets'
$Template = Join-Path $Assets 'click_button.bmp'
$SourceShot = Join-Path $Artifacts 'image_demo_source.bmp'
$Report = Join-Path $Artifacts 'image_demo_report.md'
$StateFile = Join-Path $TestWindowRoot 'runtime\state.txt'

function Fail($Message) {
    New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null
    @(
        '# Image Demo Report',
        '',
        '- Result: FAILED',
        "- Message: $Message"
    ) | Set-Content -Encoding UTF8 -LiteralPath $Report
    Write-Host "FAIL: $Message"
    exit 1
}

function Get-ClickCount {
    if (!(Test-Path -LiteralPath $StateFile)) {
        return -1
    }
    $line = Get-Content -LiteralPath $StateFile | Where-Object { $_ -like 'clicks=*' } | Select-Object -First 1
    if (!$line) {
        return -1
    }
    return [int]($line.Substring('clicks='.Length))
}

function New-ButtonTemplate {
    param([string]$Source, [string]$Destination)

    Add-Type -AssemblyName System.Drawing
    $bitmap = [System.Drawing.Bitmap]::FromFile($Source)
    try {
        $rect = New-Object System.Drawing.Rectangle(68, 101, 120, 36)
        $clone = $bitmap.Clone($rect, $bitmap.PixelFormat)
        try {
            $clone.Save($Destination, [System.Drawing.Imaging.ImageFormat]::Bmp)
        }
        finally {
            $clone.Dispose()
        }
    }
    finally {
        $bitmap.Dispose()
    }
}

& (Join-Path $Root 'build.ps1') -Root $Root -TestRepoRoot $TestRepoRoot
if ($LASTEXITCODE -ne 0) {
    Fail "build.ps1 failed with exit $LASTEXITCODE"
}

New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null
New-Item -ItemType Directory -Force -Path $Assets | Out-Null

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

    & $WinAgent screenshot --title 'Agent Test Window' --out $SourceShot | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Fail 'Could not capture source screenshot for template.'
    }

    New-ButtonTemplate -Source $SourceShot -Destination $Template
    if (!(Test-Path -LiteralPath $Template)) {
        Fail "Template was not created: $Template"
    }

    $beforeClicks = Get-ClickCount
    $findImage = & $WinAgent find-image --title 'Agent Test Window' --template $Template --tolerance 10
    $findExit = $LASTEXITCODE
    if ($findExit -ne 0) {
        Fail "find-image failed: $findImage"
    }

    $clickImage = & $WinAgent click-image --title 'Agent Test Window' --template $Template --move-mode human --move-duration-ms 800
    $clickExit = $LASTEXITCODE
    if ($clickExit -ne 0) {
        Fail "click-image failed: $clickImage"
    }

    Start-Sleep -Milliseconds 500
    $afterClicks = Get-ClickCount
    if ($afterClicks -le $beforeClicks) {
        Fail "click count did not increase. before=$beforeClicks after=$afterClicks"
    }

    @(
        '# Image Demo Report',
        '',
        '- Result: SUCCESS',
        "- Template: $Template",
        "- Clicks before: $beforeClicks",
        "- Clicks after: $afterClicks",
        '',
        '## find-image JSON',
        '',
        '```json',
        $findImage,
        '```',
        '',
        '## click-image JSON',
        '',
        '```json',
        $clickImage,
        '```'
    ) | Set-Content -Encoding UTF8 -LiteralPath $Report

    Write-Host 'PASS: Image demo passed.'
    Write-Host "Template: $Template"
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
