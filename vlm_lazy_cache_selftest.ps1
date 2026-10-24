param()

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root

$ArtifactDir = Join-Path $Root "artifacts\dev1.1.12_launch_contract_vs_startup_convergence"
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

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

function Test-Property {
    param(
        [object]$Object,
        [string]$Name
    )
    return $null -ne $Object.PSObject.Properties[$Name]
}

function Assert-Property {
    param(
        [object]$Object,
        [string]$Name,
        [string]$Context
    )
    if (Test-Property -Object $Object -Name $Name) {
        Add-Pass "$Context has $Name"
    } else {
        Add-Failure "$Context is missing $Name"
    }
}

function Invoke-WinAgentJson {
    param([string[]]$Arguments)
    $exe = Join-Path $Root "bin\winagent.exe"
    if (-not (Test-Path -LiteralPath $exe)) {
        Add-Failure "bin\winagent.exe is missing; run .\build.ps1 first"
        return $null
    }
    $output = & $exe @Arguments 2>&1
    $exit = $LASTEXITCODE
    if ($exit -ne 0) {
        Add-Failure "winagent.exe $($Arguments -join ' ') exited $exit with output: $($output -join [Environment]::NewLine)"
        return $null
    }
    $text = ($output | Select-Object -Last 1)
    if ([string]::IsNullOrWhiteSpace($text)) {
        Add-Failure "winagent.exe $($Arguments -join ' ') produced no JSON output"
        return $null
    }
    try {
        return $text | ConvertFrom-Json
    } catch {
        Add-Failure "winagent.exe $($Arguments -join ' ') produced invalid JSON: $text"
        return $null
    }
}

function New-ProbeImage {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $probePngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAF0lEQVR4nGNk+M/AwMDAxMAABYwMjAAAJHsCAkbG0o8AAAAASUVORK5CYII="
    [System.IO.File]::WriteAllBytes($Path, [Convert]::FromBase64String($probePngBase64))
}

function Assert-VlmLatencyFields {
    param(
        [object]$Object,
        [string]$Context
    )
    $fields = @(
        "vlm_probe_attempted",
        "vlm_probe_ms",
        "vlm_cache_hit",
        "vlm_cache_state",
        "vlm_provider_startup_ms",
        "vlm_exec_ms",
        "vlm_total_ms",
        "vlm_unavailable",
        "vlm_timeout",
        "vlm_required",
        "vlm_assist_allowed",
        "vlm_used_for_action",
        "vlm_degraded_to_runtime_only",
        "vlm_probe_reason",
        "vlm_skip_reason"
    )
    foreach ($field in $fields) {
        Assert-Property -Object $Object -Name $field -Context $Context
    }
}

$version = (Read-Text "VERSION").Trim()
if ($version -eq "1.1.12") {
    Add-Pass "VERSION is 1.1.12"
} else {
    Add-Failure "VERSION is '$version', expected 1.1.12"
}

$manifest = Read-Text "config\safety_manifest.json" | ConvertFrom-Json
if ($manifest.default_permission_mode -eq "DEVELOPER_CAPABILITY_DISCOVERY") {
    Add-Pass "default_permission_mode remains DEVELOPER_CAPABILITY_DISCOVERY"
} else {
    Add-Failure "default_permission_mode is '$($manifest.default_permission_mode)', expected DEVELOPER_CAPABILITY_DISCOVERY"
}

$summaryPath = Join-Path $ArtifactDir "latency_baseline_v1_1_11.json"
if (Test-Path -LiteralPath $summaryPath) {
    Remove-Item -LiteralPath $summaryPath -Force
}

$baseline = Invoke-WinAgentJson @("latency-baseline", "--out", $summaryPath)
if ($null -ne $baseline -and (Test-Path -LiteralPath $summaryPath)) {
    Add-Pass "latency-baseline wrote v1.1.12 artifact"
    $summary = Get-Content -Raw -LiteralPath $summaryPath | ConvertFrom-Json
    if ($summary.version -eq "1.1.12") {
        Add-Pass "latency baseline version is 1.1.12"
    } else {
        Add-Failure "latency baseline version is '$($summary.version)', expected 1.1.12"
    }
    Assert-VlmLatencyFields -Object $summary -Context "latency summary"
    if ($summary.vlm_probe_attempted -eq $false -and $summary.vlm_skip_reason -in @("not_required", "runtime_only_path")) {
        Add-Pass "aggregate latency baseline skips VLM probe explicitly"
    } else {
        Add-Failure "aggregate latency baseline does not explicitly skip VLM probe"
    }
    foreach ($scenario in $summary.scenarios) {
        Assert-VlmLatencyFields -Object $scenario -Context "latency scenario $($scenario.scenario)"
        if ($scenario.scenario -in @("metadata_no_action", "runtime_foreground_snapshot", "vlm_not_required")) {
            if ($scenario.vlm_probe_attempted -eq $false -and -not [string]::IsNullOrWhiteSpace([string]$scenario.vlm_skip_reason)) {
                Add-Pass "scenario $($scenario.scenario) has explicit no-probe skip reason"
            } else {
                Add-Failure "scenario $($scenario.scenario) lacks explicit no-probe skip reason"
            }
        }
    }
} else {
    Add-Failure "latency-baseline did not write $summaryPath"
}

