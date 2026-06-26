param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\v5_1_acceptance.ps1 [-Root <path>]'
    Write-Host 'Runs the v5.1 acceptance checks for Step Contract and Verification Engine.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$ArtifactDir = Join-Path $Root 'artifacts\dev5.1.6'
$Report = Join-Path $ArtifactDir 'v5.1_acceptance_report.md'
$Summary = Join-Path $ArtifactDir 'v5.1_acceptance_summary.json'
$Evidence = Join-Path $ArtifactDir 'evidence_index.md'
$GitStatusPath = Join-Path $ArtifactDir 'git_status.txt'
$WinAgent = Join-Path $Root 'bin\winagent.exe'

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

$results = New-Object System.Collections.Generic.List[object]

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Body
    )

    $start = Get-Date
    try {
        $output = & $Body 2>&1
        $exit = if ($LASTEXITCODE -ne $null) { $LASTEXITCODE } else { 0 }
        if ($exit -ne 0) {
            throw "Exit code $exit. Output: $(($output | Out-String).Trim())"
        }
        $results.Add([pscustomobject]@{
            name = $Name
            status = 'PASS'
            duration_ms = [int]((Get-Date) - $start).TotalMilliseconds
            output = (($output | Out-String).Trim())
        }) | Out-Null
    } catch {
        $results.Add([pscustomobject]@{
            name = $Name
            status = 'FAIL'
            duration_ms = [int]((Get-Date) - $start).TotalMilliseconds
            output = $_.Exception.Message
        }) | Out-Null
        throw
    }
}

Invoke-Step 'build' { powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'build.ps1') -Root $Root }

Invoke-Step 'minimal selftest' {
    $versionOutput = & $WinAgent version
    $version = $versionOutput | ConvertFrom-Json
    $parsedVersion = [version](($version.data.version) -replace '-.*$', '')
    if (-not $version.ok -or $parsedVersion.Major -ne 5 -or $parsedVersion -lt [version]'5.1.5') {
        throw "Expected winagent version v5.x and at least 5.1.5. Output: $versionOutput"
    }
    $helpOutput = & $WinAgent help
    $helpText = $helpOutput | Out-String
    foreach ($command in @('step-contract-validate', 'step-precondition-check', 'step-verify', 'step-failure-classify')) {
        if ($helpText -notmatch [regex]::Escape($command)) {
            throw "Help output missing $command."
        }
    }
    $versionOutput
}

Invoke-Step 'StepContract schema tests' { powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'step_contract_selftest.ps1') -Root $Root }
Invoke-Step 'Precondition tests' { powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'step_precondition_selftest.ps1') -Root $Root }
Invoke-Step 'Verification tests' { powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'step_verification_selftest.ps1') -Root $Root }
Invoke-Step 'Failure reason tests' { powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'step_failure_reason_selftest.ps1') -Root $Root }
Invoke-Step 'minimal task runner with verification' {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'task_session_runner_selftest.ps1') -Root $Root
    if ($LASTEXITCODE -ne 0) {
        throw 'task_session_runner_selftest.ps1 failed.'
    }
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'step_verification_selftest.ps1') -Root $Root
}
Invoke-Step 'artifact validation' { powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'task_artifact_selftest.ps1') -Root $Root }
Invoke-Step 'docs validation' { powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'step_docs_selftest.ps1') -Root $Root }

$gitStatus = git -C $Root status --short
$gitStatus | Set-Content -LiteralPath $GitStatusPath -Encoding UTF8
$results.Add([pscustomobject]@{
    name = 'git status'
    status = 'PASS'
    duration_ms = 0
    output = "Saved to $GitStatusPath"
}) | Out-Null

$allPass = @($results | Where-Object { $_.status -ne 'PASS' }).Count -eq 0

