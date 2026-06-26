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
$Artifacts = Join-Path $Root 'artifacts\recovery'
$Report = Join-Path $Artifacts 'recovery_selftest_report.md'

function Fail($Message) { throw $Message }

function Invoke-AgentJson {
    param(
        [string[]]$CmdArgs,
        [int[]]$AllowedExitCodes = @(0)
    )
    $output = & $WinAgent @CmdArgs 2>&1
    $exit = $LASTEXITCODE
    if ($AllowedExitCodes -notcontains $exit) {
        Fail "winagent $($CmdArgs -join ' ') exited $exit with output: $output"
    }
    try {
        $json = $output | ConvertFrom-Json
    } catch {
        Fail "Invalid JSON from winagent $($CmdArgs -join ' '): $output"
    }
    return @{ exit = $exit; text = [string]$output; json = $json }
}

function Add-Check {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    $script:Checks += [pscustomobject]@{
        Name = $Name
        Status = $(if ($Ok) { 'PASS' } else { 'FAIL' })
        Detail = $Detail
    }
    if (-not $Ok) { Fail "$Name failed: $Detail" }
}

function Write-TaskJson {
    param([string]$Path, [object]$Task)
    $Task | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

if (-not $SkipBuild) {
    & (Join-Path $Root 'build.ps1') -Root $Root
    if ($LASTEXITCODE -ne 0) { Fail 'Build failed.' }
}

New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null
$script:Checks = @()

$proc = $null
try {
    $proc = Start-Process -FilePath $TestWindowExe -PassThru
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 250
        $find = Invoke-AgentJson -CmdArgs @('find', '--title', 'Agent Test Window') -AllowedExitCodes @(0, 1)
    } while ($find.exit -ne 0 -and (Get-Date) -lt $deadline)
    if ($find.exit -ne 0) { Fail 'Agent Test Window did not appear.' }

    $locatorTaskPath = Join-Path $Artifacts 'locator_not_found_recovery.task.json'
    $locatorReport = Join-Path $Artifacts 'locator_not_found_recovery_report.md'
    Write-TaskJson $locatorTaskPath @{
        version = 1
        name = 'locator_not_found_recovery'
        target = @{ title = 'Agent Test Window'; process = 'TestWindow.exe' }
        budget = @{ max_recoveries = 2 }
        steps = @(
            @{
                name = 'missing_locator'
                type = 'locate'
                selector = 'uia:name=DefinitelyMissingRecoveryTargetXYZ'
            }
        )
    }
    $locator = Invoke-AgentJson -CmdArgs @('run-task', '--file', $locatorTaskPath, '--report', $locatorReport) -AllowedExitCodes @(1)
    $locatorReportText = Get-Content -LiteralPath $locatorReport -Raw
    Add-Check 'LOCATOR_NOT_FOUND records strategy attempts' (
        $locator.json.ok -eq $false -and
        $locator.json.error.code -eq 'LOCATOR_NOT_FOUND' -and
        $locatorReportText -match 'Recovery Strategy Engine' -and
        $locatorReportText -match 'LOCATOR_NOT_FOUND' -and
        $locatorReportText -match 're-observe' -and
        $locatorReportText -match 'OCR fallback' -and
        $locatorReportText -match 'attempt: 1'
    ) $locator.text

    $uniqueTaskPath = Join-Path $Artifacts 'locator_not_unique_stop.task.json'
    $uniqueReport = Join-Path $Artifacts 'locator_not_unique_stop_report.md'
    Write-TaskJson $uniqueTaskPath @{
        version = 1
        name = 'locator_not_unique_stop'
        target = @{ title = 'Agent Test Window'; process = 'TestWindow.exe' }
        budget = @{ max_recoveries = 2 }
        steps = @(
            @{
                name = 'ambiguous_locator'
                type = 'locate'
                selector = 'uia:type=Button'
            }
        )
    }
    $unique = Invoke-AgentJson -CmdArgs @('run-task', '--file', $uniqueTaskPath, '--report', $uniqueReport) -AllowedExitCodes @(1)
    $uniqueReportText = Get-Content -LiteralPath $uniqueReport -Raw
    Add-Check 'LOCATOR_NOT_UNIQUE does not auto choose' (
        $unique.json.ok -eq $false -and
        $unique.json.error.code -eq 'LOCATOR_NOT_UNIQUE' -and
        $uniqueReportText -match 'requires explicit selector or nth' -and
        $uniqueReportText -notmatch 'RECOVERED'
    ) $unique.text

    $safetyTaskPath = Join-Path $Artifacts 'safety_denied_no_recovery.task.json'
    $safetyReport = Join-Path $Artifacts 'safety_denied_no_recovery_report.md'
    Write-TaskJson $safetyTaskPath @{
        version = 1
        name = 'safety_denied_no_recovery'
        permission_mode = 'DEFAULT'
        target = @{ title = 'Credential UI'; process = 'CredentialUIBroker.exe' }
        budget = @{ max_recoveries = 2 }
        steps = @(
            @{ name = 'observe_denied'; type = 'observe' }
        )
    }
    $safety = Invoke-AgentJson -CmdArgs @('run-task', '--file', $safetyTaskPath, '--report', $safetyReport) -AllowedExitCodes @(1)
    $safetyReportText = Get-Content -LiteralPath $safetyReport -Raw
    Add-Check 'SAFETY_POLICY_DENIED is not recoverable' (
        $safety.json.ok -eq $false -and
        $safety.json.error.code -eq 'SAFETY_POLICY_DENIED' -and
        $safetyReportText -match 'SAFETY_POLICY_DENIED' -and
        $safetyReportText -match 'strategy: stop_immediately' -and
        $safetyReportText -notmatch 'attempt: 1'
    ) $safety.text
} finally {
    if ($proc -and -not $proc.HasExited) {
        $proc.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    }
}

$passCount = @($Checks | Where-Object Status -eq 'PASS').Count
$failCount = @($Checks | Where-Object Status -eq 'FAIL').Count
$lines = @(
    '# Recovery Strategy Selftest Report',
    '',
    "- Version: $((Get-Content -LiteralPath (Join-Path $Root 'VERSION') -Raw).Trim())",
    "- Result: $(if ($failCount -eq 0) { 'PASS' } else { 'FAIL' })",
    "- PASS: $passCount",
    "- FAIL: $failCount",
    '',
    '| check | status | detail |',
    '|---|---|---|'
)
foreach ($check in $Checks) {
    $detail = ([string]$check.Detail) -replace '\|', '/'
    $lines += "| $($check.Name) | $($check.Status) | $detail |"
}
$lines | Set-Content -LiteralPath $Report -Encoding UTF8

Write-Host "Recovery selftest passed. Report: $Report"
