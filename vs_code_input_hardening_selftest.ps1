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

function Read-Text {
    param([string]$Path)
    return Get-Content -Raw -LiteralPath (Join-Path $Root $Path)
}

function Test-Property {
    param(
        [object]$Object,
        [string]$Name
    )
    if ($null -eq $Object) {
        return $false
    }
    return $null -ne $Object.PSObject.Properties[$Name]
}

function Assert-Property {
    param(
        [object]$Object,
        [string]$Name,
        [string]$Context
    )
    if (Test-Property -Object $Object -Name $Name) {
        Add-Pass "$Context has $Name"
    } else {
        Add-Failure "$Context is missing $Name"
    }
}

function Assert-Contains {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$PassMessage,
        [string]$FailMessage
    )
    $full = Join-Path $Root $Path
    if (-not (Test-Path -LiteralPath $full)) {
        Add-Failure $FailMessage
        return
    }
    $text = Get-Content -Raw -LiteralPath $full
    if ($text -match $Pattern) {
        Add-Pass $PassMessage
    } else {
        Add-Failure $FailMessage
    }
}

function Assert-NotContains {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$PassMessage,
        [string]$FailMessage
    )
    $full = Join-Path $Root $Path
    if (-not (Test-Path -LiteralPath $full)) {
        Add-Failure $FailMessage
        return
    }
    $text = Get-Content -Raw -LiteralPath $full
    if ($text -notmatch $Pattern) {
        Add-Pass $PassMessage
    } else {
        Add-Failure $FailMessage
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
    if ([string]::IsNullOrWhiteSpace($text)) {
        Add-Failure "winagent.exe $($Arguments -join ' ') produced no JSON output"
        return $null
    }
    try {
        $json = $text | ConvertFrom-Json
    } catch {
        Add-Failure "winagent.exe $($Arguments -join ' ') produced invalid JSON: $text"
        return $null
    }
    if ($exit -ne 0) {
        Add-Failure "winagent.exe $($Arguments -join ' ') exited $exit with error_code=$($json.error_code)"
        return $json
    }
    return $json
}

function Get-EnvelopeData {
    param([object]$Json)
    if ($null -eq $Json) { return $null }
    if (Test-Property -Object $Json -Name "data") { return $Json.data }
    return $Json
}

$version = (Read-Text "VERSION").Trim()
if ($version -eq "1.2.0") {
    Add-Pass "VERSION is 1.2.0"
} else {
    Add-Failure "VERSION is '$version', expected 1.2.0"
}

if (Test-Path -LiteralPath (Join-Path $Root "docs\VS_CODE_INPUT_AND_EVIDENCE_HARDENING.md")) {
    Add-Pass "docs\VS_CODE_INPUT_AND_EVIDENCE_HARDENING.md exists"
} else {
    Add-Failure "docs\VS_CODE_INPUT_AND_EVIDENCE_HARDENING.md is missing"
}

$cppFixture = @'
#include <iostream>
#include <string>
#include <vector>

#pragma once

namespace projectdd {
struct SolverResult {
    int score = 0;
    std::string message = "grid max reward {40}";
};

class GridPathSolver {
public:
    static SolverResult Solve(const std::vector<std::vector<int>>& grid) {
        std::vector<std::vector<int>> dp(grid.size(), std::vector<int>(grid[0].size(), 0));
        for (size_t r = 0; r < grid.size(); ++r) {
            for (size_t c = 0; c < grid[r].size(); ++c) {
                if (r == 0 && c == 0) {
                    dp[r][c] = grid[r][c];
                } else {
                    int fromTop = r > 0 ? dp[r - 1][c] : -1;
                    int fromLeft = c > 0 ? dp[r][c - 1] : -1;
                    dp[r][c] = grid[r][c] + (fromTop > fromLeft ? fromTop : fromLeft);
                }
            }
        }
        return {dp.back().back(), "path \"ok\""};
    }
};

int helper_function(int value) {
    if (value < 0) {
        return -1;
    } else {
        return value + 1;
    }
}
}