$probeImage = Join-Path $ArtifactDir "vlm_lazy_cache_probe.png"
New-ProbeImage -Path $probeImage

$session = "vlm-lazy-cache-selftest-" + ([DateTime]::UtcNow.ToString("yyyyMMddHHmmssfff"))
$firstUnavailable = Invoke-WinAgentJson @(
    "vlm-capability-probe",
    "--provider", "codex-cli",
    "--session-id", $session,
    "--probe-image", $probeImage,
    "--cache", "true",
    "--ttl-seconds", "3600",
    "--negative-ttl-seconds", "300",
    "--simulation", "unavailable"
)

if ($null -ne $firstUnavailable) {
    $firstUnavailable | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $ArtifactDir "vlm_unavailable_report.json") -Encoding UTF8
    foreach ($field in @("vlm_probe_attempted", "vlm_probe_ms", "vlm_cache_hit", "vlm_cache_state", "vlm_unavailable", "vlm_timeout", "vlm_required", "vlm_degraded_to_runtime_only", "vlm_probe_reason", "vlm_skip_reason", "probe_timeout_ms", "positive_ttl_seconds", "negative_ttl_seconds")) {
        Assert-Property -Object $firstUnavailable -Name $field -Context "first unavailable capability probe"
    }
    if ($firstUnavailable.capability_status -eq "VLM_UNAVAILABLE" -and $firstUnavailable.vlm_unavailable -eq $true) {
        Add-Pass "provider unavailable returns VLM_UNAVAILABLE"
    } else {
        Add-Failure "provider unavailable status mismatch: capability_status=$($firstUnavailable.capability_status) vlm_unavailable=$($firstUnavailable.vlm_unavailable)"
    }
    if ([int]$firstUnavailable.probe_timeout_ms -gt 0 -and [int]$firstUnavailable.probe_timeout_ms -lt 60000) {
        Add-Pass "default capability probe timeout is below 60000ms"
    } else {
        Add-Failure "default capability probe timeout is not below 60000ms: $($firstUnavailable.probe_timeout_ms)"
    }
    if ($firstUnavailable.vlm_cache_hit -eq $false -and $firstUnavailable.vlm_cache_state -match "negative_miss") {
        Add-Pass "first unavailable probe records negative cache miss"
    } else {
        Add-Failure "first unavailable probe does not record negative cache miss"
    }
}

$secondUnavailable = Invoke-WinAgentJson @(
    "vlm-capability-probe",
    "--provider", "codex-cli",
    "--session-id", $session,
    "--probe-image", $probeImage,
    "--cache", "true",
    "--ttl-seconds", "3600",
    "--negative-ttl-seconds", "300",
    "--simulation", "unavailable"
)

if ($null -ne $firstUnavailable -and $null -ne $secondUnavailable) {
    $secondUnavailable | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $ArtifactDir "vlm_cache_report.json") -Encoding UTF8
    if ($secondUnavailable.vlm_cache_hit -eq $true -and $secondUnavailable.vlm_probe_attempted -eq $false -and $secondUnavailable.vlm_cache_state -match "negative_hit") {
        Add-Pass "negative cache hit suppresses repeated provider probe"
    } else {
        Add-Failure "negative cache hit did not suppress provider probe"
    }
    if ($secondUnavailable.raw_probe_output_path -eq $firstUnavailable.raw_probe_output_path) {
        Add-Pass "negative cache hit reuses first raw probe evidence path"
    } else {
        Add-Failure "negative cache hit did not reuse first raw probe evidence path"
    }
}

$positiveSession = $session + "-positive"
$firstAvailable = Invoke-WinAgentJson @(
    "vlm-capability-probe",
    "--provider", "codex-cli",
    "--session-id", $positiveSession,
    "--probe-image", $probeImage,
    "--cache", "true",
    "--ttl-seconds", "3600",
    "--negative-ttl-seconds", "300",
    "--simulation", "valid"
)

$secondAvailable = Invoke-WinAgentJson @(
    "vlm-capability-probe",
    "--provider", "codex-cli",
    "--session-id", $positiveSession,
    "--probe-image", $probeImage,
    "--cache", "true",
    "--ttl-seconds", "3600",
    "--negative-ttl-seconds", "300",
    "--simulation", "valid"
)

