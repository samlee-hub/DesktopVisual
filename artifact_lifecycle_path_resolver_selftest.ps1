param()

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root

$ArtifactDir = Join-Path $Root "artifacts\dev1.2.0_artifact_lifecycle_path_resolver_selftest"
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

function Assert-Equals {
    param(
        [string]$Actual,
        [string]$Expected,
        [string]$PassMessage,
        [string]$FailMessage
    )
    if ([System.String]::Equals($Actual, $Expected, [System.StringComparison]::OrdinalIgnoreCase)) {
        Add-Pass $PassMessage
    } else {
        Add-Failure "$FailMessage (actual='$Actual', expected='$Expected')"
    }
}

function Read-Text {
    param([string]$Path)
    return Get-Content -Raw -LiteralPath (Join-Path $Root $Path)
}

$fixtureParent = Join-Path $ArtifactDir "fixtures"
$fixtureReleaseRoot = Join-Path $fixtureParent "desktop_release"
$badSibling = [System.String]::Concat($fixtureReleaseRoot.TrimEnd('\'), ".desktopvisual_local")
New-Item -ItemType Directory -Force -Path $fixtureReleaseRoot | Out-Null
New-Item -ItemType Directory -Force -Path $badSibling | Out-Null

$resolverScript = Join-Path $Root "scripts\artifact_lifecycle\resolve_artifact_lifecycle_paths.ps1"
if (-not (Test-Path -LiteralPath $resolverScript)) {
    Add-Failure "resolve_artifact_lifecycle_paths.ps1 is missing"
    $report = $null
} else {
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $resolverScript -ProjectRoot $fixtureReleaseRoot -Version "1.2.0" -ActionId "0007" 2>&1
    $exit = $LASTEXITCODE
    $text = ($output -join [Environment]::NewLine)
    if ($exit -ne 0) {
        Add-Failure "resolve_artifact_lifecycle_paths.ps1 exited $exit`: $text"
        $report = $null
    } else {
        try {
            $report = $text | ConvertFrom-Json
            $text | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $ArtifactDir "lifecycle_path_resolver_report.json")
            Add-Pass "resolver script emitted JSON"
        } catch {
            Add-Failure "resolver script did not emit valid JSON: $($_.Exception.Message)"
            $report = $null
        }
    }
}

if ($report) {
    $expectedReleaseAction = Join-Path (Join-Path (Join-Path $fixtureReleaseRoot ".desktopvisual_local") "artifact_lifecycle") "release_actions\0007"
    $expectedDeveloperVersion = Join-Path (Join-Path (Join-Path $fixtureReleaseRoot ".desktopvisual_local") "artifact_lifecycle") "developer_versions\1.2.0"
    $expectedSequence = Join-Path (Split-Path -Parent $expectedReleaseAction) "ACTION_SEQUENCE.json"

    Assert-Equals $report.release_action_lifecycle_path $expectedReleaseAction "Release action lifecycle path is under ProjectRoot\\.desktopvisual_local\\artifact_lifecycle\\release_actions\\action_id" "Release action lifecycle path mismatch"
    Assert-Equals $report.developer_version_lifecycle_path $expectedDeveloperVersion "Developer lifecycle path is under ProjectRoot\\.desktopvisual_local\\artifact_lifecycle\\developer_versions\\version" "Developer lifecycle path mismatch"
    Assert-Equals $report.release_action_sequence_path $expectedSequence "Release action sequence path is under release_actions" "Release action sequence path mismatch"
    if ($report.orphan_bad_lifecycle_path.exists -eq $true -and [string]$report.orphan_bad_lifecycle_path.orphan_bad_lifecycle_path -eq $badSibling) {
        Add-Pass "Bad sibling path is detected as orphan_bad_lifecycle_path"
    } else {
        Add-Failure "Bad sibling path was not detected"
    }
    if ($report.orphan_bad_lifecycle_path.action -match "record_only") {
        Add-Pass "Bad sibling path action is record-only"
    } else {
        Add-Failure "Bad sibling path action is not record-only"
    }
}

$common = Read-Text "scripts\artifact_lifecycle\common_artifact_lifecycle.ps1"
foreach ($functionName in @(
    "Resolve-ArtifactLifecycleRoot",
    "Resolve-DeveloperVersionLifecyclePath",
    "Resolve-ReleaseActionLifecyclePath",
    "Resolve-ReleaseActionSequencePath"
)) {
    if ($common -match "function\s+$functionName") {
        Add-Pass "$functionName is defined"
    } else {
        Add-Failure "$functionName is missing"
    }
}

$scriptTexts = ""
foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $Root "scripts\artifact_lifecycle") -Filter "*.ps1" -File)) {
    $scriptTexts += "`n# $($file.Name)`n"
    $scriptTexts += Get-Content -Raw -LiteralPath $file.FullName
}

