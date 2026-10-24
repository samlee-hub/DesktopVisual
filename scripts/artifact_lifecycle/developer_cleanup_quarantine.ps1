param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$Version,
    [switch]$DryRun,
    [switch]$WhatIf,
    [switch]$ManifestOnly,
    [switch]$RequireManifest,
    [int]$KeepCurrentAndPrevious = 2,
    [switch]$ReviewAmbiguous
)

$Common = Join-Path $PSScriptRoot "common_artifact_lifecycle.ps1"
. $Common

function Get-PreviousVersionString {
    param([string]$Version)
    $parts = $Version.Split('.')
    if ($parts.Count -lt 3) { return $null }
    $patch = [int]$parts[2]
    if ($patch -le 0) { return $null }
    return ("{0}.{1}.{2}" -f $parts[0], $parts[1], ($patch - 1))
}

function Test-DeveloperManifestSafeToDelete {
    param(
        [string]$ManifestPath,
        [string]$CurrentVersion
    )
    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        return $false
    }
    $manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
    if ($manifest.scope -ne "developer_version") {
        return $false
    }
    $safeFlag = ConvertTo-ArtifactLifecycleSafeBoolean -Value $manifest.safe_to_delete
    $deletePolicy = ($manifest.delete_policy -eq "safe_to_delete" -or $manifest.delete_policy -eq "delete_after_next_version_closes")
    if (-not ($safeFlag -or $deletePolicy)) {
        return $false
    }
    if ($manifest.safe_to_delete_after_version) {
        try {
            return ([version]$CurrentVersion -ge [version]$manifest.safe_to_delete_after_version)
        } catch {
            return $false
        }
    }
    return $true
}

$ProjectRoot = Resolve-ArtifactLifecycleProjectRoot -ProjectRoot $ProjectRoot
$root = Split-Path -Parent (Resolve-DeveloperVersionLifecyclePath -ProjectRoot $ProjectRoot -Version $Version)
New-Item -ItemType Directory -Force -Path $root | Out-Null

$previous = Get-PreviousVersionString -Version $Version
$retained = @($Version)
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
    if (Test-DeveloperManifestSafeToDelete -ManifestPath $manifestPath -CurrentVersion $Version) {
        $deletable.Add($name) | Out-Null
        if (-not $DryRun -and -not $WhatIf -and -not $ManifestOnly) {
            Remove-Item -LiteralPath $dir.FullName -Recurse -Force
            $deleted.Add($name) | Out-Null
        }
    } else {
        $review.Add($name) | Out-Null
    }
}

$reviewPath = Join-Path $root "developer_cleanup_review.md"
if ($review.Count -gt 0 -and -not $DryRun -and -not $WhatIf) {
    @(
        "# Developer Cleanup Review",
        "",
        "The following developer version quarantine folders were retained for review because manifest evidence was missing or unsafe:",
        "",
        ($review | ForEach-Object { "- $_" })
    ) | Set-Content -Encoding UTF8 -LiteralPath $reviewPath
}

$result = [ordered]@{
    scope = "developer_version_cleanup"
    version = $Version
    root = $root
    retained_versions = @($retained)
    deletable_versions = @($deletable)
    review_required_versions = @($review)
    deleted_versions = @($deleted)
    dry_run = [bool]$DryRun
    what_if = [bool]$WhatIf
    require_manifest = [bool]$RequireManifest
    keep_current_and_previous = $KeepCurrentAndPrevious
    review_ambiguous = [bool]$ReviewAmbiguous
    review_report = $(if ($review.Count -gt 0) { $reviewPath } else { "" })
    release_actions_referenced = $false
}

ConvertTo-ArtifactLifecycleJson -Value $result
