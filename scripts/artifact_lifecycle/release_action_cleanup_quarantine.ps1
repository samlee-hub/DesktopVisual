param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$ActionId,
    [switch]$DryRun,
    [switch]$WhatIf,
    [switch]$ManifestOnly,
    [switch]$RequireManifest,
    [int]$KeepCurrentAndPrevious = 2,
    [switch]$ReviewAmbiguous
)

$Common = Join-Path $PSScriptRoot "common_artifact_lifecycle.ps1"
. $Common

function Get-PreviousActionId {
    param([string]$ActionId)
    $n = [int]$ActionId
    if ($n -le 1) { return $null }
    return ($n - 1).ToString(("0" * $ActionId.Length))
}

function Test-ReleaseManifestSafeToDelete {
    param(
        [string]$ManifestPath,
        [string]$CurrentActionId
    )
    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        return $false
    }
    $manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
    if ($manifest.scope -ne "release_action") {
        return $false
    }
    $safeFlag = ConvertTo-ArtifactLifecycleSafeBoolean -Value $manifest.safe_to_delete
    $deletePolicy = ($manifest.delete_policy -eq "safe_to_delete" -or $manifest.delete_policy -eq "delete_after_next_action_closes")
    if (-not ($safeFlag -or $deletePolicy)) {
        return $false
    }
    if ($manifest.safe_to_delete_after_action) {
        return ([int]$CurrentActionId -ge [int]$manifest.safe_to_delete_after_action)
    }
    return $true
}

$ProjectRoot = Resolve-ArtifactLifecycleProjectRoot -ProjectRoot $ProjectRoot
$root = Split-Path -Parent (Resolve-ReleaseActionLifecyclePath -ProjectRoot $ProjectRoot -ActionId $ActionId)
New-Item -ItemType Directory -Force -Path $root | Out-Null

$previous = Get-PreviousActionId -ActionId $ActionId
$retained = @($ActionId)
if ($previous) { $retained += $previous }
$retained = $retained | Select-Object -First $KeepCurrentAndPrevious

$deletable = New-Object System.Collections.Generic.List[string]
$review = New-Object System.Collections.Generic.List[string]
$deleted = New-Object System.Collections.Generic.List[string]

foreach ($dir in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
    $name = $dir.Name
    if ($retained -contains $name) {
        continue
    }
    $manifestPath = Join-Path $dir.FullName "manifest.json"
    if (Test-ReleaseManifestSafeToDelete -ManifestPath $manifestPath -CurrentActionId $ActionId) {
        $deletable.Add($name) | Out-Null
        if (-not $DryRun -and -not $WhatIf -and -not $ManifestOnly) {
            Remove-Item -LiteralPath $dir.FullName -Recurse -Force
            $deleted.Add($name) | Out-Null
        }
    } else {
        $review.Add($name) | Out-Null
    }
}

$sequence = [ordered]@{
    current_action_id = $ActionId
    previous_action_id = $(if ($previous) { $previous } else { "" })
    retained_action_ids = @($retained)
    deleted_action_ids = @($deleted)
    last_cleanup_ts = (Get-Date).ToUniversalTime().ToString("o")
    cleanup_policy_version = "artifact_lifecycle.v1"
    sync_protected = $true
    notes = @(
        ".desktopvisual_local is release-local state",
        "release_actions must not be deleted by developer-to-release mirror sync"
    )
}

$sequencePath = Resolve-ReleaseActionSequencePath -ProjectRoot $ProjectRoot
if (-not $DryRun -and -not $WhatIf) {
    $sequence | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $sequencePath
}

$result = [ordered]@{
    scope = "release_action_cleanup"
    action_id = $ActionId
    root = $root
    retained_action_ids = @($retained)
    deletable_action_ids = @($deletable)
    review_required_action_ids = @($review)
    deleted_action_ids = @($deleted)
    dry_run = [bool]$DryRun
    what_if = [bool]$WhatIf
    require_manifest = [bool]$RequireManifest
    keep_current_and_previous = $KeepCurrentAndPrevious
    review_ambiguous = [bool]$ReviewAmbiguous
    action_sequence_path = $sequencePath
    action_sequence = $sequence
    developer_versions_referenced = $false
}

ConvertTo-ArtifactLifecycleJson -Value $result
