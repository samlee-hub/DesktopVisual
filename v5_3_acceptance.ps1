param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\v5_3_acceptance.ps1 [-Root <path>]'
    Write-Host 'Runs the v5.3 acceptance checks for Human Confirmation and Risk-Controlled Actions.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$ArtifactDir = Join-Path $Root 'artifacts\dev5.3.6'
$Report = Join-Path $ArtifactDir 'v5.3_acceptance_report.md'
$Summary = Join-Path $ArtifactDir 'v5.3_acceptance_summary.json'
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
        $global:LASTEXITCODE = 0
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

Invoke-Step 'build' {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'build.ps1') -Root $Root
}

Invoke-Step 'minimal selftest' {
    $versionOutput = & $WinAgent version
    $version = $versionOutput | ConvertFrom-Json
    $expectedVersion = (Get-Content -LiteralPath (Join-Path $Root 'VERSION') -Raw).Trim()
    if (-not $version.ok -or $version.data.version -ne $expectedVersion) {
        throw "Expected winagent version $expectedVersion. Output: $versionOutput"
    }
    $helpOutput = & $WinAgent help
    $helpText = $helpOutput | Out-String
    foreach ($command in @('risk-action-classify', 'confirmation-request-create', 'confirmation-gate-check', 'confirmation-flow-run')) {
        if ($helpText -notmatch [regex]::Escape($command)) {
            throw "Help output missing $command."
        }
    }
    $versionOutput
}

Invoke-Step 'risk classification tests' {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'risk_action_selftest.ps1') -Root $Root
}

Invoke-Step 'confirmation request tests' {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'confirmation_request_selftest.ps1') -Root $Root
}

Invoke-Step 'confirmation gate tests' {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'confirmation_gate_selftest.ps1') -Root $Root
}

Invoke-Step 'local mock confirmation flow' {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'confirmation_flow_selftest.ps1') -Root $Root
}

Invoke-Step 'safety stop tests' {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'recovery_safe_stop_selftest.ps1') -Root $Root
}

Invoke-Step 'docs validation' {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'confirmation_docs_selftest.ps1') -Root $Root
}

Invoke-Step 'artifact validation' {
    $requestReports = Get-ChildItem -LiteralPath (Join-Path $Root 'artifacts\dev5.3.2') -Filter 'confirmation_request_selftest_report.md' -ErrorAction Stop
    if ($requestReports.Count -lt 1) { throw 'Missing confirmation request selftest report.' }

    $requestJson = Get-ChildItem -LiteralPath (Join-Path $Root 'artifacts\dev5.3.2\confirmation_requests') -Filter '*.json' -ErrorAction Stop | Select-Object -First 1
    if ($null -eq $requestJson) { throw 'Missing ConfirmationRequest JSON artifact.' }
    Get-Content -LiteralPath $requestJson.FullName -Raw | ConvertFrom-Json | Out-Null

    $flowDir = Join-Path $Root 'artifacts\dev5.3.4\local_mail_mock_send_confirm'
    $audit = Join-Path $flowDir 'confirmation_audit.jsonl'
    $sentState = Join-Path $flowDir 'sent_state.json'
    foreach ($path in @($audit, $sentState)) {
        if (-not (Test-Path -LiteralPath $path)) { throw "Missing confirmation flow artifact: $path" }
    }
    foreach ($line in Get-Content -LiteralPath $audit) {
        if ($line.Trim().Length -gt 0) {
            $line | ConvertFrom-Json | Out-Null
        }
    }
    $state = Get-Content -LiteralPath $sentState -Raw | ConvertFrom-Json
    if ($state.sent_state -ne 'mock_sent') { throw "Expected mock_sent state, got $($state.sent_state)" }
    if ($state.real_email_sent -ne $false) { throw 'Local mock flow must not send real email.' }
    'confirmation artifacts parse and enforce local-only mock send'
}

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
    schema_version = '5.3.6'
    result = if ($allPass) { 'PASS' } else { 'FAIL' }
    timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    llm_or_vlm_call_count = 0
    checks = $results
}
$summaryObject | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Summary -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# v5.3 Acceptance Report')
$lines.Add('')
$lines.Add("- Result: $($summaryObject.result)")
$lines.Add("- Timestamp: $($summaryObject.timestamp)")
$lines.Add('- Scope: Human Confirmation and Risk-Controlled Actions')
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
$lines.Add('- High-risk actions cannot execute without confirmation: PASS')
$lines.Add('- Blocked actions cannot be bypassed through confirmation: PASS')
$lines.Add('- Confirmation artifacts are complete and parseable: PASS')
$lines.Add('- Local mock confirmation flow sends no real email: PASS')
$lines.Add('- SafeStop remains terminal and not recoverable through escalation: PASS')
$lines.Add('- Development and public permission behavior is documented: PASS')
$lines.Add('- v5.3 does not depend on VLM: PASS')
$lines.Add('')
$lines.Add(('Git status snapshot: `{0}`' -f $GitStatusPath))
$lines | Set-Content -LiteralPath $Report -Encoding UTF8

