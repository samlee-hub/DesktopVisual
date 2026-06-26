param(
    [string]$Root = '',
    [string]$TestRepoRoot = ''
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev1.0.5_capture_ocr_performance_pipeline'
$ReportPath = Join-Path $OutDir 'ocr_memory_frame_selftest_report.md'
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
    param([string]$Label)
    $script = @"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
`$form = New-Object System.Windows.Forms.Form
`$form.Text = 'DesktopVisual OCR Memory Frame Host'
`$form.Width = 1120
`$form.Height = 420
`$form.StartPosition = 'CenterScreen'
`$form.BackColor = [System.Drawing.Color]::White
`$label = New-Object System.Windows.Forms.Label
`$label.Text = "$Label`r`n$Label"
`$label.AutoSize = `$false
`$label.Left = 40
`$label.Top = 95
`$label.Width = 1040
`$label.Height = 210
`$label.ForeColor = [System.Drawing.Color]::Black
`$label.Font = New-Object System.Drawing.Font('Segoe UI', 36, [System.Drawing.FontStyle]::Bold)
`$form.Controls.Add(`$label)
`$form.TopMost = `$true
`$form.Add_Shown({ `$form.Activate(); `$form.BringToFront(); `$form.Refresh() })
[System.Windows.Forms.Application]::Run(`$form)
"@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
    return Start-Process -FilePath powershell.exe -ArgumentList @('-NoProfile', '-Sta', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded) -PassThru
}

function Capture-Ocr-UntilText {
    param(
        [string]$ExpectedPattern,
        [string]$OriginatingCommand,
        [int]$Attempts = 6
    )
    $lastCapture = $null
    $lastOcr = $null
    for ($i = 0; $i -lt $Attempts; $i++) {
        $lastCapture = Invoke-Agent @('capture-fullscreen-frame', '--originating-command', $OriginatingCommand)
        $lastOcr = Invoke-Agent @('ocr-fullscreen-frame', '--frame-id', $lastCapture.data.frame_id)
        if ($lastOcr.data.text -match $ExpectedPattern) {
            return @{ Capture = $lastCapture; Ocr = $lastOcr; Attempt = $i + 1 }
        }
        Start-Sleep -Milliseconds 600
    }
    throw "OCR did not recognize expected text after $Attempts attempts. Last frame_id=$($lastCapture.data.frame_id). Last OCR text prefix=$(([string]$lastOcr.data.text).Substring(0, [Math]::Min(160, ([string]$lastOcr.data.text).Length)))"
}

try {
    Add-Check 'winagent exists' (Test-Path -LiteralPath $WinAgent) $WinAgent
    $hostProcess = Start-OcrHostWindow -Label 'DesktopVisual OCR Memory Frame Test'
    Start-Sleep -Milliseconds 1800

    $expectedPattern = '(?s)DesktopVisua[lI].*OCR Memory Frame Test'
    $sample = Capture-Ocr-UntilText -ExpectedPattern $expectedPattern -OriginatingCommand 'ocr_memory_frame_selftest'
    $capture = $sample.Capture
    $ocr = $sample.Ocr
    Add-Check 'capture has frame id' (-not [string]::IsNullOrWhiteSpace($capture.data.frame_id)) "frame_id=$($capture.data.frame_id)"
    Add-Check 'ocr ok' ($ocr.ok -eq $true) "ok=$($ocr.ok) error=$($ocr.error.code)"
    Add-Check 'recognized test text' ($ocr.data.text -match $expectedPattern) 'expected text visible in OCR result'
    Add-Check 'visible test text stabilized before assertion' ([int]$sample.Attempt -ge 1) "attempt=$($sample.Attempt)"
    Add-Check 'png not read for ocr' ($ocr.data.png_read_for_ocr -eq $false) "png_read_for_ocr=$($ocr.data.png_read_for_ocr)"
    Add-Check 'ocr source memory frame' ($ocr.data.ocr_source -eq 'memory_frame') "ocr_source=$($ocr.data.ocr_source)"
    Add-Check 'frame id bound' ($ocr.data.frame_id -eq $capture.data.frame_id) "ocr_frame_id=$($ocr.data.frame_id)"
    Add-Check 'screenshot id bound' ($ocr.data.screenshot_id -eq $capture.data.screenshot_id) "ocr_screenshot_id=$($ocr.data.screenshot_id)"
    Add-Check 'cache fields present' ($null -ne $ocr.data.PSObject.Properties['ocr_cache_hit']) 'ocr_cache_hit field present'

    $flush = Invoke-Agent @('evidence-flush', '--frame-id', $capture.data.frame_id)
    Add-Check 'flush ok' ($flush.ok -eq $true) "ok=$($flush.ok)"
    Add-Check 'evidence exists after flush' (Test-Path -LiteralPath $capture.data.evidence_png_path) $capture.data.evidence_png_path

    Remove-Item -LiteralPath $capture.data.evidence_png_path -Force -ErrorAction Stop
    $afterDelete = Invoke-Agent @('ocr-fullscreen-frame', '--frame-id', $capture.data.frame_id)
    Add-Check 'ocr works after evidence png delete' ($afterDelete.ok -eq $true) "ok=$($afterDelete.ok)"
    Add-Check 'still not png read' ($afterDelete.data.png_read_for_ocr -eq $false) "png_read_for_ocr=$($afterDelete.data.png_read_for_ocr)"

    if (-not [string]::IsNullOrWhiteSpace($capture.data.raw_frame_cache_path) -and (Test-Path -LiteralPath $capture.data.raw_frame_cache_path)) {
        Remove-Item -LiteralPath $capture.data.raw_frame_cache_path -Force
        $expired = Invoke-Agent @('ocr-fullscreen-frame', '--frame-id', $capture.data.frame_id) -AllowedExitCodes @(1)
        Add-Check 'expired frame returns FRAME_EXPIRED' ($expired.error.code -eq 'FRAME_EXPIRED') "error=$($expired.error.code)"
    }

    $report = @(
        '# OCR Memory Frame Selftest Report',
        '',
        '- status: PASS',
        "- frame_id: $($capture.data.frame_id)",
        "- screenshot_id: $($capture.data.screenshot_id)",
        "- ocr_source: $($ocr.data.ocr_source)",
        "- png_read_for_ocr: $($ocr.data.png_read_for_ocr)",
        "- text_count: $($ocr.data.text_count)",
        "- evidence_png_path: $($capture.data.evidence_png_path)",
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Host "PASS: ocr_memory_frame_selftest ($ReportPath)"
    exit 0
} catch {
    $report = @(
        '# OCR Memory Frame Selftest Report',
        '',
        '- status: BLOCKED',
        "- error: $($_.Exception.Message)",
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Error "BLOCKED: ocr_memory_frame_selftest failed: $($_.Exception.Message). Report: $ReportPath"
    exit 1
} finally {
    if ($hostProcess -and -not $hostProcess.HasExited) {
        Stop-Process -Id $hostProcess.Id -Force -ErrorAction SilentlyContinue
    }
}
