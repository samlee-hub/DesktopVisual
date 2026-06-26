param(
    [string]$Root = '',
    [string]$PublicDistRoot = ''
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($PublicDistRoot)) { $PublicDistRoot = Join-Path (Split-Path -Parent $Root) 'desktopvisual-public-dist' }
$Root = [System.IO.Path]::GetFullPath($Root)
$PublicDistRoot = [System.IO.Path]::GetFullPath($PublicDistRoot)
$env:DESKTOPVISUAL_ROOT = $PublicDistRoot

$OutDir = Join-Path $Root 'artifacts\dev1.1.0_public_permission_agent_efficiency'
$ReportPath = Join-Path $OutDir 'public_dist_sync_selftest_report.md'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Fail($Message) { throw $Message }

function Test-IsGitRepo {
    param([string]$Path)
    $inside = & git -C $Path rev-parse --is-inside-work-tree 2>$null
    return ($LASTEXITCODE -eq 0 -and $inside -eq 'true')
}

function Assert-Capabilities {
    param($Profile, [string]$Name)
    foreach ($capability in @('third_party_apps','external_web','communication','content_decision','cross_window','global_desktop','browser','explorer','local_file_open','localhost')) {
        if ($Profile.$capability -ne $true) { Fail "$Name must allow $capability." }
    }
    if ($Profile.requires_full_access_session -ne $false) { Fail "$Name must not require FULL_ACCESS session." }
}

function Remove-SmokeArtifacts {
    $target = Join-Path $PublicDistRoot 'artifacts'
    if (Test-Path -LiteralPath $target) {
        $resolvedRoot = [System.IO.Path]::GetFullPath($PublicDistRoot)
        $resolvedTarget = [System.IO.Path]::GetFullPath($target)
        if (-not $resolvedTarget.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            Fail "Refusing cleanup outside public-dist root: $resolvedTarget"
        }
        Remove-Item -LiteralPath $resolvedTarget -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-ChecksumManifest {
    $checksumPath = Join-Path $PublicDistRoot 'checksums\sha256.txt'
    if (-not (Test-Path -LiteralPath $checksumPath -PathType Leaf)) { Fail 'checksums\sha256.txt missing.' }
    $lines = Get-Content -LiteralPath $checksumPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if ($lines.Count -eq 0) { Fail 'checksums\sha256.txt is empty.' }
    foreach ($line in $lines) {
        if ($line -notmatch '^([A-Fa-f0-9]{64})  (.+)$') { Fail "Invalid checksum line: $line" }
        $expected = $Matches[1].ToLowerInvariant()
        $relative = $Matches[2]
        if ($relative -like 'checksums/*') { continue }
        $path = Join-Path $PublicDistRoot ($relative -replace '/', '\')
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Fail "Checksum target missing: $relative" }
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        if ($actual -ne $expected) { Fail "Checksum mismatch for $relative" }
    }
}

if (-not (Test-Path -LiteralPath $PublicDistRoot -PathType Container)) { Fail "Public dist root missing: $PublicDistRoot" }
$version = (Get-Content -Raw -LiteralPath (Join-Path $PublicDistRoot 'VERSION')).Trim()
if ($version -ne '1.1.0') { Fail "Public dist VERSION must be 1.1.0, got $version" }
if (-not (Test-Path -LiteralPath (Join-Path $PublicDistRoot 'bin\winagent.exe') -PathType Leaf)) { Fail 'bin\winagent.exe missing.' }
foreach ($required in @('README.md','COMMAND_PROTOCOL.md','config\safety_manifest.json','manifest\public_dist_manifest.json','checksums\sha256.txt')) {
    if (-not (Test-Path -LiteralPath (Join-Path $PublicDistRoot $required) -PathType Leaf)) { Fail "Public dist required file missing: $required" }
}
if (-not (Test-Path -LiteralPath (Join-Path $PublicDistRoot 'skills\win-desktop-agent\SKILL.md') -PathType Leaf)) { Fail 'Public Skill missing.' }

$manifest = Get-Content -Raw -LiteralPath (Join-Path $PublicDistRoot 'config\safety_manifest.json') | ConvertFrom-Json
Assert-Capabilities $manifest.permission_modes.PUBLIC_DEFAULT 'Public dist PUBLIC_DEFAULT'
if ($manifest.report_policy.report_level -ne 'compact' -or $manifest.report_policy.evidence_level -ne 'full') { Fail 'Public dist report policy must be compact/full.' }

foreach ($forbidden in @('src','artifacts','obj','dist','tools','internal_tests')) {
    if (Test-Path -LiteralPath (Join-Path $PublicDistRoot $forbidden)) { Fail "Forbidden public-dist directory exists: $forbidden" }
}
$isGitRepo = Test-IsGitRepo $PublicDistRoot
if ((Test-Path -LiteralPath (Join-Path $PublicDistRoot '.git')) -and -not $isGitRepo) {
    Fail 'Public-dist .git exists but is not an independent git repository.'
}
$forbiddenFiles = Get-ChildItem -LiteralPath $PublicDistRoot -Recurse -Force -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\.git\\' -and $_.Name -match '\.(obj|pdb|ilk|ipch|tmp|bak|old|png|bmp|jpg|jpeg)$' }
if ($forbiddenFiles.Count -gt 0) { Fail "Forbidden generated file in public dist: $($forbiddenFiles[0].FullName)" }

Test-ChecksumManifest

$WinAgent = Join-Path $PublicDistRoot 'bin\winagent.exe'
$versionOutput = & $WinAgent version 2>&1 | ConvertFrom-Json
if (-not $versionOutput.ok -or $versionOutput.data.version -ne '1.1.0') { Fail 'public smoke version failed.' }
$ordinary = & $WinAgent policy-check --title 'Ordinary HTTPS Page' --process 'msedge.exe' --action 'browser_navigate' --permission-mode 'PUBLIC_DEFAULT' 2>&1 | ConvertFrom-Json
if (-not $ordinary.ok -or -not $ordinary.data.allow) { Fail 'public smoke ordinary browser action failed.' }
$stop = & $WinAgent policy-check --title 'captcha human verification' --process 'chrome.exe' --action 'mouse.click' --permission-mode 'PUBLIC_DEFAULT' 2>&1 | ConvertFrom-Json
if ($stop.ok -or $stop.error.code -ne 'STOP_ACTIVE_PROTECTION') { Fail 'public smoke active protection stop failed.' }
Remove-SmokeArtifacts

$lines = @(
    '# Public Dist Sync Selftest',
    '',
    '- Result: PASS',
    "- Developer root: $Root",
    "- Public dist root: $PublicDistRoot",
    '- VERSION: 1.1.0',
    '- bin/winagent.exe: present',
    '- Public docs/config/Skill: present',
    '- Public permission policy: aligned',
    '- Source leakage: absent',
    '- Generated cache/artifacts: absent',
    "- Public dist git repo: $isGitRepo",
    '- checksums: matched',
    '- public smoke test: PASS'
)
$lines | Set-Content -LiteralPath $ReportPath -Encoding UTF8
Write-Host 'public_dist_sync_selftest PASS'
Write-Host "Report: $ReportPath"
