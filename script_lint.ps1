param(
    [string]$Root = '',
    [string]$TestRepoRoot = '',
    [switch]$Help,
    [switch]$DryRun,
    [switch]$IncludeGenerated
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
if (-not $TestRepoRoot) { $TestRepoRoot = $env:DESKTOPVISUAL_TESTREPO_ROOT }
if (-not $TestRepoRoot) {
    $sibling = Join-Path (Split-Path -Parent $Root) 'testrepo'
    if (Test-Path -LiteralPath $sibling) { $TestRepoRoot = $sibling }
}
if (-not $TestRepoRoot) { $TestRepoRoot = 'D:\testrepo' }
$TestRepoRoot = [System.IO.Path]::GetFullPath($TestRepoRoot)
$TestWindowRoot = Join-Path $TestRepoRoot 'testwindow'
$Report = Join-Path $Root 'artifacts\script_lint_report.md'

function Show-Help {
    Write-Host 'DesktopVisual script lint'
    Write-Host ''
    Write-Host 'Usage:'
    Write-Host '  .\script_lint.ps1 [-Root <path>] [-DryRun] [-IncludeGenerated]'
    Write-Host ''
    Write-Host 'Checks:'
    Write-Host '  - PowerShell AST parse errors'
    Write-Host '  - risky backtick double-quote sequences'
    Write-Host '  - bare Markdown list lines outside here-strings'
    Write-Host '  - Chinese smart quotes'
    Write-Host '  - manual scripts exposing -Help or -DryRun'
    Write-Host '  - rc_check.ps1 includes script_lint.ps1'
}

if ($Help) {
    Show-Help
    exit 0
}

function Add-Failure {
    param(
        [System.Collections.Generic.List[object]]$Failures,
        [string]$Check,
        [string]$Path,
        [int]$Line,
        [string]$Message
    )

    $Failures.Add([pscustomobject]@{
        Check = $Check
        Path = $Path
        Line = $Line
        Message = $Message
    }) | Out-Null
}

function Test-IsGeneratedPath {
    param([string]$Path)
    return $Path -match '\\(artifacts|bin|dist|logs|patches|agent_reports)\\'
}

function Get-HereStringLines {
    param([string[]]$Lines)

    $inside = $false
    $markers = @{}
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = [string]$Lines[$i]
        if (-not $inside -and $line -match '@["'']\s*$') {
            $inside = $true
            $markers[$i + 1] = $true
            continue
        }
        if ($inside) {
            $markers[$i + 1] = $true
            if ($line -match '^["'']@') {
                $inside = $false
            }
        }
    }
    return $markers
}

$files = @()
foreach ($base in @($Root, $TestWindowRoot)) {
    if (Test-Path -LiteralPath $base) {
        $files += Get-ChildItem -LiteralPath $base -Recurse -Force -File -Filter '*.ps1'
    }
}
if (-not $IncludeGenerated) {
    $files = @($files | Where-Object { -not (Test-IsGeneratedPath $_.FullName) })
}

$failures = New-Object System.Collections.Generic.List[object]
$backtickQuoteSequence = [string]([char]96) + '"'

foreach ($file in $files) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    foreach ($errorItem in $errors) {
        Add-Failure $failures 'parse' $file.FullName $errorItem.Extent.StartLineNumber $errorItem.Message
    }

    $lines = Get-Content -LiteralPath $file.FullName
    $hereStringLines = Get-HereStringLines $lines
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $lineNumber = $i + 1
        $line = [string]$lines[$i]
        if ($line.Contains($backtickQuoteSequence)) {
            Add-Failure $failures 'backtick_quote' $file.FullName $lineNumber 'Avoid backtick double-quote. Use single-quoted format strings or argument arrays.'
        }
        if ($line -match '[\u2018\u2019\u201C\u201D]') {
            Add-Failure $failures 'smart_quote' $file.FullName $lineNumber 'Chinese smart quotes are not allowed in scripts.'
        }
        if (-not $hereStringLines.ContainsKey($lineNumber) -and $line -match '^\s*[-*+]\s+\S') {
            Add-Failure $failures 'bare_markdown_list' $file.FullName $lineNumber 'Bare Markdown list syntax is not valid PowerShell outside strings/here-strings.'
        }
    }
}

