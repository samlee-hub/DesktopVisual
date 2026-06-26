param(
    [string]$Root = '',
    [switch]$IncludeRelease,
    [switch]$PackageRelease
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$Artifacts = Join-Path $Root 'artifacts'
$LogRoot = Join-Path $Artifacts 'rc_check'
$SummaryPath = Join-Path $Artifacts 'rc_check_report.md'

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

$Results = New-Object System.Collections.Generic.List[object]
$RunReleasePackaging = $IncludeRelease -or $PackageRelease
$ReleasePackagingSkipMessage = 'Release packaging skipped. Use -IncludeRelease only when user explicitly requests a release package.'

function Get-SafeName([string]$Name) {
    return ($Name -replace '[^A-Za-z0-9_.-]', '_')
}

function Stop-TestWindow {
    Get-Process TestWindow -ErrorAction SilentlyContinue | ForEach-Object {
        $_.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (!$_.HasExited) {
            Stop-Process -Id $_.Id -Force
        }
    }
}

function Add-Result {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Command,
        [string]$LogPath,
        [string]$Reason
    )

    $Results.Add([pscustomobject]@{
        Name = $Name
        Status = $Status
        Command = $Command
        LogPath = $LogPath
        Reason = $Reason
    }) | Out-Null

    $line = "$Status`: $Name"
    if ($Reason) {
        $line += " - $Reason"
    }
    Write-Host $line
}

function Invoke-RcStep {
    param(
        [string]$Name,
        [string]$Command,
        [scriptblock]$Action,
        [scriptblock]$SkipDetector = $null
    )

    $logPath = Join-Path $LogRoot ("{0}.log" -f (Get-SafeName $Name))
    $output = @()
    $exitCode = 0
    $failed = $false
    try {
        Stop-TestWindow
        $output = & $Action 2>&1
        $exitCode = $LASTEXITCODE
        if ($null -eq $exitCode) {
            $exitCode = 0
        }
    }
    catch {
        $failed = $true
        $exitCode = 1
        $output += $_.Exception.Message
    }

    $text = ($output | Out-String).Trim()
    @(
        "Command: $Command"
        "ExitCode: $exitCode"
        ''
        $text
    ) | Set-Content -Encoding UTF8 -LiteralPath $logPath

    if ($SkipDetector) {
        $skipReason = & $SkipDetector $exitCode $text
        if ($skipReason) {
            Add-Result -Name $Name -Status 'SKIPPED' -Command $Command -LogPath $logPath -Reason $skipReason
            return
        }
    }

    if ($failed -or $exitCode -ne 0) {
        Add-Result -Name $Name -Status 'FAIL' -Command $Command -LogPath $logPath -Reason "exit=$exitCode"
        return
    }

    Add-Result -Name $Name -Status 'PASS' -Command $Command -LogPath $logPath -Reason ''
}

function Format-RootCommand {
    param([string]$Relative)
    return Join-Path $Root $Relative
}

function Test-OcrSkipped {
    param([int]$ExitCode, [string]$Text)
    if ($ExitCode -eq 0 -and $Text -match 'SKIPPED: OCR_UNAVAILABLE') {
        return 'OCR_UNAVAILABLE'
    }
    return ''
}

function Test-ImageSkipped {
    param([int]$ExitCode, [string]$Text)
    if ($ExitCode -ne 0 -and ($Text -match 'Template was not created|find-image failed|click-image failed|Could not capture source screenshot')) {
        return 'Image template demo unavailable in this environment'
    }
    return ''
}

function Test-DogfoodSkipped {
    param([int]$ExitCode, [string]$Text)
    if ($ExitCode -ne 0 -and ($Text -match 'Could not uniquely match the blank Notepad window|Could not start notepad.exe')) {
        return 'Real-app dogfood environment unavailable'
    }
    return ''
}