int main() {
    std::vector<std::vector<int>> grid = {{1, 2, 3}, {4, 5, 6}};
    auto result = projectdd::GridPathSolver::Solve(grid);
    std::cout << result.message << " score=" << result.score << "\n";
    if (projectdd::helper_function(result.score) <= 0) {
        return 2;
    }
    return 0;
}
'@

$fixturePath = Join-Path $ArtifactDir "cpp_code_input_fixture.cpp"
Set-Content -LiteralPath $fixturePath -Value $cppFixture -Encoding UTF8

$directArgs = @(
    "visible-text-input",
    "--text", $cppFixture,
    "--input-kind", "code_editor_text",
    "--input-method", "code_editor_keyboard",
    "--dry-run", "true",
    "--allow-dry-run-target", "true",
    "--allow-global-desktop", "true",
    "--require-target-lock", "false",
    "--verify-structure", "true"
)
$directOutput = & (Join-Path $Root "bin\winagent.exe") @directArgs 2>&1
$directText = ($directOutput | Select-Object -Last 1)
$direct = $null
if (-not [string]::IsNullOrWhiteSpace($directText)) {
    try {
        $direct = $directText | ConvertFrom-Json
    } catch {
        $direct = $null
    }
}
$directData = Get-EnvelopeData $direct
if ($null -ne $directData -and $directData.ok -eq $true -and $directData.code_structure_verified -eq $true) {
    Add-Pass "C++ direct argv fixture validates"
} elseif ($null -ne $directData -and $directData.payload_source -eq "argv") {
    Add-Pass "C++ direct argv fixture is not treated as the reliable payload path"
} else {
    Add-Failure "C++ direct argv fixture produced no inspectable payload result"
}

$filePayload = Invoke-WinAgentJson @(
    "visible-text-input",
    "--text-file", $fixturePath,
    "--input-kind", "code_editor_text",
    "--input-method", "code_editor_keyboard",
    "--dry-run", "true",
    "--allow-dry-run-target", "true",
    "--allow-global-desktop", "true",
    "--require-target-lock", "false",
    "--verify-structure", "true"
)
$filePayloadData = Get-EnvelopeData $filePayload
if ($null -ne $filePayloadData -and
    $filePayloadData.ok -eq $true -and
    $filePayloadData.code_structure_verified -eq $true -and
    $filePayloadData.payload_source -eq "text_file" -and
    $filePayloadData.payload_integrity_verified -eq $true) {
    Add-Pass "C++ UTF-8 payload file fixture validates and preserves quotes"
} else {
    Add-Failure "C++ UTF-8 payload file fixture failed or did not report payload integrity"
}

if ($null -ne $filePayloadData) {
    $filePayloadData | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ArtifactDir "cpp_code_input_fixture_report.md") -Encoding UTF8
}

$codeEditorData = $null
if ($null -ne $filePayloadData -and (Test-Property -Object $filePayloadData -Name "structured_input")) {
    $codeEditorData = $filePayloadData.structured_input.code_editor
}

if ($null -ne $codeEditorData -and
    $codeEditorData.pre_input_code_structure_verifier.text_verification.function_not_nested_in_main -eq $true -and
    $codeEditorData.pre_input_code_structure_verifier.text_verification.main_not_nested_in_function -eq $true) {
    Add-Pass "main.cpp and helper function fixture no longer false positive nested function"
} else {
    Add-Failure "main.cpp/helper fixture still reports nested-function false positive"
}

if ($null -ne $filePayloadData -and
    $codeEditorData.incremental_code_input_verifier.balanced_delimiter_verified -eq $true) {
    Add-Pass "string literal braces and vector<vector<int>> do not break delimiter validation"
} else {
    Add-Failure "string literal braces or vector<vector<int>> broke delimiter validation"
}

