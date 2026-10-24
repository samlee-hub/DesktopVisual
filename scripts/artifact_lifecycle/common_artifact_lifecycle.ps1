$ErrorActionPreference = "Stop"

function Resolve-ArtifactLifecycleProjectRoot {
    param([string]$ProjectRoot)
    if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
        throw "ProjectRoot is required"
    }
    $resolved = Resolve-Path -LiteralPath $ProjectRoot -ErrorAction Stop
    return $resolved.Path
}

function Get-ArtifactLifecycleRoot {
    param([string]$ProjectRoot)
    return Resolve-ArtifactLifecycleRoot -ProjectRoot $ProjectRoot
}

function Resolve-ArtifactLifecycleRoot {
    param([string]$ProjectRoot)
    $resolvedProjectRoot = Resolve-ArtifactLifecycleProjectRoot -ProjectRoot $ProjectRoot
    $localRoot = Join-Path $resolvedProjectRoot ".desktopvisual_local"
    return Join-Path $localRoot "artifact_lifecycle"
}

function Resolve-DeveloperVersionLifecyclePath {
    param(
        [string]$ProjectRoot,
        [string]$Version
    )
    if ([string]::IsNullOrWhiteSpace($Version)) {
        throw "Version is required"
    }
    $root = Resolve-ArtifactLifecycleRoot -ProjectRoot $ProjectRoot
    $developerRoot = Join-Path $root "developer_versions"
    return Join-Path $developerRoot $Version
}

function Resolve-ReleaseActionLifecyclePath {
    param(
        [string]$ProjectRoot,
        [string]$ActionId
    )
    if ([string]::IsNullOrWhiteSpace($ActionId)) {
        throw "ActionId is required"
    }
    $root = Resolve-ArtifactLifecycleRoot -ProjectRoot $ProjectRoot
    $releaseRoot = Join-Path $root "release_actions"
    return Join-Path $releaseRoot $ActionId
}

function Resolve-ReleaseActionSequencePath {
    param([string]$ProjectRoot)
    $root = Resolve-ArtifactLifecycleRoot -ProjectRoot $ProjectRoot
    $releaseRoot = Join-Path $root "release_actions"
    return Join-Path $releaseRoot "ACTION_SEQUENCE.json"
}

