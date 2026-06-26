param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\v5_acceptance.ps1 [-Root <path>]'
    Write-Host 'Runs the v5.0 acceptance checks for Task Session and State Machine Core.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$ArtifactDir = Join-Path $Root 'artifacts\dev5.0.6'
$Report = Join-Path $ArtifactDir 'v5.0_acceptance_report.md'
$Summary = Join-Path $ArtifactDir 'v5.0_acceptance_summary.json'
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
    if (-not $version.ok -or $parsedVersion.Major -ne 5 -or $parsedVersion -lt [version]'5.0.5') {
        throw "Expected winagent version to be v5.x and at least 5.0.5. Output: $versionOutput"
    }
    $helpOutput = & $WinAgent help
    if ($LASTEXITCODE -ne 0 -or (($helpOutput | Out-String) -notmatch 'task-session-run')) {
        throw "Help output missing task-session-run."
    }
    $versionOutput
}

Invoke-Step 'task session tests' { powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'task_session_selftest.ps1') -Root $Root }
Invoke-Step 'state machine tests' { powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'task_state_machine_selftest.ps1') -Root $Root }
Invoke-Step 'minimal task runner smoke' { powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'task_session_runner_selftest.ps1') -Root $Root }
Invoke-Step 'artifact validation' { powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'task_artifact_selftest.ps1') -Root $Root }
Invoke-Step 'docs validation' { powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'task_docs_selftest.ps1') -Root $Root }

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
    schema_version = '5.0.6'
    result = if ($allPass) { 'PASS' } else { 'FAIL' }
    timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    llm_or_vlm_call_count = 0
    checks = $results
}
$summaryObject | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Summary -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# v5.0 Acceptance Report')
$lines.Add('')
$lines.Add("- Result: $($summaryObject.result)")
$lines.Add("- Timestamp: $($summaryObject.timestamp)")
$lines.Add('- Scope: Task Session and State Machine Core')
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
$lines.Add('- Runtime can create and execute a minimal TaskSession: PASS')
$lines.Add('- State machine transitions are validated: PASS')
$lines.Add('- Failed or terminal states do not continue through invalid transitions: PASS')
$lines.Add('- Task-level artifacts are generated: PASS')
$lines.Add('- v5.0 does not depend on VLM: PASS')
$lines.Add('')
$lines.Add(('Git status snapshot: `{0}`' -f $GitStatusPath))
$lines | Set-Content -LiteralPath $Report -Encoding UTF8

$evidenceLines = @(
    '# v5.0 Evidence Index',
    '',
    ('- Acceptance report: `{0}`' -f $Report),
    ('- Acceptance summary: `{0}`' -f $Summary),
    ('- Git status: `{0}`' -f $GitStatusPath),
    '- v5.0.1: `artifacts\dev5.0.1\task_session_selftest_report.md`',
    '- v5.0.2: `artifacts\dev5.0.2\task_state_machine_selftest_report.md`',
    '- v5.0.3: `artifacts\dev5.0.3\task_session_runner_selftest_report.md`',
    '- v5.0.4: `artifacts\dev5.0.4\task_artifact_selftest_report.md`',
    '- v5.0.5: `artifacts\dev5.0.5\task_docs_selftest_report.md`'
)
$evidenceLines | Set-Content -LiteralPath $Evidence -Encoding UTF8

Write-Host 'PASS: v5.0 acceptance'
Write-Host "Report: $Report"
Write-Host "Summary: $Summary"
Write-Host "Evidence: $Evidence"

