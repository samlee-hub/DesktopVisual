param(
    [string]$PlanPath = "artifacts\post_v6_physical_cleanup\delete_plan_post_v6.json",
    [string]$InventoryPath = "artifacts\post_v6_physical_cleanup\ignored_artifact_inventory.json"
)

$ErrorActionPreference = "Stop"

function Fail-Unsafe {
    param([string[]]$Messages)
    "BLOCKED_IGNORED_ARTIFACT_CLEANUP_PLAN_UNSAFE"
    $Messages | ForEach-Object { "- $_" }
    exit 2
}

function Fail-Incomplete {
    param([string[]]$Messages)
    "BLOCKED_IGNORED_ARTIFACT_CLEANUP_PLAN_INCOMPLETE"
    $Messages | ForEach-Object { "- $_" }
    exit 3
}

function Sum-Bytes {
    param([object[]]$Items)
    [int64]$sum = 0
    foreach ($item in $Items) {
        if ($null -ne $item -and $null -ne $item.size_bytes) {
            $sum += [int64]$item.size_bytes
        }
    }
    return $sum
}

function Is-ProtectedPath {
    param([string]$Path)
    $p = ($Path -replace "\\", "/")
    $name = [System.IO.Path]::GetFileName($p)

    if ($p -match "^(src|docs)/") { return $true }
    if ($p -in @("AGENTS.md", "VERSION", "CHANGELOG.md", "COMMAND_PROTOCOL.md", "build.ps1")) { return $true }
    if ($name -eq "final_status_report.md") { return $true }
    if ($name -eq "evidence_index.md") { return $true }
    if ($name -match "acceptance_gate_report") { return $true }
    if ($name -match "developer_full_access_policy_report") { return $true }
    if ($p -match "^artifacts/dev6\.12\.0_rc_gate_and_handoff/handoff_package(/|$)") { return $true }
    if ($p -match "^artifacts/dev6\.12\.0_rc_gate_and_handoff/(developer_capability_matrix|release_hardening_deferred_ledger)\.(md|json)$") { return $true }
    return $false
}

if (-not (Test-Path -LiteralPath $PlanPath -PathType Leaf)) {
    Fail-Incomplete @("delete_plan does not exist: $PlanPath")
}

if (-not (Test-Path -LiteralPath $InventoryPath -PathType Leaf)) {
    Fail-Incomplete @("ignored artifact inventory does not exist: $InventoryPath")
}

$plan = Get-Content -Raw -LiteralPath $PlanPath | ConvertFrom-Json
$inventory = Get-Content -Raw -LiteralPath $InventoryPath | ConvertFrom-Json
$entries = @($plan.entries)
$safe = @($entries | Where-Object { $_.safe_to_delete -eq $true })

$unsafe = New-Object System.Collections.Generic.List[string]
$incomplete = New-Object System.Collections.Generic.List[string]

if ($entries.Count -eq 0) {
    $incomplete.Add("delete_plan has zero entries")
}

$protectedSafe = @($safe | Where-Object { Is-ProtectedPath $_.file_path })
foreach ($entry in $protectedSafe) {
    $unsafe.Add("protected path marked safe_to_delete=true: $($entry.file_path)")
}

$unknownSafe = @($safe | Where-Object { $_.category -eq "unknown" })
foreach ($entry in $unknownSafe) {
    $unsafe.Add("unknown category marked safe_to_delete=true: $($entry.file_path)")
}

$allowedDeleteCategories = @(
    "ignored_bmp_screenshot",
    "ignored_ocr_bmp",
    "ignored_scaled_bmp",
    "build_output_bin",
    "build_intermediate_obj",
    "browser_profile_cache",
    "browser_crashpad_cache",
    "temporary_log",
    "temporary_stdout_stderr",
    "temporary_package",
    "ignored_cache"
)

$badCategorySafe = @($safe | Where-Object { $_.category -notin $allowedDeleteCategories })
foreach ($entry in $badCategorySafe) {
    $unsafe.Add("non-cleanup category marked safe_to_delete=true: $($entry.file_path) [$($entry.category)]")
}

$explicitTemporaryCategories = @("temporary_stdout_stderr", "temporary_log", "temporary_package")
$notIgnoredOrTemp = @($safe | Where-Object { ($_.ignored_status -ne $true) -and ($_.category -notin $explicitTemporaryCategories) })
foreach ($entry in $notIgnoredOrTemp) {
    $unsafe.Add("safe_to_delete entry is neither ignored nor explicit temporary generated file: $($entry.file_path) [$($entry.category)]")
}

$sourceDocSafe = @($safe | Where-Object { ($_.file_path -replace "\\", "/") -match "^(src|docs)/" })
foreach ($entry in $sourceDocSafe) {
    $unsafe.Add("source/docs path marked safe_to_delete=true: $($entry.file_path)")
}

$finalStatusSafe = @($safe | Where-Object { [System.IO.Path]::GetFileName($_.file_path) -eq "final_status_report.md" })
if ($finalStatusSafe.Count -gt 0) {
    $unsafe.Add("final_status_report.md appears in delete candidates")
}

$evidenceIndexSafe = @($safe | Where-Object { [System.IO.Path]::GetFileName($_.file_path) -eq "evidence_index.md" })
if ($evidenceIndexSafe.Count -gt 0) {
    $unsafe.Add("evidence_index.md appears in delete candidates")
}

