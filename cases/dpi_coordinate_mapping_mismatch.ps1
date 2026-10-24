<#
.SYNOPSIS
    Minimal repro driver for the DPI coordinate-mapping bug.

.DESCRIPTION
    Step 1 produces artifacts\dpi_coordinate_map_actual.json with bin\winagent.exe coordinate-map.
    Step 2 hands cases\dpi_coordinate_mapping_mismatch.case to run-case.

    The case asserts the *fixed* values (dpi_scale 1.5 / screen_x 853 / screen_y 533), which are
    specific to a 150% display scale, so this driver refuses to run on any other scale.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File cases\dpi_coordinate_mapping_mismatch.ps1

.OUTPUTS
    Exit code 0 - case PASSED (bug fixed)
    Exit code 1 - case FAILED (bug reproduced)
    Exit code 2 - precondition not met (host is not at 150%) or setup error
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$Root      = Split-Path -Parent $PSScriptRoot
$WinAgent  = Join-Path $Root 'bin\winagent.exe'
$Artifacts = Join-Path $Root 'artifacts'
$MapJson   = Join-Path $Artifacts 'dpi_coordinate_map_actual.json'
$CaseFile  = Join-Path $PSScriptRoot 'dpi_coordinate_mapping_mismatch.case'
$Report    = Join-Path $Artifacts 'dpi_coordinate_mapping_mismatch_report.json'
$ProbeBmp  = Join-Path $Artifacts '_dpi_scale_probe.bmp'

if (-not (Test-Path $WinAgent)) { Write-Host "FATAL: winagent.exe not found at $WinAgent"; exit 2 }
if (-not (Test-Path $CaseFile)) { Write-Host "FATAL: case file not found at $CaseFile"; exit 2 }
New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null

# winagent emits UTF-8; make PowerShell decode native output the same way.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

function Invoke-WinAgent {
    param([string[]]$ArgList)
    return ((& $WinAgent @ArgList 2>&1) | Out-String)
}

try {
    # --- precondition: the asserted numbers only hold on a 150% display -----------------
    $shot = Invoke-WinAgent @('screenshot', '--out', $ProbeBmp) | ConvertFrom-Json
    $physicalWidth = [double]$shot.data.physical_width

    $wins    = Invoke-WinAgent @('windows') | ConvertFrom-Json
    $desktop = $wins.windows | Where-Object { $_.title -eq 'Program Manager' } | Select-Object -First 1
    if (-not $desktop) { Write-Host "FATAL: could not locate 'Program Manager' to derive the logical screen width."; exit 2 }
    $logicalWidth = [double]$desktop.rect.right - [double]$desktop.rect.left
    if ($logicalWidth -le 0) { Write-Host "FATAL: logical screen width is $logicalWidth."; exit 2 }

    $scale = [math]::Round($physicalWidth / $logicalWidth, 3)
    Write-Host ("Host display: physical {0} x logical {1} -> scale {2}" -f $physicalWidth, $logicalWidth, $scale)
    if ([math]::Abs($scale - 1.5) -gt 0.05) {
        Write-Host "SKIP: this case asserts 150% values; host scale is $scale. Nothing was asserted."
        exit 2
    }

    # --- step 1: produce the mapping JSON the case asserts on ---------------------------
    $mapArgs = @(
        'coordinate-map',
        '--capture-scope', 'global_desktop',
        '--capture-left',   '0',
        '--capture-top',    '0',
        '--capture-width',  '2560',
        '--capture-height', '1600',
        '--pixel-x',        '1280',
        '--pixel-y',        '800'
    )
    $mapRaw = (Invoke-WinAgent $mapArgs).Trim()
    [System.IO.File]::WriteAllText($MapJson, $mapRaw, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Mapping JSON written to $MapJson"
    Write-Host ("  actual: " + $mapRaw)

    # --- step 2: run the case -----------------------------------------------------------
    Write-Host "Running run-case on $CaseFile"
    $caseRaw = (Invoke-WinAgent @('run-case', '--file', $CaseFile, '--report', $Report)).Trim()
    Write-Host ("  run-case: " + $caseRaw)
    Write-Host "Report: $Report"

    $caseResult = $caseRaw | ConvertFrom-Json
    if ($caseResult.ok -eq $true) {
        Write-Host "RESULT: PASSED - the coordinate mapper now applies the device scale factor."
        exit 0
    }

    Write-Host "RESULT: FAILED - bug reproduced (see the failing step in the report above)."
    exit 1
}
finally {
    Remove-Item -Force -Path $ProbeBmp -ErrorAction SilentlyContinue
}
