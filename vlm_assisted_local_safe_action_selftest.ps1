param(
    [string]$Root = '',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$TestWindowExe = 'D:\testrepo\testwindow\bin\TestWindow.exe'
$StateFile = 'D:\testrepo\testwindow\runtime\state.txt'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.6.0_vlm_assisted_unknown_ui_candidate_handling'
$SelftestRoot = Join-Path $ArtifactRoot 'selftest\local_safe_action'
$ReportPath = Join-Path $ArtifactRoot 'local_safe_action_report.md'
$ProgressPath = Join-Path $SelftestRoot 'progress.log'
New-Item -ItemType Directory -Force -Path $SelftestRoot | Out-Null
Set-Content -LiteralPath $ProgressPath -Value '' -Encoding UTF8

if (-not $SkipBuild) {
    & (Join-Path $Root 'build.ps1') -Root $Root
    if ($LASTEXITCODE -ne 0) { throw 'build failed' }
}
if (-not (Test-Path -LiteralPath $WinAgent)) { throw "winagent.exe not found: $WinAgent" }
if (-not (Test-Path -LiteralPath $TestWindowExe)) { throw "TestWindow.exe not found: $TestWindowExe" }

function Write-Mark {
    param([string]$Message)
    Add-Content -LiteralPath $ProgressPath -Value ("{0} {1}" -f (Get-Date -Format 's'), $Message) -Encoding UTF8
}

function Quote-ProcessArg {
    param([string]$Value)
    if ($Value -notmatch '[\s"]') { return $Value }
    '"' + ($Value -replace '"', '\"') + '"'
}

$script:InvokeIndex = 0
function Invoke-WinAgentJson {
    param([string[]]$Arguments, [int[]]$AllowedExitCodes = @(0))
    $script:InvokeIndex += 1
    $stdoutPath = Join-Path $SelftestRoot ('winagent_{0:000}_stdout.json' -f $script:InvokeIndex)
    $stderrPath = Join-Path $SelftestRoot ('winagent_{0:000}_stderr.txt' -f $script:InvokeIndex)
    $argLine = ($Arguments | ForEach-Object { Quote-ProcessArg $_ }) -join ' '
    Write-Mark "winagent start: $($Arguments -join ' ')"
    $proc = Start-Process -FilePath $WinAgent -ArgumentList $argLine -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $exit = $proc.ExitCode
    $text = ''
    if (Test-Path -LiteralPath $stdoutPath) {
        $rawStdout = Get-Content -LiteralPath $stdoutPath -Raw
        if ($null -ne $rawStdout) { $text = $rawStdout.Trim() }
    }
    $stderr = ''
    if (Test-Path -LiteralPath $stderrPath) {
        $rawStderr = Get-Content -LiteralPath $stderrPath -Raw
        if ($null -ne $rawStderr) { $stderr = $rawStderr.Trim() }
    }
    if (-not $text -and $stderr) { $text = $stderr }
    Write-Mark "winagent exit=${exit}: $($Arguments[0])"
    try { $json = $text | ConvertFrom-Json } catch { throw "Invalid JSON from winagent $($Arguments -join ' '): $text" }
    if ($AllowedExitCodes -notcontains $exit) {
        throw "Unexpected exit $exit from winagent $($Arguments -join ' '): $text"
    }
    [pscustomobject]@{ exit = $exit; json = $json; text = $text; args = $Arguments }
}

function Stop-TestWindow {
    Get-Process TestWindow -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Wait-TestWindow {
    for ($i = 0; $i -lt 30; $i++) {
        $find = Invoke-WinAgentJson -Arguments @('find', '--title', 'Agent Test Window') -AllowedExitCodes @(0, 1)
        if ($find.exit -eq 0 -and $find.json.ok -eq $true) { return }
        Start-Sleep -Milliseconds 200
    }
    throw 'Agent Test Window did not appear.'
}

$resultPath = Join-Path $SelftestRoot 'local_safe_action_result.json'
$evidenceDir = Join-Path $SelftestRoot 'evidence'
$failures = [System.Collections.Generic.List[string]]::new()
$stateText = ''
$payload = $null

Stop-TestWindow
Write-Mark 'stopped pre-existing TestWindow'
Remove-Item -LiteralPath $StateFile -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $StateFile) | Out-Null

try {
    Write-Mark 'starting TestWindow'
    Start-Process -FilePath $TestWindowExe | Out-Null
    Write-Mark 'waiting TestWindow'
    Wait-TestWindow
    Write-Mark 'TestWindow ready'

    Invoke-WinAgentJson -Arguments @(
        'vlm-assisted-locate-and-click-local-safe',
        '--allow-legacy-mock-vlm', 'true',
        '--target', 'Click Me',
        '--provider', 'mock',
        '--scenario', 'testwindow_click_me',
        '--title', 'Agent Test Window',
        '--expected-marker', 'clicks=1',
        '--result', $resultPath,
        '--evidence-dir', $evidenceDir,
        '--move-mode', 'instant'
    ) | Out-Null
    Write-Mark 'local-safe command completed'

    $payload = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    $stateText = Get-Content -LiteralPath $StateFile -Raw
    Write-Mark 'result and state loaded'

    if ($payload.vlm_candidate_used -ne $true) { $failures.Add('vlm_candidate_used was not true') | Out-Null }
    if ($payload.runtime_candidate_validated -ne $true) { $failures.Add('runtime_candidate_validated was not true') | Out-Null }
    if ($payload.runtime_context_guard_used -ne $true) { $failures.Add('runtime_context_guard_used was not true') | Out-Null }
    if ($payload.mouse_click_sent -ne $true) { $failures.Add('mouse_click_sent was not true') | Out-Null }
    if ($payload.post_action_verified -ne $true) { $failures.Add('post_action_verified was not true') | Out-Null }
    if ($payload.coordinate_source_type -ne 'vlm_assisted_runtime_validated') { $failures.Add('coordinate_source_type mismatch') | Out-Null }
    if ($payload.runtime_executed -ne $true) { $failures.Add('runtime_executed was not true') | Out-Null }
    if ($payload.action_evidence.human_action_result.actual_click_sent -ne $true) { $failures.Add('actual_click_sent was not true') | Out-Null }
    if ($payload.action_evidence.context_guard_result.ok -ne $true) { $failures.Add('RuntimeContextGuard result was not ok') | Out-Null }
    if ($payload.locator_candidate.requires_final_guard_check -ne $true) { $failures.Add('requires_final_guard_check was not true') | Out-Null }
    if ($payload.locator_candidate.requires_mouse_first_evidence -ne $true) { $failures.Add('requires_mouse_first_evidence was not true') | Out-Null }
    if ($payload.locator_candidate.requires_post_action_verification -ne $true) { $failures.Add('requires_post_action_verification was not true') | Out-Null }
    if ($stateText -notmatch 'clicks=1') { $failures.Add('state marker clicks=1 was not observed') | Out-Null }
} finally {
    Write-Mark 'cleaning TestWindow'
    Stop-TestWindow
    Write-Mark 'cleaned TestWindow'
}

Write-Mark 'building report status'
$status = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
Write-Mark 'writing report'
$reportLines = @(
    '# v6.6.0 VLM-Assisted Local-Safe Action Report',
    '',
    "- Result: $status",
    "- Runtime locate failed path used: $($payload.runtime_locator_failed)",
    "- VLM candidate used: $($payload.vlm_candidate_used)",
    "- Runtime candidate validated: $($payload.runtime_candidate_validated)",
    "- RuntimeContextGuard used: $($payload.runtime_context_guard_used)",
    "- Mouse click sent: $($payload.mouse_click_sent)",
    "- Actual click sent: $($payload.action_evidence.human_action_result.actual_click_sent)",
    "- Post-action verified: $($payload.post_action_verified)",
    "- Coordinate source type: $($payload.coordinate_source_type)",
    "- Selected candidate id: $($payload.bridge_result.selected_candidate_id)",
    "- Validation method: $($payload.runtime_candidate_validation.selected_candidate.validation_method)",
    "- State marker observed: $($stateText -match 'clicks=1')",
    "- Result path: $resultPath",
    "- Evidence dir: $evidenceDir"
)
[System.IO.File]::WriteAllLines($ReportPath, [string[]]$reportLines, [System.Text.UTF8Encoding]::new($false))
Write-Mark 'report written'

if ($failures.Count -ne 0) {
    throw "VLM-assisted local-safe action selftest failed: $($failures -join '; ')"
}

Write-Mark 'emitting pass output'
Write-Output 'PASS: v6.6.0 VLM-assisted local-safe action selftest'
Write-Output "Report: $ReportPath"
Write-Mark 'script complete'
