param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$TestRepoRoot = & (Join-Path $Root 'scripts\Resolve-TestRepoRoot.ps1') -Root $Root
$TestWindowRoot = Join-Path $TestRepoRoot 'testwindow'
$TestWindowExe = Join-Path $TestWindowRoot 'bin\TestWindow.exe'
$ProfilesRoot = Join-Path $Root 'profiles'
$Artifacts = Join-Path $Root 'artifacts\dev4.5.0'
$SelftestReport = Join-Path $Artifacts 'app_profile_selftest_report.md'
$InvalidProfile = Join-Path $Artifacts 'invalid_missing_fields.profile.json'

function Fail($Message) { throw $Message }

function Invoke-WinAgentJson {
    param([string[]]$WinArgs, [int[]]$AllowedExitCodes = @(0))
    $output = & $WinAgent @WinArgs 2>&1
    $exit = $LASTEXITCODE
    if ($AllowedExitCodes -notcontains $exit) {
        Fail "winagent $($WinArgs -join ' ') exited $exit with output: $output"
    }
    try {
        $json = $output | ConvertFrom-Json
    } catch {
        Fail "Invalid JSON from winagent $($WinArgs -join ' '): $output"
    }
    return @{ exit = $exit; text = [string]$output; json = $json }
}

if (!(Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run $Root\build.ps1 first." }
if (!(Test-Path -LiteralPath $TestWindowExe)) { Fail "Missing $TestWindowExe. Run $Root\build.ps1 first." }
if (!(Test-Path -LiteralPath $ProfilesRoot)) { Fail "Missing profiles root: $ProfilesRoot" }

New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null
Remove-Item -LiteralPath $SelftestReport -ErrorAction SilentlyContinue

Get-ChildItem -LiteralPath $ProfilesRoot -Filter '*.profile.json' | ForEach-Object {
    Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json | Out-Null
}

$ProfileReport = Invoke-WinAgentJson -WinArgs @('profile-report')
if ($ProfileReport.json.data.loaded_count -lt 6) { Fail "Expected at least 6 built-in profiles: $($ProfileReport.text)" }
if ($ProfileReport.json.data.invalid_count -ne 0) { Fail "Built-in profiles must be valid: $($ProfileReport.text)" }
$profileNames = @($ProfileReport.json.data.profiles | ForEach-Object { $_.profile_name })
if ($profileNames -notcontains 'testwindow') { Fail "testwindow profile missing: $($ProfileReport.text)" }
$testProfile = @($ProfileReport.json.data.profiles | Where-Object { $_.profile_name -eq 'testwindow' })[0]
if ($testProfile.effective_capabilities.can_override_safety_manifest -ne $false) {
    Fail "Profile report must state profiles cannot override Safety Manifest: $($ProfileReport.text)"
}
if ($testProfile.common_locator_count -lt 1) { Fail "testwindow profile must expose common locators: $($ProfileReport.text)" }

'{"profile_name":"broken","version":"4.5.0"}' | Set-Content -Encoding UTF8 -LiteralPath $InvalidProfile
$invalidReport = Invoke-WinAgentJson -WinArgs @('profile-report', '--path', $InvalidProfile)
if ($invalidReport.json.data.invalid_count -ne 1) { Fail "Invalid profile must be reported without crashing: $($invalidReport.text)" }
if ($invalidReport.json.data.loaded_count -ne 0) { Fail "Invalid single profile should not load: $($invalidReport.text)" }

$tw = $null
try {
    $tw = Start-Process -FilePath $TestWindowExe -PassThru
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 250
        $find = Invoke-WinAgentJson -WinArgs @('find', '--title', 'Agent Test Window') -AllowedExitCodes @(0, 1)
    } while ($find.exit -ne 0 -and (Get-Date) -lt $deadline)
    if ($find.exit -ne 0) { Fail 'Agent Test Window did not appear.' }

    $located = Invoke-WinAgentJson -WinArgs @('locate', '--title', 'Agent Test Window', '--profile', 'testwindow', '--profile-locator', 'click_button')
    if ($located.json.data.profile_candidate.source -ne 'app_profile') { Fail "Missing app_profile candidate: $($located.text)" }
    if ($located.json.data.profile_candidate.selector -ne 'uia:name=Click Me,type=Button') { Fail "Unexpected profile selector: $($located.text)" }
    if ($located.json.data.profile_candidate.action_gate -ne 'requires_runtime_safety_policy') { Fail "Profile locator must keep runtime safety gate: $($located.text)" }

    $blocked = Invoke-WinAgentJson -WinArgs @('act', '--title', 'Agent Test Window', '--selector', 'visual:id=image_template:0', '--action', 'click') -AllowedExitCodes @(1)
    if ($blocked.json.error.code -ne 'ACTION_BLOCKED_SEMANTIC_UNRESOLVED') {
        Fail "visual-only unresolved action was not blocked: $($blocked.text)"
    }
} finally {
    if ($tw -and !$tw.HasExited) {
        $tw.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (!$tw.HasExited) { Stop-Process -Id $tw.Id -Force }
    }
}

@(
    '# DesktopVisual App Profile Selftest',
    '',
    '- Result: PASS',
    '- Built-in profile JSON parse: PASS',
    "- Built-in profile load count: $($ProfileReport.json.data.loaded_count)",
    '- Invalid profile graceful failure: PASS',
    '- TestWindow profile locator integration: PASS',
    '- Profile safety boundary: can_override_safety_manifest=false',
    '- Visual-only unresolved ActionExecutor gate: ACTION_BLOCKED_SEMANTIC_UNRESOLVED'
) | Set-Content -Encoding UTF8 -LiteralPath $SelftestReport

Write-Host 'app profile selftest passed.'
Write-Host "Report: $SelftestReport"
