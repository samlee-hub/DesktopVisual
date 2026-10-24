param()

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root

$ArtifactDir = Join-Path $Root "artifacts\dev1.2.0_brace_safe_selftest"
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

$Failures = New-Object System.Collections.Generic.List[string]

function Add-Failure {
    param([string]$Message)
    $script:Failures.Add($Message) | Out-Null
    Write-Host "[FAIL] $Message"
}

function Add-Pass {
    param([string]$Message)
    Write-Host "[PASS] $Message"
}

function Test-Property {
    param([object]$Object, [string]$Name)
    return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

function Assert-Value {
    param(
        [object]$Actual,
        [object]$Expected,
        [string]$PassMessage,
        [string]$FailMessage
    )
    if ($Actual -eq $Expected) {
        Add-Pass $PassMessage
    } else {
        Add-Failure "$FailMessage (actual='$Actual', expected='$Expected')"
    }
}

function Invoke-WinAgentJson {
    param([string[]]$Arguments)
    $exe = Join-Path $Root "bin\winagent.exe"
    if (-not (Test-Path -LiteralPath $exe)) {
        Add-Failure "bin\winagent.exe is missing; run .\build.ps1 first"
        return $null
    }
    $output = & $exe @Arguments 2>&1
    $exit = $LASTEXITCODE
    $text = ($output | Select-Object -Last 1)
    try {
        $json = $text | ConvertFrom-Json
    } catch {
        Add-Failure "winagent.exe $($Arguments -join ' ') produced invalid JSON: $text"
        return $null
    }
    if ($exit -ne 0) {
        Add-Failure "winagent.exe $($Arguments -join ' ') exited $exit"
    }
    return $json
}

$result = Invoke-WinAgentJson -Arguments @("vs-launch-preflight", "--fixture", "true")
$data = if ($result -and (Test-Property -Object $result -Name "data")) { $result.data } else { $null }

if ($data) {
    Assert-Value $data.launch_contract_version "1.2.0" "VS preflight reports launch_contract_version 1.2.0" "VS preflight launch contract version mismatch"
    Assert-Value $data.desktop_icon_path_first $true "VS preflight requires desktop icon path first" "VS preflight does not require desktop icon path first"
    Assert-Value $data.desktop_icon_locate_success_blocks_start_menu $true "Desktop icon locate success blocks Start Menu fallback" "Desktop icon locate success does not block Start Menu fallback"
    Assert-Value $data.visual_studio_installer_is_visual_studio_ide $false "VS Installer is not IDE" "VS Installer incorrectly treated as IDE"
    Assert-Value $data.visual_studio_installer_excluded $true "VS Installer is excluded" "VS Installer exclusion missing"
    Assert-Value $data.multiple_vs_windows_result "WINDOW_NOT_UNIQUE" "Multiple VS windows return WINDOW_NOT_UNIQUE" "Multiple VS windows result mismatch"
    Assert-Value $data.multiple_vs_windows_allows_code_input $false "Multiple VS windows block code input" "Multiple VS windows do not block code input"
    Assert-Value $data.unique_vs_main_window_target_lock_allowed $true "Unique VS main window allows target lock" "Unique VS main window does not allow target lock"
    Assert-Value $data.installer_target_lock_allowed $false "Installer cannot be target-locked as VS IDE" "Installer target lock rule missing"
    Assert-Value $data.field_test_template_uses_generic_visible_app_launch $false "VS field-test template does not use generic visible-app-launch" "VS field-test template uses generic visible-app-launch"
    foreach ($field in @(
        "launch_target",
        "desktop_icon_visible",
        "desktop_icon_locate_attempts",
        "desktop_icon_double_click_attempted",
        "desktop_icon_double_click_result",
        "keyboard_or_start_menu_fallback_attempted",
        "keyboard_or_start_menu_fallback_reason",
        "backend_fallback_attempted",
        "backend_fallback_reason",
        "final_launch_layer",
        "fallback_evidence",
        "allowed_by_contract",
        "launch_contract_violation",
        "priority_violation"
    )) {
        if (Test-Property -Object $data -Name $field) {
            Add-Pass "VS preflight includes $field"
        } else {
            Add-Failure "VS preflight missing $field"
        }
    }
    $data | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $ArtifactDir "vs_launch_preflight_fixture_report.json")
    $data | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $ArtifactDir "launch_contract_fixture_report.json")
} else {
    Add-Failure "vs-launch-preflight returned no data"
}

$templateFiles = @()
$templateFiles += @(Get-ChildItem -LiteralPath $Root -Filter "*field*.ps1" -File -ErrorAction SilentlyContinue)
$templateFiles += @(Get-ChildItem -LiteralPath (Join-Path $Root "scripts") -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'field|vs' })
$templateFiles += @(Get-ChildItem -LiteralPath (Join-Path $Root "docs") -Recurse -Filter "*.md" -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'FIELD|VS' })

foreach ($file in $templateFiles | Sort-Object FullName -Unique) {
    $text = Get-Content -Raw -LiteralPath $file.FullName
    $matches = [regex]::Matches($text, 'visible-app-launch\s+--target\s+["'']Visual Studio["'']')
    foreach ($match in $matches) {
        $start = [Math]::Max(0, $match.Index - 120)
        $length = [Math]::Min($text.Length - $start, 260)
        $context = $text.Substring($start, $length)
        if ($context -notmatch '(?i)must not|do not|invalid|INVALID_ARGUMENT_NON_EXECUTING|non-executing|not use') {
            Add-Failure "$($file.FullName) appears to use generic visible-app-launch --target `"Visual Studio`" as a field-test template"
        }
    }
}

if ($Failures.Count -gt 0) {
    Write-Host ""
    Write-Host "VS launch preflight selftest FAILED with $($Failures.Count) failure(s)."
    exit 1
}

Write-Host ""
Write-Host "VS launch preflight selftest PASSED."
