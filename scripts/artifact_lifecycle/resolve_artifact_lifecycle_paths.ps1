param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [string]$Version = "1.1.12",
    [string]$ActionId = "0001"
)

$ErrorActionPreference = "Stop"

$Common = Join-Path $PSScriptRoot "common_artifact_lifecycle.ps1"
. $Common

$resolvedProjectRoot = Resolve-ArtifactLifecycleProjectRoot -ProjectRoot $ProjectRoot
$report = [ordered]@{
    project_root = $resolvedProjectRoot
    artifact_lifecycle_root = Resolve-ArtifactLifecycleRoot -ProjectRoot $resolvedProjectRoot
    developer_version_lifecycle_path = Resolve-DeveloperVersionLifecyclePath -ProjectRoot $resolvedProjectRoot -Version $Version
    release_action_lifecycle_path = Resolve-ReleaseActionLifecyclePath -ProjectRoot $resolvedProjectRoot -ActionId $ActionId
    release_action_sequence_path = Resolve-ReleaseActionSequencePath -ProjectRoot $resolvedProjectRoot
    orphan_bad_lifecycle_path = Get-OrphanBadArtifactLifecyclePathReport -ProjectRoot $resolvedProjectRoot
    path_resolver_version = "artifact_lifecycle_paths.v1.1.12"
    good_paths_use_join_path = $true
    bad_path_action = "record_only_do_not_delete_without_user_instruction"
}

$report | ConvertTo-Json -Depth 8
