param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ManifestPath = Join-Path $Root 'config\safety_manifest.json'
$OutDir = Join-Path $Root 'artifacts\dev1.1.0_public_permission_agent_efficiency'
$ReportPath = Join-Path $OutDir 'permission_profile_separation_selftest_report.md'

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Fail($Message) { throw $Message }

function Invoke-AgentJson {
    param([string[]]$CmdArgs)
    $output = & $WinAgent @CmdArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        Fail "winagent $($CmdArgs -join ' ') exited $LASTEXITCODE with output: $output"
    }
    try {
        return ($output | ConvertFrom-Json)
    } catch {
        Fail "Invalid JSON from winagent $($CmdArgs -join ' '): $output"
    }
}

function Test-AllCapabilitiesTrue {
    param($Profile, [string]$Name)
    foreach ($capability in @(
        'third_party_apps',
        'external_web',
        'communication',
        'content_decision',
        'cross_window',
        'global_desktop',
        'browser',
        'explorer',
        'local_file_open',
        'localhost'
    )) {
        if ($Profile.$capability -ne $true) {
            Fail "$Name must keep $capability=true."
        }
    }
    if ($Profile.requires_full_access_session -ne $false) {
        Fail "$Name must not require a full access session for ordinary visible operations."
    }
}

if (-not (Test-Path -LiteralPath $WinAgent)) { Fail "winagent.exe missing: $WinAgent" }
$manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json

Test-AllCapabilitiesTrue $manifest.permission_modes.DEVELOPER_CAPABILITY_DISCOVERY 'DEVELOPER_CAPABILITY_DISCOVERY'
Test-AllCapabilitiesTrue $manifest.permission_modes.DEVELOPER_FULL_RUNTIME 'DEVELOPER_FULL_RUNTIME'
Test-AllCapabilitiesTrue $manifest.permission_modes.PUBLIC_DEFAULT 'PUBLIC_DEFAULT'

$stopTriggers = @($manifest.active_protection.signals)
if ($stopTriggers.Count -lt 10) {
    Fail 'PUBLIC_DEFAULT STOP triggers must remain populated through active_protection.signals.'
}

$status = Invoke-AgentJson -CmdArgs @('permission-status')
if (-not $status.ok) { Fail 'permission-status returned ok=false.' }
if ($status.data.permission_mode -ne 'DEVELOPER_CAPABILITY_DISCOVERY') {
    Fail 'permission-status default permission_mode must remain DEVELOPER_CAPABILITY_DISCOVERY.'
}
if ($status.data.active_profile -ne 'DEVELOPER_CAPABILITY_DISCOVERY') {
    Fail 'permission-status must output active_profile=DEVELOPER_CAPABILITY_DISCOVERY.'
}
Test-AllCapabilitiesTrue $status.data.developer_profile 'permission-status developer_profile'
Test-AllCapabilitiesTrue $status.data.public_default_profile 'permission-status public_default_profile'

$report = Invoke-AgentJson -CmdArgs @('safety-report')
if (-not $report.ok) { Fail 'safety-report returned ok=false.' }
if ($null -eq $report.data.public_developer_profile_difference) {
    Fail 'safety-report must include public_developer_profile_difference.'
}
if ($report.data.public_developer_profile_difference.ordinary_visible_capabilities_aligned -ne $true) {
    Fail 'safety-report must summarize public/developer ordinary capability alignment.'
}
if (-not $report.data.public_developer_profile_difference.stop_triggers_preserved) {
    Fail 'safety-report must summarize preserved STOP triggers.'
}

$lines = @(
    '# Permission Profile Separation Selftest',
    '',
    '- Result: PASS',
    "- Root: $Root",
    '- Developer profile capability: v1.0.5-compatible',
    '- Public profile ordinary visible capability: aligned',
    '- Public STOP triggers: populated',
    '- permission-status active_profile: present',
    '- safety-report public/developer difference summary: present'
)
$lines | Set-Content -LiteralPath $ReportPath -Encoding UTF8

Write-Host 'permission_profile_separation_selftest PASS'
Write-Host "Report: $ReportPath"
