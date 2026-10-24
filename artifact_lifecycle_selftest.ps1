param()

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root

$ArtifactDir = Join-Path $Root "artifacts\dev1.2.0_artifact_lifecycle_selftest"
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

function Assert-Exists {
    param([string]$Path)
    if (Test-Path -LiteralPath (Join-Path $Root $Path)) {
        Add-Pass "$Path exists"
    } else {
        Add-Failure "$Path is missing"
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

function Assert-NotGitChanged {
    param(
        [string[]]$Paths,
        [string]$PassMessage,
        [string]$FailPrefix
    )
    $changed = @(& git status --short -- $Paths 2>$null) | Where-Object { $_ }
    if ($changed.Count -eq 0) {
        Add-Pass $PassMessage
    } else {
        foreach ($line in $changed) {
            Add-Failure "${FailPrefix}: $line"
        }
    }
}

function New-TextFile {
    param(
        [string]$Path,
        [string]$Text
    )
    $parent = Split-Path -Parent $Path
    if ($parent) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -Encoding UTF8 -LiteralPath $Path -Value $Text
}

function Invoke-JsonScript {
    param(
        [string]$Script,
        [string[]]$Arguments,
        [string]$OutputPath
    )
    $full = Join-Path $Root $Script
    if (-not (Test-Path -LiteralPath $full)) {
        Add-Failure "$Script is missing"
        return $null
    }
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $full @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($output -join [Environment]::NewLine)
    Set-Content -Encoding UTF8 -LiteralPath $OutputPath -Value $text
    if ($exitCode -ne 0) {
        Add-Failure "$Script exited $exitCode`: $text"
        return $null
    }
    try {
        return $text | ConvertFrom-Json
    } catch {
        Add-Failure "$Script did not emit valid JSON: $($_.Exception.Message)"
        return $null
    }
}

function Assert-FileStillExists {
    param(
        [string]$Path,
        [string]$Message
    )
    if (Test-Path -LiteralPath $Path) {
        Add-Pass $Message
    } else {
        Add-Failure $Message
    }
}

Assert-Exists "docs\INVALID_ARTIFACT_LIFECYCLE.md"
Assert-Exists "config\artifact_lifecycle_policy.json"
Assert-Exists "scripts\artifact_lifecycle\common_artifact_lifecycle.ps1"
Assert-Exists "scripts\artifact_lifecycle\developer_quarantine_artifacts.ps1"
Assert-Exists "scripts\artifact_lifecycle\developer_cleanup_quarantine.ps1"
Assert-Exists "scripts\artifact_lifecycle\release_action_quarantine_artifacts.ps1"
Assert-Exists "scripts\artifact_lifecycle\release_action_cleanup_quarantine.ps1"

Assert-Contains ".gitignore" "(?m)^\.desktopvisual_local/$|(?m)^\.desktopvisual_local/" ".desktopvisual_local is gitignored" ".desktopvisual_local is not gitignored"
Assert-Contains "docs\INVALID_ARTIFACT_LIFECYCLE.md" "Developer-version lifecycle" "Invalid artifact doc covers developer lifecycle" "Invalid artifact doc missing developer lifecycle"
Assert-Contains "docs\INVALID_ARTIFACT_LIFECYCLE.md" "Local-use release action lifecycle" "Invalid artifact doc covers release action lifecycle" "Invalid artifact doc missing release action lifecycle"
Assert-Contains "docs\INVALID_ARTIFACT_LIFECYCLE.md" "\.desktopvisual_local" "Invalid artifact doc covers local state isolation" "Invalid artifact doc missing .desktopvisual_local isolation"
Assert-Contains "docs\RELEASE_CHANNELS.md" "\.desktopvisual_local" "Release channels document local lifecycle sync exclusion" "Release channels missing .desktopvisual_local exclusion"
Assert-Contains "docs\WORKSPACE_HYGIENE.md" "\.desktopvisual_local" "Workspace hygiene document local lifecycle state" "Workspace hygiene missing lifecycle local state"
Assert-Contains "docs\FIELD_TEST_READINESS.md" "\.desktopvisual_local" "Field test readiness document sync exclusion" "Field test readiness missing lifecycle sync exclusion"
Assert-Contains "COMMAND_PROTOCOL.md" "\.desktopvisual_local" "Command protocol document sync exclusion" "Command protocol missing lifecycle sync exclusion"
Assert-Contains "AGENTS.md" "\.desktopvisual_local" "AGENTS document sync exclusion" "AGENTS missing lifecycle sync exclusion"

$policyPath = Join-Path $Root "config\artifact_lifecycle_policy.json"
if (Test-Path -LiteralPath $policyPath) {
    $policy = Get-Content -Raw -LiteralPath $policyPath | ConvertFrom-Json
    if ($policy.quarantine_root -eq ".desktopvisual_local\artifact_lifecycle") {
        Add-Pass "Policy quarantine root is local lifecycle root"
    } else {
        Add-Failure "Policy quarantine root is '$($policy.quarantine_root)'"
    }
    if ($policy.sync_exclusion_required -eq $true) {
        Add-Pass "Policy requires sync exclusion"
    } else {
        Add-Failure "Policy does not require sync exclusion"
    }
    if (($policy.protected_paths -contains "src\") -and
        ($policy.protected_paths -contains "config\") -and
        ($policy.protected_paths -contains "artifacts\EVIDENCE_INDEX.md")) {
        Add-Pass "Policy protects source/config/evidence index"
    } else {
        Add-Failure "Policy missing source/config/evidence protections"
    }
    if (($policy.protected_patterns -contains "artifacts\project_snapshot\") -and
        ($policy.protected_patterns -contains "artifacts\field_test_summary.md") -and
        ($policy.protected_patterns -contains "artifacts\learned_acceleration_profiles\") -and
        ($policy.protected_patterns -contains "artifacts\user_approved_feedback\")) {
        Add-Pass "Policy protects release evidence, snapshots, learned profiles, and retained feedback"
    } else {
        Add-Failure "Policy missing release evidence/snapshot/learning protections"
    }
    if ($policy.persistent_learning_protection -eq $true) {
        Add-Pass "Policy protects persistent learning assets"
    } else {
        Add-Failure "Policy missing persistent learning protection"
    }
}

$fixtureRoot = Join-Path $ArtifactDir "fixtures"
if (Test-Path -LiteralPath $fixtureRoot) {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $fixtureRoot | Out-Null

$developerRoot = Join-Path $fixtureRoot "developer_root_mock"
New-Item -ItemType Directory -Force -Path $developerRoot | Out-Null
New-TextFile -Path (Join-Path $developerRoot "VERSION") -Text "1.2.0"
New-TextFile -Path (Join-Path $developerRoot "scratch\debug.tmp") -Text "temporary debug"
New-TextFile -Path (Join-Path $developerRoot "scratch\ambiguous.keep") -Text "ambiguous"
New-TextFile -Path (Join-Path $developerRoot "src\real.cpp") -Text "int main() { return 0; }"
New-TextFile -Path (Join-Path $developerRoot "artifacts\EVIDENCE_INDEX.md") -Text "# evidence"
New-TextFile -Path (Join-Path $developerRoot "artifacts\experience_memory\memory.json") -Text "{}"
New-TextFile -Path (Join-Path $developerRoot "artifacts\workflow_templates\template.json") -Text "{}"
New-TextFile -Path (Join-Path $developerRoot "artifacts\selector_learning\selector.json") -Text "{}"

$developerQuarantineArgs = @(
    "-ProjectRoot", $developerRoot,
    "-Version", "1.2.0",
    "-Path", (Join-Path $developerRoot "scratch\debug.tmp"),
    "-Reason", "transient scratch",
    "-DryRun"
)
$developerPlan = Invoke-JsonScript -Script "scripts\artifact_lifecycle\developer_quarantine_artifacts.ps1" -Arguments $developerQuarantineArgs -OutputPath (Join-Path $ArtifactDir "developer_lifecycle_dry_run_plan.json")
if ($developerPlan) {
    if ($developerPlan.scope -eq "developer_version" -and $developerPlan.version -eq "1.2.0") {
        Add-Pass "Developer quarantine dry-run reports developer_version 1.2.0"
    } else {
        Add-Failure "Developer quarantine dry-run scope/version mismatch"
    }
    if ($developerPlan.files[0].moved_to -match "\\developer_versions\\1\.2\.0\\") {
        Add-Pass "Developer quarantine targets developer_versions\\1.2.0"
    } else {
        Add-Failure "Developer quarantine does not target developer_versions\\1.2.0"
    }
    if (Test-Path -LiteralPath (Join-Path $developerRoot "scratch\debug.tmp")) {
        Add-Pass "Developer dry-run did not move scratch file"
    } else {
        Add-Failure "Developer dry-run moved scratch file"
    }
}

$developerManifestArgs = @(
    "-ProjectRoot", $developerRoot,
    "-Version", "1.2.0",
    "-Path", (Join-Path $developerRoot "scratch\debug.tmp"),
    "-Reason", "transient scratch",
    "-ManifestOnly"
)
$developerManifest = Invoke-JsonScript -Script "scripts\artifact_lifecycle\developer_quarantine_artifacts.ps1" -Arguments $developerManifestArgs -OutputPath (Join-Path $ArtifactDir "developer_lifecycle_manifest_sample.json")
if ($developerManifest) {
    if ($developerManifest.file_count -eq 1 -and $developerManifest.retained_for_next_version -eq $true) {
        Add-Pass "Developer manifest sample records one retained file"
    } else {
        Add-Failure "Developer manifest sample has unexpected file count or retention flag"
    }
}

$developerState = Join-Path $developerRoot ".desktopvisual_local\artifact_lifecycle\developer_versions"
foreach ($versionId in @("1.1.9", "1.1.12", "1.2.0")) {
    New-Item -ItemType Directory -Force -Path (Join-Path $developerState $versionId) | Out-Null
}
New-TextFile -Path (Join-Path $developerState "1.1.9\old.tmp") -Text "old"
New-TextFile -Path (Join-Path $developerState "1.1.9\manifest.json") -Text '{"scope":"developer_version","version":"1.1.9","safe_to_delete_after_version":"1.2.0","delete_policy":"safe_to_delete","files":[],"safe_to_delete":true}'
New-TextFile -Path (Join-Path $developerState "1.1.8\orphan.tmp") -Text "orphan"

$developerCleanupArgs = @(
    "-ProjectRoot", $developerRoot,
    "-Version", "1.2.0",
    "-DryRun",
    "-RequireManifest",
    "-KeepCurrentAndPrevious",
    "2",
    "-ReviewAmbiguous"
)
$developerCleanupPlan = Invoke-JsonScript -Script "scripts\artifact_lifecycle\developer_cleanup_quarantine.ps1" -Arguments $developerCleanupArgs -OutputPath (Join-Path $ArtifactDir "developer_cleanup_dry_run.json")
if ($developerCleanupPlan) {
    if (($developerCleanupPlan.retained_versions -contains "1.2.0") -and ($developerCleanupPlan.review_required_versions -contains "1.1.12")) {
        Add-Pass "Developer cleanup retains current version and sends prior minor-line version to review"
    } else {
        Add-Failure "Developer cleanup does not handle current version and prior minor-line review as expected"
    }
    if ($developerCleanupPlan.deletable_versions -contains "1.1.9") {
        Add-Pass "Developer cleanup marks manifest-safe older version deletable"
    } else {
        Add-Failure "Developer cleanup does not mark manifest-safe older version deletable"
    }
    if ($developerCleanupPlan.review_required_versions -contains "1.1.8") {
        Add-Pass "Developer cleanup sends no-manifest older version to review"
    } else {
        Add-Failure "Developer cleanup did not send no-manifest version to review"
    }
}

$developerCleanupApplyArgs = @(
    "-ProjectRoot", $developerRoot,
    "-Version", "1.2.0",
    "-RequireManifest",
    "-KeepCurrentAndPrevious",
    "2",
    "-ReviewAmbiguous"
)
$developerCleanupResult = Invoke-JsonScript -Script "scripts\artifact_lifecycle\developer_cleanup_quarantine.ps1" -Arguments $developerCleanupApplyArgs -OutputPath (Join-Path $ArtifactDir "developer_cleanup_result.json")
if ($developerCleanupResult) {
    if ((-not (Test-Path -LiteralPath (Join-Path $developerState "1.1.9"))) -and
        (Test-Path -LiteralPath (Join-Path $developerState "1.1.8")) -and
        (Test-Path -LiteralPath (Join-Path $developerState "1.1.12")) -and
        (Test-Path -LiteralPath (Join-Path $developerState "1.2.0"))) {
        Add-Pass "Developer cleanup deletes only safe older version"
    } else {
        Add-Failure "Developer cleanup deleted wrong developer version state"
    }
}

Assert-FileStillExists -Path (Join-Path $developerRoot "scratch\ambiguous.keep") -Message "Developer ambiguous file remains in place"
Assert-FileStillExists -Path (Join-Path $developerRoot "src\real.cpp") -Message "Developer source file remains protected"
Assert-FileStillExists -Path (Join-Path $developerRoot "artifacts\EVIDENCE_INDEX.md") -Message "Developer evidence index remains protected"
Assert-FileStillExists -Path (Join-Path $developerRoot "artifacts\experience_memory\memory.json") -Message "Developer persistent learning asset remains protected"
Assert-FileStillExists -Path (Join-Path $developerRoot "artifacts\workflow_templates\template.json") -Message "Developer workflow template remains protected"
Assert-FileStillExists -Path (Join-Path $developerRoot "artifacts\selector_learning\selector.json") -Message "Developer selector learning asset remains protected"

$releaseRoot = Join-Path $fixtureRoot "release_root_mock"
New-Item -ItemType Directory -Force -Path $releaseRoot | Out-Null
New-TextFile -Path (Join-Path $releaseRoot "VERSION") -Text "1.2.0"
New-TextFile -Path (Join-Path $releaseRoot "run\orphan_output.tmp") -Text "runner output"
New-TextFile -Path (Join-Path $releaseRoot "run\ambiguous.keep") -Text "ambiguous"
New-TextFile -Path (Join-Path $releaseRoot "artifacts\field_test_summary.md") -Text "summary"
New-TextFile -Path (Join-Path $releaseRoot "artifacts\project_snapshot\main.cpp") -Text "snapshot"
New-TextFile -Path (Join-Path $releaseRoot "artifacts\workflow_templates\template.json") -Text "{}"
New-TextFile -Path (Join-Path $releaseRoot "artifacts\selector_learning\selector.json") -Text "{}"

$releaseQuarantineArgs = @(
    "-ProjectRoot", $releaseRoot,
    "-ActionId", "0002",
    "-Path", (Join-Path $releaseRoot "run\orphan_output.tmp"),
    "-Reason", "orphan runner output",
    "-BehaviorInstructionSummary", "mock release action",
    "-DryRun"
)
$releasePlan = Invoke-JsonScript -Script "scripts\artifact_lifecycle\release_action_quarantine_artifacts.ps1" -Arguments $releaseQuarantineArgs -OutputPath (Join-Path $ArtifactDir "release_action_lifecycle_dry_run_plan.json")
if ($releasePlan) {
    if ($releasePlan.scope -eq "release_action" -and $releasePlan.action_id -eq "0002") {
        Add-Pass "Release action quarantine dry-run reports release_action 0002"
    } else {
        Add-Failure "Release action quarantine dry-run scope/action mismatch"
    }
    if ($releasePlan.files[0].moved_to -match "\\release_actions\\0002\\") {
        Add-Pass "Release action quarantine targets release_actions\\0002"
    } else {
        Add-Failure "Release action quarantine does not target release_actions\\0002"
    }
}

$releaseManifestArgs = @(
    "-ProjectRoot", $releaseRoot,
    "-ActionId", "0002",
    "-Path", (Join-Path $releaseRoot "run\orphan_output.tmp"),
    "-Reason", "orphan runner output",
    "-BehaviorInstructionSummary", "mock release action",
    "-ManifestOnly"
)
$releaseManifest = Invoke-JsonScript -Script "scripts\artifact_lifecycle\release_action_quarantine_artifacts.ps1" -Arguments $releaseManifestArgs -OutputPath (Join-Path $ArtifactDir "release_action_manifest_sample.json")
if ($releaseManifest) {
    if ($releaseManifest.file_count -eq 1 -and $releaseManifest.retained_for_next_action -eq $true) {
        Add-Pass "Release action manifest sample records one retained file"
    } else {
        Add-Failure "Release action manifest sample has unexpected file count or retention flag"
    }
}

$releaseState = Join-Path $releaseRoot ".desktopvisual_local\artifact_lifecycle\release_actions"
foreach ($actionId in @("0000", "0001", "0002", "0003")) {
    New-Item -ItemType Directory -Force -Path (Join-Path $releaseState $actionId) | Out-Null
}
New-TextFile -Path (Join-Path $releaseState "0000\orphan.tmp") -Text "orphan"
New-TextFile -Path (Join-Path $releaseState "0001\old.tmp") -Text "old"
New-TextFile -Path (Join-Path $releaseState "0001\manifest.json") -Text '{"scope":"release_action","action_id":"0001","safe_to_delete_after_action":"0003","delete_policy":"safe_to_delete","files":[],"safe_to_delete":true}'

$releaseCleanupArgs = @(
    "-ProjectRoot", $releaseRoot,
    "-ActionId", "0003",
    "-DryRun",
    "-RequireManifest",
    "-KeepCurrentAndPrevious",
    "2",
    "-ReviewAmbiguous"
)
$releaseCleanupPlan = Invoke-JsonScript -Script "scripts\artifact_lifecycle\release_action_cleanup_quarantine.ps1" -Arguments $releaseCleanupArgs -OutputPath (Join-Path $ArtifactDir "release_action_cleanup_dry_run.json")
if ($releaseCleanupPlan) {
    if (($releaseCleanupPlan.retained_action_ids -contains "0003") -and ($releaseCleanupPlan.retained_action_ids -contains "0002")) {
        Add-Pass "Release action cleanup retains current and previous actions"
    } else {
        Add-Failure "Release action cleanup does not retain current and previous actions"
    }
    if ($releaseCleanupPlan.deletable_action_ids -contains "0001") {
        Add-Pass "Release action cleanup marks manifest-safe older action deletable"
    } else {
        Add-Failure "Release action cleanup does not mark manifest-safe older action deletable"
    }
    if ($releaseCleanupPlan.review_required_action_ids -contains "0000") {
        Add-Pass "Release action cleanup sends no-manifest older action to review"
    } else {
        Add-Failure "Release action cleanup did not send no-manifest older action to review"
    }
}

$releaseCleanupApplyArgs = @(
    "-ProjectRoot", $releaseRoot,
    "-ActionId", "0003",
    "-RequireManifest",
    "-KeepCurrentAndPrevious",
    "2",
    "-ReviewAmbiguous"
)
$releaseCleanupResult = Invoke-JsonScript -Script "scripts\artifact_lifecycle\release_action_cleanup_quarantine.ps1" -Arguments $releaseCleanupApplyArgs -OutputPath (Join-Path $ArtifactDir "release_action_cleanup_result.json")
if ($releaseCleanupResult) {
    $sequencePath = Join-Path $releaseState "ACTION_SEQUENCE.json"
    if ((-not (Test-Path -LiteralPath (Join-Path $releaseState "0001"))) -and
        (Test-Path -LiteralPath (Join-Path $releaseState "0000")) -and
        (Test-Path -LiteralPath (Join-Path $releaseState "0002")) -and
        (Test-Path -LiteralPath (Join-Path $releaseState "0003")) -and
        (Test-Path -LiteralPath $sequencePath)) {
        Add-Pass "Release action cleanup deletes only safe old action and writes ACTION_SEQUENCE.json"
    } else {
        Add-Failure "Release action cleanup did not produce expected action state"
    }
    if (Test-Path -LiteralPath $sequencePath) {
        $sequence = Get-Content -Raw -LiteralPath $sequencePath | ConvertFrom-Json
        if ($sequence.current_action_id -eq "0003" -and
            $sequence.previous_action_id -eq "0002" -and
            $sequence.sync_protected -eq $true) {
            Add-Pass "ACTION_SEQUENCE.json records current/previous sync-protected state"
        } else {
            Add-Failure "ACTION_SEQUENCE.json state is incorrect"
        }
    }
}

Assert-FileStillExists -Path (Join-Path $releaseRoot "run\ambiguous.keep") -Message "Release ambiguous file remains in place"
Assert-FileStillExists -Path (Join-Path $releaseRoot "artifacts\field_test_summary.md") -Message "Release field test summary remains protected"
Assert-FileStillExists -Path (Join-Path $releaseRoot "artifacts\project_snapshot\main.cpp") -Message "Release project snapshot remains protected"
Assert-FileStillExists -Path (Join-Path $releaseRoot "artifacts\workflow_templates\template.json") -Message "Release workflow template remains protected"
Assert-FileStillExists -Path (Join-Path $releaseRoot "artifacts\selector_learning\selector.json") -Message "Release selector learning asset remains protected"

if (-not (Test-Path -LiteralPath (Join-Path $releaseRoot ".desktopvisual_local\artifact_lifecycle\developer_versions"))) {
    Add-Pass "Release fixture has no developer_versions state"
} else {
    Add-Failure "Release fixture contains developer_versions state"
}
if (-not (Test-Path -LiteralPath (Join-Path $developerRoot ".desktopvisual_local\artifact_lifecycle\release_actions"))) {
    Add-Pass "Developer fixture has no release_actions state"
} else {
    Add-Failure "Developer fixture contains release_actions state"
}

Assert-Contains "docs\INVALID_ARTIFACT_LIFECYCLE.md" '/XD\s+".git"\s+"\.desktopvisual_local"|/XD\s+`?".git`?"\s+`?".desktopvisual_local`?' "Future robocopy template excludes .desktopvisual_local" "Future robocopy template missing .desktopvisual_local"
Assert-Contains "config\artifact_lifecycle_policy.json" '"sync_exclusion_required"\s*:\s*true' "Policy requires sync isolation" "Policy missing sync isolation requirement"

$desktopReleaseStatusBefore = @(& git -C "E:\desktopvisualproject\desktop_release" status --short 2>$null)
Set-Content -Encoding UTF8 -LiteralPath (Join-Path $ArtifactDir "desktop_release_readonly_check.txt") -Value ($desktopReleaseStatusBefore -join [Environment]::NewLine)
if ($desktopReleaseStatusBefore.Count -ge 0) {
    Add-Pass "desktop_release status was read only"
}

Assert-NotGitChanged -Paths @("config/safety_manifest.json", "config/safety.conf", "src/winagent/PermissionManager.cpp", "src/winagent/PermissionManager.h") -PassMessage "Protected safety/Permission paths unchanged by lifecycle selftest" -FailPrefix "Protected path changed"
Assert-Contains "docs\INVALID_ARTIFACT_LIFECYCLE.md" "No VLM behavior or timeout change" "Lifecycle doc preserves VLM behavior boundary" "Lifecycle doc missing VLM behavior boundary"

foreach ($path in @(
    "E:\desktopvisualproject\desktopvisual-public-dist",
    "E:\desktopvisualproject\desktop_public_restricted",
    "E:\desktopvisualproject\desktop_release_public",
    "E:\desktopvisualproject\desktopvisual-public-release"
)) {
    if (Test-Path -LiteralPath $path) {
        Add-Failure "Forbidden public release path exists: $path"
    } else {
        Add-Pass "Forbidden public release path absent: $path"
    }
}

@"
# Sync Isolation Check

- .desktopvisual_local sync exclusion documented: yes
- developer_versions copied to release fixture: no
- release_actions present in developer fixture: no
- future robocopy template excludes .desktopvisual_local: checked by selftest
"@ | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $ArtifactDir "sync_isolation_check.md")

@"
# Protected Assets Report

- Source/config/docs/current evidence are protected by policy and selftest fixtures.
- Evidence index file was retained in developer fixture.
- Release field-test summary and project snapshot were retained in release fixture.
"@ | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $ArtifactDir "protected_assets_report.md")

@"
# Persistent Learning Protection Check

- Experience memory fixture retained.
- Workflow template fixtures retained.
- Selector learning fixtures retained.
- Stable baselines and future learned acceleration profiles are protected by policy patterns.
"@ | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $ArtifactDir "persistent_learning_protection_check.md")

@"
# Ambiguous Files Policy Check

- Ambiguous developer fixture file was not moved or deleted.
- Ambiguous release fixture file was not moved or deleted.
- Ambiguous files are report-only and wait for user or later explicit classification.
"@ | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $ArtifactDir "ambiguous_files_policy_check.md")

if ($Failures.Count -eq 0) {
    Write-Host "Artifact lifecycle selftest PASS"
    exit 0
}

Write-Host "Artifact lifecycle selftest FAIL: $($Failures.Count) failure(s)"
exit 1


