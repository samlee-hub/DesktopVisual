param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\step_failure_reason_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates v5.1.4 Step failure reason classification.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.1.4'
$Report = Join-Path $ArtifactDir 'step_failure_reason_selftest_report.md'

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

$cases = @(
    @{ code = 'PRECONDITION_FAILED'; expected = 'PRECONDITION_FAILED' },
    @{ code = 'LOCATOR_NOT_FOUND'; expected = 'LOCATOR_NOT_FOUND' },
    @{ code = 'TARGET_NOT_READY'; expected = 'TARGET_NOT_READY' },
    @{ code = 'ACTION_FAILED'; expected = 'ACTION_FAILED' },
    @{ code = 'ACTION_NO_EFFECT'; expected = 'ACTION_NO_EFFECT' },
    @{ code = 'VERIFICATION_TIMEOUT'; expected = 'VERIFICATION_TIMEOUT' },
    @{ code = 'UNEXPECTED_SCENE'; expected = 'UNEXPECTED_SCENE' },
    @{ code = 'SAFETY_DENIED'; expected = 'SAFETY_DENIED' },
    @{ code = 'SEMANTIC_UNRESOLVED'; expected = 'SEMANTIC_UNRESOLVED' }
)

$outputs = New-Object System.Collections.Generic.List[string]
foreach ($case in $cases) {
    $output = & $WinAgent step-failure-classify --error-code $case.code --step-id "case_$($case.code)" 2>&1
    $exit = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    $json = $text | ConvertFrom-Json
    if ($exit -ne 0 -or -not $json.ok) {
        throw "Expected classification pass for $($case.code). output=$text"
    }
    if ($json.data.failure_reason -ne $case.expected) {
        throw "Expected $($case.expected), got $($json.data.failure_reason)"
    }
    if (-not $json.data.recommended_action) {
        throw "Expected recommended_action for $($case.code)"
    }
    $outputs.Add($text) | Out-Null
}

$lines = @(
    '# v5.1.4 Step Failure Reason Selftest Report',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    '',
    '## Outputs',
    '',
    '```json'
)
$lines += $outputs
$lines += '```'
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.1.4 Step failure reason selftest'
Write-Host "Report: $Report"
