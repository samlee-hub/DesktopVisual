param(
    [string]$Root = '',
    [string]$ReleaseRoot = '',
    [string]$PublicDistRoot = ''
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ReleaseRoot)) { $ReleaseRoot = Join-Path (Split-Path -Parent $Root) 'desktopvisual-release' }
if ([string]::IsNullOrWhiteSpace($PublicDistRoot)) { $PublicDistRoot = Join-Path (Split-Path -Parent $Root) 'desktopvisual-public-dist' }
$Root = [System.IO.Path]::GetFullPath($Root)
$ReleaseRoot = [System.IO.Path]::GetFullPath($ReleaseRoot)
$PublicDistRoot = [System.IO.Path]::GetFullPath($PublicDistRoot)

$OutDir = Join-Path $Root 'artifacts\dev1.1.0_public_permission_agent_efficiency'
$ReportPath = Join-Path $OutDir 'release_sync_readiness_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Fail($Message) { throw $Message }
function Read-Version([string]$Path) { return (Get-Content -Raw -LiteralPath (Join-Path $Path 'VERSION')).Trim() }
function Assert-Capabilities($Profile, [string]$Name) {
    foreach ($capability in @('third_party_apps','external_web','communication','content_decision','cross_window','global_desktop','browser','explorer','local_file_open','localhost')) {
        if ($Profile.$capability -ne $true) { Fail "$Name must allow $capability." }
    }
}

if ((Read-Version $Root) -ne '1.1.0') { Fail 'Developer VERSION must be 1.1.0.' }
if ((Read-Version $ReleaseRoot) -ne '1.1.0') { Fail 'Release VERSION must be 1.1.0.' }
if ((Read-Version $PublicDistRoot) -ne '1.1.0') { Fail 'Public dist VERSION must be 1.1.0.' }

& git -C $Root diff --check
if ($LASTEXITCODE -ne 0) { Fail 'Developer tree is not clean-capable: git diff --check failed.' }

$devManifest = Get-Content -Raw -LiteralPath (Join-Path $Root 'config\safety_manifest.json') | ConvertFrom-Json
$releaseManifest = Get-Content -Raw -LiteralPath (Join-Path $ReleaseRoot 'config\safety_manifest.json') | ConvertFrom-Json
$distManifest = Get-Content -Raw -LiteralPath (Join-Path $PublicDistRoot 'config\safety_manifest.json') | ConvertFrom-Json
Assert-Capabilities $devManifest.permission_modes.PUBLIC_DEFAULT 'developer PUBLIC_DEFAULT'
Assert-Capabilities $devManifest.permission_modes.DEVELOPER_CAPABILITY_DISCOVERY 'developer profile'
Assert-Capabilities $releaseManifest.permission_modes.PUBLIC_DEFAULT 'release PUBLIC_DEFAULT'
Assert-Capabilities $distManifest.permission_modes.PUBLIC_DEFAULT 'public-dist PUBLIC_DEFAULT'
if ($devManifest.default_permission_mode -ne 'DEVELOPER_CAPABILITY_DISCOVERY') { Fail 'Developer default permission mode was tightened.' }
if ($releaseManifest.default_permission_mode -ne 'PUBLIC_DEFAULT') { Fail 'Release default permission mode must be PUBLIC_DEFAULT.' }
if ($distManifest.default_permission_mode -ne 'PUBLIC_DEFAULT') { Fail 'Public dist default permission mode must be PUBLIC_DEFAULT.' }

foreach ($report in @(
    'source_release_sync_selftest_report.md',
    'public_dist_sync_selftest_report.md',
    'public_permission_alignment_selftest_report.md',
    'permission_profile_separation_selftest_report.md',
    'agent_compact_output_policy_selftest_report.md',
    'skill_public_permission_and_efficiency_selftest_report.md'
)) {
    $path = Join-Path $OutDir $report
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Fail "Required evidence report missing: $report" }
    $text = Get-Content -Raw -LiteralPath $path
    if ($text -notmatch 'Result: PASS') { Fail "Evidence report is not PASS: $report" }
}

if (Get-ChildItem -LiteralPath $ReleaseRoot -Recurse -Force -File -Filter '*.zip' -ErrorAction SilentlyContinue) { Fail 'Release packaging zip must not be generated.' }
if (Get-ChildItem -LiteralPath $PublicDistRoot -Recurse -Force -File -Filter '*.zip' -ErrorAction SilentlyContinue) { Fail 'Public dist packaging zip must not be generated.' }
if (Test-Path -LiteralPath (Join-Path $PublicDistRoot 'src')) { Fail 'Public dist must not contain src.' }

$lines = @(
    '# Release Sync Readiness Selftest',
    '',
    '- Result: PASS',
    "- Developer root: $Root",
    "- Release root: $ReleaseRoot",
    "- Public dist root: $PublicDistRoot",
    '- Developer VERSION: 1.1.0',
    '- Source release VERSION: 1.1.0',
    '- Public dist VERSION: 1.1.0',
    '- Public permission policy: defined and tested',
    '- Developer profile: not tightened',
    '- Source release sync: PASS',
    '- Public dist sync: PASS',
    '- GitHub operation: not performed',
    '- Release zip/package: not generated'
)
$lines | Set-Content -LiteralPath $ReportPath -Encoding UTF8
Write-Host 'release_sync_readiness_selftest PASS'
Write-Host "Report: $ReportPath"
