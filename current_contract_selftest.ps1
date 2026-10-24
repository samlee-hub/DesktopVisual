param()

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root

$Failures = New-Object System.Collections.Generic.List[string]

function Add-Failure {
    param([string]$Message)
    $script:Failures.Add($Message) | Out-Null
    Write-Host "[FAIL] $Message"
}

function Add-Pass {
    param([string]$Message)
    Write-Host "[PASS] $Message"
}

function Read-Text {
    param([string]$Path)
    return Get-Content -Raw -LiteralPath (Join-Path $Root $Path)
}

$contractPath = Join-Path $Root "CURRENT_EXECUTION_CONTRACT.md"
if (Test-Path -LiteralPath $contractPath) {
    Add-Pass "CURRENT_EXECUTION_CONTRACT.md exists"
} else {
    Add-Failure "CURRENT_EXECUTION_CONTRACT.md is missing"
}

$version = (Read-Text "VERSION").Trim()
if ($version -eq "1.1.12") {
    Add-Pass "VERSION is 1.1.12"
} else {
    Add-Failure "VERSION is '$version', expected 1.1.12"
}

$mustReferenceContract = @(
    "AGENTS.md",
    "README.md",
    "COMMAND_PROTOCOL.md",
    "docs\DEVELOPMENT_STATUS.md",
    "docs\RELEASE_CHANNELS.md"
)

foreach ($path in $mustReferenceContract) {
    $text = Read-Text $path
    if ($text -match [regex]::Escape("CURRENT_EXECUTION_CONTRACT.md")) {
        Add-Pass "$path references CURRENT_EXECUTION_CONTRACT.md"
    } else {
        Add-Failure "$path does not reference CURRENT_EXECUTION_CONTRACT.md"
    }
}

$localReleasePolicy = Read-Text "docs\LOCAL_RELEASE_PERMISSION_POLICY.md"
if ($localReleasePolicy -match "(?i)not\s+(the\s+)?final\s+restricted\s+public\s+release" -and
    ($localReleasePolicy -match "(?i)same\s+permission\s+semantics\s+as\s+the\s+developer" -or
     $localReleasePolicy -match "(?i)aligned\s+with\s+the\s+developer\s+tree")) {
    Add-Pass "LOCAL_RELEASE_PERMISSION_POLICY.md states current local-use release semantics"
} else {
    Add-Failure "LOCAL_RELEASE_PERMISSION_POLICY.md does not state the current local-use release semantics"
}

if ($localReleasePolicy -match "(?i)(current\s+desktop_release|desktop_release.{0,60}current).{0,80}(must|shall|required).{0,50}(restricted|permission\s+reduction|permission\s+hardening|narrow|final\s+restricted\s+public)") {
    Add-Failure "LOCAL_RELEASE_PERMISSION_POLICY.md still describes current desktop_release as requiring restricted-public hardening"
} else {
    Add-Pass "LOCAL_RELEASE_PERMISSION_POLICY.md does not require current desktop_release hardening"
}

foreach ($path in @("docs\SAFETY_MODEL.md", "docs\AGENT_USAGE_GUIDE.md")) {
    $text = Read-Text $path
    if ($text -match "(?im)^\s*Current\s+(trusted\s+)?version:\s*`?v[3-6]\.") {
        Add-Failure "$path still describes v3/v4/v5/v6 as the current version"
    } else {
        Add-Pass "$path does not describe v3/v4/v5/v6 as the current version"
    }
}

$manifest = Read-Text "config\safety_manifest.json" | ConvertFrom-Json
if ($manifest.default_permission_mode -eq "DEVELOPER_CAPABILITY_DISCOVERY") {
    Add-Pass "default_permission_mode remains DEVELOPER_CAPABILITY_DISCOVERY"
} else {
    Add-Failure "default_permission_mode is '$($manifest.default_permission_mode)', expected DEVELOPER_CAPABILITY_DISCOVERY"
}

$currentRuleFiles = @(
    "CURRENT_EXECUTION_CONTRACT.md",
    "AGENTS.md",
    "README.md",
    "COMMAND_PROTOCOL.md",
    "docs\DEVELOPMENT_STATUS.md",
    "docs\RELEASE_CHANNELS.md",
    "docs\LOCAL_RELEASE_PERMISSION_POLICY.md",
    "docs\SAFETY_MODEL.md",
    "docs\AGENT_USAGE_GUIDE.md"
)

$badCurrentRulePatterns = @(
    @{
        Name = "keyword/category current STOP rule"
        Pattern = "(?i)(current|v1\.1\.x|developer|desktop_release).{0,100}(keyword|test|exam|challenge|assessment|interview|contest|submit).{0,100}(must|shall|required|default)(?!\s+not).{0,50}(STOP|BLOCK|deny|disabled)"
    },
    @{
        Name = "ordinary app/web default BLOCK rule"
        Pattern = "(?i)(current|v1\.1\.x|developer|desktop_release).{0,100}(\bordinary\s+apps?\b|\bordinary\s+web(pages?)?\b|\bHTTPS\b|\blocalhost\b|\bIDEs?\b|\bExplorer\b|\bcommunication\b|\bemail\b|\bcode\s+platforms?\b).{0,100}(default|must|shall|required)(?!\s+not).{0,50}(BLOCK|STOP|deny|disabled)"
    },
    @{
        Name = "current release permission reduction rule"
        Pattern = "(?i)(current|v1\.1\.x|desktop_release).{0,100}(must|shall|required)(?!\s+not).{0,50}(permission\s+reduction|permission\s+hardening|restricted\s+public|narrow)"
    }
)

foreach ($path in $currentRuleFiles) {
    $text = Read-Text $path
    foreach ($rule in $badCurrentRulePatterns) {
        if ($text -match $rule.Pattern) {
            Add-Failure "$path contains a prohibited current-rule pattern: $($rule.Name)"
        }
    }
}

if ($Failures.Count -eq 0) {
    Write-Host "Current contract selftest PASS"
    exit 0
}

Write-Host "Current contract selftest FAIL: $($Failures.Count) failure(s)"
exit 1



