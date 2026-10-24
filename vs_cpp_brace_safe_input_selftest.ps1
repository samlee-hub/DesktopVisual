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

function Has-Property {
    param(
        [object]$Object,
        [string]$Name
    )
    return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

$WinAgent = Join-Path $Root "bin\winagent.exe"
if (-not (Test-Path -LiteralPath $WinAgent)) {
    Add-Failure "bin\winagent.exe is missing; run .\build.ps1 first"
} else {
    $expectedVersion = "1.2.0"
    $fileVersion = (Get-Content -Raw -LiteralPath (Join-Path $Root "VERSION")).Trim()
    if ($fileVersion -eq $expectedVersion) {
        Add-Pass "VERSION is $expectedVersion"
    } else {
        Add-Failure "VERSION is '$fileVersion', expected $expectedVersion"
    }

    $versionRaw = & $WinAgent version 2>&1
    $versionJson = ($versionRaw | Select-Object -Last 1) | ConvertFrom-Json
    if ($versionJson.data.version -eq $expectedVersion) {
        Add-Pass "winagent version is $expectedVersion"
    } else {
        Add-Failure "winagent version is '$($versionJson.data.version)', expected $expectedVersion"
    }

    $cpp = @'
#include <iostream>
#include <string>
#include <vector>

namespace developertest {
struct Item {
    int value = 0;
};

int score_items(const std::vector<Item>& items) {
    int total = 0;
    for (const auto& item : items) {
        if (item.value > 0) {
            total += item.value;
        }
    }
    return total;
}
}

int main() {
    std::vector<developertest::Item> items = {{1}, {2}, {3}};
    int total = developertest::score_items(items);
    if (total == 6) {
        std::cout << "developertest brace safe input passed" << std::endl;
        return 0;
    }
    return 1;
}
'@

    $fixture = Join-Path $ArtifactDir "brace_safe_fixture.cpp"
    Set-Content -Encoding UTF8 -LiteralPath $fixture -Value $cpp

    $raw = & $WinAgent visible-text-input `
        --text-file $fixture `
        --input-kind code_editor_text `
        --input-method code_editor_keyboard `
        --dry-run true `
        --allow-dry-run-target true `
        --allow-global-desktop true `
        --require-target-lock false `
        --verify-structure true 2>&1
    $jsonText = $raw | Select-Object -Last 1
    $jsonText | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $ArtifactDir "brace_safe_dry_run_raw.json")
    $result = $jsonText | ConvertFrom-Json
    $data = $result.data
    $codeEditor = $data.structured_input.code_editor

    if ($data.ok -eq $true) {
        Add-Pass "visible-text-input dry-run policy accepts C++ fixture"
    } else {
        Add-Failure "visible-text-input dry-run policy failed for C++ fixture"
    }

    if ($codeEditor.language -eq "cpp") {
        Add-Pass "C++ fixture resolves as cpp"
    } else {
        Add-Failure "C++ fixture language was '$($codeEditor.language)', expected cpp"
    }

    foreach ($field in @(
        "brace_safe_default_enabled",
        "brace_safe_preflight_enabled",
        "brace_safe_open_brace_count",
        "brace_safe_synthetic_close_count",
        "brace_safe_backspace_count",
        "brace_safe_delete_count",
        "auto_pair_corruption_count",
        "failure_triggered_strategy_switch"
    )) {
        if (Has-Property -Object $codeEditor -Name $field) {
            Add-Pass "code editor result has $field"
        } else {
            Add-Failure "code editor result missing $field"
        }
    }

    if ($codeEditor.brace_safe_default_enabled -eq $true -and
        $codeEditor.brace_safe_preflight_enabled -eq $true -and
        [int]$codeEditor.brace_safe_open_brace_count -ge 1 -and
        [int]$codeEditor.brace_safe_synthetic_close_count -eq 0 -and
        [int]$codeEditor.brace_safe_backspace_count -eq 0 -and
        [int]$codeEditor.brace_safe_delete_count -eq [int]$codeEditor.brace_safe_open_brace_count) {
        Add-Pass "C++ brace-safe strategy is enabled before typing"
    } else {
        Add-Failure "C++ brace-safe strategy is not enabled before typing"
    }

    if ([int]$codeEditor.auto_pair_corruption_count -eq 0) {
        Add-Pass "auto-pair corruption count is zero"
    } else {
        Add-Failure "auto-pair corruption count is $($codeEditor.auto_pair_corruption_count), expected 0"
    }

    if ($codeEditor.failure_triggered_strategy_switch -eq $false) {
        Add-Pass "brace-safe was not introduced after a first-pass failure"
    } else {
        Add-Failure "brace-safe appears to be failure-triggered"
    }

    $segmentation = $data.keyboard_safe_segmentation
    if ($segmentation.brace_safe_default_enabled -eq $true -and
        $segmentation.chosen_typing_mode -match "brace_safe") {
        Add-Pass "keyboard-safe segmentation records brace-safe default"
    } else {
        Add-Failure "keyboard-safe segmentation does not record brace-safe default"
    }
}

if ($Failures.Count -eq 0) {
    Write-Host "VS C++ brace-safe input selftest PASS"
    exit 0
}

Write-Host "VS C++ brace-safe input selftest FAIL: $($Failures.Count) failure(s)"
exit 1