$forbiddenPatterns = @(
    '\$Root\s*\+\s*"\.desktopvisual_local"',
    '"\$Root\.desktopvisual_local"',
    '"\$ProjectRoot\.desktopvisual_local"',
    '\$ProjectRoot\s*\+\s*"\.desktopvisual_local"'
)
foreach ($pattern in $forbiddenPatterns) {
    if ($scriptTexts -match $pattern) {
        Add-Failure "Lifecycle scripts contain forbidden handwritten lifecycle path pattern: $pattern"
    } else {
        Add-Pass "No forbidden handwritten lifecycle path pattern: $pattern"
    }
}

foreach ($check in @(
    @{ File = "scripts\artifact_lifecycle\release_action_quarantine_artifacts.ps1"; Pattern = "Resolve-ReleaseActionLifecyclePath"; Message = "release action quarantine uses resolver" },
    @{ File = "scripts\artifact_lifecycle\release_action_cleanup_quarantine.ps1"; Pattern = "Resolve-ReleaseActionLifecyclePath|Resolve-ReleaseActionSequencePath"; Message = "release action cleanup uses resolver" },
    @{ File = "scripts\artifact_lifecycle\developer_quarantine_artifacts.ps1"; Pattern = "Resolve-DeveloperVersionLifecyclePath"; Message = "developer quarantine uses resolver" },
    @{ File = "scripts\artifact_lifecycle\developer_cleanup_quarantine.ps1"; Pattern = "Resolve-DeveloperVersionLifecyclePath"; Message = "developer cleanup uses resolver" }
)) {
    $text = Read-Text $check.File
    if ($text -match $check.Pattern) {
        Add-Pass $check.Message
    } else {
        Add-Failure "$($check.File) does not use expected resolver"
    }
}

$releaseScript = Read-Text "scripts\artifact_lifecycle\release_action_quarantine_artifacts.ps1"
$developerScript = Read-Text "scripts\artifact_lifecycle\developer_quarantine_artifacts.ps1"
if ($releaseScript -notmatch "Resolve-DeveloperVersionLifecyclePath|developer_versions\\\\") {
    Add-Pass "Release action lifecycle script does not write developer_versions"
} else {
    Add-Failure "Release action lifecycle script references developer_versions"
}
if ($developerScript -notmatch "Resolve-ReleaseActionLifecyclePath|desktop_release") {
    Add-Pass "Developer lifecycle script does not write desktop_release"
} else {
    Add-Failure "Developer lifecycle script references desktop_release"
}

$syncDocs = @(
    (Read-Text "docs\RELEASE_CHANNELS.md"),
    (Read-Text "docs\WORKSPACE_HYGIENE.md"),
    (Read-Text "docs\INVALID_ARTIFACT_LIFECYCLE.md"),
    (Read-Text "COMMAND_PROTOCOL.md")
) -join "`n"

$syncReport = New-Object System.Collections.Generic.List[string]
foreach ($term in @(".desktopvisual_local", "field_test_*", "release_sync_*", "developer_versions", "release_actions")) {
    if ($syncDocs -match [regex]::Escape($term)) {
        Add-Pass "Sync documentation protects $term"
        $syncReport.Add("- PASS: $term protected") | Out-Null
    } else {
        Add-Failure "Sync documentation does not protect $term"
        $syncReport.Add("- FAIL: $term missing") | Out-Null
    }
}

@(
    "# Sync Exclusion Template Check",
    "",
    "Version: 1.2.0",
    "",
    $syncReport
) | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $ArtifactDir "sync_exclusion_template_check.md")

if ($Failures.Count -gt 0) {
    Write-Host ""
    Write-Host "Artifact lifecycle path resolver selftest FAILED with $($Failures.Count) failure(s)."
    exit 1
}

Write-Host ""
Write-Host "Artifact lifecycle path resolver selftest PASSED."