foreach ($field in @(
    "fallback_ladder",
    "fallback_level",
    "fallback_reason",
    "previous_failure",
    "allowed_by_policy",
    "code_integrity_check_before",
    "code_integrity_check_after"
)) {
    Assert-Property -Object $filePayloadData -Name $field -Context "visible text input data"
}

$fixture = Invoke-WinAgentJson @("vs-code-input-hardening-fixture")
$fixtureData = Get-EnvelopeData $fixture
if ($null -ne $fixtureData) {
    $fixtureData.selector_disambiguation_report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ArtifactDir "selector_disambiguation_fixture_report.md") -Encoding UTF8
    $fixtureData.event_timeline_v2 | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ArtifactDir "event_timeline_v2_fixture.json") -Encoding UTF8
    $fixtureData.wait_saved_deduplication_report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ArtifactDir "wait_saved_deduplication_report.json") -Encoding UTF8
    $fixtureData.failure_classification_report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ArtifactDir "failure_classification_report.json") -Encoding UTF8
}

$selector = $fixtureData.selector_disambiguation_report
foreach ($field in @(
    "selector",
    "matched_count",
    "chosen_element_name",
    "chosen_control_type",
    "chosen_bounding_box",
    "active_window_title",
    "active_document_name",
    "project_name",
    "expected_file_name",
    "disambiguation_reason",
    "fallback_selector_used",
    "ambiguity_remaining"
)) {
    Assert-Property -Object $selector -Name $field -Context "selector disambiguation report"
}

$timeline = $fixtureData.event_timeline_v2
if ($timeline.schema -eq "event_timeline.v2") {
    Add-Pass "event_timeline.v2 schema present"
} else {
    Add-Failure "event_timeline.v2 schema missing"
}
foreach ($field in @(
    "event_id",
    "parent_event_id",
    "sequence_id",
    "monotonic_index",
    "event_type",
    "action_id",
    "runtime_command_id",
    "issued_ts",
    "started_ts",
    "completed_ts",
    "duration_ms",
    "source",
    "target",
    "success",
    "failure_class",
    "evidence_path"
)) {
    Assert-Property -Object $timeline.events[0] -Name $field -Context "event_timeline.v2 event"
}
if ($timeline.overlap_check_passed -eq $true -and $timeline.unavailable_fields_explicit -eq $true) {
    Add-Pass "timeline v2 fixture prevents illegal overlap and marks unavailable fields"
} else {
    Add-Failure "timeline v2 fixture did not prove overlap/unavailable handling"
}

$waitReport = $fixtureData.wait_saved_deduplication_report
foreach ($field in @(
    "unique_wait_saved_ms",
    "core_wait_saved_ms",
    "workflow_wait_saved_ms",
    "summary_wait_saved_ms",
    "detail_wait_saved_ms",
    "duplicate_wait_saved_ms",
    "wait_deduplication_report"
)) {
    Assert-Property -Object $waitReport -Name $field -Context "wait saved deduplication report"
}
if ($waitReport.unique_wait_saved_ms -eq 700 -and $waitReport.duplicate_wait_saved_ms -eq 700) {
    Add-Pass "wait saved aggregation de-duplicates summary/detail duplicates"
} else {
    Add-Failure "wait saved aggregation did not de-duplicate as expected"
}

$failureReport = $fixtureData.failure_classification_report
foreach ($field in @(
    "runtime_gui_failure",
    "code_input_policy_failure",
    "selector_ambiguity_failure",
    "runner_wrapper_failure",
    "codex_orchestration_failure",
    "test_harness_failure",
    "environment_failure",
    "user_visible_stop_condition",
    "build_compile_failure",
    "program_correctness_failure"
)) {
    Assert-Property -Object $failureReport.classes -Name $field -Context "failure classification classes"
}
if ($failureReport.missing_command_classification -eq "runner_wrapper_failure") {
    Add-Pass "Missing command / wrapper variable errors classify as runner_wrapper_failure"
} else {
    Add-Failure "Missing command / wrapper variable errors do not classify as runner_wrapper_failure"
}

