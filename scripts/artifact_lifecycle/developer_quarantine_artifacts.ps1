param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$Version,
    [string[]]$Path = @(),
    [string]$Reason = "invalid developer artifact",
    [string]$SourceContext = "developer_version_lifecycle",
    [switch]$DryRun,
    [switch]$WhatIf,
    [switch]$ManifestOnly,
    [switch]$RequireManifest,
    [int]$KeepCurrentAndPrevious = 2,
    [switch]$ReviewAmbiguous
)

$Common = Join-Path $PSScriptRoot "common_artifact_lifecycle.ps1"
. $Common

$ProjectRoot = Resolve-ArtifactLifecycleProjectRoot -ProjectRoot $ProjectRoot
$statePath = Resolve-DeveloperVersionLifecyclePath -ProjectRoot $ProjectRoot -Version $Version
$plan = New-ArtifactLifecyclePlan -ProjectRoot $ProjectRoot -Scope "developer_version" -StatePath $statePath -Paths $Path -Reason $Reason -SourceContext $SourceContext -DeletePolicy "delete_after_next_version_closes"

$base = New-ArtifactLifecycleManifestBase -Scope "developer_version" -Reason $Reason -SourceContext $SourceContext -Files $plan.files -AmbiguousFiles $plan.ambiguous_files -DeletePolicy "delete_after_next_version_closes" -ProtectedAssetsChecked $true -Notes @("developer_versions state is developer-local", "release_actions state is not used by developer lifecycle")
$manifest = [ordered]@{
    scope = $base.scope
    version = $Version
    created_at = $base.created_at
    source_context = $base.source_context
    files = $base.files
    file_count = $base.file_count
    total_bytes = $base.total_bytes
    classification = $base.classification
    reason = $base.reason
    moved_from = $base.moved_from
    moved_to = $base.moved_to
    referenced_by = $base.referenced_by
    safe_to_delete_after_version = $Version
    retained_for_next_version = $true
    delete_policy = $base.delete_policy
    protected_assets_checked = $base.protected_assets_checked
    ambiguous_files = $base.ambiguous_files
    ambiguous_files_report = $(if (@($base.ambiguous_files).Count -gt 0) { Join-Path $statePath "ambiguous_files.md" } else { "" })
    notes = $base.notes
    safe_to_delete = $true
    keep_current_and_previous = $KeepCurrentAndPrevious
}

if (-not $DryRun -and -not $WhatIf) {
    Write-ArtifactLifecycleManifest -Manifest $manifest -StatePath $statePath | Out-Null
    Write-ArtifactLifecycleAmbiguousReport -AmbiguousFiles $manifest.ambiguous_files -StatePath $statePath -Scope "developer_version" | Out-Null
    if (-not $ManifestOnly) {
        Move-ArtifactLifecycleFiles -Manifest $manifest
    }
}

ConvertTo-ArtifactLifecycleJson -Value $manifest
