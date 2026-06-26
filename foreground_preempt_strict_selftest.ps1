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

$preempt = Invoke-Agent -WinArgs @('foreground-preempt', '--dry-run', 'true')
Assert ($preempt.ok -eq $true) 'foreground-preempt dry-run should pass.'
Assert ($preempt.data.preempt_run -eq $true) 'foreground-preempt must report preempt_run=true.'
Assert ($preempt.data.before_first_observation -eq $true) 'foreground-preempt must be usable before first observation.'

$out = Join-Path $OutDir 'foreground_preempt_global.bmp'
$shot = Invoke-Agent -WinArgs @('global-screenshot', '--out', $out, '--include-metadata', 'true')
Assert ($shot.ok -eq $true) 'global-screenshot should pass.'
Assert ($shot.data.foreground_preempt -ne $null) 'global-screenshot must include foreground_preempt evidence.'
Assert ($shot.data.foreground_preempt.preempt_run -eq $true) 'global-screenshot must run foreground preempt before capture.'

$report = Join-Path $OutDir 'foreground_preempt_report.md'
@(
    '# Foreground Preempt Strict Selftest',
    '',
    '- result: PASS',
    '- foreground-preempt dry-run: PASS',
    '- global-screenshot preempt evidence: PASS'
) | Set-Content -Encoding UTF8 -LiteralPath $report
Write-Host "PASS foreground_preempt_strict_selftest"
exit 0
