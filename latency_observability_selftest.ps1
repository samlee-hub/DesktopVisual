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

$version = (Read-Text "VERSION").Trim()
if ($version -eq "1.1.12") {
    Add-Pass "VERSION is 1.1.12"
} else {
    Add-Failure "VERSION is '$version', expected 1.1.12"
}

$latencyDocPath = Join-Path $Root "docs\LATENCY_OBSERVABILITY.md"
if (Test-Path -LiteralPath $latencyDocPath) {
    $latencyDoc = Read-Text "docs\LATENCY_OBSERVABILITY.md"
    Add-Pass "docs\LATENCY_OBSERVABILITY.md exists"
    if ($latencyDoc -match "first_action_latency_ms" -and
        $latencyDoc -match "Runtime receives" -and
        $latencyDoc -match "first real externally visible action") {
        Add-Pass "Latency doc defines first_action_latency_ms"
    } else {
        Add-Failure "Latency doc does not define first_action_latency_ms"
    }
    if ($latencyDoc -match "vlm_cache_state" -and
        $latencyDoc -match "vlm_skip_reason" -and
        $latencyDoc -match "vlm_degraded_to_runtime_only" -and
        $latencyDoc -match "state_wait_total_ms" -and
        $latencyDoc -match "wait_not_replaced_count" -and
        $latencyDoc -match "workflow_wait_total_ms" -and
        $latencyDoc -match "browser_wait_saved_ms") {
        Add-Pass "Latency doc states VLM lazy/cache fields and wait-state fields"
    } else {
        Add-Failure "Latency doc does not state VLM lazy/cache fields and wait-state fields"
    }
} else {
    Add-Failure "docs\LATENCY_OBSERVABILITY.md is missing"
}

$manifest = Read-Text "config\safety_manifest.json" | ConvertFrom-Json
if ($manifest.default_permission_mode -eq "DEVELOPER_CAPABILITY_DISCOVERY") {
    Add-Pass "default_permission_mode remains DEVELOPER_CAPABILITY_DISCOVERY"
} else {
    Add-Failure "default_permission_mode is '$($manifest.default_permission_mode)', expected DEVELOPER_CAPABILITY_DISCOVERY"
}

$artifactDir = Join-Path $Root "artifacts\dev1.1.12_launch_contract_vs_startup_convergence"
New-Item -ItemType Directory -Force -Path $artifactDir | Out-Null
$summaryPath = Join-Path $artifactDir "latency_observability_selftest_summary.json"
if (Test-Path -LiteralPath $summaryPath) {
    Remove-Item -LiteralPath $summaryPath -Force
}

$exe = Join-Path $Root "bin\winagent.exe"
if (Test-Path -LiteralPath $exe) {
    $output = & $exe latency-baseline --out $summaryPath 2>&1
    $exit = $LASTEXITCODE
    if ($exit -eq 0) {
        Add-Pass "winagent.exe latency-baseline exits 0"
    } else {
        Add-Failure "winagent.exe latency-baseline exited $exit with output: $output"
    }
} else {
    Add-Failure "bin\winagent.exe is missing; run .\build.ps1 before latency observability selftest"
}

