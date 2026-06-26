param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\release.ps1 [-Root <path>]'
    Write-Host 'Builds, selftests, and creates dist\DesktopVisual-v<VERSION>.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$Version = (Get-Content (Join-Path $Root 'VERSION') -Raw).Trim()
$DistRoot = Join-Path $Root 'dist'
$Dist = Join-Path $DistRoot "DesktopVisual-v$Version"
$SkillTemplate = Join-Path $Root 'skill_template'

function Assert-PathExists($Path, $Message) {
    if (!(Test-Path -LiteralPath $Path)) {
        throw $Message
    }
}

Assert-PathExists (Join-Path $Root 'docs\SKILL_INSTALLATION.md') 'Missing docs\SKILL_INSTALLATION.md'
Assert-PathExists (Join-Path $Root 'docs\REPOSITORY_HYGIENE.md') 'Missing docs\REPOSITORY_HYGIENE.md'
Assert-PathExists (Join-Path $Root 'docs\AGENT_ADAPTERS.md') 'Missing docs\AGENT_ADAPTERS.md'
Assert-PathExists (Join-Path $Root 'docs\BENCHMARK_METHODOLOGY.md') 'Missing docs\BENCHMARK_METHODOLOGY.md'
Assert-PathExists (Join-Path $Root 'docs\SAFETY_MODEL.md') 'Missing docs\SAFETY_MODEL.md'
Assert-PathExists (Join-Path $Root 'docs\VISUAL_SAFETY_FREEZE.md') 'Missing docs\VISUAL_SAFETY_FREEZE.md'
Assert-PathExists (Join-Path $Root 'uia_selftest.ps1') 'Missing uia_selftest.ps1'
Assert-PathExists (Join-Path $Root 'run_uia_demo.ps1') 'Missing run_uia_demo.ps1'
Assert-PathExists (Join-Path $Root 'run_ocr_demo.ps1') 'Missing run_ocr_demo.ps1'
Assert-PathExists (Join-Path $Root 'run_image_demo.ps1') 'Missing run_image_demo.ps1'
Assert-PathExists (Join-Path $Root 'run_real_dev_workflow.ps1') 'Missing run_real_dev_workflow.ps1'
Assert-PathExists (Join-Path $Root 'docs\REAL_DEV_WORKFLOW.md') 'Missing docs\REAL_DEV_WORKFLOW.md'
Assert-PathExists (Join-Path $Root 'cases\real_dev_workflow.template.case') 'Missing cases\real_dev_workflow.template.case'
Assert-PathExists (Join-Path $Root 'config\safety.conf') 'Missing config\safety.conf'
Assert-PathExists (Join-Path $Root 'config\safety_manifest.json') 'Missing config\safety_manifest.json'
Assert-PathExists (Join-Path $Root 'safety_selftest.ps1') 'Missing safety_selftest.ps1'
Assert-PathExists (Join-Path $Root 'safety_manifest_selftest.ps1') 'Missing safety_manifest_selftest.ps1'
Assert-PathExists (Join-Path $Root 'focus_selftest.ps1') 'Missing focus_selftest.ps1'
Assert-PathExists (Join-Path $Root 'read_path_selftest.ps1') 'Missing read_path_selftest.ps1'
Assert-PathExists (Join-Path $Root 'input_primitives_selftest.ps1') 'Missing input_primitives_selftest.ps1'
Assert-PathExists (Join-Path $Root 'motion_selftest.ps1') 'Missing motion_selftest.ps1'
Assert-PathExists (Join-Path $Root 'motion_profile_selftest.ps1') 'Missing motion_profile_selftest.ps1'
Assert-PathExists (Join-Path $Root 'motion_profile_demo.ps1') 'Missing motion_profile_demo.ps1'
Assert-PathExists (Join-Path $Root 'motion_calibration_session.ps1') 'Missing motion_calibration_session.ps1'
Assert-PathExists (Join-Path $Root 'motion_human_profile_check.ps1') 'Missing motion_human_profile_check.ps1'
Assert-PathExists (Join-Path $Root 'portable_root_selftest.ps1') 'Missing portable_root_selftest.ps1'
Assert-PathExists (Join-Path $Root 'adapter_selftest.ps1') 'Missing adapter_selftest.ps1'
Assert-PathExists (Join-Path $Root 'benchmark_matrix.ps1') 'Missing benchmark_matrix.ps1'
Assert-PathExists (Join-Path $Root 'benchmark_selftest.ps1') 'Missing benchmark_selftest.ps1'
Assert-PathExists (Join-Path $Root 'export_evidence_pack.ps1') 'Missing export_evidence_pack.ps1'
Assert-PathExists (Join-Path $Root 'observe_selftest.ps1') 'Missing observe_selftest.ps1'
Assert-PathExists (Join-Path $Root 'selector_selftest.ps1') 'Missing selector_selftest.ps1'
Assert-PathExists (Join-Path $Root 'build.ps1') 'Missing build.ps1'
Assert-PathExists (Join-Path $Root 'script_lint.ps1') 'Missing script_lint.ps1'
Assert-PathExists (Join-Path $Root 'package_source.ps1') 'Missing package_source.ps1'
Assert-PathExists (Join-Path $Root 'public_repo_check.ps1') 'Missing public_repo_check.ps1'
Assert-PathExists (Join-Path $Root 'clean_artifacts.ps1') 'Missing clean_artifacts.ps1'
Assert-PathExists (Join-Path $Root 'verify_release.ps1') 'Missing verify_release.ps1'
Assert-PathExists (Join-Path $Root 'rc_check.ps1') 'Missing rc_check.ps1'
Assert-PathExists (Join-Path $Root 'RELEASE_NOTES_v1.0.md') 'Missing RELEASE_NOTES_v1.0.md'
Assert-PathExists (Join-Path $Root 'RELEASE_NOTES_v3.0.1.md') 'Missing RELEASE_NOTES_v3.0.1.md'
Assert-PathExists (Join-Path $Root 'RELEASE_NOTES_v3.0.2.md') 'Missing RELEASE_NOTES_v3.0.2.md'
Assert-PathExists (Join-Path $Root 'RELEASE_NOTES_v3.0.3.md') 'Missing RELEASE_NOTES_v3.0.3.md'
Assert-PathExists (Join-Path $Root 'RELEASE_NOTES_v3.0.4.md') 'Missing RELEASE_NOTES_v3.0.4.md'
Assert-PathExists (Join-Path $Root 'RELEASE_NOTES_v3.0.5.md') 'Missing RELEASE_NOTES_v3.0.5.md'
Assert-PathExists (Join-Path $Root 'adapters\codex\win-desktop-agent\SKILL.md') 'Missing adapters\codex\win-desktop-agent\SKILL.md'
Assert-PathExists (Join-Path $Root 'adapters\claude-code\DESKTOPVISUAL.md') 'Missing adapters\claude-code\DESKTOPVISUAL.md'
Assert-PathExists (Join-Path $Root 'adapters\generic-cli\desktopvisual-agent-contract.md') 'Missing adapters\generic-cli\desktopvisual-agent-contract.md'
Assert-PathExists (Join-Path $Root 'benchmarks\README.md') 'Missing benchmarks\README.md'