function Get-OrphanBadArtifactLifecyclePathReport {
    param([string]$ProjectRoot)
    $resolvedProjectRoot = Resolve-ArtifactLifecycleProjectRoot -ProjectRoot $ProjectRoot
    $badPath = [System.String]::Concat($resolvedProjectRoot.TrimEnd('\'), ".desktopvisual_local")
    return [pscustomobject]@{
        orphan_bad_lifecycle_path = $badPath
        exists = (Test-Path -LiteralPath $badPath)
        action = "record_only_do_not_delete_without_user_instruction"
        expected_lifecycle_root = (Resolve-ArtifactLifecycleRoot -ProjectRoot $resolvedProjectRoot)
    }
}

function ConvertTo-ArtifactLifecycleRelativePath {
    param(
        [string]$Root,
        [string]$Path
    )
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
    $pathFull = [System.IO.Path]::GetFullPath($Path)
    if (-not $pathFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside ProjectRoot: $Path"
    }
    return $pathFull.Substring($rootFull.Length).TrimStart('\')
}

function ConvertTo-ArtifactLifecycleSafeBoolean {
    param([object]$Value)
    if ($null -eq $Value) {
        return $false
    }
    if ($Value -is [bool]) {
        return $Value
    }
    return ($Value.ToString() -match '^(?i:true|yes|1|safe_to_delete)$')
}

function Get-ArtifactLifecycleDefaultPolicy {
    return [pscustomobject]@{
        quarantine_root = ".desktopvisual_local\artifact_lifecycle"
        protected_paths = @(
            "src\",
            "include\",
            "tools\",
            "config\",
            "scripts\",
            "build.ps1",
            "VERSION",
            "README.md",
            "AGENTS.md",
            "COMMAND_PROTOCOL.md",
            "CHANGELOG.md",
            "CURRENT_EXECUTION_CONTRACT.md",
            "docs\",
            "artifact_lifecycle_selftest.ps1",
            "artifacts\EVIDENCE_INDEX.md"
        )
        protected_patterns = @(
            "artifacts\dev*\",
            "artifacts\evidence\",
            "artifacts\field_test_summary.md",
            "artifacts\project_snapshot\",
            "artifacts\release*\",
            "artifacts\experience_memory\",
            "artifacts\workflow_templates\",
            "artifacts\selector_learning\",
            "artifacts\stable_window_baselines\",
            "artifacts\future_learning\",
            "artifacts\learned_acceleration_profiles\",
            "artifacts\user_approved_feedback\",
            "tests\fixtures\",
            "*.ps1"
        )
        allowed_temp_patterns = @(
            "*.tmp",
            "*.bak",
            "*.orig",
            "*.log.tmp",
            "PowerShell_transcript*.txt",
            "*scratch*",
            "*debug_dump*",
            "*orphan_output*",
            "*temporary*"
        )
        ambiguous_patterns = @(
            "*.keep",
            "*ambiguous*"
        )
        persistent_learning_protection = $true
        sync_exclusion_required = $true
    }
}

function Get-ArtifactLifecyclePolicy {
    param([string]$ProjectRoot)
    $policyPath = Join-Path $ProjectRoot "config\artifact_lifecycle_policy.json"
    if (Test-Path -LiteralPath $policyPath) {
        return Get-Content -Raw -LiteralPath $policyPath | ConvertFrom-Json
    }
    return Get-ArtifactLifecycleDefaultPolicy
}

function Test-ArtifactLifecycleWildcard {
    param(
        [string]$Text,
        [string]$Pattern
    )
    return $Text -like $Pattern
}

function Test-ArtifactLifecycleProtectedPath {
    param(
        [string]$RelativePath,
        [object]$Policy,
        [string]$Scope
    )
    $normalized = $RelativePath.TrimStart('\')
    foreach ($path in @($Policy.protected_paths)) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            continue
        }
        $p = $path.TrimStart('\')
        if ($p.EndsWith("\")) {
            if ($normalized.StartsWith($p, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        } elseif ($normalized.Equals($p, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    foreach ($pattern in @($Policy.protected_patterns)) {
        if ([string]::IsNullOrWhiteSpace($pattern)) {
            continue
        }
        $p = $pattern.TrimStart('\')
        if ($p.EndsWith("\")) {
            if ($normalized.StartsWith($p, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
            continue
        }
        if (Test-ArtifactLifecycleWildcard -Text $normalized -Pattern $pattern) {
            return $true
        }
    }
    if ($Scope -eq "developer_version" -and $normalized -like ".desktopvisual_local\artifact_lifecycle\release_actions*") {
        return $true
    }
    if ($Scope -eq "release_action" -and $normalized -like ".desktopvisual_local\artifact_lifecycle\developer_versions*") {
        return $true
    }
    return $false
}

function Test-ArtifactLifecycleAmbiguousPath {
    param(
        [string]$RelativePath,
        [object]$Policy
    )
    $leaf = Split-Path -Leaf $RelativePath
    foreach ($pattern in @($Policy.ambiguous_patterns)) {
        if ((Test-ArtifactLifecycleWildcard -Text $RelativePath -Pattern $pattern) -or
            (Test-ArtifactLifecycleWildcard -Text $leaf -Pattern $pattern)) {
            return $true
        }
    }
    return $false
}

function Test-ArtifactLifecycleAllowedTempPath {
    param(
        [string]$RelativePath,
        [object]$Policy
    )
    $leaf = Split-Path -Leaf $RelativePath
    foreach ($pattern in @($Policy.allowed_temp_patterns)) {
        if ((Test-ArtifactLifecycleWildcard -Text $RelativePath -Pattern $pattern) -or
            (Test-ArtifactLifecycleWildcard -Text $leaf -Pattern $pattern)) {
            return $true
        }
    }
    return $false
}

function New-ArtifactLifecycleManifestBase {
    param(
        [string]$Scope,
        [string]$Reason,
        [string]$SourceContext,
        [object[]]$Files,
        [string[]]$AmbiguousFiles,
        [string]$DeletePolicy,
        [bool]$ProtectedAssetsChecked,
        [string[]]$Notes
    )
    $totalBytes = 0
    foreach ($file in @($Files)) {
        if ($null -ne $file.bytes) {
            $totalBytes += [int64]$file.bytes
        }
    }
    return [ordered]@{
        scope = $Scope
        created_at = (Get-Date).ToUniversalTime().ToString("o")
        source_context = $SourceContext
        files = @($Files)
        file_count = @($Files).Count
        total_bytes = $totalBytes
        classification = "invalid_artifact"
        reason = $Reason
        moved_from = @($Files | ForEach-Object { $_.moved_from })
        moved_to = @($Files | ForEach-Object { $_.moved_to })
        referenced_by = @()
        delete_policy = $DeletePolicy
        protected_assets_checked = $ProtectedAssetsChecked
        ambiguous_files = @($AmbiguousFiles)
        notes = @($Notes)
    }
}

function New-ArtifactLifecyclePlan {
    param(
        [string]$ProjectRoot,
        [string]$Scope,
        [string]$StatePath,
        [string[]]$Paths,
        [string]$Reason,
        [string]$SourceContext,
        [string]$DeletePolicy
    )
    $policy = Get-ArtifactLifecyclePolicy -ProjectRoot $ProjectRoot
    $files = New-Object System.Collections.Generic.List[object]
    $ambiguous = New-Object System.Collections.Generic.List[string]
    foreach ($path in @($Paths)) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            continue
        }
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Candidate path does not exist: $path"
        }
        $item = Get-Item -LiteralPath $path
        if ($item.PSIsContainer) {
            $children = Get-ChildItem -LiteralPath $item.FullName -Recurse -File
        } else {
            $children = @($item)
        }
        foreach ($child in $children) {
            $relative = ConvertTo-ArtifactLifecycleRelativePath -Root $ProjectRoot -Path $child.FullName
            $isProtected = Test-ArtifactLifecycleProtectedPath -RelativePath $relative -Policy $policy -Scope $Scope
            $isAmbiguous = Test-ArtifactLifecycleAmbiguousPath -RelativePath $relative -Policy $policy
            $isAllowed = Test-ArtifactLifecycleAllowedTempPath -RelativePath $relative -Policy $policy
            if ($isAmbiguous -or (-not $isAllowed) -or $isProtected) {
                $ambiguous.Add($relative) | Out-Null
                continue
            }
            $target = Join-Path (Join-Path $StatePath "files") $relative
            $files.Add([pscustomobject]@{
                path = $relative
                bytes = [int64]$child.Length
                classification = "invalid_artifact"
                reason = $Reason
                moved_from = $child.FullName
                moved_to = $target
                referenced_by = @()
                protected = $false
            }) | Out-Null
        }
    }
    return [pscustomobject]@{
        files = $files.ToArray()
        ambiguous_files = $ambiguous.ToArray()
    }
}

function Write-ArtifactLifecycleAmbiguousReport {
    param(
        [string[]]$AmbiguousFiles,
        [string]$StatePath,
        [string]$Scope
    )
    if (@($AmbiguousFiles).Count -eq 0) {
        return ""
    }
    New-Item -ItemType Directory -Force -Path $StatePath | Out-Null
    $reportPath = Join-Path $StatePath "ambiguous_files.md"
    @(
        "# Ambiguous Files",
        "",
        "Scope: $Scope",
        "",
        "These files were recorded only. They were not moved and must not be deleted without explicit later classification.",
        "",
        (@($AmbiguousFiles) | ForEach-Object { "- $_" })
    ) | Set-Content -Encoding UTF8 -LiteralPath $reportPath
    return $reportPath
}

function Write-ArtifactLifecycleManifest {
    param(
        [object]$Manifest,
        [string]$StatePath
    )
    New-Item -ItemType Directory -Force -Path $StatePath | Out-Null
    $manifestPath = Join-Path $StatePath "manifest.json"
    $Manifest | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -LiteralPath $manifestPath
    return $manifestPath
}

function Move-ArtifactLifecycleFiles {
    param([object]$Manifest)
    foreach ($file in @($Manifest.files)) {
        $targetParent = Split-Path -Parent $file.moved_to
        New-Item -ItemType Directory -Force -Path $targetParent | Out-Null
        Move-Item -LiteralPath $file.moved_from -Destination $file.moved_to -Force
    }
}

function ConvertTo-ArtifactLifecycleJson {
    param([object]$Value)
    return ($Value | ConvertTo-Json -Depth 12)
}
