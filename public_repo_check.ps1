param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$Artifacts = Join-Path $Root 'artifacts'
$Report = Join-Path $Artifacts 'public_repo_check_report.md'
New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null

$checks = New-Object System.Collections.Generic.List[object]

function Add-Check {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    $script:checks.Add([pscustomobject]@{ Name = $Name; Ok = $Ok; Detail = $Detail })
    if ($Ok) { Write-Host "PASS: $Name - $Detail" -ForegroundColor Green }
    else { Write-Host "FAIL: $Name - $Detail" -ForegroundColor Red }
}

function Get-DirSize {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @{ Files = 0; Bytes = 0 } }
    $items = Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue
    $sum = ($items | Measure-Object Length -Sum).Sum
    if ($null -eq $sum) { $sum = 0 }
    return @{ Files = ($items | Measure-Object).Count; Bytes = [int64]$sum }
}

function Test-GitIgnorePattern {
    param([string]$Pattern)
    $gitignorePath = Join-Path $Root '.gitignore'
    if (-not (Test-Path -LiteralPath $gitignorePath)) { return $false }
    $lines = Get-Content -LiteralPath $gitignorePath
    return [bool]($lines | Where-Object { $_.Trim() -eq $Pattern })
}

$requiredFiles = @('.gitignore','package_source.ps1','clean_artifacts.ps1','README.md','build.ps1','script_lint.ps1','portable_root_selftest.ps1','adapter_selftest.ps1','benchmark_matrix.ps1','benchmark_selftest.ps1','export_evidence_pack.ps1','safety_manifest_selftest.ps1','selftest.ps1','RELEASE_NOTES_v3.0.2.md','RELEASE_NOTES_v3.0.3.md','RELEASE_NOTES_v3.0.4.md','RELEASE_NOTES_v3.0.5.md','docs\REPOSITORY_HYGIENE.md','docs\AGENT_ADAPTERS.md','docs\BENCHMARK_METHODOLOGY.md','docs\BENCHMARKS.md','docs\PERCEPTION.md','docs\SAFETY_MODEL.md','docs\RELEASE_SUMMARY_v3.md','docs\ROADMAP_v4.md','docs\RESUME_POSITIONING.md','docs\LOCAL_RELEASE_PERMISSION_POLICY.md','config\safety_manifest.json')
foreach ($file in $requiredFiles) {
    Add-Check "Required file $file" (Test-Path -LiteralPath (Join-Path $Root $file)) $file
}

$readmePath = Join-Path $Root 'README.md'
$readme = if (Test-Path -LiteralPath $readmePath) { Get-Content -LiteralPath $readmePath -Raw } else { '' }
$readmeChecks = @(
    @{ Name = 'README project positioning'; Pattern = 'Windows-only, agent-agnostic, auditable, safety-bounded Computer Use Runtime' },
    @{ Name = 'README Windows-only'; Pattern = 'Windows-only' },
    @{ Name = 'README not official Codex'; Pattern = 'not the official built-in Codex Computer Use feature' },
    @{ Name = 'README safety boundary'; Pattern = 'Safety' },
    @{ Name = 'README build.ps1'; Pattern = 'build.ps1' },
    @{ Name = 'README selftest.ps1'; Pattern = 'selftest.ps1' },
    @{ Name = 'README portable mode'; Pattern = 'Portable Mode' },
    @{ Name = 'README DESKTOPVISUAL_ROOT'; Pattern = 'DESKTOPVISUAL_ROOT' },
    @{ Name = 'README agent adapters'; Pattern = 'Agent Adapters' },
    @{ Name = 'README benchmark evidence'; Pattern = 'Benchmark Evidence' },
    @{ Name = 'README safety manifest'; Pattern = 'Safety Manifest' },
    @{ Name = 'README release candidate'; Pattern = 'public release candidate' },
    @{ Name = 'README release tree'; Pattern = 'D:\desktopvisual-release' }
)
foreach ($check in $readmeChecks) {
    Add-Check $check.Name ($readme -like "*$($check.Pattern)*") $check.Pattern
}
$readmePreamble = (($readme -split "`r?`n") | Select-Object -First 8) -join "`n"
Add-Check 'README ASCII preamble' (-not ($readmePreamble -match '[^\x00-\x7F]')) 'first 8 README lines contain only ASCII release positioning'

$ignorePatterns = @(
    'artifacts/','artifacts/motion_profile/**/raw/','bin/','obj/','dist/',
    '*.obj','*.pdb','*.ilk','*.exe','*.dll','*.lib','*.exp','*.log',
    '*.bmp','*.png','*.jpg','*.jpeg','*.tmp','*.cache','*.zip','*.7z',
    'edge_profile/','debug_profile/','browser_profile/','profile/','BrowserMetrics/','Cache/','Code Cache/',
    'Crashpad/','GPUCache/','Service Worker/','runs/','temp/','tmp/','.vs/','*.user','*.suo',
    'Local Storage/','Session Storage/','IndexedDB/','Cookies','History','Login Data','Web Data',
    'config/operator_motion_profile.json','!samples/**/operator_motion_profile*.json'
)
foreach ($pattern in $ignorePatterns) {
    Add-Check ".gitignore covers $pattern" (Test-GitIgnorePattern $pattern) $pattern
}

$srcSize = Get-DirSize (Join-Path $Root 'src')
$artifactsSize = Get-DirSize (Join-Path $Root 'artifacts')
$distSize = Get-DirSize (Join-Path $Root 'dist')

$failed = @($checks | Where-Object { -not $_.Ok })
$result = if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# Public Repo Check Report')
$lines.Add('')
$lines.Add("- Result: $result")
$lines.Add("- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$lines.Add("- Root: $Root")
$lines.Add('')
$lines.Add('## Size Summary')
$lines.Add('')
$lines.Add('| path | files | size_mb |')
$lines.Add('|---|---:|---:|')
$lines.Add(("| src | {0} | {1} |" -f $srcSize.Files, [math]::Round($srcSize.Bytes / 1MB, 2)))
$lines.Add(("| artifacts | {0} | {1} |" -f $artifactsSize.Files, [math]::Round($artifactsSize.Bytes / 1MB, 2)))
$lines.Add(("| dist | {0} | {1} |" -f $distSize.Files, [math]::Round($distSize.Bytes / 1MB, 2)))
$lines.Add('')
$lines.Add('## Checks')
$lines.Add('')
$lines.Add('| check | result | detail |')
$lines.Add('|---|---|---|')
foreach ($check in $checks) {
    $lines.Add(("| {0} | {1} | {2} |" -f $check.Name, $(if ($check.Ok) { 'PASS' } else { 'FAIL' }), ($check.Detail -replace '\|','/')))
}

$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host "Report: $Report"
Write-Host "Overall result: $result"

if ($failed.Count -gt 0) { exit 1 }
exit 0
