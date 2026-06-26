param(
    [string]$Root = '',
    [string]$TestRepoRoot = ''
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev1.0.5_capture_ocr_performance_pipeline'
$ReportPath = Join-Path $OutDir 'ocr_cache_tile_hash_selftest_report.md'
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
    param([string]$Text)
    $script = @"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
`$form = New-Object System.Windows.Forms.Form
`$form.Text = 'DesktopVisual OCR Cache Frame Host'
`$form.Width = 1120
`$form.Height = 420
`$form.StartPosition = 'CenterScreen'
`$form.BackColor = [System.Drawing.Color]::White
`$label = New-Object System.Windows.Forms.Label
`$label.Text = "$Text`r`n$Text"
`$label.AutoSize = `$false
`$label.Left = 40
`$label.Top = 95
`$label.Width = 1040
`$label.Height = 210
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
    Invoke-Agent @('ocr-cache-clear') | Out-Null
    $hostProcess = Start-OcrHostWindow -Text 'DesktopVisual OCR Cache Frame Test'
    Start-Sleep -Milliseconds 1800

    $capture = Invoke-Agent @('capture-fullscreen-frame', '--originating-command', 'ocr_cache_tile_hash_selftest')
    $first = Invoke-Agent @('ocr-fullscreen-frame', '--frame-id', $capture.data.frame_id)
    Add-Check 'first full OCR miss' ($first.data.ocr_cache_hit -eq $false) "hit=$($first.data.ocr_cache_hit)"
    Add-Check 'first cache validated' ($first.data.cache_validated -eq $true) "validated=$($first.data.cache_validated)"
    $second = Invoke-Agent @('ocr-fullscreen-frame', '--frame-id', $capture.data.frame_id)
    Add-Check 'second full OCR hit' ($second.data.ocr_cache_hit -eq $true) "hit=$($second.data.ocr_cache_hit)"
    Add-Check 'second full cache key present' (-not [string]::IsNullOrWhiteSpace($second.data.cache_key)) "cache_key=$($second.data.cache_key)"

    $cropFirst = Invoke-Agent @('ocr-foreground-from-frame', '--frame-id', $capture.data.frame_id)
    Add-Check 'first crop OCR ok' ($cropFirst.ok -eq $true) "ok=$($cropFirst.ok)"
    $cropSecond = Invoke-Agent @('ocr-foreground-from-frame', '--frame-id', $capture.data.frame_id)
    Add-Check 'second crop OCR cache hit' ($cropSecond.data.ocr_cache_hit -eq $true) "hit=$($cropSecond.data.ocr_cache_hit)"
    Add-Check 'second crop tile cache hit' ($cropSecond.data.tile_cache_hit -eq $true) "tile_hit=$($cropSecond.data.tile_cache_hit)"
    Add-Check 'tile hash present' (-not [string]::IsNullOrWhiteSpace($cropSecond.data.tile_hash)) "tile_hash=$($cropSecond.data.tile_hash)"

    if ($hostProcess -and -not $hostProcess.HasExited) {
        Stop-Process -Id $hostProcess.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
    }
    $hostProcess = Start-OcrHostWindow -Text 'DesktopVisual OCR Cache Changed Text'
    Start-Sleep -Milliseconds 1800
    $changedCapture = Invoke-Agent @('capture-fullscreen-frame', '--originating-command', 'ocr_cache_tile_hash_selftest_changed')
    $changed = Invoke-Agent @('ocr-fullscreen-frame', '--frame-id', $changedCapture.data.frame_id)
    Add-Check 'changed frame does not reuse old frame cache' ($changed.data.ocr_cache_hit -eq $false) "hit=$($changed.data.ocr_cache_hit)"
    Add-Check 'changed cache key differs' ($changed.data.cache_key -ne $second.data.cache_key) 'cache key changed'

    Invoke-Agent @('ocr-cache-clear') | Out-Null
    $afterClear = Invoke-Agent @('ocr-fullscreen-frame', '--frame-id', $changedCapture.data.frame_id)
    Add-Check 'cache clear causes miss' ($afterClear.data.ocr_cache_hit -eq $false) "hit=$($afterClear.data.ocr_cache_hit)"
    $status = Invoke-Agent @('ocr-cache-status')
    Add-Check 'cache status command ok' ($status.ok -eq $true) "ok=$($status.ok)"

    $report = @(
        '# OCR Cache Tile Hash Selftest Report',
        '',
        '- status: PASS',
        "- frame_id: $($capture.data.frame_id)",
        "- first_full_cache_hit: $($first.data.ocr_cache_hit)",
        "- second_full_cache_hit: $($second.data.ocr_cache_hit)",
        "- second_crop_cache_hit: $($cropSecond.data.ocr_cache_hit)",
        "- second_crop_tile_cache_hit: $($cropSecond.data.tile_cache_hit)",
        "- changed_frame_cache_hit: $($changed.data.ocr_cache_hit)",
        "- after_clear_cache_hit: $($afterClear.data.ocr_cache_hit)",
        "- cache_entry_count: $($status.data.entry_count)",
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Host "PASS: ocr_cache_tile_hash_selftest ($ReportPath)"
    exit 0
} catch {
    $report = @(
        '# OCR Cache Tile Hash Selftest Report',
        '',
        '- status: BLOCKED',
        "- error: $($_.Exception.Message)",
        '',
        '## Checks',
        ''
    ) + $checks
    Set-Content -LiteralPath $ReportPath -Value ($report -join [Environment]::NewLine) -Encoding UTF8
    Write-Error "BLOCKED: ocr_cache_tile_hash_selftest failed: $($_.Exception.Message). Report: $ReportPath"
    exit 1
} finally {
    if ($hostProcess -and -not $hostProcess.HasExited) {
        Stop-Process -Id $hostProcess.Id -Force -ErrorAction SilentlyContinue
    }
}
