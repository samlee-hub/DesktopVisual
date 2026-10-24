param()

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root

$ArtifactDir = Join-Path $Root "artifacts\dev1.1.12_launch_contract_vs_startup_convergence"
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

$Failures = New-Object System.Collections.Generic.List[string]
$PayloadRows = New-Object System.Collections.Generic.List[string]

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
    if ($null -eq $Object) { return $false }
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
    }
    return $json
}

function Get-EnvelopeData {
    param([object]$Json)
    if ($null -eq $Json) { return $null }
    if (Test-Property -Object $Json -Name "data") { return $Json.data }
    return $Json
}

function Write-JsonArtifact {
    param(
        [object]$Value,
        [string]$Name
    )
    $path = Join-Path $ArtifactDir $Name
    if ($null -eq $Value) {
        "{}" | Set-Content -LiteralPath $path -Encoding UTF8
    } else {
        $Value | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $path -Encoding UTF8
    }
}

function Assert-GitCleanForPaths {
    param(
        [string[]]$Paths,
        [string]$PassMessage,
        [string]$FailPrefix
    )
    $gitAvailable = $false
    try {
        & git rev-parse --is-inside-work-tree *> $null
        $gitAvailable = ($LASTEXITCODE -eq 0)
    } catch {
        $gitAvailable = $false
    }
    if (-not $gitAvailable) {
        Add-Failure "git is unavailable; cannot verify $FailPrefix"
        return
    }

    $changed = @(& git diff --name-only -- $Paths)
    $staged = @(& git diff --cached --name-only -- $Paths)
    $untracked = @(& git ls-files --others --exclude-standard -- $Paths)
    $all = @($changed + $staged + $untracked) | Where-Object { $_ }
    if ($all.Count -eq 0) {
        Add-Pass $PassMessage
    } else {
        foreach ($path in $all) {
            Add-Failure "${FailPrefix}: $path"
        }
    }
}

$version = (Read-Text "VERSION").Trim()
Assert-Value $version "1.1.12" "VERSION is 1.1.12" "VERSION mismatch"

$fixtureDir = Join-Path $Root "tests\fixtures\vs_projectdd_v119_repeat_payloads"
$payloadNames = @(
    "GridPathSolver.h.txt",
    "GridPathSolver.cpp.txt",
    "KnapsackPlanner.h.txt",
    "KnapsackPlanner.cpp.txt",
    "main.cpp.txt"
)

$payloadRows.Add("# Real Payload Fixture Report") | Out-Null
$payloadRows.Add("") | Out-Null
$payloadRows.Add("Source: v1.1.9 repeat field-test project_snapshot payloads.") | Out-Null
$payloadRows.Add("") | Out-Null
$payloadRows.Add("| Payload | Exists | Validation | Notes |") | Out-Null
$payloadRows.Add("| --- | --- | --- | --- |") | Out-Null

foreach ($name in $payloadNames) {
    $path = Join-Path $fixtureDir $name
    if (-not (Test-Path -LiteralPath $path)) {
        Add-Failure "real payload fixture missing: $name"
        $payloadRows.Add("| $name | NO | FAIL | missing |") | Out-Null
        continue
    }

    Add-Pass "real payload fixture exists: $name"
    $text = Get-Content -Raw -LiteralPath $path
    $markerOk = $true
    $notes = New-Object System.Collections.Generic.List[string]
    if ($name -like "*.h.txt" -and $text -notmatch "#pragma once") {
        $markerOk = $false
        $notes.Add("missing pragma once") | Out-Null
    }
    if ($name -like "GridPathSolver*" -and $text -notmatch "GridPathSolver_solve") {
        $markerOk = $false
        $notes.Add("missing GridPathSolver_solve") | Out-Null
    }
    if ($name -like "KnapsackPlanner*" -and $text -notmatch "KnapsackPlanner_plan") {
        $markerOk = $false
        $notes.Add("missing KnapsackPlanner_plan") | Out-Null
    }
    if ($name -eq "main.cpp.txt" -and $text -notmatch "projectdd DP demo completed successfully") {
        $markerOk = $false
        $notes.Add("missing success message") | Out-Null
    }
    if ($text -match "std::vector<std::vector<int>>") {
        $notes.Add("vector<vector<int>> marker") | Out-Null
    }
    if ($text -match '""') {
        $markerOk = $false
        $notes.Add("suspicious empty string quote marker") | Out-Null
    }

    if ($markerOk) {
        Add-Pass "$name important markers validate"
    } else {
        Add-Failure "$name marker validation failed"
    }

    $json = Invoke-WinAgentJson @(
        "visible-text-input",
        "--text-file", $path,
        "--input-kind", "code_editor_text",
        "--input-method", "code_editor_keyboard",
        "--dry-run", "true",
        "--allow-dry-run-target", "true",
        "--allow-global-desktop", "true",
        "--require-target-lock", "false",
        "--verify-structure", "true"
    )
    $data = Get-EnvelopeData $json
    $validation = "FAIL"
    if ($null -ne $data -and $data.ok -eq $true -and
        $data.payload_source -eq "text_file" -and
        $data.payload_integrity_verified -eq $true -and
        $data.code_structure_verified -eq $true -and
        $data.clipboard_used -eq $false -and
        $data.backend_file_write_used -eq $false) {
        Add-Pass "$name pre-input validation PASS"
        $validation = "PASS"
    } else {
        Add-Failure "$name pre-input validation failed"
    }

    if ($null -ne $data) {
        Assert-Property $data "keyboard_safe_segmentation" "$name visible-text-input result"
        Assert-Property $data "target_lock_preflight" "$name visible-text-input result"
        Assert-Property $data "code_input_integrity_v2" "$name visible-text-input result"
        if (Test-Property $data "code_input_integrity_v2") {
            Assert-Value $data.code_input_integrity_v2.corruption_count 0 "$name integrity corruption_count is 0" "$name integrity corruption_count mismatch"
        }
    }

    $noteText = if ($notes.Count -eq 0) { "balanced marker set" } else { ($notes -join "; ") }
    $existsText = if (Test-Path -LiteralPath $path) { "YES" } else { "NO" }
    $payloadRows.Add("| $name | $existsText | $validation | $noteText |") | Out-Null
}

