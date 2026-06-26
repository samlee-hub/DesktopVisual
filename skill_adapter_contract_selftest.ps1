param([string]$Root = '')

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$SourceSkill = Join-Path $Root 'skill_template\win-desktop-agent\SKILL.md'
$AdapterRoot = Join-Path $Root 'adapters\codex\win-desktop-agent'
$AdapterSkill = Join-Path $AdapterRoot 'SKILL.md'
$AdapterScripts = Join-Path $AdapterRoot 'scripts'
$SharedRoot = Join-Path $Root 'adapters\shared'
$OutDir = Join-Path $Root 'artifacts\dev1.0.2_skill_contract_hardening'
$Report = Join-Path $OutDir 'skill_adapter_contract_selftest_report.md'

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$Checks = New-Object System.Collections.Generic.List[object]
$Failed = 0

function Add-Check([string]$Name, [string]$Status, [string]$Detail) {
    $script:Checks.Add([pscustomobject]@{
        name = $Name
        status = $Status
        detail = $Detail
    }) | Out-Null
    if ($Status -eq 'FAIL') { $script:Failed++ }
}

function Check([string]$Name, [scriptblock]$Body) {
    try {
        & $Body
        Add-Check $Name 'PASS' ''
    } catch {
        Add-Check $Name 'FAIL' $_.Exception.Message
    }
}

function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Read-Text([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "missing file: $Path" }
    return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
}

function Assert-ContainsAll([string]$Text, [string[]]$Phrases, [string]$Scope) {
    foreach ($phrase in $Phrases) {
        Assert ($Text -match [regex]::Escape($phrase)) "$Scope missing required phrase: $phrase"
    }
}

function Assert-NoOldConflicts([string]$Text, [string]$Scope) {
    Assert ($Text -notmatch 'Stop on every visual locator failure\.') "$Scope keeps old absolute locator failure stop wording."
    Assert ($Text -notmatch 'If a locator returns .* stop\. Do not guess nearby coordinates or silently switch locator methods\.') "$Scope keeps old immediate locator stop wording."
    foreach ($bad in @(
        'Start Menu visible search is the first choice',
        'Start Menu is the first choice',
        'Start Menu can be the first choice',
        'Start Menu may be the first choice',
        'backend is the first choice',
        'backend can be the first choice',
        'backend may be the first choice',
        'backend launch is the default path'
    )) {
        Assert ($Text -notmatch [regex]::Escape($bad)) "$Scope contains forbidden phrase: $bad"
    }
    Assert ($Text -notmatch 'because it is faster.*fallback') "$Scope appears to allow speed-based fallback."
    Assert ($Text -notmatch 'because it is convenient.*fallback') "$Scope appears to allow convenience-based fallback."
}

$source = Read-Text $SourceSkill
$adapter = Read-Text $AdapterSkill
$sharedText = ''
if (Test-Path -LiteralPath $SharedRoot) {
    foreach ($file in Get-ChildItem -LiteralPath $SharedRoot -Filter '*.md') {
        $sharedText += "`n<!-- $($file.Name) -->`n"
        $sharedText += Read-Text $file.FullName
    }
}
$adapterContractText = $adapter + "`n" + $sharedText

Check 'adapter and source share core visible-first contract' {
    foreach ($phrase in @(
        'visible-app-launch',
        'desktop-first',
        'Start Menu visible search is a fallback, not the first choice.',
        'backend fallback is not the default path',
        'two bounded visible attempts or strict surface-impossible evidence',
        'target_not_found, uia_not_found, ocr_not_found, and click_failed alone are not surface-impossible evidence.',
        'v1.0.3 supports provider-gated VLM assist.'
    )) {
        Assert ($source -match [regex]::Escape($phrase)) "source Skill missing core phrase: $phrase"
        Assert ($adapterContractText -match [regex]::Escape($phrase)) "adapter contract missing core phrase: $phrase"
    }
}

Check 'adapter has required v1.0.3 contract points' {
    Assert-ContainsAll $adapterContractText @(
        'Use visible-app-launch for app, URL, local shortcut, .lnk, .url, and webpage shortcut launches.',
        'App launch is desktop-first.',
        'Start Menu visible search is a fallback, not the first choice.',
        'One failure cannot directly move to fallback.',
        'Entering fallback requires two bounded visible attempts or strict surface-impossible evidence.',
        'backend fallback is not the default path',
        'Do not disguise clipboard/backend write as visible input success.',
        'Developer mode does not stop on broad category or keyword matching without active protection.',
        'v1.0.3 supports provider-gated VLM assist.',
        'If `VLM_UNAVAILABLE`, continue Runtime-only visible paths',
        'VLM provides visual understanding and candidate bbox/point evidence only.',
        'Errors and policy violations must be reported as failure or BLOCKED, not PASS.'
    ) 'adapter contract'
}

