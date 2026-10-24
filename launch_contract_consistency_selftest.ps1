param()

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root

$ArtifactDir = Join-Path $Root "artifacts\dev1.2.0_brace_safe_selftest"
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

$Failures = New-Object System.Collections.Generic.List[string]
$Report = New-Object System.Collections.Generic.List[string]

function Add-Failure {
    param([string]$Message)
    $script:Failures.Add($Message) | Out-Null
    $script:Report.Add("- FAIL: $Message") | Out-Null
    Write-Host "[FAIL] $Message"
}

function Add-Pass {
    param([string]$Message)
    $script:Report.Add("- PASS: $Message") | Out-Null
    Write-Host "[PASS] $Message"
}

function Read-Text {
    param([string]$Path)
    return Get-Content -Raw -LiteralPath (Join-Path $Root $Path)
}

function Assert-Contains {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$PassMessage,
        [string]$FailMessage
    )
    $full = Join-Path $Root $Path
    if (-not (Test-Path -LiteralPath $full)) {
        Add-Failure "$Path is missing"
        return
    }
    $text = Get-Content -Raw -LiteralPath $full
    if ($text -match $Pattern) {
        Add-Pass $PassMessage
    } else {
        Add-Failure $FailMessage
    }
}

$version = (Read-Text "VERSION").Trim()
if ($version -eq "1.2.0") {
    Add-Pass "VERSION is 1.2.0"
} else {
    Add-Failure "VERSION is '$version', expected 1.2.0"
}

Assert-Contains "docs\LAUNCH_CONTRACT.md" "Layer 1.*desktop icon|desktop icon double-click first" "Launch Contract defines desktop icon first" "Launch Contract does not define desktop icon first"
Assert-Contains "docs\LAUNCH_CONTRACT.md" "Layer 2.*Start Menu|keyboard or Start Menu fallback" "Launch Contract defines Layer 2 keyboard/Start Menu fallback" "Launch Contract does not define Layer 2 fallback"
Assert-Contains "docs\LAUNCH_CONTRACT.md" "Layer 3.*backend" "Launch Contract defines Layer 3 backend fallback" "Launch Contract does not define Layer 3 backend fallback"
Assert-Contains "docs\LAUNCH_CONTRACT.md" "fallback_evidence" "Launch Contract requires fallback evidence" "Launch Contract does not require fallback evidence"
Assert-Contains "docs\LAUNCH_CONTRACT.md" "launch_contract_violation" "Launch Contract defines launch_contract_violation" "Launch Contract does not define launch_contract_violation"
Assert-Contains "docs\LAUNCH_CONTRACT.md" "INVALID_ARGUMENT_NON_EXECUTING" "Launch Contract defines bare dry-run non-execution" "Launch Contract does not define bare dry-run non-execution"
Assert-Contains "docs\LAUNCH_CONTRACT.md" "NON_EXECUTING_HELP" "Launch Contract defines help non-execution" "Launch Contract does not define help non-execution"
Assert-Contains "docs\LAUNCH_CONTRACT.md" "Visual Studio Installer is not Visual Studio IDE" "Launch Contract excludes VS Installer" "Launch Contract does not exclude VS Installer"

$mustReferenceLaunchContract = @(
    "CURRENT_EXECUTION_CONTRACT.md",
    "AGENTS.md",
    "COMMAND_PROTOCOL.md",
    "README.md",
    "docs\FIELD_TEST_READINESS.md",
    "docs\WORKSPACE_HYGIENE.md",
    "docs\INVALID_ARTIFACT_LIFECYCLE.md",
    "docs\RELEASE_CHANNELS.md",
    "docs\DEVELOPMENT_STATUS.md",
    "adapters\codex\win-desktop-agent\SKILL.md",
    "adapters\codex\desktopvisual\SKILL.md",
    "adapters\shared\TASK_FLOW.md",
    "adapters\shared\SAFETY_RULES.md",
    "adapters\shared\ERROR_HANDLING.md",
    "adapters\shared\REPORT_READING.md",
    "adapters\generic-cli\desktopvisual-agent-contract.md",
    "adapters\generic-cli\README.md",
    "adapters\claude-code\DESKTOPVISUAL.md"
)

foreach ($path in $mustReferenceLaunchContract) {
    Assert-Contains $path "LAUNCH_CONTRACT\.md|Launch Contract" "$path references Launch Contract" "$path does not reference Launch Contract"
}

$scanFiles = @(
    "CURRENT_EXECUTION_CONTRACT.md",
    "AGENTS.md",
    "COMMAND_PROTOCOL.md",
    "README.md"
)
$scanFiles += @(Get-ChildItem -LiteralPath (Join-Path $Root "docs") -Filter "*.md" -File | ForEach-Object { "docs\$($_.Name)" })
$scanFiles += @(Get-ChildItem -LiteralPath (Join-Path $Root "adapters") -Recurse -Filter "*.md" -File | ForEach-Object { $_.FullName.Substring($Root.Length + 1) })

$badPatterns = @(
    @{
        Name = "Start Menu first while desktop icon exists"
        Pattern = "(?i)(current|v1\.1\.12|Launch Contract).{0,120}(Start Menu|start-menu).{0,40}(is|as|must be|can be|may be)\s+(?!not\b).{0,30}(first|default|primary).{0,120}(desktop icon|shortcut)"
    },
    @{
        Name = "backend launch default"
        Pattern = "(?i)(current|v1\.1\.12|Launch Contract).{0,120}backend.{0,40}(is|as|must be|can be|may be)\s+(?!not\b).{0,30}(first|default|primary)"
    },
    @{
        Name = "visible-app-launch may bypass desktop icon first"
        Pattern = "(?i)visible-app-launch.{0,120}(bypass|skip|ignore).{0,120}desktop icon"
    }
)

foreach ($path in $scanFiles | Sort-Object -Unique) {
    $text = Read-Text $path
    foreach ($rule in $badPatterns) {
        if ($text -match $rule.Pattern) {
            Add-Failure "$path contains conflicting current launch rule: $($rule.Name)"
        }
    }
}

Assert-Contains "COMMAND_PROTOCOL.md" "vs-launch-preflight" "COMMAND_PROTOCOL documents vs-launch-preflight" "COMMAND_PROTOCOL missing vs-launch-preflight"
Assert-Contains "src\winagent\WinAgent.cpp" "launch_contract_version" "Runtime emits launch_contract_version" "Runtime missing launch_contract_version"
Assert-Contains "src\winagent\WinAgent.cpp" "INVALID_ARGUMENT_NON_EXECUTING" "Runtime handles bare dry-run non-execution" "Runtime missing INVALID_ARGUMENT_NON_EXECUTING"
Assert-Contains "src\winagent\WinAgent.cpp" "NON_EXECUTING_HELP" "Runtime handles help non-execution" "Runtime missing NON_EXECUTING_HELP"

$reportPath = Join-Path $ArtifactDir "rule_conflict_scan_report.md"
@(
    "# Rule Conflict Scan Report",
    "",
    "Version: 1.2.0",
    "",
    "Scanned files: $($scanFiles.Count)",
    "",
    $Report
) | Set-Content -Encoding UTF8 -LiteralPath $reportPath

if ($Failures.Count -gt 0) {
    Write-Host ""
    Write-Host "Launch contract consistency selftest FAILED with $($Failures.Count) failure(s)."
    exit 1
}

Write-Host ""
Write-Host "Launch contract consistency selftest PASSED."
