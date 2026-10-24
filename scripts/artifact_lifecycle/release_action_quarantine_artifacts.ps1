param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$ActionId,
    [string[]]$Path = @(),
    [string]$Reason = "invalid release action artifact",
    [string]$BehaviorInstructionSummary = "local-use release action",
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
$statePath = Resolve-ReleaseActionLifecyclePath -ProjectRoot $ProjectRoot -ActionId $ActionId
$plan = New-ArtifactLifecyclePlan -ProjectRoot $ProjectRoot -Scope "release_action" -StatePath $statePath -Paths $Path -Reason $Reason -SourceContext $BehaviorInstructionSummary -DeletePolicy "delete_after_next_action_closes"

$base = New-ArtifactLifecycleManifestBase -Scope "release_action" -Reason $Reason -SourceContext $BehaviorInstructionSummary -Files $plan.files -AmbiguousFiles $plan.ambiguous_files -DeletePolicy "delete_after_next_action_closes" -ProtectedAssetsChecked $true -Notes @("release_actions state is release-local", "developer_versions state is not used by release action lifecycle")
$manifest = [ordered]@{
    scope = $base.scope
    action_id = $ActionId
    created_at = $base.created_at
    behavior_instruction_summary = $BehaviorInstructionSummary
    source_context = $base.source_context
    files = $base.files
    file_count = $base.file_count
    total_bytes = $base.total_bytes
    classification = $base.classification
    reason = $base.reason
    moved_from = $base.moved_from
    moved_to = $base.moved_to
    referenced_by = $base.referenced_by
    safe_to_delete_after_action = $ActionId
    retained_for_next_action = $true
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
    Write-ArtifactLifecycleAmbiguousReport -AmbiguousFiles $manifest.ambiguous_files -StatePath $statePath -Scope "release_action" | Out-Null
    if (-not $ManifestOnly) {
        Move-ArtifactLifecycleFiles -Manifest $manifest
    }
}

ConvertTo-ArtifactLifecycleJson -Value $manifest
