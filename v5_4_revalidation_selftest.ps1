param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\v5_4_revalidation_selftest.ps1 [-Root <path>]'
    Write-Host 'Runs Phase 6 v5.4 TaskTemplateV2 and AppProfile binding revalidation checks.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$PhaseDir = Join-Path $Root 'artifacts\dev5.8.7_revalidation\phase_06_v5.4'
$TempDir = Join-Path $PhaseDir 'temp_v5_4_revalidation'
$Report = Join-Path $PhaseDir 'v5_4_revalidation_selftest_report.md'

New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

function Invoke-JsonCommand {
    param(
        [string[]]$Arguments,
        [int[]]$AllowedExitCodes = @(0)
    )
    $output = & $WinAgent @Arguments 2>&1
    $exit = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    if ($AllowedExitCodes -notcontains $exit) {
        throw "Unexpected exit $exit for $($Arguments -join ' '). output=$text"
    }
    $json = $text | ConvertFrom-Json
    return [pscustomobject]@{ ExitCode = $exit; Text = $text; Json = $json }
}

$outputs = New-Object System.Collections.Generic.List[string]
$TemplateDir = Join-Path $Root 'tasks\templates_v2'
$SamplesTaskDir = Join-Path $Root 'samples\tasks'
$SamplesProfileDir = Join-Path $Root 'samples\profiles'

$builtins = @(
    'local_form_fill_submit',
    'local_problem_page_run_read',
    'local_mail_mock_compose_attach_no_real_send',
    'notepad_edit_verify',
    'explorer_file_select_mock'
)

foreach ($name in $builtins) {
    $path = Join-Path $TemplateDir "$name.task-template-v2.json"
    Get-Content -LiteralPath $path -Raw | ConvertFrom-Json | Out-Null
    $validated = Invoke-JsonCommand @('task-template-v2-validate', '--file', $path)
    if (-not $validated.Json.ok) { throw "Template validation failed for $name. output=$($validated.Text)" }
    foreach ($field in @('schema_version','runtime_version','protocol_version','template_id','required_profile','parameters','states','steps','preconditions','verification','recovery','confirmation_nodes','final_state_policy')) {
        if ($null -eq $validated.Json.data.$field) { throw "Validation data for $name missing $field" }
    }
    if ($validated.Json.data.safety.profile_can_override_safety -ne $false) { throw "$name profile_can_override_safety must be false." }
    if ($validated.Json.data.safety.no_fixed_coordinates -ne $true) { throw "$name must report no_fixed_coordinates=true." }
    $outputs.Add($validated.Text) | Out-Null
}

$invalidTemplate = Join-Path $Root 'tasks\templates_v2\invalid_missing_profile.task-template-v2.json'
$invalid = Invoke-JsonCommand @('task-template-v2-validate', '--file', $invalidTemplate) @(1)
if ($invalid.Json.ok -or $invalid.Json.error.code -ne 'TASK_TEMPLATE_V2_SCHEMA_INVALID') { throw "Invalid template was not rejected. output=$($invalid.Text)" }
$outputs.Add($invalid.Text) | Out-Null

$mailTemplate = Join-Path $TemplateDir 'local_mail_mock_compose_attach_no_real_send.task-template-v2.json'
$mailParams = Join-Path $SamplesTaskDir 'local_mail_mock_compose_attach_no_real_send.params.json'
$resolvedMail = Invoke-JsonCommand @('task-template-v2-resolve', '--template', $mailTemplate, '--profile', 'local_mail_mock', '--params-file', $mailParams)
if (-not $resolvedMail.Json.ok) { throw "Profile binding failed for local_mail_mock. output=$($resolvedMail.Text)" }
foreach ($binding in @('common_locators','roi_definitions','visual_strategy','recovery_strategy','confirmation_nodes')) {
    if ($resolvedMail.Json.data.bound_profile.$binding -ne $true) { throw "Expected profile binding for $binding." }
}
if ($resolvedMail.Json.data.bound_profile.can_override_safety_manifest -ne $false -or $resolvedMail.Json.data.safety.profile_can_override_safety -ne $false) {
    throw 'Profile binding must not override Safety.'
}
$outputs.Add($resolvedMail.Text) | Out-Null