$handoffSafe = @($safe | Where-Object { ($_.file_path -replace "\\", "/") -match "^artifacts/dev6\.12\.0_rc_gate_and_handoff/handoff_package(/|$)" })
if ($handoffSafe.Count -gt 0) {
    $unsafe.Add("handoff_package core file appears in delete candidates")
}

$deferredLedgerSafe = @($safe | Where-Object { ($_.file_path -replace "\\", "/") -match "^artifacts/dev6\.12\.0_rc_gate_and_handoff/release_hardening_deferred_ledger\.(md|json)$" })
if ($deferredLedgerSafe.Count -gt 0) {
    $unsafe.Add("release hardening deferred ledger appears in delete candidates")
}

$developerPolicySafe = @($safe | Where-Object { [System.IO.Path]::GetFileName($_.file_path) -match "developer_full_access_policy_report" })
if ($developerPolicySafe.Count -gt 0) {
    $unsafe.Add("developer full access report appears in delete candidates")
}

$ignoredBmpBytes = [int64]$inventory.bmp_bytes
$ignoredBinBytes = [int64]$inventory.bin_bytes
$ignoredObjBytes = [int64]$inventory.obj_bytes
$ignoredBrowserBytes = [int64]$inventory.browser_profile_cache_bytes
$ignoredTotalBytes = [int64]$inventory.total_ignored_bytes

$safeBmp = @($safe | Where-Object { $_.category -in @("ignored_bmp_screenshot", "ignored_ocr_bmp", "ignored_scaled_bmp") })
$safeBin = @($safe | Where-Object { $_.category -eq "build_output_bin" })
$safeObj = @($safe | Where-Object { $_.category -eq "build_intermediate_obj" })
$safeBrowser = @($safe | Where-Object { $_.category -in @("browser_profile_cache", "browser_crashpad_cache") })

$safeBmpBytes = Sum-Bytes $safeBmp
$safeBinBytes = Sum-Bytes $safeBin
$safeObjBytes = Sum-Bytes $safeObj
$safeBrowserBytes = Sum-Bytes $safeBrowser
$safeTotalBytes = Sum-Bytes $safe

if ($ignoredBmpBytes -gt 0 -and $safeBmp.Count -eq 0) {
    $incomplete.Add("ignored BMP files exist but delete_plan has no safe BMP coverage")
}

if ($ignoredBmpBytes -gt 104857600 -and $safeBmpBytes -le 0) {
    $incomplete.Add("ignored BMP total exceeds 100MB but delete_plan does not cover BMP deletion")
}

if ($ignoredBinBytes -gt 0 -and $safeBin.Count -eq 0) {
    $incomplete.Add("ignored bin/ files exist but delete_plan has no build_output_bin deletion coverage")
}

if ($ignoredObjBytes -gt 0 -and $safeObj.Count -eq 0) {
    $incomplete.Add("ignored obj/ files exist but delete_plan has no build_intermediate_obj deletion coverage")
}

if ($ignoredBrowserBytes -gt 0 -and $safeBrowser.Count -eq 0) {
    $incomplete.Add("ignored browser profile/cache files exist but delete_plan has no browser cache deletion coverage")
}

if ($ignoredTotalBytes -gt 0) {
    $coverage = [double]$safeTotalBytes / [double]$ignoredTotalBytes
    if ($coverage -lt 0.70) {
        $incomplete.Add(("delete_plan safe_to_delete bytes cover only {0:P2} of ignored bytes" -f $coverage))
    }
}

if ($ignoredBmpBytes -gt 0) {
    $bmpCoverage = [double]$safeBmpBytes / [double]$ignoredBmpBytes
    if ($ignoredBmpBytes -gt 104857600 -and $bmpCoverage -lt 0.70) {
        $incomplete.Add(("delete_plan safe BMP bytes cover only {0:P2} of ignored BMP bytes" -f $bmpCoverage))
    }
}

if ($ignoredBinBytes -gt 0) {
    $binCoverage = [double]$safeBinBytes / [double]$ignoredBinBytes
    if ($binCoverage -lt 0.50) {
        $incomplete.Add(("delete_plan safe bin bytes cover only {0:P2} of ignored bin bytes" -f $binCoverage))
    }
}

if ($ignoredBrowserBytes -gt 0) {
    $browserCoverage = [double]$safeBrowserBytes / [double]$ignoredBrowserBytes
    if ($browserCoverage -lt 0.50) {
        $incomplete.Add(("delete_plan safe browser cache bytes cover only {0:P2} of ignored browser cache bytes" -f $browserCoverage))
    }
}

if ($unsafe.Count -gt 0) {
    Fail-Unsafe $unsafe.ToArray()
}

if ($incomplete.Count -gt 0) {
    Fail-Incomplete $incomplete.ToArray()
}

"POST_V6_PHYSICAL_CLEANUP_PLAN_VERIFIER_PASS"
"plan_path=$PlanPath"
"inventory_path=$InventoryPath"
"safe_to_delete_count=$($safe.Count)"
"safe_to_delete_bytes=$safeTotalBytes"
"ignored_total_bytes=$ignoredTotalBytes"
"ignored_bmp_bytes=$ignoredBmpBytes"
"safe_bmp_bytes=$safeBmpBytes"
"safe_bin_bytes=$safeBinBytes"
"safe_obj_bytes=$safeObjBytes"
"safe_browser_cache_bytes=$safeBrowserBytes"
exit 0