if ($null -ne $firstAvailable -and $null -ne $secondAvailable) {
    if ($firstAvailable.capability_status -eq "VLM_AVAILABLE" -and $firstAvailable.vlm_cache_hit -eq $false -and $firstAvailable.vlm_cache_state -match "positive_miss") {
        Add-Pass "first available probe records positive cache miss"
    } else {
        Add-Failure "first available probe does not record positive cache miss"
    }
    if ($secondAvailable.capability_status -eq "VLM_AVAILABLE" -and $secondAvailable.vlm_cache_hit -eq $true -and $secondAvailable.vlm_probe_attempted -eq $false -and $secondAvailable.vlm_cache_state -match "positive_hit") {
        Add-Pass "positive cache hit suppresses repeated provider probe"
    } else {
        Add-Failure "positive cache hit did not suppress provider probe"
    }
}

$assistUnavailable = Invoke-WinAgentJson @(
    "vlm-assist-locate",
    "--provider", "codex-cli",
    "--session-id", ($session + "-assist"),
    "--image", $probeImage,
    "--target", "sample button",
    "--target-window-title", "vlm-lazy-cache-selftest",
    "--cache", "true",
    "--capability-simulation", "unavailable"
)

if ($null -ne $assistUnavailable) {
    foreach ($field in @("vlm_required", "vlm_assist_allowed", "vlm_probe_attempted", "vlm_cache_hit", "vlm_cache_state", "vlm_unavailable", "vlm_degraded_to_runtime_only", "vlm_probe_reason", "vlm_skip_reason", "probe_timeout_ms")) {
        Assert-Property -Object $assistUnavailable -Name $field -Context "assist unavailable report"
    }
    if ($assistUnavailable.capability_status -eq "VLM_UNAVAILABLE" -and $assistUnavailable.vlm_degraded_to_runtime_only -eq $true -and $assistUnavailable.runtime_action_executed -eq $false) {
        Add-Pass "VLM assist unavailable degrades to runtime-only without action"
    } else {
        Add-Failure "VLM assist unavailable did not report runtime-only degradation"
    }
}

$bridgeText = Read-Text "src\winagent\RealVlmRuntimeBridge.cpp"
if ($bridgeText -match "60000\s*;\s*//\s*probe" -or $bridgeText -match "CapabilityProbeArgs\s*\{[\s\S]{0,200}60000") {
    Add-Failure "Capability probe default still appears to be 60000ms"
} else {
    Add-Pass "Capability probe default is not hard-coded to 60000ms"
}

$providerText = Read-Text "tools\codex_vlm_provider.ps1"
if ($providerText -match '\[int\]\$TimeoutMs\s*=\s*60000') {
    Add-Failure "PowerShell provider wrapper default TimeoutMs is still 60000 for all modes"
} else {
    Add-Pass "PowerShell provider wrapper no longer defaults every mode to 60000ms"
}

$gitAvailable = $false
try {
    & git rev-parse --is-inside-work-tree *> $null
    $gitAvailable = ($LASTEXITCODE -eq 0)
} catch {
    $gitAvailable = $false
}

if ($gitAvailable) {
    $protected = @("config/safety_manifest.json", "config/safety.conf")
    $changedProtected = @(& git diff --name-only -- $protected)
    if ($changedProtected.Count -eq 0) {
        Add-Pass "safety manifest and safety.conf are unmodified"
    } else {
        foreach ($path in $changedProtected) {
            Add-Failure "protected config modified: $path"
        }
    }

    $releasePaths = @(& git status --short -- "desktop_release" "desktopvisual-public-dist" "public-dist" "public_dist" 2>$null)
    if ($releasePaths.Count -eq 0) {
        Add-Pass "no desktop_release or public-dist paths changed inside developer tree"
    } else {
        foreach ($path in $releasePaths) {
            Add-Failure "unexpected release/public-dist path changed: $path"
        }
    }

    $vlmBridgeText = Read-Text "src\winagent\RealVlmRuntimeBridge.cpp"
    $vlmWrapperText = Read-Text "tools\codex_vlm_provider.ps1"
    if ($vlmBridgeText -notmatch "\bSleep\s*\(" -and $vlmBridgeText -notmatch "sleep_for" -and $vlmWrapperText -notmatch "Start-Sleep") {
        Add-Pass "VLM lazy/cache changes did not replace Sleep wait strategy"
    } else {
        Add-Failure "VLM lazy/cache files contain Sleep wait strategy changes"
    }
} else {
    Add-Failure "git is unavailable; cannot verify protected boundaries"
}

if ($Failures.Count -eq 0) {
    Write-Host "VLM lazy/cache selftest PASS"
    exit 0
}

Write-Host "VLM lazy/cache selftest FAIL: $($Failures.Count) failure(s)"
exit 1




