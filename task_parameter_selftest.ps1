param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\task_parameter_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates v5.4.3 Task Template v2 parameter validation.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.4.3'
$Report = Join-Path $ArtifactDir 'task_parameter_selftest_report.md'
$Template = Join-Path $Root 'tasks\templates_v2\local_mail_mock_compose_attach_no_real_send.task-template-v2.json'
$ValidParams = Join-Path $Root 'samples\tasks\local_mail_mock_compose_attach_no_real_send.params.json'
$MissingParams = Join-Path $Root 'samples\tasks\missing_subject.params.json'
$BadPathParams = Join-Path $Root 'samples\tasks\bad_path.params.json'

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "Missing winagent.exe. Run build.ps1 first: $WinAgent"
}

function Invoke-JsonCommand {
    param([string[]]$Arguments, [int[]]$AllowedExitCodes = @(0))

    $output = & $WinAgent @Arguments 2>&1
    $exit = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    if ($AllowedExitCodes -notcontains $exit) {
        throw "Unexpected exit $exit for $($Arguments -join ' '): $text"
    }
    $json = $text | ConvertFrom-Json
    return [pscustomobject]@{ ExitCode = $exit; Text = $text; Json = $json }
}

$valid = Invoke-JsonCommand @('task-template-v2-resolve', '--template', $Template, '--profile', 'local_mail_mock', '--params-file', $ValidParams)
if (-not $valid.Json.ok -or $valid.Json.data.parameter_count -lt 4) {
    throw "Expected valid parameters to pass. output=$($valid.Text)"
}

$missing = Invoke-JsonCommand @('task-template-v2-resolve', '--template', $Template, '--profile', 'local_mail_mock', '--params-file', $MissingParams) -AllowedExitCodes @(1)
if ($missing.Json.ok -or $missing.Json.error.code -ne 'TASK_PARAMETER_MISSING') {
    throw "Expected missing required parameter failure. output=$($missing.Text)"
}
if ($missing.Json.error.message -notmatch 'subject') {
    throw "Expected missing parameter error to mention subject. output=$($missing.Text)"
}

$badPath = Invoke-JsonCommand @('task-template-v2-resolve', '--template', $Template, '--profile', 'local_mail_mock', '--params-file', $BadPathParams) -AllowedExitCodes @(1)
if ($badPath.Json.ok -or $badPath.Json.error.code -ne 'TASK_PARAMETER_PATH_INVALID') {
    throw "Expected invalid path parameter failure. output=$($badPath.Text)"
}

$lines = @(
    '# v5.4.3 Task Parameter Selftest Report',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    '- parameter validation: PASS',
    '- missing required parameter: PASS',
    '- path validation: PASS',
    '',
    '## Valid Output',
    '',
    '```json',
    $valid.Text,
    '```',
    '',
    '## Missing Parameter Output',
    '',
    '```json',
    $missing.Text,
    '```',
    '',
    '## Invalid Path Output',
    '',
    '```json',
    $badPath.Text,
    '```'
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.4.3 task parameter selftest'
Write-Host "Report: $Report"