Check 'adapter does not keep v1.0.1-conflicting old rules' {
    Assert-NoOldConflicts $adapter 'adapter SKILL.md'
}

Check 'shared adapter rules do not conflict with v1.0.3 Skill contract' {
    if (Test-Path -LiteralPath $SharedRoot) {
        Assert-NoOldConflicts $sharedText 'adapters\shared'
        Assert ($sharedText -match [regex]::Escape('Active protection or security interception is STOP, not fallback.')) 'shared rules must preserve active-protection STOP.'
        Assert ($sharedText -match [regex]::Escape('Developer mode does not stop on broad category or keyword matching without active protection.')) 'shared rules must preserve developer broad-category allowance.'
    }
}

Check 'adapter scripts accept -Root and resolve the project root' {
    foreach ($scriptName in @('selftest-skill-template.ps1', 'run-skill-basic.ps1')) {
        $scriptPath = Join-Path $AdapterScripts $scriptName
        $text = Read-Text $scriptPath
        Assert ($text -match 'param\(') "$scriptName must declare parameters."
        Assert ($text -match '\[string\]\$Root') "$scriptName must accept -Root."
        Assert ($text -match 'Resolve-DesktopVisualRoot\.ps1') "$scriptName must use Resolve-DesktopVisualRoot.ps1."
        Assert ($text -match 'DESKTOPVISUAL_ROOT') "$scriptName must set DESKTOPVISUAL_ROOT."
        Assert ($text -match '\$LASTEXITCODE') "$scriptName must inspect command exit codes."
    }
}

Check 'adapter scripts are not fixed PASS stubs' {
    $selftest = Read-Text (Join-Path $AdapterScripts 'selftest-skill-template.ps1')
    $basic = Read-Text (Join-Path $AdapterScripts 'run-skill-basic.ps1')
    Assert-ContainsAll $selftest @(
        'Check ',
        'Start-Process',
        'run-task.ps1',
        'locate-target.ps1',
        'Fail '
    ) 'selftest-skill-template.ps1'
    Assert-ContainsAll $basic @(
        'Invoke-WinAgentJson',
        'Ensure-AgentTestWindow',
        'run-case',
        'ReadLatestReport'
    ) 'run-skill-basic.ps1'
    Assert ($selftest -notmatch '(?s)Write-Host\s+[''"]PASS[''"].{0,120}exit\s+0') 'selftest-skill-template.ps1 looks like a fixed PASS stub.'
    Assert ($basic -notmatch '(?s)Write-Host\s+[''"]PASS[''"].{0,120}exit\s+0') 'run-skill-basic.ps1 looks like a fixed PASS stub.'
}

Check 'adapter scripts execute with current root' {
    $selftestScript = Join-Path $AdapterScripts 'selftest-skill-template.ps1'
    $basicScript = Join-Path $AdapterScripts 'run-skill-basic.ps1'

    $selftestOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $selftestScript -Root $Root -SkipBuild 2>&1
    $selftestExit = $LASTEXITCODE
    Assert ($selftestExit -eq 0) "selftest-skill-template.ps1 failed with exit=$selftestExit output=$($selftestOutput | Out-String)"
    Assert (($selftestOutput | Out-String) -match 'Skill Template Selftest') 'selftest output missing Skill Template Selftest marker.'

    $basicOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $basicScript -Root $Root 2>&1
    $basicExit = $LASTEXITCODE
    Assert ($basicExit -eq 0) "run-skill-basic.ps1 failed with exit=$basicExit output=$($basicOutput | Out-String)"
    Assert (($basicOutput | Out-String) -match 'Report:') 'run-skill-basic output missing report path.'
}

$lines = @(
    '# Skill Adapter Contract Selftest Report',
    '',
    "- result: $(if ($Failed -eq 0) { 'PASS' } else { 'FAIL' })",
    "- root: $Root",
    "- adapter_skill: $AdapterSkill",
    '',
    '| check | status | detail |',
    '|---|---|---|'
)
foreach ($check in $Checks) {
    $detail = ([string]$check.detail).Replace('|', '\|')
    $lines += "| $($check.name) | $($check.status) | $detail |"
}
$lines | Set-Content -Encoding UTF8 -LiteralPath $Report

if ($Failed -gt 0) {
    Write-Host 'FAIL skill_adapter_contract_selftest'
    Write-Host "Report: $Report"
    exit 1
}

Write-Host 'PASS skill_adapter_contract_selftest'
Write-Host "Report: $Report"
exit 0