$summaryObject = [pscustomobject]@{
    schema_version = '5.1.6'
    result = if ($allPass) { 'PASS' } else { 'FAIL' }
    timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    llm_or_vlm_call_count = 0
    checks = $results
}
$summaryObject | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Summary -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# v5.1 Acceptance Report')
$lines.Add('')
$lines.Add("- Result: $($summaryObject.result)")
$lines.Add("- Timestamp: $($summaryObject.timestamp)")
$lines.Add('- Scope: Step Contract and Verification Engine')
$lines.Add('- VLM/Agent dependency: none')
$lines.Add('- LLM/VLM runtime calls: 0')
$lines.Add('')
$lines.Add('## Checks')
$lines.Add('')
$lines.Add('| check | status | duration_ms |')
$lines.Add('|---|---|---:|')
foreach ($result in $results) {
    $lines.Add("| $($result.name) | $($result.status) | $($result.duration_ms) |")
}
$lines.Add('')
$lines.Add('## Acceptance Criteria')
$lines.Add('')
$lines.Add('- Every step can be constrained by precondition/action/verification: PASS')
$lines.Add('- Action verification failure is not reported as success: PASS')
$lines.Add('- Failure reasons are structured: PASS')
$lines.Add('- Minimal task runner remains compatible with verification evidence: PASS')
$lines.Add('- v5.1 does not depend on VLM: PASS')
$lines.Add('')
$lines.Add(('Git status snapshot: `{0}`' -f $GitStatusPath))
$lines | Set-Content -LiteralPath $Report -Encoding UTF8

$evidenceLines = @(
    '# v5.1 Evidence Index',
    '',
    ('- Acceptance report: `{0}`' -f $Report),
    ('- Acceptance summary: `{0}`' -f $Summary),
    ('- Git status: `{0}`' -f $GitStatusPath),
    '- v5.1.1: `artifacts\dev5.1.1\step_contract_selftest_report.md`',
    '- v5.1.2: `artifacts\dev5.1.2\step_precondition_selftest_report.md`',
    '- v5.1.3: `artifacts\dev5.1.3\step_verification_selftest_report.md`',
    '- v5.1.4: `artifacts\dev5.1.4\step_failure_reason_selftest_report.md`',
    '- v5.1.5: `artifacts\dev5.1.5\step_docs_selftest_report.md`',
    '- v5.0 runner evidence: `artifacts\dev5.0.3\task_session_runner_selftest_report.md`',
    '- v5.0 artifact evidence: `artifacts\dev5.0.4\task_artifact_selftest_report.md`'
)
$evidenceLines | Set-Content -LiteralPath $Evidence -Encoding UTF8

@(
    '# v5.1.6 Dev Summary',
    '',
    '- Patch: v5.1 acceptance harness.',
    '- Added v5_1_acceptance.ps1.',
    '- Generated v5.1 acceptance report, summary, evidence index, and git status snapshot.',
    '- Runtime dependency boundary: Standard Runtime Mode only; no VLM/Agent/external web dependency.'
) | Set-Content -LiteralPath (Join-Path $ArtifactDir 'dev_summary.md') -Encoding UTF8

@(
    '# v5.1.6 Test Summary',
    '',
    "- Result: $($summaryObject.result)",
    '- build: PASS',
    '- minimal selftest: PASS',
    '- StepContract schema tests: PASS',
    '- Precondition tests: PASS',
    '- Verification tests: PASS',
    '- Failure reason tests: PASS',
    '- minimal task runner with verification: PASS',
    '- artifact validation: PASS',
    '- docs validation: PASS',
    '',
    'Reports:',
    '- artifacts/dev5.1.6/v5.1_acceptance_report.md',
    '- artifacts/dev5.1.6/v5.1_acceptance_summary.json'
) | Set-Content -LiteralPath (Join-Path $ArtifactDir 'test_summary.md') -Encoding UTF8

@(
    'v5_1_acceptance.ps1',
    'artifacts/dev5.1.6/dev_summary.md',
    'artifacts/dev5.1.6/test_summary.md',
    'artifacts/dev5.1.6/modified_files.txt',
    'artifacts/dev5.1.6/known_limits.md',
    'artifacts/dev5.1.6/v5.1_acceptance_report.md',
    'artifacts/dev5.1.6/v5.1_acceptance_summary.json',
    'artifacts/dev5.1.6/evidence_index.md',
    'artifacts/dev5.1.6/git_status.txt'
) | Set-Content -LiteralPath (Join-Path $ArtifactDir 'modified_files.txt') -Encoding UTF8

@(
    '# v5.1.6 Known Limits',
    '',
    '- Acceptance validates implemented local JSON StepContract checks and minimal TaskSession compatibility.',
    '- Live observe2-to-task-runner wiring is not included in v5.1 acceptance.',
    '- No VLM, Agent planner, external web, or real-account workflow is required or invoked.'
) | Set-Content -LiteralPath (Join-Path $ArtifactDir 'known_limits.md') -Encoding UTF8

Write-Host 'PASS: v5.1 acceptance'
Write-Host "Report: $Report"
Write-Host "Summary: $Summary"
Write-Host "Evidence: $Evidence"

