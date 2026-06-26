param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.2.0_persistent_runtime_session_latency_gate'
$LogRoot = Join-Path $ArtifactRoot 'full_regression_logs'
$FullResultPath = Join-Path $ArtifactRoot 'full_regression_result.json'
$FullReportPath = Join-Path $ArtifactRoot 'full_regression_result.md'
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

function Stop-UiResidue {
    Get-Process TestWindow -ErrorAction SilentlyContinue | ForEach-Object {
        $_.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 200
        if (!$_.HasExited) {
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
    }
    Get-CimInstance Win32_Process -Filter "name = 'msedge.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -like '*dev6.2.0_persistent_runtime_session_latency_gate*' -or
            $_.CommandLine -like '*desktopvisual_mail_mock.html*' -or
            $_.CommandLine -like '*desktopvisual_long_scroll_test.html*' -or
            $_.CommandLine -like '*desktopvisual_wrong_page_mock.html*'
        } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
}

function Invoke-MatrixScript {
    param(
        [string]$Name,
        [int]$TimeoutMs = 300000
    )

    $scriptPath = Join-Path $Root $Name
    $stdoutPath = Join-Path $LogRoot ($Name + '.stdout.txt')
    $stderrPath = Join-Path $LogRoot ($Name + '.stderr.txt')

    if (-not (Test-Path -LiteralPath $scriptPath)) {
        "MISSING: $Name" | Set-Content -LiteralPath $stdoutPath -Encoding UTF8
        '' | Set-Content -LiteralPath $stderrPath -Encoding UTF8
        return [pscustomobject]([ordered]@{
            name = $Name
            path = $scriptPath
            exit_code = $null
            status = 'MISSING'
            duration_ms = 0
            timed_out = $false
            stdout = $stdoutPath
            stderr = $stderrPath
        })
    }

    Stop-UiResidue
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $scriptPath + '"'
    $psi.WorkingDirectory = $Root
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    [void]$proc.Start()

    $timedOut = $false
    if (-not $proc.WaitForExit($TimeoutMs)) {
        $timedOut = $true
        try { $proc.Kill() } catch {}
        try { $proc.WaitForExit(5000) | Out-Null } catch {}
    }
    $sw.Stop()

    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    if ($timedOut) {
        $stderr = @($stderr, "TIMEOUT after ${TimeoutMs}ms") -join [Environment]::NewLine
    }
    $stdout | Set-Content -LiteralPath $stdoutPath -Encoding UTF8
    $stderr | Set-Content -LiteralPath $stderrPath -Encoding UTF8

    $exitCode = if ($timedOut) { -999 } else { $proc.ExitCode }
    $status = if ($timedOut) { 'TIMEOUT' } elseif ($exitCode -eq 0) { 'PASS' } else { 'FAIL' }
    return [pscustomobject]([ordered]@{
        name = $Name
        path = $scriptPath
        exit_code = $exitCode
        status = $status
        duration_ms = [int]$sw.ElapsedMilliseconds
        timed_out = [bool]$timedOut
        stdout = $stdoutPath
        stderr = $stderrPath
    })
}

function Get-VerifierStatus {
    $path = Join-Path $ArtifactRoot 'v6_2_0_verifier_report.json'
    if (-not (Test-Path -LiteralPath $path)) { return 'MISSING' }
    try {
        return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).status
    } catch {
        return 'INVALID'
    }
}

function Get-RawRunnerStatus {
    $path = Join-Path $ArtifactRoot 'v6_2_0_runner_raw_result.json'
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    try {
        return [bool](Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).raw_completed_unverified
    } catch {
        return $false
    }
}

