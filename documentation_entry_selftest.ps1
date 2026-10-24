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

$version = (Read-Text "VERSION").Trim()
if ($version -eq "1.1.12") {
    Add-Pass "VERSION is 1.1.12"
} else {
    Add-Failure "VERSION is '$version', expected 1.1.12"
}

if (Test-Path -LiteralPath (Join-Path $Root "CURRENT_EXECUTION_CONTRACT.md")) {
    Add-Pass "CURRENT_EXECUTION_CONTRACT.md exists"
} else {
    Add-Failure "CURRENT_EXECUTION_CONTRACT.md is missing"
}

$readmeHead = Read-HeadText "README.md" 120
if ($readmeHead -match [regex]::Escape("CURRENT_EXECUTION_CONTRACT.md") -and
    $readmeHead -match [regex]::Escape("docs\RELEASE_CHANNELS.md") -and
    $readmeHead -match [regex]::Escape("docs\CORE_WAIT_STATE_HARDENING.md") -and
    $readmeHead -match [regex]::Escape("docs\WORKFLOW_WAIT_STATE_HARDENING.md")) {
    Add-Pass "README.md top 120 lines reference current contract, release channels, and wait-state docs"
} else {
    Add-Failure "README.md top 120 lines do not reference current contract, release channels, and wait-state docs"
}

$agentsHead = Read-HeadText "AGENTS.md" 120
if ($agentsHead -match [regex]::Escape("CURRENT_EXECUTION_CONTRACT.md") -and
    $agentsHead -match [regex]::Escape("docs\RELEASE_CHANNELS.md") -and
    $agentsHead -match [regex]::Escape("docs\CORE_WAIT_STATE_HARDENING.md") -and
    $agentsHead -match [regex]::Escape("docs\WORKFLOW_WAIT_STATE_HARDENING.md")) {
    Add-Pass "AGENTS.md top 120 lines reference current contract, release channels, and wait-state docs"
} else {
    Add-Failure "AGENTS.md top 120 lines do not reference current contract, release channels, and wait-state docs"
}

$protocolHead = Read-HeadText "COMMAND_PROTOCOL.md" 160
if ($protocolHead -match "Current Minimal Agent Contract" -and
    $protocolHead -match [regex]::Escape("CURRENT_EXECUTION_CONTRACT.md") -and
    $protocolHead -match [regex]::Escape("docs\RELEASE_CHANNELS.md") -and
    $protocolHead -match [regex]::Escape("docs\CORE_WAIT_STATE_HARDENING.md") -and
    $protocolHead -match [regex]::Escape("docs\WORKFLOW_WAIT_STATE_HARDENING.md")) {
    Add-Pass "COMMAND_PROTOCOL.md top 160 lines include Current Minimal Agent Contract and current doc references"
} else {
    Add-Failure "COMMAND_PROTOCOL.md top 160 lines are missing Current Minimal Agent Contract or current doc references"
}

$status = Read-Text "docs\DEVELOPMENT_STATUS.md"
if ($status -match "(?m)^current_trusted_version:\s*1\.1\.12\s*$" -and
    $status -match "(?m)^runtime_version:\s*1\.1\.12\s*$" -and
    $status -match "(?m)^last_completed_version:\s*1\.1\.11\s*$" -and
    $status -match "(?m)^last_completed_status:\s*pass\s*$" -and
    $status -match "(?m)^next_planned_version:\s*none\s*$" -and
    $status -match "(?m)^current_stage:\s*launch_contract_vs_startup_convergence\s*$") {
    Add-Pass "DEVELOPMENT_STATUS points to v1.1.12 launch contract and VS startup convergence"
} else {
    Add-Failure "DEVELOPMENT_STATUS does not point to v1.1.12 launch contract and VS startup convergence"
}

if (Test-Path -LiteralPath (Join-Path $Root "docs\RELEASE_CHANNELS.md")) {
    Add-Pass "docs\RELEASE_CHANNELS.md exists"
} else {
    Add-Failure "docs\RELEASE_CHANNELS.md is missing"
}

$safetyHead = Read-HeadText "docs\SAFETY_MODEL.md" 160
if ($safetyHead -match "(?i)v3/v4/v5/v6" -and
    $safetyHead -match "(?i)historical|lineage|archived") {
    Add-Pass "SAFETY_MODEL top 160 lines mark old v3/v4/v5/v6 safety content as historical lineage"
} else {
    Add-Failure "SAFETY_MODEL top 160 lines do not mark old v3/v4/v5/v6 safety content as historical lineage"
}

$agentGuideHead = Read-HeadText "docs\AGENT_USAGE_GUIDE.md" 160
if ($agentGuideHead.Contains('First read `CURRENT_EXECUTION_CONTRACT.md`') -or
    $agentGuideHead.Contains('Agents must read `CURRENT_EXECUTION_CONTRACT.md`')) {
    Add-Pass "AGENT_USAGE_GUIDE top 160 lines instruct agents to read CURRENT_EXECUTION_CONTRACT.md first"
} else {
    Add-Failure "AGENT_USAGE_GUIDE top 160 lines do not instruct agents to read CURRENT_EXECUTION_CONTRACT.md first"
}

$localRelease = Read-Text "docs\LOCAL_RELEASE_PERMISSION_POLICY.md"
if ($localRelease -match "(?i)current\s+.*desktop_release.*local-use\s*/\s*demo\s*/\s*testing\s+release" -and
    $localRelease -match "(?i)not\s+the\s+final\s+restricted\s+public\s+release") {
    Add-Pass "LOCAL_RELEASE_PERMISSION_POLICY states current desktop_release is local-use/demo/testing and not final restricted public release"
} else {
    Add-Failure "LOCAL_RELEASE_PERMISSION_POLICY does not clearly state current desktop_release local-use/demo/testing and not final restricted public release"
}

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
        "src/winagent/PermissionManager.cpp",
        "src/winagent/CodeEditorWorkflow.cpp",
        "config/safety_manifest.json",
        "config/safety.conf"
    )

    $changed = @(& git diff --name-only -- $forbiddenPaths)
    $untrackedForbidden = @(& git ls-files --others --exclude-standard -- $forbiddenPaths)
    if ($changed.Count -eq 0 -and $untrackedForbidden.Count -eq 0) {
        Add-Pass "No forbidden PermissionManager/Code workflow/config files modified or added"
    } else {
        foreach ($path in $changed) {
            Add-Failure "Forbidden tracked file modified: $path"
        }
        foreach ($path in $untrackedForbidden) {
            Add-Failure "Forbidden workflow/config path untracked: $path"
        }
    }
} else {
    Add-Failure "git is unavailable; cannot verify Runtime/config unchanged"
}

if ($Failures.Count -eq 0) {
    Write-Host "Documentation entry selftest PASS"
    exit 0
}

Write-Host "Documentation entry selftest FAIL: $($Failures.Count) failure(s)"
exit 1