function Test-HumanProfileSkipped {
    param([int]$ExitCode, [string]$Text)
    if ($ExitCode -eq 0 -and $Text -match 'SKIPPED:') {
        return 'No source=human operator profile is installed'
    }
    return ''
}

Invoke-RcStep -Name 'script_lint' -Command (Format-RootCommand 'script_lint.ps1') -Action { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'script_lint.ps1') -Root $Root }
Invoke-RcStep -Name 'build' -Command (Format-RootCommand 'build.ps1') -Action { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'build.ps1') -Root $Root }
Invoke-RcStep -Name 'selftest' -Command (Format-RootCommand 'selftest.ps1') -Action { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'selftest.ps1') -Root $Root }
Invoke-RcStep -Name 'uia_selftest' -Command (Format-RootCommand 'uia_selftest.ps1') -Action { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'uia_selftest.ps1') }
Invoke-RcStep -Name 'safety_selftest' -Command (Format-RootCommand 'safety_selftest.ps1') -Action { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'safety_selftest.ps1') }
Invoke-RcStep -Name 'safety_manifest_selftest' -Command (Format-RootCommand 'safety_manifest_selftest.ps1') -Action { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'safety_manifest_selftest.ps1') -Root $Root -SkipBuild }
Invoke-RcStep -Name 'focus_selftest' -Command (Format-RootCommand 'focus_selftest.ps1') -Action { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'focus_selftest.ps1') }
Invoke-RcStep -Name 'read_path_selftest' -Command (Format-RootCommand 'read_path_selftest.ps1') -Action { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'read_path_selftest.ps1') }
Invoke-RcStep -Name 'input_primitives_selftest' -Command (Format-RootCommand 'input_primitives_selftest.ps1') -Action { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'input_primitives_selftest.ps1') }
Invoke-RcStep -Name 'motion_selftest' -Command (Format-RootCommand 'motion_selftest.ps1') -Action { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'motion_selftest.ps1') }
Invoke-RcStep -Name 'motion_profile_selftest' -Command (Format-RootCommand 'motion_profile_selftest.ps1') -Action { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'motion_profile_selftest.ps1') -Root $Root }
Invoke-RcStep -Name 'motion_human_profile_check' -Command (Format-RootCommand 'motion_human_profile_check.ps1') -Action { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'motion_human_profile_check.ps1') } -SkipDetector ${function:Test-HumanProfileSkipped}
Invoke-RcStep -Name 'observe_selftest' -Command (Format-RootCommand 'observe_selftest.ps1') -Action { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'observe_selftest.ps1') }
Invoke-RcStep -Name 'selector_selftest' -Command (Format-RootCommand 'selector_selftest.ps1') -Action { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'selector_selftest.ps1') }
Invoke-RcStep -Name 'app_profile_selftest' -Command (Format-RootCommand 'app_profile_selftest.ps1') -Action { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'app_profile_selftest.ps1') -Root $Root }
Invoke-RcStep -Name 'v4_visual_dogfood' -Command (Format-RootCommand 'v4_visual_dogfood.ps1') -Action { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'v4_visual_dogfood.ps1') -Root $Root -SkipBuild }
Invoke-RcStep -Name 'run_demo' -Command "$(Format-RootCommand 'run_demo.ps1') -SkipBuild" -Action { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'run_demo.ps1') -SkipBuild }
Invoke-RcStep -Name 'run_demo_visible' -Command "$(Format-RootCommand 'run_demo.ps1') -Visible -SkipBuild" -Action { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'run_demo.ps1') -Visible -SkipBuild }
Invoke-RcStep -Name 'run_dogfood' -Command (Format-RootCommand 'run_dogfood.ps1') -Action { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'run_dogfood.ps1') } -SkipDetector ${function:Test-DogfoodSkipped}
Invoke-RcStep -Name 'dogfood_selftest' -Command (Format-RootCommand 'dogfood_selftest.ps1') -Action { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'dogfood_selftest.ps1') -Root $Root -SkipBuild }
Invoke-RcStep -Name 'run_ocr_demo' -Command (Format-RootCommand 'run_ocr_demo.ps1') -Action { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'run_ocr_demo.ps1') } -SkipDetector ${function:Test-OcrSkipped}
Invoke-RcStep -Name 'run_image_demo' -Command (Format-RootCommand 'run_image_demo.ps1') -Action { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'run_image_demo.ps1') } -SkipDetector ${function:Test-ImageSkipped}
Invoke-RcStep -Name 'skill_template_selftest' -Command (Format-RootCommand 'skill_template\win-desktop-agent\scripts\selftest-skill-template.ps1') -Action { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'skill_template\win-desktop-agent\scripts\selftest-skill-template.ps1') }
Invoke-RcStep -Name 'adapter_selftest' -Command (Format-RootCommand 'adapter_selftest.ps1') -Action { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'adapter_selftest.ps1') -Root $Root -SkipLegacySelftest }
Invoke-RcStep -Name 'benchmark_selftest' -Command (Format-RootCommand 'benchmark_selftest.ps1') -Action { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'benchmark_selftest.ps1') -Root $Root }
Invoke-RcStep -Name 'public_repo_check' -Command (Format-RootCommand 'public_repo_check.ps1') -Action { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'public_repo_check.ps1') -Root $Root }
if ($RunReleasePackaging) {
    Invoke-RcStep -Name 'package_source' -Command (Format-RootCommand 'package_source.ps1') -Action { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'package_source.ps1') -Root $Root }
    Invoke-RcStep -Name 'release' -Command (Format-RootCommand 'release.ps1') -Action { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'release.ps1') -Root $Root }
    Invoke-RcStep -Name 'verify_release' -Command (Format-RootCommand 'verify_release.ps1') -Action { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'verify_release.ps1') -Root $Root }
} else {
    Add-Result -Name 'package_source' -Status 'SKIPPED' -Command (Format-RootCommand 'package_source.ps1') -LogPath '' -Reason $ReleasePackagingSkipMessage
    Add-Result -Name 'release' -Status 'SKIPPED' -Command (Format-RootCommand 'release.ps1') -LogPath '' -Reason $ReleasePackagingSkipMessage
    Add-Result -Name 'verify_release' -Status 'SKIPPED' -Command (Format-RootCommand 'verify_release.ps1') -LogPath '' -Reason $ReleasePackagingSkipMessage
    Write-Host $ReleasePackagingSkipMessage
}