$requiredSkillFiles = @(
    'win-desktop-agent\SKILL.md',
    'win-desktop-agent\references\COMMAND_PROTOCOL.md',
    'win-desktop-agent\references\ERROR_CODES.md',
    'win-desktop-agent\references\SAFETY.md',
    'win-desktop-agent\references\SAFETY_MODEL.md',
    'win-desktop-agent\references\CASE_FORMAT.md',
    'win-desktop-agent\references\VISUAL_SAFETY_FREEZE.md',
    'win-desktop-agent\scripts\run-basic-demo.ps1',
    'win-desktop-agent\scripts\run-visible-demo.ps1',
    'win-desktop-agent\scripts\run-skill-basic.ps1',
    'win-desktop-agent\scripts\run-case.ps1',
    'win-desktop-agent\scripts\read-latest-report.ps1',
    'win-desktop-agent\scripts\explain-report.ps1',
    'win-desktop-agent\scripts\run-failure-demo.ps1',
    'win-desktop-agent\scripts\selftest-skill-template.ps1'
)
foreach ($relative in $requiredSkillFiles) {
    Assert-PathExists (Join-Path $SkillTemplate $relative) "Missing Skill template file: skill_template\$relative"
}

Get-Process TestWindow -ErrorAction SilentlyContinue | ForEach-Object {
    $_.CloseMainWindow() | Out-Null
    Start-Sleep -Milliseconds 300
    if (!$_.HasExited) {
        Stop-Process -Id $_.Id -Force
    }
}