$payloadRows | Set-Content -LiteralPath (Join-Path $ArtifactDir "real_payload_fixture_report.md") -Encoding UTF8

$fixtureEnvelope = Invoke-WinAgentJson @("vs-field-test-closure-fixture")
$fixture = Get-EnvelopeData $fixtureEnvelope
if ($null -eq $fixture) {
    Add-Failure "vs-field-test-closure-fixture did not return data"
} else {
    Assert-Property $fixture "keyboard_safe_segmentation_report" "closure fixture"
    Assert-Property $fixture "target_lock_preflight_report" "closure fixture"
    Assert-Property $fixture "code_input_integrity_v2_report" "closure fixture"
    Assert-Property $fixture "event_timeline_v2_1" "closure fixture"
    Assert-Property $fixture "timeline_overlap_check_report" "closure fixture"
    Assert-Property $fixture "command_discovery_report" "closure fixture"
    Assert-Property $fixture "locator_disambiguation_report" "closure fixture"
    Assert-Property $fixture "locator_miss_report" "closure fixture"
    Assert-Property $fixture "first_action_proxy_report" "closure fixture"

    Write-JsonArtifact $fixture.keyboard_safe_segmentation_report "keyboard_safe_segmentation_report.json"
    Write-JsonArtifact $fixture.target_lock_preflight_report "target_lock_preflight_fixture_report.json"
    Write-JsonArtifact $fixture.code_input_integrity_v2_report "code_input_integrity_v2_fixture_report.json"
    Write-JsonArtifact $fixture.event_timeline_v2_1 "event_timeline_v2_1_fixture.json"
    Write-JsonArtifact $fixture.timeline_overlap_check_report "timeline_overlap_check_report.json"
    Write-JsonArtifact $fixture.command_discovery_report "command_discovery_report.json"
    Write-JsonArtifact $fixture.locator_disambiguation_report "locator_disambiguation_fixture_report.json"
    Write-JsonArtifact $fixture.locator_miss_report "locator_miss_fixture_report.json"
    Write-JsonArtifact $fixture.first_action_proxy_report "first_action_proxy_report.json"

    if (Test-Property $fixture "keyboard_safe_segmentation_report") {
        Assert-Property $fixture.keyboard_safe_segmentation_report "files" "keyboard segmentation report"
        Assert-Property $fixture.keyboard_safe_segmentation_report "total_segment_count" "keyboard segmentation report"
        Assert-Value $fixture.keyboard_safe_segmentation_report.clipboard_paste_used $false "keyboard segmentation keeps clipboard paste disabled" "keyboard segmentation clipboard default mismatch"
        Assert-Value $fixture.keyboard_safe_segmentation_report.direct_file_write_fallback_used $false "keyboard segmentation keeps direct write disabled" "keyboard segmentation direct write default mismatch"
    }
    if (Test-Property $fixture "target_lock_preflight_report") {
        foreach ($field in @("active_window_title", "expected_visual_studio_process", "active_document_name", "expected_file_name", "editor_control_present", "editor_focused_or_focusable", "caret_available_or_text_insertion_target_verified", "project_context", "buffer_readback_possible")) {
            Assert-Property $fixture.target_lock_preflight_report $field "target lock preflight report"
        }
        Assert-Value $fixture.target_lock_preflight_report.target_lock_failure_count 0 "target lock failure fixture count is 0" "target lock failure count mismatch"
    }
    if (Test-Property $fixture "code_input_integrity_v2_report") {
        Assert-Value $fixture.code_input_integrity_v2_report.code_input_corruption_count 0 "code-input corruption fixture count is 0" "code-input corruption fixture count mismatch"
    }
    if (Test-Property $fixture "event_timeline_v2_1") {
        Assert-Value $fixture.event_timeline_v2_1.schema "event_timeline.v2.1" "event timeline schema is v2.1" "event timeline schema mismatch"
    }
    if (Test-Property $fixture "timeline_overlap_check_report") {
        Assert-Value $fixture.timeline_overlap_check_report.timeline_overlap_count 0 "timeline overlap fixture count is 0" "timeline overlap count mismatch"
        Assert-Value $fixture.timeline_overlap_check_report.typing_save_overlap_count 0 "typing/save overlap fixture count is 0" "typing/save overlap count mismatch"
    }
    if (Test-Property $fixture "command_discovery_report") {
        Assert-Value $fixture.command_discovery_report.invalid_argument_action_failure_count 0 "INVALID_ARGUMENT action failure count is 0" "INVALID_ARGUMENT action failure count mismatch"
        Assert-Value $fixture.command_discovery_report.runner_wrapper_failure_count 0 "runner wrapper failure count is 0" "runner wrapper failure count mismatch"
    }
    if (Test-Property $fixture "locator_disambiguation_report") {
        Assert-Property $fixture.locator_disambiguation_report "matched_count" "locator disambiguation report"
        Assert-Property $fixture.locator_disambiguation_report "chosen_reason" "locator disambiguation report"
        Assert-Property $fixture.locator_disambiguation_report "ambiguity_remaining" "locator disambiguation report"
    }
    if (Test-Property $fixture "locator_miss_report") {
        Assert-Property $fixture.locator_miss_report "miss_reobserve_count" "locator miss report"
        Assert-Property $fixture.locator_miss_report "miss_recovery_result" "locator miss report"
    }
    if (Test-Property $fixture "first_action_proxy_report") {
        foreach ($field in @("user_instruction_received_ts", "field_test_instruction_start_ts", "first_runtime_command_issued_ts", "first_runtime_command_completed_ts", "first_visible_action_proxy_ts", "proxy_first_visible_action_latency_ms", "unavailable_reason")) {
            Assert-Property $fixture.first_action_proxy_report $field "first-action proxy report"
        }
    }
}