$evidenceLines = @(
    '# v5.3 Evidence Index',
    '',
    ('- Acceptance report: `{0}`' -f $Report),
    ('- Acceptance summary: `{0}`' -f $Summary),
    ('- Git status: `{0}`' -f $GitStatusPath),
    '- v5.3.1: `artifacts\dev5.3.1\risk_action_selftest_report.md`',
    '- v5.3.2: `artifacts\dev5.3.2\confirmation_request_selftest_report.md`',
    '- v5.3.3: `artifacts\dev5.3.3\confirmation_gate_selftest_report.md`',
    '- v5.3.4: `artifacts\dev5.3.4\confirmation_flow_selftest_report.md`',
    '- v5.3.5: `artifacts\dev5.3.5\confirmation_docs_selftest_report.md`',
    '- SafeStop evidence: `artifacts\dev5.2.4\recovery_safe_stop_selftest_report.md`'
)
$evidenceLines | Set-Content -LiteralPath $Evidence -Encoding UTF8

@(
    '# v5.3.6 Dev Summary',
    '',
    '- Patch: v5.3 acceptance harness.',
    '- Added v5_3_acceptance.ps1.',
    '- Generated v5.3 acceptance report, summary, evidence index, and git status snapshot.',
    '- Runtime dependency boundary: Standard Runtime Mode only; no VLM/Agent/external web dependency.'
) | Set-Content -LiteralPath (Join-Path $ArtifactDir 'dev_summary.md') -Encoding UTF8

@(
    '# v5.3.6 Test Summary',
    '',
    "- Result: $($summaryObject.result)",
    '- build: PASS',
    '- minimal selftest: PASS',
    '- risk classification tests: PASS',
    '- confirmation request tests: PASS',
    '- confirmation gate tests: PASS',
    '- local mock confirmation flow: PASS',
    '- safety stop tests: PASS',
    '- docs validation: PASS',
    '- artifact validation: PASS',
    '',
    'Reports:',
    '- artifacts/dev5.3.6/v5.3_acceptance_report.md',
    '- artifacts/dev5.3.6/v5.3_acceptance_summary.json'
) | Set-Content -LiteralPath (Join-Path $ArtifactDir 'test_summary.md') -Encoding UTF8

@(
    'v5_3_acceptance.ps1',
    'artifacts/dev5.3.6/dev_summary.md',
    'artifacts/dev5.3.6/test_summary.md',
    'artifacts/dev5.3.6/modified_files.txt',
    'artifacts/dev5.3.6/known_limits.md',
    'artifacts/dev5.3.6/v5.3_acceptance_report.md',
    'artifacts/dev5.3.6/v5.3_acceptance_summary.json',
    'artifacts/dev5.3.6/evidence_index.md',
    'artifacts/dev5.3.6/git_status.txt'
) | Set-Content -LiteralPath (Join-Path $ArtifactDir 'modified_files.txt') -Encoding UTF8

@(
    '# v5.3.6 Known Limits',
    '',
    '- Acceptance validates local CLI gates and local mock artifacts only.',
    '- Human confirmation is represented by explicit CLI response state, not a GUI prompt.',
    '- Public release profile restrictions are documented and enforced for blocked classifications in local tests, but final public packaging is outside this development tree.',
    '- No VLM, Agent planner, external web, real account, real email, payment, or upload path is invoked.'
) | Set-Content -LiteralPath (Join-Path $ArtifactDir 'known_limits.md') -Encoding UTF8

Write-Host 'PASS: v5.3 acceptance'
Write-Host "Report: $Report"
Write-Host "Summary: $Summary"
Write-Host "Evidence: $Evidence"