& (Join-Path $Root 'build.ps1') -Root $Root
& (Join-Path $Root 'script_lint.ps1') -Root $Root
& (Join-Path $Root 'selftest.ps1') -Root $Root

if (Test-Path $Dist) {
    Remove-Item -LiteralPath $Dist -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $Dist | Out-Null

Copy-Item -Path (Join-Path $Root 'bin') -Destination $Dist -Recurse
Copy-Item -Path (Join-Path $Root 'cases') -Destination $Dist -Recurse
Copy-Item -Path (Join-Path $Root 'tasks') -Destination $Dist -Recurse
Copy-Item -Path (Join-Path $Root 'docs') -Destination $Dist -Recurse
Copy-Item -Path (Join-Path $Root 'config') -Destination $Dist -Recurse
Copy-Item -Path (Join-Path $Root 'adapters') -Destination $Dist -Recurse
Copy-Item -Path (Join-Path $Root 'benchmarks') -Destination $Dist -Recurse
Copy-Item -Path (Join-Path $Root 'skill_template') -Destination $Dist -Recurse
Copy-Item -Path (Join-Path $Root 'scripts') -Destination $Dist -Recurse
if (Test-Path -LiteralPath (Join-Path $Root 'assets')) {
    Copy-Item -Path (Join-Path $Root 'assets') -Destination $Dist -Recurse
}

Copy-Item -Path (Join-Path $Root 'README.md') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'COMMAND_PROTOCOL.md') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'CHANGELOG.md') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'RELEASE_NOTES_v1.0.md') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'RELEASE_NOTES_v3.0.1.md') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'RELEASE_NOTES_v3.0.2.md') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'RELEASE_NOTES_v3.0.3.md') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'RELEASE_NOTES_v3.0.4.md') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'RELEASE_NOTES_v3.0.5.md') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'VERSION') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'run_demo.ps1') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'run_dogfood.ps1') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'uia_selftest.ps1') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'run_uia_demo.ps1') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'run_ocr_demo.ps1') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'run_image_demo.ps1') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'run_real_dev_workflow.ps1') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'safety_selftest.ps1') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'safety_manifest_selftest.ps1') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'focus_selftest.ps1') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'read_path_selftest.ps1') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'input_primitives_selftest.ps1') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'motion_selftest.ps1') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'motion_profile_selftest.ps1') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'motion_profile_demo.ps1') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'motion_calibration_session.ps1') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'motion_human_profile_check.ps1') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'portable_root_selftest.ps1') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'adapter_selftest.ps1') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'benchmark_matrix.ps1') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'benchmark_selftest.ps1') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'export_evidence_pack.ps1') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'observe_selftest.ps1') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'selector_selftest.ps1') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'selftest.ps1') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'build.ps1') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'script_lint.ps1') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'package_source.ps1') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'public_repo_check.ps1') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'clean_artifacts.ps1') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'release.ps1') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'verify_release.ps1') -Destination $Dist
Copy-Item -Path (Join-Path $Root 'rc_check.ps1') -Destination $Dist

Write-Host "Release created: $Dist"
