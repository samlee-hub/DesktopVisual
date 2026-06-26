param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\step_precondition_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates v5.1.2 StepContract precondition checks.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.1.2'
$Report = Join-Path $ArtifactDir 'step_precondition_selftest_report.md'
$Contract = Join-Path $Root 'tasks\step_contract\valid_local_form_submit.step.json'
$Pass = Join-Path $Root 'tasks\step_contract\perception_pass.json'
$Missing = Join-Path $Root 'tasks\step_contract\perception_missing_element.json'
$WrongScene = Join-Path $Root 'tasks\step_contract\perception_wrong_scene.json'

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

foreach ($jsonPath in @($Contract, $Pass, $Missing, $WrongScene)) {
    Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json | Out-Null
}

function Invoke-JsonCommand {
    param([string[]]$Arguments)
    $output = & $WinAgent @Arguments 2>&1
    $exit = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    $json = $text | ConvertFrom-Json
    return [pscustomobject]@{ ExitCode = $exit; Text = $text; Json = $json }
}

$passResult = Invoke-JsonCommand @('step-precondition-check', '--contract', $Contract, '--perception', $Pass)
if ($passResult.ExitCode -ne 0 -or -not $passResult.Json.ok) {
    throw "Expected precondition pass. output=$($passResult.Text)"
}
if ($passResult.Json.data.passed_count -lt 6) {
    throw "Expected at least six passed preconditions."
}

$missingResult = Invoke-JsonCommand @('step-precondition-check', '--contract', $Contract, '--perception', $Missing)
if ($missingResult.ExitCode -eq 0 -or $missingResult.Json.ok) {
    throw "Expected missing element precondition failure. output=$($missingResult.Text)"
}
if ($missingResult.Json.error.code -ne 'PRECONDITION_FAILED' -or $missingResult.Json.error.message -notmatch 'submit-button') {
    throw "Expected PRECONDITION_FAILED mentioning submit-button. output=$($missingResult.Text)"
}

$sceneResult = Invoke-JsonCommand @('step-precondition-check', '--contract', $Contract, '--perception', $WrongScene)
if ($sceneResult.ExitCode -eq 0 -or $sceneResult.Json.ok) {
    throw "Expected wrong scene_state precondition failure. output=$($sceneResult.Text)"
}
if ($sceneResult.Json.error.code -ne 'PRECONDITION_FAILED' -or $sceneResult.Json.error.message -notmatch 'scene_state') {
    throw "Expected PRECONDITION_FAILED mentioning scene_state. output=$($sceneResult.Text)"
}

$lines = @(
    '# v5.1.2 Step Precondition Selftest Report',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    ('- Contract: `{0}`' -f $Contract),
    '',
    '## Pass Output',
    '',
    '```json',
    $passResult.Text,
    '```',
    '',
    '## Missing Element Output',
    '',
    '```json',
    $missingResult.Text,
    '```',
    '',
    '## Wrong Scene Output',
    '',
    '```json',
    $sceneResult.Text,
    '```'
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.1.2 Step precondition selftest'
Write-Host "Report: $Report"
