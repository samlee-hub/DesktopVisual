param([string]$Root = '')

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$OutDir = Join-Path $Root 'artifacts\dev6.12.1_visible_ui_foundation_hardening'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Invoke-Agent([string[]]$WinArgs, [int[]]$Allowed = @(0)) {
    $output = & $WinAgent @WinArgs
    $exit = $LASTEXITCODE
    if ($Allowed -notcontains $exit) { throw "winagent $($WinArgs -join ' ') exited $exit with output: $output" }
    return $output | ConvertFrom-Json
}
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }

$pass = Invoke-Agent -WinArgs @('visible-ui-verify', '--global-final-frame', 'true', '--target-lock', 'true', '--expected-output-visible', 'true', '--raw-completed', 'false', '--window-only', 'false')
Assert ($pass.ok -eq $true) 'visible-ui-verify should pass with global evidence.'
Assert ($pass.data.final_result -eq 'PASS') 'final result should be PASS.'
Assert ($pass.data.global_final_frame_required -eq $true) 'global frame requirement missing.'

$windowOnly = Invoke-Agent -WinArgs @('visible-ui-verify', '--global-final-frame', 'false', '--target-lock', 'true', '--expected-output-visible', 'true', '--window-only', 'true') -Allowed @(1)
Assert ($windowOnly.ok -eq $false) 'window-only final evidence should fail.'
Assert ($windowOnly.error.code -eq 'FAIL_FINAL_EVIDENCE_WINDOW_ONLY') 'window-only failure code mismatch.'

$raw = Invoke-Agent -WinArgs @('visible-ui-verify', '--global-final-frame', 'true', '--target-lock', 'true', '--expected-output-visible', 'true', '--raw-completed', 'true') -Allowed @(1)
Assert ($raw.ok -eq $false) 'raw completed as pass should fail.'
Assert ($raw.error.code -eq 'FAIL_RAW_COMPLETED_AS_PASS') 'raw completed failure code mismatch.'

$report = Join-Path $OutDir 'visible_ui_verification_report.md'
@(
    '# Visible UI Verification Policy Selftest',
    '',
    '- result: PASS',
    '- global final frame accepted: PASS',
    '- window-only rejected: PASS',
    '- raw completed rejected: PASS'
) | Set-Content -Encoding UTF8 -LiteralPath $report
Write-Host "PASS visible_ui_verification_policy_selftest"
exit 0
