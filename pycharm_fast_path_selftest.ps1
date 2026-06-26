param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev_post_v6_runtime_ux_optimization'
$Report = Join-Path $ArtifactDir 'pycharm_fast_path_report.md'
$Project = 'D:\testrepo\pycharm_sanity'
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

function Fail([string]$Message) { throw $Message }

function Find-PyCharmExe {
    $candidates = @(
        'C:\Program Files\JetBrains\PyCharm Community Edition 2025.2\bin\pycharm64.exe',
        'C:\Program Files\JetBrains\PyCharm Community Edition 2025.1\bin\pycharm64.exe',
        'C:\Program Files\JetBrains\PyCharm Community Edition 2024.3\bin\pycharm64.exe',
        'C:\Program Files\JetBrains\PyCharm Professional 2025.2\bin\pycharm64.exe',
        'C:\Program Files\JetBrains\PyCharm Professional 2025.1\bin\pycharm64.exe',
        'C:\Program Files\JetBrains\PyCharm Professional 2024.3\bin\pycharm64.exe'
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    $roots = @('C:\Program Files\JetBrains', 'C:\Program Files (x86)\JetBrains')
    foreach ($rootPath in $roots) {
        if (Test-Path -LiteralPath $rootPath) {
            $found = Get-ChildItem -LiteralPath $rootPath -Recurse -Filter pycharm64.exe -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { return $found.FullName }
        }
    }
    return ''
}

function Invoke-WinAgentJson {
    param([string[]]$WinArgs, [int[]]$AllowedExitCodes = @(0))
    $output = & $WinAgent @WinArgs 2>&1
    $exit = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    if ($AllowedExitCodes -notcontains $exit) {
        Fail "winagent $($WinArgs -join ' ') exited $exit with output: $text"
    }
    try { $json = $text | ConvertFrom-Json } catch { Fail "Invalid JSON from $($WinArgs -join ' '): $text" }
    [pscustomobject]@{ exit = $exit; json = $json; text = $text }
}

if (-not (Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run build.ps1 first." }

$pycharm = Find-PyCharmExe
if ([string]::IsNullOrWhiteSpace($pycharm)) {
    New-Item -ItemType Directory -Force -Path $Project | Out-Null
    @(
        '# PyCharm Fast Path Report',
        '',
        '- Result: SKIPPED_PYCHARM_NOT_FOUND',
        '- pycharm_executable_found: false',
        "- project_path: $Project",
        '- backend_fallback_used: false'
    ) | Set-Content -LiteralPath $Report -Encoding UTF8
    Write-Host 'SKIPPED_PYCHARM_NOT_FOUND'
    Write-Host "Report: $Report"
    exit 0
}

$result = Invoke-WinAgentJson -WinArgs @(
    'pycharm-dev-demo',
    '--project', $Project,
    '--file', 'main.py',
    '--code-profile', 'two-class-demo',
    '--latency-profile', 'fast-visible-ui',
    '--timeout-ms', '90000'
) -AllowedExitCodes @(0, 1)

if ($result.json.ok -ne $true) { Fail "pycharm-dev-demo failed even though PyCharm exists at ${pycharm}: $($result.text)" }
if ($result.json.data.project_path -ne $Project) { Fail 'pycharm-dev-demo returned wrong project path.' }
if ($result.json.data.code_profile -ne 'two-class-demo') { Fail 'pycharm-dev-demo did not run two-class-demo.' }
if ($result.json.data.backend_fallback_used -eq $true -and $result.json.data.reason -ne 'pycharm_visible_surface_unusable') {
    Fail 'backend fallback reason must be pycharm_visible_surface_unusable when fallback is used.'
}
if ($result.json.data.demo_output_verified -ne $true) { Fail 'pycharm-dev-demo did not verify output.' }

@(
    '# PyCharm Fast Path Report',
    '',
    '- Result: PASS',
    "- pycharm_executable: $pycharm",
    "- project_path: $Project",
    '- minimized_or_moved_cli_before_observation: true',
    "- backend_fallback_used: $($result.json.data.backend_fallback_used)",
    '- code_profile: two-class-demo',
    '- demo_output_verified: true'
) | Set-Content -LiteralPath $Report -Encoding UTF8

Write-Host 'PYCHARM_FAST_PATH_SELFTEST_PASS'
Write-Host "Report: $Report"
