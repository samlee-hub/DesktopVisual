param(
    [switch]$Help,
    [string]$Root = '',
    [string]$Version = ''
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\verify_release.ps1 [-Root <path>] [-Version <version>]'
    Write-Host 'Verifies the release package for the requested or current VERSION.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
if (!$Version) {
    $Version = (Get-Content -LiteralPath (Join-Path $Root 'VERSION') -Raw).Trim()
}

$Dist = Join-Path (Join-Path $Root 'dist') "DesktopVisual-v$Version"
$Failures = New-Object System.Collections.Generic.List[string]

function Add-Failure([string]$Message) {
    $Failures.Add($Message) | Out-Null
}

function Test-RequiredPath([string]$Path, [string]$Label) {
    if (!(Test-Path -LiteralPath $Path)) {
        Add-Failure "Missing $Label`: $Path"
    }
}

Test-RequiredPath $Dist 'dist directory'

$requiredDirs = @(
    'bin',
    'cases',
    'tasks',
    'docs',
    'adapters',
    'benchmarks',
    'skill_template',
    'config',
    'scripts',
    'assets'
)
foreach ($dir in $requiredDirs) {
    Test-RequiredPath (Join-Path $Dist $dir) $dir
}

$requiredFiles = @(
    'README.md',
    'COMMAND_PROTOCOL.md',
    'CHANGELOG.md',
    'RELEASE_NOTES_v1.0.md',
    'RELEASE_NOTES_v3.0.1.md',
    'RELEASE_NOTES_v3.0.2.md',
    'RELEASE_NOTES_v3.0.3.md',
    'RELEASE_NOTES_v3.0.4.md',
    'RELEASE_NOTES_v3.0.5.md',
    'VERSION',
    'build.ps1',
    'script_lint.ps1',
    'package_source.ps1',
    'public_repo_check.ps1',
    'clean_artifacts.ps1',
    'portable_root_selftest.ps1',
    'adapter_selftest.ps1',
    'benchmark_matrix.ps1',
    'benchmark_selftest.ps1',
    'export_evidence_pack.ps1',
    'selftest.ps1',
    'release.ps1',
    'verify_release.ps1',
    'rc_check.ps1',
    'run_demo.ps1',
    'run_dogfood.ps1',
    'run_uia_demo.ps1',
    'run_ocr_demo.ps1',
    'run_image_demo.ps1',
    'run_real_dev_workflow.ps1',
    'safety_selftest.ps1',
    'safety_manifest_selftest.ps1',
    'focus_selftest.ps1',
    'read_path_selftest.ps1',
    'input_primitives_selftest.ps1',
    'motion_selftest.ps1',
    'motion_profile_selftest.ps1',
    'motion_profile_demo.ps1',
    'motion_calibration_session.ps1',
    'motion_human_profile_check.ps1',
    'observe_selftest.ps1',
    'selector_selftest.ps1',
    'uia_selftest.ps1'
)
foreach ($file in $requiredFiles) {
    Test-RequiredPath (Join-Path $Dist $file) $file
}

$requiredDocs = @(
    'ARCHITECTURE.md',
    'CASE_FORMAT.md',
    'ERROR_CODES.md',
    'KNOWN_LIMITATIONS.md',
    'REAL_DEV_WORKFLOW.md',
    'RECOVERY_DRAFT.md',
    'ROADMAP.md',
    'SAFETY.md',
    'SKILL_INSTALLATION.md',
    'SKILL_INTEGRATION_PLAN.md',
    'REPOSITORY_HYGIENE.md',
    'AGENT_ADAPTERS.md',
    'BENCHMARK_METHODOLOGY.md',
    'SAFETY_MODEL.md',
    'AGENT_USAGE_GUIDE.md',
    'VISUAL_SAFETY_FREEZE.md'
)
foreach ($doc in $requiredDocs) {
    Test-RequiredPath (Join-Path (Join-Path $Dist 'docs') $doc) "docs\$doc"
}

Test-RequiredPath (Join-Path (Join-Path $Dist 'config') 'safety_manifest.json') 'config\safety_manifest.json'

$requiredCases = @(
    'basic_click.case',
    'visible_action.case',
    'uia_action.case',
    'skill_basic.case',
    'failure_window_not_found.case',
    'failure_invalid_click.case',
    'failure_assert.case',
    'real_dev_workflow.template.case'
)
foreach ($case in $requiredCases) {
    Test-RequiredPath (Join-Path (Join-Path $Dist 'cases') $case) "cases\$case"
}

$skillRoot = Join-Path $Dist 'skill_template\win-desktop-agent'
$requiredSkillFiles = @(
    'SKILL.md',
    'references\COMMAND_PROTOCOL.md',
    'references\ERROR_CODES.md',
    'references\SAFETY.md',
    'references\CASE_FORMAT.md',
    'references\VISUAL_SAFETY_FREEZE.md',
    'scripts\run-basic-demo.ps1',
    'scripts\run-visible-demo.ps1',
    'scripts\run-skill-basic.ps1',
    'scripts\run-case.ps1',
    'scripts\read-latest-report.ps1',
    'scripts\explain-report.ps1',
    'scripts\run-failure-demo.ps1',
    'scripts\selftest-skill-template.ps1'
)
foreach ($relative in $requiredSkillFiles) {
    Test-RequiredPath (Join-Path $skillRoot $relative) "skill_template\win-desktop-agent\$relative"
}

Test-RequiredPath (Join-Path $Dist 'adapters\codex\win-desktop-agent\SKILL.md') 'adapters\codex\win-desktop-agent\SKILL.md'
Test-RequiredPath (Join-Path $Dist 'adapters\claude-code\DESKTOPVISUAL.md') 'adapters\claude-code\DESKTOPVISUAL.md'
Test-RequiredPath (Join-Path $Dist 'adapters\generic-cli\desktopvisual-agent-contract.md') 'adapters\generic-cli\desktopvisual-agent-contract.md'
Test-RequiredPath (Join-Path $Dist 'adapters\shared\TASK_FLOW.md') 'adapters\shared\TASK_FLOW.md'
Test-RequiredPath (Join-Path $Dist 'benchmarks\README.md') 'benchmarks\README.md'
Test-RequiredPath (Join-Path $Dist 'benchmarks\tasks\testwindow_basic.task.json') 'benchmarks\tasks\testwindow_basic.task.json'

$winagent = Join-Path $Dist 'bin\winagent.exe'
Test-RequiredPath $winagent 'bin\winagent.exe'
if (Test-Path -LiteralPath $winagent) {
    try {
        $output = & $winagent version
        if ($LASTEXITCODE -ne 0) {
            Add-Failure "winagent.exe version exited $LASTEXITCODE"
        } else {
            $json = $output | ConvertFrom-Json
            if ($json.ok -ne $true -or $json.command -ne 'version') {
                Add-Failure 'winagent.exe version did not return a successful version envelope.'
            }
            if ($json.data.version -ne $Version) {
                Add-Failure "winagent.exe version reported $($json.data.version), expected $Version"
            }
        }
    } catch {
        Add-Failure "winagent.exe version failed: $($_.Exception.Message)"
    }
}

if ($Failures.Count -gt 0) {
    Write-Host 'FAIL: release verification failed.'
    foreach ($failure in $Failures) {
        Write-Host "- $failure"
    }
    exit 1
}

Write-Host "PASS: release verification passed for $Dist"