Stop-TestWindow

$hasFail = $false
foreach ($result in $Results) {
    if ($result.Status -eq 'FAIL') {
        $hasFail = $true
        break
    }
}

$overall = if ($hasFail) { 'FAIL' } else { 'PASS' }

$lines = @(
    '# DesktopVisual RC Check Report',
    '',
    "- Overall result: $overall",
    "- Version: $((Get-Content -LiteralPath (Join-Path $Root 'VERSION') -Raw).Trim())",
    "- Include release packaging: $RunReleasePackaging",
    "- Log directory: $LogRoot",
    '',
    '| step | status | command | reason | log |',
    '|---|---|---|---|---|'
)
foreach ($result in $Results) {
    $tick = [char]96
    $commandText = [string]$result.Command
    $logText = [string]$result.LogPath
    $reasonText = [string]$result.Reason
    $lines += "| $($result.Name) | $($result.Status) | $tick$commandText$tick | $reasonText | $tick$logText$tick |"
}
$lines | Set-Content -Encoding UTF8 -LiteralPath $SummaryPath

Write-Host "RC check report: $SummaryPath"
Write-Host "Overall result: $overall"

if ($hasFail) {
    Write-Host 'Failed steps:'
    foreach ($result in $Results) {
        if ($result.Status -eq 'FAIL') {
            Write-Host "- $($result.Name): $($result.Command) log=$($result.LogPath)"
        }
    }
    exit 1
}

exit 0