$manualScripts = @(
    'build.ps1',
    'clean_artifacts.ps1',
    'dogfood_matrix.ps1',
    'motion_calibration_session.ps1',
    'motion_profile_demo.ps1',
    'package_source.ps1',
    'release.ps1',
    'run_demo.ps1',
    'run_dogfood.ps1',
    'run_image_demo.ps1',
    'run_ocr_demo.ps1',
    'run_real_dev_workflow.ps1',
    'run_uia_demo.ps1',
    'serve_start.ps1',
    'serve_stop.ps1',
    'verify_release.ps1',
    'dogfood\calculator\run.ps1',
    'dogfood\edge\run.ps1',
    'dogfood\explorer\run.ps1',
    'dogfood\notepad\run.ps1',
    'dogfood\vscode\run.ps1',
    'script_lint.ps1',
    '..\testrepo\testwindow\build.ps1'
)

foreach ($relative in $manualScripts) {
    $path = if ($relative -like '..\testrepo\testwindow\*') {
        Join-Path $TestWindowRoot ($relative.Substring('..\testrepo\testwindow\'.Length))
    } else {
        Join-Path $Root $relative
    }
    if (-not (Test-Path -LiteralPath $path)) {
        Add-Failure $failures 'manual_script_missing' $path 0 'Manual script listed in script_lint.ps1 was not found.'
        continue
    }
    $raw = Get-Content -LiteralPath $path -Raw
    $hasHelp = $raw -match '(?i)\[switch\]\s*\$Help\b|\$(Help|ShowHelp)\b|\.SYNOPSIS|\.PARAMETER'
    $hasDryRun = $raw -match '(?i)\[switch\]\s*\$DryRun\b|\$DryRun\b'
    if (-not $hasHelp -and -not $hasDryRun) {
        Add-Failure $failures 'manual_help_or_dryrun' $path 1 'Manual scripts must expose -Help or -DryRun.'
    }
}

$rcCheck = Join-Path $Root 'rc_check.ps1'
if (Test-Path -LiteralPath $rcCheck) {
    $rcText = Get-Content -LiteralPath $rcCheck -Raw
    if ($rcText -notmatch 'script_lint\.ps1') {
        Add-Failure $failures 'rc_check_integration' $rcCheck 1 'rc_check.ps1 must run script_lint.ps1.'
    }
} else {
    Add-Failure $failures 'rc_check_missing' $rcCheck 0 'rc_check.ps1 was not found.'
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Report) | Out-Null
$status = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# DesktopVisual Script Lint Report')
$lines.Add('')
$lines.Add("- Result: $status")
$lines.Add("- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$lines.Add("- Files scanned: $($files.Count)")
$lines.Add("- Include generated: $([bool]$IncludeGenerated)")
$lines.Add("- Failures: $($failures.Count)")
$lines.Add('')
$lines.Add('| check | path | line | message |')
$lines.Add('|---|---|---:|---|')
foreach ($failure in $failures) {
    $msg = ([string]$failure.Message) -replace '\|', '/'
    $lines.Add("| $($failure.Check) | `$($failure.Path)` | $($failure.Line) | $msg |")
}

if (-not $DryRun) {
    $lines | Set-Content -LiteralPath $Report -Encoding UTF8
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL: script lint found $($failures.Count) issue(s)." -ForegroundColor Red
    foreach ($failure in $failures | Select-Object -First 30) {
        Write-Host "- [$($failure.Check)] $($failure.Path):$($failure.Line) $($failure.Message)"
    }
    if ($failures.Count -gt 30) {
        Write-Host "... $($failures.Count - 30) more issue(s). See $Report"
    }
    if (-not $DryRun) {
        Write-Host "Report: $Report"
    }
    exit 1
}

Write-Host "PASS: script lint scanned $($files.Count) script(s)."
if (-not $DryRun) {
    Write-Host "Report: $Report"
}
exit 0
