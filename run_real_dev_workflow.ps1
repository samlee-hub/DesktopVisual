param(
    [string]$Root = '',
    [switch]$Help,
    [string]$TargetTitle,
    [string]$StateFile,
    [string]$CaseFile = '',
    [string]$ReportFile = ''
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\run_real_dev_workflow.ps1 [-Root <path>] -TargetTitle <title> -StateFile <path> [-CaseFile <path>] [-ReportFile <path>]'
    Write-Host 'Runs a reviewed real-development workflow case against an authorized target.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$Artifacts = Join-Path $Root 'artifacts'
if (-not $CaseFile) { $CaseFile = Join-Path $Root 'cases\real_dev_workflow.template.case' }
if (-not $ReportFile) { $ReportFile = Join-Path $Artifacts 'real_dev_workflow_report.md' }
$AllowedRoots = @(
    $Root,
    'D:\testrepo\testwindow'
)

function Write-WorkflowReport {
    param(
        [string]$Result,
        [string]$Reason,
        [string[]]$Details = @()
    )

    New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null
    $lines = @(
        '# Real Dev Workflow Report',
        '',
        "- Result: $Result",
        "- Reason: $Reason",
        "- TargetTitle: $TargetTitle",
        "- CaseFile: $CaseFile",
        "- ReportFile: $ReportFile"
    )
    if ($StateFile) {
        $lines += "- StateFile: $StateFile"
    }
    if ($Details.Count -gt 0) {
        $lines += ''
        $lines += '## Details'
        $lines += ''
        $lines += $Details
    }
    $lines | Set-Content -Encoding UTF8 -LiteralPath $ReportFile
}

function Is-UnderAllowedRoot {
    param([string]$Path)

    if (!$Path) {
        return $true
    }
    try {
        $full = [System.IO.Path]::GetFullPath($Path)
    } catch {
        return $false
    }
    foreach ($rootPath in $AllowedRoots) {
        $rootFull = [System.IO.Path]::GetFullPath($rootPath)
        if ($full.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

if (!$TargetTitle) {
    Write-WorkflowReport -Result 'SKIPPED' -Reason 'Real dev workflow requires user-approved target window title and project path.' -Details @(
        '- No real project path was accessed.',
        '- Provide -TargetTitle and a case file configured for an authorized window.',
        '- Provide -StateFile only after approving that path.'
    )
    Write-Host 'SKIPPED: Real dev workflow requires user-approved project path.'
    Write-Host "Report: $ReportFile"
    exit 0
}

if ($StateFile -and !(Is-UnderAllowedRoot -Path $StateFile)) {
    Write-WorkflowReport -Result 'SKIPPED' -Reason 'StateFile is outside currently authorized roots.' -Details @(
        "- Requested StateFile: $StateFile",
        '- The script did not read this path.',
        '- Ask the user to approve this exact path before rerunning.'
    )
    Write-Host 'SKIPPED: StateFile is outside authorized roots. No access performed.'
    Write-Host "Requested StateFile: $StateFile"
    Write-Host "Report: $ReportFile"
    exit 0
}

if (!(Test-Path -LiteralPath $WinAgent)) {
    throw "Missing $WinAgent. Run $Root\build.ps1 first."
}
if (!(Test-Path -LiteralPath $CaseFile)) {
    throw "Missing case file: $CaseFile"
}

$caseText = Get-Content -Raw -LiteralPath $CaseFile
if ($caseText -match 'USER_APPROVED_') {
    Write-WorkflowReport -Result 'SKIPPED' -Reason 'Case file still contains USER_APPROVED placeholders.' -Details @(
        '- Fill placeholders only after the user approves the target window and state file path.',
        '- No real project path was accessed.'
    )
    Write-Host 'SKIPPED: Case file still contains USER_APPROVED placeholders.'
    Write-Host "Report: $ReportFile"
    exit 0
}

$find = & $WinAgent find --title $TargetTitle
if ($LASTEXITCODE -ne 0) {
    Write-WorkflowReport -Result 'FAILED' -Reason 'Target window was not found or not unique.' -Details @($find)
    Write-Host 'FAILED: Target window was not found or not unique.'
    Write-Host "Report: $ReportFile"
    exit 1
}

$result = & $WinAgent run-case --file $CaseFile --report $ReportFile
$exit = $LASTEXITCODE
Write-Output $result
Write-Host "Report: $ReportFile"
exit $exit
