param()

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root

$ArtifactDir = Join-Path $Root "artifacts\dev1.2.0_brace_safe_selftest"
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

$Failures = New-Object System.Collections.Generic.List[string]
$DryRunReports = New-Object System.Collections.Generic.List[object]
$HelpReports = New-Object System.Collections.Generic.List[object]

function Add-Failure {
    param([string]$Message)
    $script:Failures.Add($Message) | Out-Null
    Write-Host "[FAIL] $Message"
}

function Add-Pass {
    param([string]$Message)
    Write-Host "[PASS] $Message"
}

function Get-ErrorCode {
    param([object]$Json)
    if ($null -eq $Json) { return "" }
    if ($Json.PSObject.Properties["error_code"]) { return [string]$Json.error_code }
    if ($Json.PSObject.Properties["error"] -and $Json.error.PSObject.Properties["code"]) { return [string]$Json.error.code }
    return ""
}

function Get-VsSnapshot {
    $items = @()
    foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) {
        $title = ""
        try { $title = [string]$p.MainWindowTitle } catch { $title = "" }
        if ($p.ProcessName -match '^(devenv|VisualStudioInstaller|vs_installer|vswhere|setup)$' -or $title -match 'Visual Studio Installer') {
            $items += [pscustomobject]@{
                id = $p.Id
                process = $p.ProcessName
                title = $title
            }
        }
    }
    return @($items)
}

function Invoke-WinAgentRaw {
    param([string[]]$Arguments)
    $exe = Join-Path $Root "bin\winagent.exe"
    $before = Get-VsSnapshot
    $output = & $exe @Arguments 2>&1
    $exit = $LASTEXITCODE
    $after = Get-VsSnapshot
    $text = ($output | Select-Object -Last 1)
    $json = $null
    try {
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            $json = $text | ConvertFrom-Json
        }
    } catch {
        Add-Failure "winagent.exe $($Arguments -join ' ') produced invalid JSON: $text"
    }
    $beforeIds = @($before | ForEach-Object { $_.id })
    $newVs = @($after | Where-Object { $beforeIds -notcontains $_.id })
    return [pscustomobject]@{
        command = "winagent.exe $($Arguments -join ' ')"
        exit_code = $exit
        raw_output = ($output -join [Environment]::NewLine)
        json = $json
        error_code = Get-ErrorCode -Json $json
        vs_processes_before = @($before)
        vs_processes_after = @($after)
        new_vs_processes = @($newVs)
    }
}

$exePath = Join-Path $Root "bin\winagent.exe"
if (-not (Test-Path -LiteralPath $exePath)) {
    Add-Failure "bin\winagent.exe is missing; run .\build.ps1 first"
} else {
    $versionRun = Invoke-WinAgentRaw -Arguments @("version")
    $runtimeVersion = ""
    if ($versionRun.json -and $versionRun.json.PSObject.Properties["data"] -and $versionRun.json.data.PSObject.Properties["version"]) {
        $runtimeVersion = [string]$versionRun.json.data.version
    }
    if ($runtimeVersion -ne "1.2.0") {
        Add-Failure "bin\winagent.exe version is '$runtimeVersion', expected 1.2.0; skipping action discovery probes"
    } else {
        Add-Pass "bin\winagent.exe version is 1.2.0"

        $dryRunCase = Invoke-WinAgentRaw -Arguments @("visible-app-launch", "--target", "Visual Studio", "--dry-run")
        $DryRunReports.Add($dryRunCase) | Out-Null
        if ($dryRunCase.exit_code -ne 0 -and $dryRunCase.error_code -eq "INVALID_ARGUMENT_NON_EXECUTING") {
            Add-Pass "Bare visible-app-launch --dry-run is INVALID_ARGUMENT_NON_EXECUTING"
        } else {
            Add-Failure "Bare visible-app-launch --dry-run returned exit=$($dryRunCase.exit_code), error_code=$($dryRunCase.error_code)"
        }
        if (@($dryRunCase.new_vs_processes).Count -eq 0) {
            Add-Pass "Bare --dry-run did not create new VS/Installer processes"
        } else {
            Add-Failure "Bare --dry-run created new VS/Installer processes"
        }
        if ($dryRunCase.json -and $dryRunCase.json.data -and $dryRunCase.json.data.runtime_action_executed -eq $false -and $dryRunCase.json.data.desktop_action_executed -eq $false) {
            Add-Pass "Bare --dry-run report states no runtime or desktop action executed"
        } else {
            Add-Failure "Bare --dry-run report does not prove non-execution"
        }

        $helpCases = @(
            @("visible-show-desktop", "--help"),
            @("desktop-icon-double-click", "--help"),
            @("visible-text-input", "--help"),
            @("target-lock-acquire", "--help"),
            @("desktop-icon-locate", "--help"),
            @("visible-window-switch", "--help")
        )
        foreach ($args in $helpCases) {
            $case = Invoke-WinAgentRaw -Arguments $args
            $HelpReports.Add($case) | Out-Null
            if ($case.exit_code -eq 0 -and $case.error_code -eq "NON_EXECUTING_HELP") {
                Add-Pass "$($case.command) returned NON_EXECUTING_HELP"
            } else {
                Add-Failure "$($case.command) returned exit=$($case.exit_code), error_code=$($case.error_code)"
            }
            if (@($case.new_vs_processes).Count -eq 0) {
                Add-Pass "$($case.command) did not create new VS/Installer processes"
            } else {
                Add-Failure "$($case.command) created new VS/Installer processes"
            }
            if ($case.json -and $case.json.data -and $case.json.data.runtime_action_executed -eq $false -and $case.json.data.desktop_action_executed -eq $false) {
                Add-Pass "$($case.command) report states no runtime or desktop action executed"
            } else {
                Add-Failure "$($case.command) report does not prove non-execution"
            }
        }
    }
}

$DryRunReports | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $ArtifactDir "dry_run_non_execution_report.json")
$HelpReports | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $ArtifactDir "help_non_execution_report.json")

if ($Failures.Count -gt 0) {
    Write-Host ""
    Write-Host "Safe CLI non-execution selftest FAILED with $($Failures.Count) failure(s)."
    exit 1
}

Write-Host ""
Write-Host "Safe CLI non-execution selftest PASSED."
