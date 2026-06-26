param(
    [string]$Root = '',
    [string]$PortableRoot = 'D:\desktopvisual_portable_test',
    [switch]$SkipOriginalSelftest
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$Root = [System.IO.Path]::GetFullPath($Root)
$env:DESKTOPVISUAL_ROOT = $Root

$PortableRoot = [System.IO.Path]::GetFullPath($PortableRoot)
$Artifacts = Join-Path $Root 'artifacts\portable_root_selftest'
$Report = Join-Path $Artifacts 'portable_root_selftest_report.md'
$PackageOut = Join-Path $Artifacts 'release'
$ExportRoot = Join-Path $PackageOut 'DesktopVisual-v3.0.2-source'
$SourceZip = Join-Path $PackageOut 'DesktopVisual-v3.0.2-source.zip'

function Fail($Message) {
    throw "FAIL: $Message"
}

function Pass($Message) {
    Write-Host "PASS: $Message" -ForegroundColor Green
}

function Invoke-Checked {
    param(
        [string]$Name,
        [scriptblock]$Action
    )
    Write-Host "Running: $Name"
    $output = & $Action 2>&1
    $exit = $LASTEXITCODE
    if ($null -eq $exit) { $exit = 0 }
    if ($exit -ne 0) {
        Fail "$Name exited $exit. Output: $($output | Out-String)"
    }
    Pass $Name
    return $output
}

function Assert-UnderRoot {
    param([string]$Path, [string]$ExpectedRoot, [string]$Label)
    $full = [System.IO.Path]::GetFullPath($Path)
    $rootFull = [System.IO.Path]::GetFullPath($ExpectedRoot)
    if (-not ($full.Equals($rootFull, [System.StringComparison]::OrdinalIgnoreCase) -or
        $full.StartsWith($rootFull + '\', [System.StringComparison]::OrdinalIgnoreCase))) {
        Fail "$Label is outside expected root. Path=$full Root=$rootFull"
    }
}

function Reset-PortableRoot {
    $resolved = [System.IO.Path]::GetFullPath($PortableRoot)
    if ($resolved -ne 'D:\desktopvisual_portable_test') {
        Fail "Refusing to delete unexpected portable root: $resolved"
    }
    if (Test-Path -LiteralPath $resolved) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $resolved | Out-Null
}

New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null

if (-not $SkipOriginalSelftest) {
    Invoke-Checked 'original build' { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'build.ps1') -Root $Root }
    Invoke-Checked 'original selftest' { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'selftest.ps1') -Root $Root }
}

if (Test-Path -LiteralPath $ExportRoot) {
    Remove-Item -LiteralPath $ExportRoot -Recurse -Force
}

Invoke-Checked 'source package export' {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'package_source.ps1') -Root $Root -OutDir $PackageOut -ExportRoot $ExportRoot
}
if (!(Test-Path -LiteralPath $SourceZip)) {
    Fail "Source zip was not created: $SourceZip"
}

Reset-PortableRoot
Copy-Item -Path (Join-Path $ExportRoot '*') -Destination $PortableRoot -Recurse -Force

$oldRoot = $env:DESKTOPVISUAL_ROOT
try {
    $env:DESKTOPVISUAL_ROOT = $PortableRoot
    Invoke-Checked 'portable build' { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PortableRoot 'build.ps1') -Root $PortableRoot }
    Invoke-Checked 'portable selftest' { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PortableRoot 'selftest.ps1') -Root $PortableRoot }

    $versionOutput = & (Join-Path $PortableRoot 'bin\winagent.exe') version
    if ($LASTEXITCODE -ne 0) {
        Fail "portable winagent version exited $LASTEXITCODE"
    }
    $versionJson = $versionOutput | ConvertFrom-Json
    if ($versionJson.data.project_root -ne $PortableRoot) {
        Fail "Expected project_root $PortableRoot, got $($versionJson.data.project_root)"
    }
    Pass 'version project_root is portable root'

    $configPath = Join-Path $PortableRoot 'config\safety.conf'
    if (!(Select-String -LiteralPath $configPath -Pattern '${PROJECT_ROOT}' -SimpleMatch -Quiet)) {
        Fail 'safety.conf does not contain ${PROJECT_ROOT}'
    }
    $readResult = & (Join-Path $PortableRoot 'bin\winagent.exe') read-file --path (Join-Path $PortableRoot 'VERSION')
    if ($LASTEXITCODE -ne 0) {
        Fail "read-file portable VERSION exited $LASTEXITCODE with output: $readResult"
    }
    ($readResult | ConvertFrom-Json) | Out-Null
    Pass 'PROJECT_ROOT expansion allows portable read-file'

    $portableReport = Join-Path $PortableRoot 'artifacts\selftest_report.md'
    if (!(Test-Path -LiteralPath $portableReport)) {
        Fail "Portable selftest report was not written: $portableReport"
    }
    Assert-UnderRoot $portableReport $PortableRoot 'portable selftest report'
    Pass 'artifacts written under portable root'

    Invoke-Checked 'portable source package' {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PortableRoot 'package_source.ps1') -Root $PortableRoot
    }
}
finally {
    $env:DESKTOPVISUAL_ROOT = $oldRoot
}

$lines = @(
    '# DesktopVisual Portable Root Selftest',
    '',
    '- Result: PASS',
    "- Original root: $Root",
    "- Portable root: $PortableRoot",
    "- Source zip: $SourceZip",
    "- Portable report: $(Join-Path $PortableRoot 'artifacts\selftest_report.md')",
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8

Write-Host "Portable root selftest passed."
Write-Host "Report: $Report"
Write-Host "Source zip: $SourceZip"