$missingLocator = Invoke-JsonCommand @('task-template-v2-resolve', '--template', (Join-Path $TemplateDir 'invalid_missing_locator_binding.task-template-v2.json'), '--profile', 'local_mail_mock', '--params-file', $mailParams) @(1)
if ($missingLocator.Json.error.code -ne 'PROFILE_BINDING_MISSING_LOCATOR' -or $null -eq $missingLocator.Json.data.locator_ref) {
    throw "Missing locator did not produce structured failure. output=$($missingLocator.Text)"
}
$outputs.Add($missingLocator.Text) | Out-Null

$missingRequired = Invoke-JsonCommand @('task-template-v2-resolve', '--template', $mailTemplate, '--profile', 'local_mail_mock', '--params-file', (Join-Path $SamplesTaskDir 'missing_subject.params.json')) @(1)
if ($missingRequired.Json.error.code -ne 'TASK_PARAMETER_MISSING' -or $missingRequired.Json.data.parameter -ne 'subject') {
    throw "Missing required parameter did not fail correctly. output=$($missingRequired.Text)"
}
$outputs.Add($missingRequired.Text) | Out-Null

$badPath = Invoke-JsonCommand @('task-template-v2-resolve', '--template', $mailTemplate, '--profile', 'local_mail_mock', '--params-file', (Join-Path $SamplesTaskDir 'bad_path.params.json')) @(1)
if ($badPath.Json.error.code -ne 'TASK_PARAMETER_PATH_INVALID') { throw "Bad path did not fail path validation. output=$($badPath.Text)" }
$outputs.Add($badPath.Text) | Out-Null

$badTypeTemplate = Join-Path $TempDir 'invalid_parameter_type.task-template-v2.json'
$baseTemplateText = Get-Content -LiteralPath (Join-Path $TemplateDir 'notepad_edit_verify.task-template-v2.json') -Raw
$badTypeText = $baseTemplateText -replace '"type": "string"', '"type": "number"'
$badTypeText | Set-Content -LiteralPath $badTypeTemplate -Encoding UTF8
Get-Content -LiteralPath $badTypeTemplate -Raw | ConvertFrom-Json | Out-Null
$badType = Invoke-JsonCommand @('task-template-v2-validate', '--file', $badTypeTemplate) @(1)
if ($badType.Json.error.code -ne 'TASK_TEMPLATE_V2_SCHEMA_INVALID' -or $badType.Json.error.message -notmatch 'parameter') {
    throw "Invalid parameter type was not rejected. output=$($badType.Text)"
}
$outputs.Add($badType.Text) | Out-Null

$smokeForm = Invoke-JsonCommand @('task-template-v2-resolve', '--task', (Join-Path $SamplesTaskDir 'local_form_fill_submit_v2.task.json'))
if (-not $smokeForm.Json.ok -or $smokeForm.Json.data.template_id -ne 'local_form_fill_submit') { throw "local_form_fill_submit smoke failed. output=$($smokeForm.Text)" }
$outputs.Add($smokeForm.Text) | Out-Null

$smokeProblem = Invoke-JsonCommand @('task-template-v2-resolve', '--task', (Join-Path $SamplesTaskDir 'local_problem_page_run_read.task.json'))
if (-not $smokeProblem.Json.ok -or $smokeProblem.Json.data.template_id -ne 'local_problem_page_run_read') { throw "local_problem_page_run_read smoke failed. output=$($smokeProblem.Text)" }
$outputs.Add($smokeProblem.Text) | Out-Null

Get-ChildItem -LiteralPath $SamplesTaskDir -Filter '*.json' | ForEach-Object {
    Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json | Out-Null
}
Get-ChildItem -LiteralPath $SamplesProfileDir -Filter '*.json' | ForEach-Object {
    Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json | Out-Null
}

foreach ($requiredParam in @('recipient','subject','body','file_path','expected_result','local_url','output_region')) {
    $found = Select-String -Path (Join-Path $TemplateDir '*.json') -Pattern ('"name": "' + $requiredParam + '"') -Quiet
    if (-not $found) { throw "Required parameter coverage missing: $requiredParam" }
}

$lines = @(
    '# Phase 6 v5.4 Revalidation Selftest Report',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    '- Scope: TaskTemplateV2 schema, AppProfile binding, TaskParameter validation, built-in templates, samples.',
    '- Runtime action execution: 0',
    '- VLM/Agent provider calls: 0',
    '',
    '## Command Outputs',
    '',
    '```json'
)
$lines += $outputs
$lines += '```'
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: Phase 6 v5.4 revalidation selftest'
Write-Host "Report: $Report"