if (Test-Path -LiteralPath $summaryPath) {
    Add-Pass "Latency summary artifact exists"
    $summary = Get-Content -Raw -LiteralPath $summaryPath | ConvertFrom-Json

    $requiredTopLevel = @(
        "version",
        "generated_at",
        "command",
        "schema",
        "scenarios",
        "task_received_ts",
        "runtime_start_ts",
        "permission_check_start_ts",
        "permission_check_end_ts",
        "policy_check_start_ts",
        "policy_check_end_ts",
        "foreground_prepare_start_ts",
        "foreground_prepare_end_ts",
        "first_observe_start_ts",
        "first_observe_end_ts",
        "first_action_start_ts",
        "first_action_end_ts",
        "task_end_ts",
        "total_task_latency_ms",
        "first_action_latency_ms",
        "permission_check_ms",
        "policy_check_ms",
        "foreground_prepare_ms",
        "first_observe_ms",
        "first_action_ms",
        "screenshot_ms",
        "uia_ms",
        "ocr_ms",
        "frame_registry_write_ms",
        "evidence_write_ms",
        "observe_total_ms",
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
        "vlm_skip_reason",
        "recovery_attempted",
        "recovery_wait_ms",
        "fixed_sleep_wait_ms",
        "state_wait_total_ms",
        "state_wait_saved_ms",
        "wait_reason",
        "wait_site",
        "wait_budget_ms",
        "wait_actual_ms",
        "wait_exit_reason",
        "wait_replaced_from_sleep_ms",
        "wait_state_ready",
        "wait_timeout_count",
        "wait_not_replaced_count",
        "wait_not_replaced_reasons",
        "workflow_wait_total_ms",
        "workflow_wait_saved_ms",
        "workflow_wait_timeout_count",
        "workflow_wait_not_replaced_count",
        "workflow_wait_sites",
        "workflow_wait_replaced_from_sleep_ms",
        "workflow_wait_exit_reasons",
        "explorer_wait_total_ms",
        "explorer_wait_saved_ms",
        "browser_wait_total_ms",
        "browser_wait_saved_ms",
        "code_workflow_wait_total_ms",
        "code_workflow_wait_saved_ms",
        "codex_thinking_gap_ms",
        "external_agent_planning_ms",
        "skill_context_load_ms",
        "winagent_process_start_ms",
        "powershell_startup_ms",
        "runner_startup_ms",
        "first_action_reason",
        "unavailable_fields",
        "notes"
    )

    foreach ($field in $requiredTopLevel) {
        Assert-Property -Object $summary -Name $field -Context "latency summary"
    }

    if ($summary.version -eq "1.1.12") {
        Add-Pass "Latency summary version is 1.1.12"
    } else {
        Add-Failure "Latency summary version is '$($summary.version)', expected 1.1.12"
    }

    if ($summary.unavailable_fields.Count -gt 0) {
        Add-Pass "Latency summary records unavailable_fields"
    } else {
        Add-Failure "Latency summary does not record unavailable_fields"
    }

    $unavailableMustBeNull = @(
        "screenshot_ms",
        "uia_ms",
        "ocr_ms",
        "codex_thinking_gap_ms",
        "external_agent_planning_ms",
        "skill_context_load_ms",
        "winagent_process_start_ms",
        "powershell_startup_ms",
        "runner_startup_ms"
    )
    foreach ($field in $unavailableMustBeNull) {
        if (($summary.unavailable_fields -contains $field) -and $null -ne $summary.$field) {
            Add-Failure "$field is marked unavailable but is not null"
        }
    }

    $noActionScenario = @($summary.scenarios | Where-Object {
        $_.first_action_reason -in @("no_action_task", "blocked_before_action", "stopped_before_action", "failed_before_action")
    }) | Select-Object -First 1
    if ($null -ne $noActionScenario -and $null -eq $noActionScenario.first_action_latency_ms) {
        Add-Pass "No-action or blocked-before-action scenario reports null first_action_latency_ms"
    } else {
        Add-Failure "No-action or blocked-before-action scenario with null first_action_latency_ms was not found"
    }

    $runtimeScenario = @($summary.scenarios | Where-Object { $_.scenario -eq "runtime_foreground_snapshot" }) | Select-Object -First 1
    if ($null -ne $runtimeScenario -and $null -ne $runtimeScenario.total_task_latency_ms -and $null -ne $runtimeScenario.observe_total_ms) {
        Add-Pass "Runtime-only foreground snapshot scenario has nonempty latency summary"
    } else {
        Add-Failure "Runtime-only foreground snapshot scenario is missing total/observe latency"
    }

    $vlmScenario = @($summary.scenarios | Where-Object { $_.scenario -eq "vlm_not_required" }) | Select-Object -First 1
    if ($null -ne $vlmScenario -and
        $vlmScenario.vlm_required -eq $false -and
        $vlmScenario.vlm_assist_allowed -eq $false -and
        $vlmScenario.vlm_probe_attempted -eq $false -and
        $vlmScenario.vlm_skip_reason -eq "not_required") {
        Add-Pass "VLM-not-required scenario reports explicit lazy no-probe skip reason"
    } else {
        Add-Failure "VLM-not-required scenario is missing or does not report explicit lazy no-probe skip reason"
    }

    $coreWaitScenario = @($summary.scenarios | Where-Object { $_.scenario -eq "core_state_wait_probe" }) | Select-Object -First 1
    if ($null -ne $coreWaitScenario -and
        $coreWaitScenario.wait_site -eq "OperationTimelineProfiler.core_state_wait_probe" -and
        $coreWaitScenario.wait_exit_reason -eq "state_ready" -and
        $coreWaitScenario.wait_state_ready -eq $true -and
        $coreWaitScenario.wait_replaced_from_sleep_ms -eq 500 -and
        $null -ne $coreWaitScenario.state_wait_total_ms -and
        $null -ne $coreWaitScenario.state_wait_saved_ms) {
        Add-Pass "Core state wait probe scenario reports Runtime wait-state fields"
    } else {
        Add-Failure "Core state wait probe scenario is missing or does not report Runtime wait-state fields"
    }

    if ($summary.wait_timeout_count -ne $null -and $summary.wait_not_replaced_count -ne $null) {
        Add-Pass "Aggregate latency summary reports wait timeout and not-replaced counts"
    } else {
        Add-Failure "Aggregate latency summary is missing wait timeout or not-replaced counts"
    }

    $workflowWaitScenario = @($summary.scenarios | Where-Object { $_.scenario -eq "workflow_state_wait_probe" }) | Select-Object -First 1
    if ($null -ne $workflowWaitScenario -and
        $null -ne $workflowWaitScenario.workflow_wait_total_ms -and
        $null -ne $workflowWaitScenario.workflow_wait_saved_ms -and
        $workflowWaitScenario.workflow_wait_exit_reasons -contains "state_ready" -and
        $workflowWaitScenario.explorer_wait_saved_ms -ne $null -and
        $workflowWaitScenario.browser_wait_saved_ms -ne $null) {
        Add-Pass "Workflow state wait probe scenario reports Runtime workflow wait-state fields"
    } else {
        Add-Failure "Workflow state wait probe scenario is missing or does not report Runtime workflow wait-state fields"
    }

    if ($summary.workflow_wait_total_ms -ne $null -and
        $summary.workflow_wait_saved_ms -ne $null -and
        $summary.workflow_wait_timeout_count -ne $null -and
        $summary.workflow_wait_not_replaced_count -ne $null) {
        Add-Pass "Aggregate latency summary reports workflow wait totals"
    } else {
        Add-Failure "Aggregate latency summary is missing workflow wait totals"
    }
} else {
    Add-Failure "Latency summary artifact was not written"
}

$regressionScripts = @(
    "current_contract_selftest.ps1",
    "documentation_entry_selftest.ps1",
    "release_channel_semantics_selftest.ps1"
)

foreach ($script in $regressionScripts) {
    $scriptPath = Join-Path $Root $script
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        Add-Failure "$script is missing"
        continue
    }
    & $scriptPath *> $null
    if ($LASTEXITCODE -eq 0) {
        Add-Pass "$script PASS"
    } else {
        Add-Failure "$script FAIL"
    }
}

if ($Failures.Count -eq 0) {
    Write-Host "Latency observability selftest PASS"
    exit 0
}

Write-Host "Latency observability selftest FAIL: $($Failures.Count) failure(s)"
exit 1




