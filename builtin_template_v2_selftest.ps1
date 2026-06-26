param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\builtin_template_v2_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates v5.4.4 built-in local Task Template v2 templates.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.4.4'
$Report = Join-Path $ArtifactDir 'builtin_template_v2_selftest_report.md'
$TemplateDir = Join-Path $Root 'tasks\templates_v2'

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

$templates = @(
    'local_form_fill_submit',
    'local_problem_page_run_read',
    'local_mail_mock_compose_attach_no_real_send',
    'notepad_edit_verify',
    'explorer_file_select_mock'
)

$outputs = New-Object System.Collections.Generic.List[string]
foreach ($name in $templates) {
    $path = Join-Path $TemplateDir "$name.task-template-v2.json"
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing built-in template: $path"
    }
    Get-Content -LiteralPath $path -Raw | ConvertFrom-Json | Out-Null
    $validated = Invoke-JsonCommand @('task-template-v2-validate', '--file', $path)
    if (-not $validated.Json.ok -or $validated.Json.data.template_id -ne $name) {
        throw "Built-in template validation failed for $name. output=$($validated.Text)"
    }
    $outputs.Add($validated.Text) | Out-Null
}

$smokeForm = Invoke-JsonCommand @('task-template-v2-resolve', '--task', (Join-Path $Root 'samples\tasks\local_form_fill_submit_v2.task.json'))
if (-not $smokeForm.Json.ok -or $smokeForm.Json.data.template_id -ne 'local_form_fill_submit') {
    throw "local_form_fill_submit smoke failed. output=$($smokeForm.Text)"
}
$smokeMail = Invoke-JsonCommand @('task-template-v2-resolve', '--task', (Join-Path $Root 'samples\tasks\local_mail_mock_compose_attach_no_real_send.task.json'))
if (-not $smokeMail.Json.ok -or $smokeMail.Json.data.template_id -ne 'local_mail_mock_compose_attach_no_real_send') {
    throw "local mail mock smoke failed. output=$($smokeMail.Text)"
}

$lines = @(
    '# v5.4.4 Built-in Template v2 Selftest Report',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    '- built-in template parse: PASS',
    '- local_form_fill_submit smoke: PASS',
    '- local_mail_mock_compose_attach_no_real_send smoke: PASS',
    '',
    '## Smoke Outputs',
    '',
    '```json',
    $smokeForm.Text,
    $smokeMail.Text,
    '```'
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.4.4 built-in Task Template v2 selftest'
Write-Host "Report: $Report"
