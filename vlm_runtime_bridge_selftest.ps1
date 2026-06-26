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

$manual = Invoke-Agent -WinArgs @('vlm-runtime-candidate', '--visual-manual-inspection', 'true')
Assert ($manual.ok -eq $true) 'manual visual inspection classification should pass.'
Assert ($manual.data.vlm_assisted -eq $false) 'manual inspection must not be vlm_assisted.'
Assert ($manual.data.visual_manual_inspection -eq $true) 'manual inspection flag missing.'

$missingMapper = Invoke-Agent -WinArgs @('vlm-runtime-candidate', '--global-frame', 'true', '--observation-request', 'true', '--observation-result', 'true', '--candidate-target', 'true', '--runtime-validator', 'true', '--coordinate-mapper', 'false', '--target-lock', 'true', '--action', 'true', '--verification', 'true') -Allowed @(1)
Assert ($missingMapper.ok -eq $false) 'missing mapper should fail.'
Assert ($missingMapper.error.code -eq 'FAIL_VLM_COORDINATE_MAPPING_INVALID') 'missing mapper failure code mismatch.'

$full = Invoke-Agent -WinArgs @('vlm-runtime-candidate', '--global-frame', 'true', '--observation-request', 'true', '--observation-result', 'true', '--candidate-target', 'true', '--runtime-validator', 'true', '--coordinate-mapper', 'true', '--target-lock', 'true', '--action', 'true', '--verification', 'true')
Assert ($full.ok -eq $true) 'full VLM runtime chain should pass.'
Assert ($full.data.vlm_assisted -eq $true) 'full chain must set vlm_assisted=true.'
Assert ($full.data.runtime_candidate_validated -eq $true) 'runtime validator evidence missing.'

$report = Join-Path $OutDir 'vlm_runtime_bridge_report.md'
@(
    '# VLM Runtime Bridge Selftest',
    '',
    '- result: PASS',
    '- manual visual inspection distinguished: PASS',
    '- missing mapper rejected: PASS',
    '- complete runtime chain accepted: PASS'
) | Set-Content -Encoding UTF8 -LiteralPath $report
Write-Host "PASS vlm_runtime_bridge_selftest"
exit 0