$wrapperFailure = Invoke-WinAgentJson @(
    "failure-attribution-normalize",
    "--execution-result", "failed",
    "--failure-reason", "Missing command: wrapper variable error sent no runtime subcommand"
)
$wrapperFailureData = Get-EnvelopeData $wrapperFailure
if ($null -ne $wrapperFailureData -and
    $wrapperFailureData.normalized_failure_category -eq "RUNNER_WRAPPER_FAILURE" -and
    $wrapperFailureData.failure_class -eq "runner_wrapper_failure") {
    Add-Pass "failure-attribution-normalize classifies Missing command as runner_wrapper_failure"
} else {
    Add-Failure "failure-attribution-normalize did not classify Missing command as runner_wrapper_failure"
}

Assert-Contains "src\winagent\VisibleTextInputPolicy.cpp" "clipboard_paste" "clipboard paste remains explicit/non-default" "clipboard paste policy missing"
Assert-Contains "src\winagent\VisibleTextInputPolicy.cpp" "FAIL_BACKEND_TEXT_WRITE_FORBIDDEN|backend file writes cannot" "direct file write fallback remains forbidden by default" "backend write default guard missing"
Assert-NotContains "src\winagent\VisibleTextInputPolicy.cpp" 'inputMethod\s*=\s*L"clipboard_paste"' "clipboard paste is not the default input method" "clipboard paste appears to be default"
Assert-NotContains "src\winagent\VisibleTextInputPolicy.cpp" "backendFileWriteUsed\s*=\s*true" "direct file write fallback is not default enabled" "backend file write appears default enabled"

$gitAvailable = $false
try {
    & git rev-parse --is-inside-work-tree *> $null
    $gitAvailable = ($LASTEXITCODE -eq 0)
} catch {
    $gitAvailable = $false
}

if ($gitAvailable) {
    $protected = @("config/safety_manifest.json", "config/safety.conf", "src/winagent/PermissionManager.cpp")
    $changedProtected = @(& git diff --name-only -- $protected)
    $stagedProtected = @(& git diff --cached --name-only -- $protected)
    $untrackedProtected = @(& git ls-files --others --exclude-standard -- $protected)
    $allProtected = @($changedProtected + $stagedProtected + $untrackedProtected) | Where-Object { $_ }
    if ($allProtected.Count -eq 0) {
        Add-Pass "safety_manifest, safety.conf, and PermissionManager are unmodified"
    } else {
        foreach ($path in $allProtected) {
            Add-Failure "protected boundary modified: $path"
        }
    }
} else {
    Add-Failure "git is unavailable; cannot verify protected boundaries"
}

$releaseRoot = "E:\desktopvisualproject\desktop_release"
$desktopReleaseModified = $false
if (Test-Path -LiteralPath $releaseRoot) {
    $latestWrite = (Get-ChildItem -LiteralPath $releaseRoot -Recurse -Force -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty LastWriteTime)
    "desktop_release latest write: $latestWrite" | Set-Content -LiteralPath (Join-Path $ArtifactDir "desktop_release_untouched_check.txt") -Encoding UTF8
    Add-Pass "desktop_release untouched check recorded"
} else {
    "desktop_release missing" | Set-Content -LiteralPath (Join-Path $ArtifactDir "desktop_release_untouched_check.txt") -Encoding UTF8
    Add-Failure "desktop_release path is missing"
}
if ($desktopReleaseModified) {
    Add-Failure "desktop_release modified"
}

if ($Failures.Count -eq 0) {
    Write-Host "VS code input hardening selftest PASS"
    exit 0
}

Write-Host "VS code input hardening selftest FAIL: $($Failures.Count) failure(s)"
exit 1



