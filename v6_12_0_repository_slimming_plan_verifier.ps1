param(
    [string]$PlanPath = "artifacts\cleanup\v6.12_final_slimming\delete_plan_v6.12.json"
)

$ErrorActionPreference = "Stop"

function Fail([string]$message) {
    Write-Error $message
    exit 1
}

if (!(Test-Path -LiteralPath $PlanPath)) {
    Fail "BLOCKED_SLIMMING_PLAN_UNSAFE: delete_plan missing: $PlanPath"
}

$plan = Get-Content -LiteralPath $PlanPath -Raw | ConvertFrom-Json
if ($null -eq $plan) {
    Fail "BLOCKED_SLIMMING_PLAN_UNSAFE: delete_plan is empty"
}

$items = @()
if ($plan -is [array]) {
    $items = @($plan)
} elseif ($plan.items) {
    $items = @($plan.items)
} else {
    Fail "BLOCKED_SLIMMING_PLAN_UNSAFE: delete_plan has no items"
}

$requiredFields = @(
    "file_path",
    "tracked_status",
    "size_bytes",
    "category",
    "reason",
    "referenced_by_evidence_index",
    "referenced_by_final_status",
    "safe_to_delete",
    "safe_to_archive",
    "preserve_reason",
    "hash"
)

$allowedDeleteCategories = @(
    "stdout_stderr",
    "temp_json",
    "debug_log",
    "duplicate_runner_output",
    "cache",
    "raw_screenshot",
    "old_export_package"
)

$allowedDeletePatterns = @(
    '^artifacts[/\\].*[/\\]stdout[^/\\]*\.txt$',
    '^artifacts[/\\].*[/\\]stderr[^/\\]*\.txt$',
    '^artifacts[/\\].*[_\.]stdout\.(txt|json)$',
    '^artifacts[/\\].*[_\.]stderr\.txt$',
    '^artifacts[/\\].*[/\\]debug_[^/\\]*\.(log|md)$',
    '^artifacts[/\\].*[/\\]trace_[^/\\]*\.log$',
    '^artifacts[/\\].*[/\\]temp_[^/\\]*\.(log|json)$',
    '^artifacts[/\\].*[/\\]runner_temp_[^/\\]*\.json$',
    '^artifacts[/\\].*[/\\]intermediate_[^/\\]*\.json$',
    '^artifacts[/\\].*[/\\]runner_output_[^/\\]*\.json$',
    '^artifacts[/\\].*[/\\]raw_runner_[^/\\]*\.json$',
    '^artifacts[/\\](cache|tmp|intermediate|dump)([/\\].*)?$',
    '^artifacts[/\\].*_screenshot\.png$',
    '^artifacts[/\\].*scaled\.png$',
    '^artifacts[/\\].*[/\\]debug[^/\\]*\.png$',
    '^artifacts[/\\].*\.(zip|7z|tmp)$'
)

$safeDeleteCount = 0
$safeArchiveCount = 0

foreach ($item in $items) {
    foreach ($field in $requiredFields) {
        if (-not ($item.PSObject.Properties.Name -contains $field)) {
            Fail "BLOCKED_SLIMMING_PLAN_UNSAFE: missing field '$field'"
        }
    }

    $path = [string]$item.file_path
    $normalized = $path -replace '/', '\'
    $normalizedLower = $normalized.ToLowerInvariant()

    if ($normalizedLower -match '^src\\') {
        Fail "BLOCKED_SLIMMING_PLAN_UNSAFE: src entry in delete_plan: $path"
    }
    if ($normalizedLower -match '^docs\\') {
        Fail "BLOCKED_SLIMMING_PLAN_UNSAFE: docs entry in delete_plan: $path"
    }
    if ($normalizedLower -in @("agents.md", "version", "changelog.md", "command_protocol.md", "build.ps1")) {
        Fail "BLOCKED_SLIMMING_PLAN_UNSAFE: protected root entry in delete_plan: $path"
    }
    if ($normalizedLower.EndsWith("final_status_report.md")) {
        Fail "BLOCKED_SLIMMING_PLAN_UNSAFE: final_status_report entry in delete_plan: $path"
    }
    if ($normalizedLower.EndsWith("evidence_index.md")) {
        Fail "BLOCKED_SLIMMING_PLAN_UNSAFE: evidence_index entry in delete_plan: $path"
    }
    if ($normalizedLower -match 'acceptance_gate_report') {
        Fail "BLOCKED_SLIMMING_PLAN_UNSAFE: acceptance gate report entry in delete_plan: $path"
    }
    if ($normalizedLower -match 'handoff_package\\') {
        Fail "BLOCKED_SLIMMING_PLAN_UNSAFE: handoff_package entry in delete_plan: $path"
    }
    if ($normalizedLower -match 'developer_full_access_policy_report') {
        Fail "BLOCKED_SLIMMING_PLAN_UNSAFE: developer full access policy report entry in delete_plan: $path"
    }
    if ($normalizedLower -match 'release_hardening_deferred_ledger') {
        Fail "BLOCKED_SLIMMING_PLAN_UNSAFE: release hardening deferred ledger entry in delete_plan: $path"
    }

    if ([string]$item.category -eq "unknown" -and [bool]$item.safe_to_delete) {
        Fail "BLOCKED_SLIMMING_PLAN_UNSAFE: unknown category marked safe_to_delete: $path"
    }

    if ($normalizedLower -match '^artifacts\\runtime_sessions\\') {
        if ([bool]$item.safe_to_delete) {
            Fail "BLOCKED_SLIMMING_PLAN_UNSAFE: runtime_sessions entry marked safe_to_delete: $path"
        }
        if (-not [bool]$item.safe_to_archive) {
            Fail "BLOCKED_SLIMMING_PLAN_UNSAFE: runtime_sessions entry not marked safe_to_archive: $path"
        }
    }

    if ([bool]$item.safe_to_delete) {
        $safeDeleteCount++
        if ($allowedDeleteCategories -notcontains [string]$item.category) {
            Fail "BLOCKED_SLIMMING_PLAN_UNSAFE: disallowed delete category '$($item.category)' for $path"
        }

        $matchesAllowedPattern = $false
        $slashPath = $path -replace '\\', '/'
        foreach ($pattern in $allowedDeletePatterns) {
            if ($slashPath -match $pattern) {
                $matchesAllowedPattern = $true
                break
            }
        }
        if (-not $matchesAllowedPattern) {
            Fail "BLOCKED_SLIMMING_PLAN_UNSAFE: safe_to_delete path does not match allowed patterns: $path"
        }
    }

    if ([bool]$item.safe_to_archive) {
        $safeArchiveCount++
    }
}

Write-Host "v6_12_0_repository_slimming_plan_verifier PASS"
Write-Host "delete_items=$safeDeleteCount"
Write-Host "archive_items=$safeArchiveCount"
exit 0
