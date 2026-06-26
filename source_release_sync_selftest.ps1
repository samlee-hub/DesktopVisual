param(
    [string]$Root = '',
    [string]$ReleaseRoot = '',
    [string]$TestRepoRoot = ''
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ReleaseRoot)) { $ReleaseRoot = Join-Path (Split-Path -Parent $Root) 'desktopvisual-release' }
if ([string]::IsNullOrWhiteSpace($TestRepoRoot)) { $TestRepoRoot = Join-Path (Split-Path -Parent $Root) 'testrepo' }
$Root = [System.IO.Path]::GetFullPath($Root)
$ReleaseRoot = [System.IO.Path]::GetFullPath($ReleaseRoot)
$TestRepoRoot = [System.IO.Path]::GetFullPath($TestRepoRoot)
$env:DESKTOPVISUAL_ROOT = $ReleaseRoot

$OutDir = Join-Path $Root 'artifacts\dev1.1.0_public_permission_agent_efficiency'
$ReportPath = Join-Path $OutDir 'source_release_sync_selftest_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Fail($Message) { throw $Message }

function Test-IsGitRepo {
    param([string]$Path)
    $inside = & git -C $Path rev-parse --is-inside-work-tree 2>$null
    return ($LASTEXITCODE -eq 0 -and $inside -eq 'true')
}

function Assert-Path {
    param([string]$Relative, [string]$Kind)
    $path = Join-Path $ReleaseRoot $Relative
    if ($Kind -eq 'Container') {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { Fail "Missing directory in release: $Relative" }
    } else {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Fail "Missing file in release: $Relative" }
    }
}

function Assert-Capabilities {
    param($Profile, [string]$Name)
    foreach ($capability in @('third_party_apps','external_web','communication','content_decision','cross_window','global_desktop','browser','explorer','local_file_open','localhost')) {
        if ($Profile.$capability -ne $true) { Fail "$Name must allow $capability." }
    }
    if ($Profile.requires_full_access_session -ne $false) { Fail "$Name must not require FULL_ACCESS session." }
}

function Remove-ReleaseGeneratedOutput {
    $resolvedRelease = [System.IO.Path]::GetFullPath($ReleaseRoot)
    foreach ($relative in @('bin','artifacts','obj','.vs','dist')) {
        $target = Join-Path $ReleaseRoot $relative
        if (Test-Path -LiteralPath $target) {
            $resolvedTarget = [System.IO.Path]::GetFullPath($target)
            if (-not $resolvedTarget.StartsWith($resolvedRelease, [System.StringComparison]::OrdinalIgnoreCase)) {
                Fail "Refusing cleanup outside release root: $resolvedTarget"
            }
            Remove-Item -LiteralPath $resolvedTarget -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

if (-not (Test-Path -LiteralPath $ReleaseRoot -PathType Container)) { Fail "Release root missing: $ReleaseRoot" }

$version = (Get-Content -Raw -LiteralPath (Join-Path $ReleaseRoot 'VERSION')).Trim()
if ($version -ne '1.1.0') { Fail "Release VERSION must be 1.1.0, got $version" }

foreach ($dir in @('src','docs','config','skill_template','adapters','tasks','cases','scripts')) {
    Assert-Path $dir 'Container'
}
foreach ($file in @('README.md','CHANGELOG.md','COMMAND_PROTOCOL.md','AGENTS.md','build.ps1','script_lint.ps1','public_permission_alignment_selftest.ps1','permission_profile_separation_selftest.ps1','agent_compact_output_policy_selftest.ps1','skill_public_permission_and_efficiency_selftest.ps1')) {
    Assert-Path $file 'Leaf'
}

$manifestPath = Join-Path $ReleaseRoot 'config\safety_manifest.json'
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($manifest.default_permission_mode -ne 'PUBLIC_DEFAULT') { Fail 'Release default_permission_mode must be PUBLIC_DEFAULT.' }
Assert-Capabilities $manifest.permission_modes.PUBLIC_DEFAULT 'Release PUBLIC_DEFAULT'
Assert-Capabilities $manifest.permission_modes.DEVELOPER_CAPABILITY_DISCOVERY 'Release developer profile'
if ($manifest.report_policy.report_level -ne 'compact' -or $manifest.report_policy.evidence_level -ne 'full') { Fail 'Release report policy must be compact/full.' }

$isGitRepo = Test-IsGitRepo $ReleaseRoot
if ((Test-Path -LiteralPath (Join-Path $ReleaseRoot '.git')) -and -not $isGitRepo) {
    Fail 'Release .git exists but is not an independent git repository.'
}

foreach ($forbidden in @('artifacts','bin','obj','dist','desktopvisual-public-dist')) {
    if (Test-Path -LiteralPath (Join-Path $ReleaseRoot $forbidden)) { Fail "Forbidden release generated directory exists: $forbidden" }
}
$forbiddenFiles = Get-ChildItem -LiteralPath $ReleaseRoot -Recurse -Force -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\.git\\' -and $_.Name -match '\.(obj|pdb|ilk|ipch|tmp|bak|old|zip|7z|png|bmp|jpg|jpeg)$' }
if ($forbiddenFiles.Count -gt 0) { Fail "Forbidden generated files in release: $($forbiddenFiles[0].FullName)" }

& powershell -ExecutionPolicy Bypass -File (Join-Path $ReleaseRoot 'script_lint.ps1') -Root $ReleaseRoot -TestRepoRoot $TestRepoRoot -DryRun
if ($LASTEXITCODE -ne 0) { Fail 'script_lint failed in release tree.' }

& powershell -ExecutionPolicy Bypass -File (Join-Path $ReleaseRoot 'build.ps1') -Root $ReleaseRoot -TestRepoRoot $TestRepoRoot
if ($LASTEXITCODE -ne 0) { Fail 'build failed in release tree.' }
Remove-ReleaseGeneratedOutput

$lines = @(
    '# Source Release Sync Selftest',
    '',
    '- Result: PASS',
    "- Developer root: $Root",
    "- Release root: $ReleaseRoot",
    '- VERSION: 1.1.0',
    '- Source/docs/config/Skill/adapters/tests: present',
    '- Public permission policy: aligned',
    '- Developer runtime cache: absent',
    "- Release git repo: $isGitRepo",
    '- script_lint: PASS',
    '- build: PASS, generated output cleaned'
)
$lines | Set-Content -LiteralPath $ReportPath -Encoding UTF8
Write-Host 'source_release_sync_selftest PASS'
Write-Host "Report: $ReportPath"
