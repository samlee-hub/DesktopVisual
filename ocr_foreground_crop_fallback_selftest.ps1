param(
    [string]$Root = '',
    [string]$TestRepoRoot = ''
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev1.0.5_capture_ocr_performance_pipeline'
$ReportPath = Join-Path $OutDir 'ocr_foreground_crop_fallback_selftest_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$checks = New-Object System.Collections.Generic.List[string]
$hostProcess = $null

function Add-Check {
    param([string]$Name, [bool]$Passed, [string]$Detail)
    $status = if ($Passed) { 'PASS' } else { 'FAIL' }
    $script:checks.Add("- ${status}: ${Name} - ${Detail}") | Out-Null
    if (-not $Passed) { throw "${Name}: ${Detail}" }
}

function Invoke-Agent {
    param([string[]]$Arguments, [int[]]$AllowedExitCodes = @(0))
    $output = & $WinAgent @Arguments
    $exit = $LASTEXITCODE
    if ($AllowedExitCodes -notcontains $exit) {
        throw "winagent $($Arguments -join ' ') exited ${exit}: $($output | Out-String)"
    }
    $text = ($output | Select-Object -Last 1)
    if ([string]::IsNullOrWhiteSpace($text)) { throw 'winagent produced no JSON output' }
    return $text | ConvertFrom-Json
}

function Start-OcrHostWindow {
    $script = @"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
`$form = New-Object System.Windows.Forms.Form
`$form.Text = 'DesktopVisual OCR Foreground Frame Host'
`$form.Width = 1140
`$form.Height = 430
`$form.StartPosition = 'CenterScreen'
`$form.BackColor = [System.Drawing.Color]::White
`$label = New-Object System.Windows.Forms.Label
`$label.Text = "DesktopVisual Foreground Crop Frame Test`r`nDesktopVisual Foreground Crop Frame Test"
`$label.AutoSize = `$false
`$label.Left = 40
`$label.Top = 95
`$label.Width = 1060
`$label.Height = 220
`$label.ForeColor = [System.Drawing.Color]::Black
`$label.Font = New-Object System.Drawing.Font('Segoe UI', 34, [System.Drawing.FontStyle]::Bold)
`$form.Controls.Add(`$label)
`$form.TopMost = `$true
`$form.Add_Shown({ `$form.Activate(); `$form.BringToFront(); `$form.Refresh() })
[System.Windows.Forms.Application]::Run(`$form)
"@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
    return Start-Process -FilePath powershell.exe -ArgumentList @('-NoProfile', '-Sta', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded) -PassThru
}

try {
    Add-Check 'winagent exists' (Test-Path -LiteralPath $WinAgent) $WinAgent
    $hostProcess = Start-OcrHostWindow
    Start-Sleep -Milliseconds 1800

    $expectedPattern = '(?s)DesktopVisua[lI].*Foreground Crop Frame Test'
    $capture = Invoke-Agent @('capture-fullscreen-frame', '--originating-command', 'ocr_foreground_crop_fallback_selftest')
    $crop = Invoke-Agent @('ocr-foreground-from-frame', '--frame-id', $capture.data.frame_id)
    Add-Check 'foreground crop OCR ok' ($crop.ok -eq $true) "ok=$($crop.ok)"
    Add-Check 'foreground text recognized' ($crop.data.text -match $expectedPattern) 'expected foreground text'
    Add-Check 'crop from full screen frame' ($crop.data.crop_from_fullscreen_frame -eq $true) "crop=$($crop.data.crop_from_fullscreen_frame)"
    Add-Check 'partial screenshot not used' ($crop.data.partial_screenshot_used -eq $false) "partial=$($crop.data.partial_screenshot_used)"
    Add-Check 'same frame id' ($crop.data.frame_id -eq $capture.data.frame_id) "frame_id=$($crop.data.frame_id)"
    Add-Check 'same screenshot id' ($crop.data.screenshot_id -eq $capture.data.screenshot_id) "screenshot_id=$($crop.data.screenshot_id)"
    Add-Check 'foreground rect present' ($null -ne $crop.data.foreground_crop_rect) 'foreground_crop_rect present'

    $fallback = Invoke-Agent @('ocr-foreground-from-frame', '--frame-id', $capture.data.frame_id, '--force-crop-failure', 'true')
    Add-Check 'fallback command ok' ($fallback.ok -eq $true) "ok=$($fallback.ok)"
    Add-Check 'fallback used' ($fallback.data.full_screen_ocr_fallback_used -eq $true) "fallback=$($fallback.data.full_screen_ocr_fallback_used)"
    Add-Check 'same frame for fallback' ($fallback.data.same_frame_for_fallback -eq $true) "same_frame=$($fallback.data.same_frame_for_fallback)"
    Add-Check 'no recapture for fallback' ($fallback.data.screenshot_recaptured_for_fallback -eq $false) "recaptured=$($fallback.data.screenshot_recaptured_for_fallback)"
    Add-Check 'fallback text recognized' ($fallback.data.text -match $expectedPattern) 'expected fallback text'

    $flush = Invoke-Agent @('evidence-flush', '--frame-id', $capture.data.frame_id)
    Add-Check 'flush ok' ($flush.ok -eq $true) "ok=$($flush.ok)"
    Add-Check 'evidence png exists after flush' (Test-Path -LiteralPath $capture.data.evidence_png_path) $capture.data.evidence_png_path

    $report = @(
        '# OCR Foreground Crop Fallback Selftest Report',
        '',
        '- status: PASS',
        "- frame_id: $($capture.data.frame_id)",
        "- screenshot_id: $($capture.data.screenshot_id)",
        '- crop_from_fullscreen_frame: true',
        '- partial_screenshot_used: false',
        '- full_screen_ocr_fallback_used: true',
        '- same_frame_for_fallback: true',
        "- evidence_png_path: $($capture.data.evidence_png_path)",
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Host "PASS: ocr_foreground_crop_fallback_selftest ($ReportPath)"
    exit 0
} catch {
    $report = @(
        '# OCR Foreground Crop Fallback Selftest Report',
        '',
        '- status: BLOCKED',
        "- error: $($_.Exception.Message)",
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Error "BLOCKED: ocr_foreground_crop_fallback_selftest failed: $($_.Exception.Message). Report: $ReportPath"
    exit 1
} finally {
    if ($hostProcess -and -not $hostProcess.HasExited) {
        Stop-Process -Id $hostProcess.Id -Force -ErrorAction SilentlyContinue
    }
}