function Write-FullRegressionResult {
    param(
        [object[]]$Commands,
        [string[]]$Required,
        [string[]]$Optional,
        [object]$RcCheck,
        [object]$AcceptanceGate,
        [string]$Status,
        [bool]$RequiredPass,
        [bool]$AcceptanceGatePass
    )

    $verifierStatus = Get-VerifierStatus
    $rawRunner = Get-RawRunnerStatus
    $result = [ordered]@{
        schema_version = 'v6.2.0.full_regression'
        generated_at = (Get-Date).ToString('o')
        branch = (& git -C $Root branch --show-current).Trim()
        status = $Status
        required_pass = [bool]$RequiredPass
        acceptance_gate_pass = [bool]$AcceptanceGatePass
        verifier_status = $verifierStatus
        runner_raw_completed_unverified = [bool]$rawRunner
        no_raw_completed_unverified_as_pass = [bool]($rawRunner -and $verifierStatus -eq 'PASS')
        rc_check_status = if ($RcCheck) { $RcCheck.status } else { 'NOT_RUN' }
        rc_check_exit_code = if ($RcCheck) { $RcCheck.exit_code } else { $null }
        required_commands = $Required
        optional_commands = $Optional
        commands = $Commands
    }
    $result | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $FullResultPath -Encoding UTF8

    $requiredLines = @($Commands | Where-Object { $Required -contains $_.name } | ForEach-Object {
        "- $($_.name): $($_.status) (exit $($_.exit_code), $($_.duration_ms) ms)"
    })
    $optionalLines = @($Commands | Where-Object { $Optional -contains $_.name } | ForEach-Object {
        "- $($_.name): $($_.status) (exit $($_.exit_code), $($_.duration_ms) ms)"
    })
    $acceptanceLine = if ($AcceptanceGate) {
        "- v6_2_0_persistent_runtime_acceptance_gate.ps1: $($AcceptanceGate.status) (exit $($AcceptanceGate.exit_code), $($AcceptanceGate.duration_ms) ms)"
    } else {
        '- v6_2_0_persistent_runtime_acceptance_gate.ps1: NOT_RUN'
    }
    $rcLine = if ($RcCheck) {
        "- rc_check.ps1: $($RcCheck.status) (exit $($RcCheck.exit_code), $($RcCheck.duration_ms) ms)"
    } else {
        '- rc_check.ps1: NOT_RUN'
    }

    @(
        '# v6.2.0 Full Regression Result',
        '',
        "- Status: $Status",
        "- Required pass: $RequiredPass",
        "- Acceptance gate pass: $AcceptanceGatePass",
        "- Verifier status: $verifierStatus",
        "- rc_check: $($result.rc_check_status)",
        '',
        '## Required',
        $requiredLines,
        '',
        '## Acceptance Gate',
        $acceptanceLine,
        '',
        '## Optional',
        $optionalLines,
        '',
        '## rc_check',
        $rcLine
    ) | Set-Content -LiteralPath $FullReportPath -Encoding UTF8
}

$required = @(
    'build.ps1',
    'selftest.ps1',
    'runtime_context_guard_selftest.ps1',
    'browser_surface_normalization_selftest.ps1',
    'runtime_session_selftest.ps1',
    'runtime_session_cache_selftest.ps1',
    'runtime_session_latency_benchmark.ps1',
    'v6_1_2_pre_v6_2_acceptance_gate.ps1',
    'v6_1_3_scroll_acceptance_gate.ps1',
    'v6_1_4_runtime_guard_acceptance_gate.ps1',
    'v6_1_5_safe_context_recovery_acceptance_gate.ps1',
    'v6_1_5a_mouse_first_interaction_acceptance_gate.ps1',
    'v6_1_6_scope_reset_step_completion_acceptance_gate.ps1',
    'v6_2_0_persistent_runtime_runner.ps1',
    'v6_2_0_persistent_runtime_verifier.ps1'
)
$optional = @(
    'adapter_selftest.ps1',
    'app_profile_selftest.ps1',
    'case_v2_selftest.ps1',
    'selector_selftest.ps1',
    'serve_selftest.ps1'
)

Set-Location $Root
$commands = @()
foreach ($name in $required) {
    Write-Host "RUN $name"
    $commands += Invoke-MatrixScript -Name $name -TimeoutMs 420000
}
foreach ($name in $optional) {
    if (Test-Path -LiteralPath (Join-Path $Root $name)) {
        Write-Host "RUN optional $name"
        $commands += Invoke-MatrixScript -Name $name -TimeoutMs 300000
    }
}

$rcEntry = $null
if (Test-Path -LiteralPath (Join-Path $Root 'rc_check.ps1')) {
    Write-Host 'RUN rc_check.ps1'
    $rcEntry = Invoke-MatrixScript -Name 'rc_check.ps1' -TimeoutMs 300000
    $commands += $rcEntry
}

$requiredPass = @($commands | Where-Object { $required -contains $_.name -and $_.status -ne 'PASS' }).Count -eq 0
$preliminaryStatus = if ($requiredPass -and (Get-VerifierStatus) -eq 'PASS') { 'PASS' } else { 'BLOCKED' }
Write-FullRegressionResult -Commands $commands -Required $required -Optional $optional -RcCheck $rcEntry -AcceptanceGate $null -Status $preliminaryStatus -RequiredPass $requiredPass -AcceptanceGatePass $false

Write-Host 'RUN v6_2_0_persistent_runtime_acceptance_gate.ps1'
$gateEntry = Invoke-MatrixScript -Name 'v6_2_0_persistent_runtime_acceptance_gate.ps1' -TimeoutMs 300000
$commands += $gateEntry
$gatePass = $gateEntry.status -eq 'PASS'
$finalStatus = if ($requiredPass -and $gatePass) { 'PASS' } else { 'BLOCKED' }
Write-FullRegressionResult -Commands $commands -Required $required -Optional $optional -RcCheck $rcEntry -AcceptanceGate $gateEntry -Status $finalStatus -RequiredPass $requiredPass -AcceptanceGatePass $gatePass

Write-Host "FULL_REGRESSION_$finalStatus"
if ($finalStatus -ne 'PASS') {
    exit 1
}
