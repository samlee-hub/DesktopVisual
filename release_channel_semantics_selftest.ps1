param()

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root

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

function Read-HeadText {
    param(
        [string]$Path,
        [int]$Lines
    )
    return (Get-Content -LiteralPath (Join-Path $Root $Path) -TotalCount $Lines) -join "`n"
}

function Assert-TextMatch {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$PassMessage,
        [string]$FailMessage
    )

    if ($Text -match $Pattern) {
        Add-Pass $PassMessage
    } else {
        Add-Failure $FailMessage
    }
}

function Test-ApprovedDesktopReleaseSync {
    param(
        [string]$ReleaseRoot,
        [string]$ExpectedVersion
    )
    $evidenceRoot = Join-Path $ReleaseRoot "artifacts\release_sync_v$($ExpectedVersion)_local_use_demo"
    $requiredEvidence = @(
        "sync_summary.md",
        "source_version_before_sync.txt",
        "target_version_before_sync.txt",
        "robocopy_actual_sync.log",
        "target_version_after_sync.txt"
    )
    foreach ($name in $requiredEvidence) {
        if (-not (Test-Path -LiteralPath (Join-Path $evidenceRoot $name))) {
            return $false
        }
    }
    return $true
}

$version = (Read-Text "VERSION").Trim()
if ($version -eq "1.1.12") {
    Add-Pass "VERSION is 1.1.12"
} else {
    Add-Failure "VERSION is '$version', expected 1.1.12"
}

$releaseChannelsPath = Join-Path $Root "docs\RELEASE_CHANNELS.md"
if (Test-Path -LiteralPath $releaseChannelsPath) {
    Add-Pass "docs\RELEASE_CHANNELS.md exists"
    $releaseChannels = Read-Text "docs\RELEASE_CHANNELS.md"
} else {
    Add-Failure "docs\RELEASE_CHANNELS.md is missing"
    $releaseChannels = ""
}

$contract = Read-Text "CURRENT_EXECUTION_CONTRACT.md"
if ($contract -match [regex]::Escape("docs\RELEASE_CHANNELS.md") -or
    ($contract -match "(?i)developer tree" -and
     $contract -match "(?i)local-use/demo release tree" -and
     $contract -match "(?i)future restricted public release")) {
    Add-Pass "CURRENT_EXECUTION_CONTRACT.md references docs\RELEASE_CHANNELS.md or contains release channel definitions"
} else {
    Add-Failure "CURRENT_EXECUTION_CONTRACT.md lacks docs\RELEASE_CHANNELS.md reference and complete release channel definitions"
}

$agentsHead = Read-HeadText "AGENTS.md" 160
if ($agentsHead -match [regex]::Escape("docs\RELEASE_CHANNELS.md")) {
    Add-Pass "AGENTS.md top 160 lines reference docs\RELEASE_CHANNELS.md"
} else {
    Add-Failure "AGENTS.md top 160 lines do not reference docs\RELEASE_CHANNELS.md"
}

$readmeHead = Read-HeadText "README.md" 160
if ($readmeHead -match [regex]::Escape("docs\RELEASE_CHANNELS.md")) {
    Add-Pass "README.md top 160 lines reference docs\RELEASE_CHANNELS.md"
} else {
    Add-Failure "README.md top 160 lines do not reference docs\RELEASE_CHANNELS.md"
}

$protocolHead = Read-HeadText "COMMAND_PROTOCOL.md" 200
if ($protocolHead -match [regex]::Escape("docs\RELEASE_CHANNELS.md")) {
    Add-Pass "COMMAND_PROTOCOL.md top 200 lines reference docs\RELEASE_CHANNELS.md"
} else {
    Add-Failure "COMMAND_PROTOCOL.md top 200 lines do not reference docs\RELEASE_CHANNELS.md"
}

$localRelease = Read-Text "docs\LOCAL_RELEASE_PERMISSION_POLICY.md"
Assert-TextMatch `
    -Text $localRelease `
    -Pattern "(?i)current\s+role:\s*local-use/demo/testing\s+release" `
    -PassMessage "LOCAL_RELEASE_PERMISSION_POLICY states current desktop_release is local-use/demo/testing release" `
    -FailMessage "LOCAL_RELEASE_PERMISSION_POLICY does not state current desktop_release is local-use/demo/testing release"

Assert-TextMatch `
    -Text $localRelease `
    -Pattern "(?i)(current\s+desktop_release|desktop_release).{0,80}not\s+(the\s+)?final\s+restricted\s+public\s+release" `
    -PassMessage "LOCAL_RELEASE_PERMISSION_POLICY states current desktop_release is not final restricted public release" `
    -FailMessage "LOCAL_RELEASE_PERMISSION_POLICY does not state current desktop_release is not final restricted public release"

Assert-TextMatch `
    -Text $releaseChannels `
    -Pattern "(?i)future\s+restricted\s+public\s+release\s+is\s+not\s+created\s+yet" `
    -PassMessage "RELEASE_CHANNELS states future restricted public release is not created yet" `
    -FailMessage "RELEASE_CHANNELS does not state future restricted public release is not created yet"