$visibleTextInputPolicy = Read-Text "src\winagent\VisibleTextInputPolicy.cpp"
if ($visibleTextInputPolicy -match "clipboard_paste.*!options\.allowClipboard") {
    Add-Pass "clipboard paste default remains rejected"
} else {
    Add-Failure "clipboard paste default rejection was not found"
}
if ($visibleTextInputPolicy -match "backendFileWriteUsed") {
    Add-Pass "direct file write fallback remains rejected"
} else {
    Add-Failure "direct file write fallback rejection was not found"
}

Assert-GitCleanForPaths -Paths @("config/safety_manifest.json", "config/safety.conf") -PassMessage "protected safety config is unmodified" -FailPrefix "Protected safety config modified"
Assert-GitCleanForPaths -Paths @("src/winagent/PermissionManager.cpp", "src/winagent/PermissionManager.h") -PassMessage "PermissionManager is unmodified" -FailPrefix "PermissionManager modified"

$releaseRoot = Join-Path (Split-Path -Parent $Root) "desktop_release"
if (Test-Path -LiteralPath $releaseRoot) {
    $latest = Get-ChildItem -LiteralPath $releaseRoot -Recurse -Force -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 FullName, LastWriteTime
    $releaseVersion = ""
    $releaseVersionPath = Join-Path $releaseRoot "VERSION"
    if (Test-Path -LiteralPath $releaseVersionPath) {
        $releaseVersion = (Get-Content -Raw -LiteralPath $releaseVersionPath).Trim()
    }
    @(
        "desktop_release path: $releaseRoot",
        "desktop_release version: $releaseVersion",
        "latest file: $($latest.FullName)",
        "latest write: $($latest.LastWriteTime.ToString('o'))",
        "sync performed by this selftest: NO"
    ) | Set-Content -LiteralPath (Join-Path $ArtifactDir "desktop_release_untouched_check.txt") -Encoding UTF8
    Add-Pass "desktop_release untouched check recorded without writing release tree"
} else {
    "desktop_release path missing: $releaseRoot" | Set-Content -LiteralPath (Join-Path $ArtifactDir "desktop_release_untouched_check.txt") -Encoding UTF8
    Add-Failure "desktop_release path is missing; cannot verify untouched release tree"
}

if ($version -ne "1.2.0" -and $version -notmatch "^1\.2\.") {
    Add-Pass "development tree has not entered v1.2.0"
} else {
    Add-Failure "development tree appears to have entered v1.2.0"
}

foreach ($path in @("desktopvisual-public-dist", "public-dist", "public_dist", "restricted_public_release")) {
    if (Test-Path -LiteralPath (Join-Path $Root $path)) {
        Add-Failure "Unexpected public/restricted release tree exists inside developer tree: $path"
    } else {
        Add-Pass "$path is absent inside developer tree"
    }
}

@(
    "VERSION: $version",
    "desktop_release synced: NO",
    "desktop_release modified by selftest: NO",
    "entered v1.2.0: NO",
    "public restricted release created: NO",
    "public-dist tree created: NO"
) | Set-Content -LiteralPath (Join-Path $ArtifactDir "boundary_check.txt") -Encoding UTF8

if ($Failures.Count -eq 0) {
    Write-Host "VS field test closure selftest PASS"
    exit 0
}

Write-Host "VS field test closure selftest FAIL: $($Failures.Count) failure(s)"
exit 1