Assert-TextMatch `
    -Text $releaseChannels `
    -Pattern "(?i)v1\.1\.12.{0,120}synchroni[sz]es.{0,120}after developer validation|protected.{0,80}sync" `
    -PassMessage "RELEASE_CHANNELS states desktop_release sync is protected after v1.1.12 validation" `
    -FailMessage "RELEASE_CHANNELS does not state protected v1.1.12 desktop_release sync"

Assert-TextMatch `
    -Text $releaseChannels `
    -Pattern "(?i)v1\.2\.0\s+does\s+not\s+create\s+public\s+restricted\s+release\s+by\s+default" `
    -PassMessage "RELEASE_CHANNELS states v1.2.0 does not create public restricted release by default" `
    -FailMessage "RELEASE_CHANNELS does not state v1.2.0 does not create public restricted release by default"

Assert-TextMatch `
    -Text $releaseChannels `
    -Pattern "(?i)do\s+not\s+infer\s+permission\s+reduction\s+from\s+the\s+word\s+release" `
    -PassMessage "RELEASE_CHANNELS states do not infer permission reduction from the word release" `
    -FailMessage "RELEASE_CHANNELS does not state do not infer permission reduction from the word release"

$manifest = Read-Text "config\safety_manifest.json" | ConvertFrom-Json
if ($manifest.default_permission_mode -eq "DEVELOPER_CAPABILITY_DISCOVERY") {
    Add-Pass "default_permission_mode remains DEVELOPER_CAPABILITY_DISCOVERY"
} else {
    Add-Failure "default_permission_mode is '$($manifest.default_permission_mode)', expected DEVELOPER_CAPABILITY_DISCOVERY"
}

$gitAvailable = $false
try {
    & git rev-parse --is-inside-work-tree *> $null
    $gitAvailable = ($LASTEXITCODE -eq 0)
} catch {
    $gitAvailable = $false
}

if ($gitAvailable) {
    $forbiddenPaths = @(
        "config/safety_manifest.json",
        "config/safety.conf"
    )

    $changedForbidden = @(& git diff --name-only -- $forbiddenPaths)
    $stagedForbidden = @(& git diff --cached --name-only -- $forbiddenPaths)
    $untrackedForbidden = @(& git ls-files --others --exclude-standard -- $forbiddenPaths)
    $allForbidden = @($changedForbidden + $stagedForbidden + $untrackedForbidden) | Where-Object { $_ }

    if ($allForbidden.Count -eq 0) {
        Add-Pass "No protected config paths modified"
    } else {
        foreach ($path in $allForbidden) {
            Add-Failure "Forbidden config path modified or added: $path"
        }
    }

    $developerTreeReleasePaths = @(& git status --short -- "desktop_release" "desktopvisual-public-dist" "public-dist" "public_dist" 2>$null)
    if ($developerTreeReleasePaths.Count -eq 0) {
        Add-Pass "No desktop_release or public-dist paths changed inside developer tree"
    } else {
        foreach ($path in $developerTreeReleasePaths) {
            Add-Failure "Unexpected release/public-dist path changed inside developer tree: $path"
        }
    }
} else {
    Add-Failure "git is unavailable; cannot verify Runtime/config unchanged"
}

$rootName = Split-Path -Leaf $Root
$siblingReleaseRoot = Join-Path (Split-Path -Parent $Root) "desktop_release"
if ($rootName -ieq "desktop_release") {
    if (Test-ApprovedDesktopReleaseSync -ReleaseRoot $Root -ExpectedVersion $version) {
        Add-Pass "Current desktop_release is v$version with approved local-use/demo/testing sync evidence"
    } else {
        Add-Failure "Current desktop_release is v$version but approved sync evidence is incomplete"
    }
} elseif (Test-Path -LiteralPath $siblingReleaseRoot) {
    $siblingVersionPath = Join-Path $siblingReleaseRoot "VERSION"
    if (Test-Path -LiteralPath $siblingVersionPath) {
        $siblingVersion = (Get-Content -Raw -LiteralPath $siblingVersionPath).Trim()
        if ($siblingVersion -eq $version) {
            if (Test-ApprovedDesktopReleaseSync -ReleaseRoot $siblingReleaseRoot -ExpectedVersion $version) {
                Add-Pass "Sibling desktop_release VERSION is $version with approved local-use/demo/testing sync evidence"
            } else {
                Add-Failure "Sibling desktop_release VERSION is $version without approved sync evidence"
            }
        } else {
            Add-Pass "Sibling desktop_release VERSION is not $version"
        }
    } else {
        Add-Pass "Sibling desktop_release has no VERSION file to indicate v$version sync"
    }
} else {
    Add-Pass "Sibling desktop_release path is absent; no v$version sync detected"
}

if ($Failures.Count -eq 0) {
    Write-Host "Release channel semantics selftest PASS"
    exit 0
}

Write-Host "Release channel semantics selftest FAIL: $($Failures.Count) failure(s)"
exit 1



