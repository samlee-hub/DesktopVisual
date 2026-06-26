param([string]$Root = '')

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$SkillRoot = Join-Path $Root 'skill_template\win-desktop-agent'
$SkillPath = Join-Path $SkillRoot 'SKILL.md'
$RefsDir = Join-Path $SkillRoot 'references'
$OutDir = Join-Path $Root 'artifacts\dev1.0.2_skill_contract_hardening'
$Report = Join-Path $OutDir 'skill_contract_hardening_selftest_report.md'

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

function Get-Section([string]$Text, [string]$Heading) {
    $pattern = "(?ms)^##\s+$([regex]::Escape($Heading))\s*`r?`n(?<body>.*?)(?=^##\s+|\z)"
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return '' }
    return $match.Groups['body'].Value
}

function Assert-ContainsAll([string]$Text, [string[]]$Phrases, [string]$Scope) {
    foreach ($phrase in $Phrases) {
        Assert ($Text -match [regex]::Escape($phrase)) "$Scope missing required phrase: $phrase"
    }
}

$skill = Read-Text $SkillPath
$visibleContractPath = Join-Path $RefsDir 'VISIBLE_FIRST_CONTRACT.md'
$visibleContract = if (Test-Path -LiteralPath $visibleContractPath) { Read-Text $visibleContractPath } else { '' }

$referenceText = ''
foreach ($name in @(
    'AGENT_USAGE_GUIDE.md',
    'COMMAND_PROTOCOL.md',
    'KNOWN_LIMITATIONS.md',
    'REAL_DEV_WORKFLOW.md',
    'SAFETY.md',
    'SAFETY_MODEL.md'
)) {
    $path = Join-Path $RefsDir $name
    if (Test-Path -LiteralPath $path) {
        $referenceText += "`n" + (Read-Text $path)
    }
}

$contractText = $skill + "`n" + $visibleContract + "`n" + $referenceText

Check 'SKILL.md frontmatter is valid' {
    Assert ($skill -match "(?s)\A---\r?\n(?<frontmatter>.*?)\r?\n---\r?\n") 'SKILL.md must start with YAML frontmatter.'
    $fm = $Matches['frontmatter']
    Assert ($fm -match "(?m)^name:\s*win-desktop-agent\s*$") 'frontmatter must declare name: win-desktop-agent.'
    Assert ($fm -match "(?m)^description:\s*.+") 'frontmatter must declare a non-empty description.'
    Assert ($fm -match 'visible-first') 'frontmatter description must mention visible-first behavior.'
}

Check 'dedicated visible-first reference exists and is linked' {
    Assert (Test-Path -LiteralPath $visibleContractPath) 'Missing references\VISIBLE_FIRST_CONTRACT.md.'
    Assert ($skill -match [regex]::Escape('references\VISIBLE_FIRST_CONTRACT.md')) 'SKILL.md must reference VISIBLE_FIRST_CONTRACT.md.'
}

Check 'all Skill reference files are linked from SKILL.md' {
    $linked = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($m in [regex]::Matches($skill, 'references\\([^`\)\s]+\.md)', [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        [void]$linked.Add($m.Groups[1].Value)
    }
    foreach ($ref in Get-ChildItem -LiteralPath $RefsDir -Filter '*.md') {
        Assert ($linked.Contains($ref.Name)) "SKILL.md does not link reference file: $($ref.Name)"
    }
}

Check 'contract has required section structure' {
    foreach ($heading in @(
        'DesktopVisual Positioning Contract',
        'Visible-App-Launch Contract',
        'Three-Layer Fallback Contract',
        'Developer Permission Contract',
        'VLM Assist Contract',
        'Error Handling Contract'
    )) {
        Assert ((Get-Section $visibleContract $heading).Trim().Length -gt 0) "VISIBLE_FIRST_CONTRACT.md missing section: $heading"
    }
}

Check 'DesktopVisual positioning contract is explicit' {
    Assert-ContainsAll $contractText @(
        'DesktopVisual is a Windows visible-first desktop runtime, not a background script executor.',
        "The agent's goal is not the fastest path; it must prefer visible, auditable, human-like desktop operations.",
        'Every input action must have observe / locate / act / verify evidence, or an equivalent task/visible command evidence chain.',
        'A task can fail because the path was illegal even when the final application state appears correct.'
    ) 'positioning contract'
}

Check 'visible-app-launch startup contract is explicit' {
    Assert-ContainsAll $contractText @(
        'Use visible-app-launch for app, URL, local shortcut, .lnk, .url, and webpage shortcut launches.',
        'visible-app-launch is desktop-first.',
        'Start Menu visible search is a fallback, not the first choice.',
        'backend launch, ShellExecute, direct file open, and background browser navigation are not default launch paths.',
        'two bounded desktop visible attempts or strict surface-impossible evidence',
        'If target-title or process is provided, target_window_verified must be true before the launch is reported successful.',
        'runtime_visible_first_launch',
        'launch_strategy',
        'desktop_surface_attempted',
        'desktop_icon_path_used',
        'start_menu_fallback_attempted',
        'backend_launch_used',
        'bounded_recovery_attempted',
        'target_window_verified'
    ) 'visible-app-launch contract'
}

Check 'fallback contract preserves the three layers and gates' {
    Assert-ContainsAll $contractText @(
        'Layer 1: visible UI path',
        'Layer 2: visible keyboard fallback',
        'Layer 3: backend fallback',
        'Do not jump to shortcuts because they are faster.',
        'Do not jump to backend because it is convenient.',
        'Do not switch layers after one locator failure.',
        'Do not switch layers after one click failure.',
        'target_not_found, uia_not_found, ocr_not_found, and click_failed alone are not surface-impossible evidence.',
        'Entering shortcut fallback requires at least two bounded visible attempts or strict surface-impossible evidence.',
        'Entering backend fallback requires visible path failure plus keyboard fallback failure.',
        'The backend fallback reason must be non-empty and must not be convenience, speed, or test shortcut.',
        'Active protection or security interception is STOP, not fallback.'
    ) 'fallback contract'
}

Check 'bounded visible attempts are fully described' {
    Assert-ContainsAll $contractText @(
        'pre-action checkpoint',
        'observe / locate / action',
        'failure reason',
        'bounded recovery',
        're-observe / re-locate',
        'second visible action'
    ) 'bounded visible attempt contract'
}

Check 'developer permission contract is not narrowed' {
    Assert-ContainsAll $contractText @(
        'DEVELOPER_CAPABILITY_DISCOVERY',
        'DEVELOPER_FULL_RUNTIME',
        'ordinary app, ordinary webpage, https, localhost, IDE, browser, file manager, mail page, communication page, coding practice page, test, exam, challenge, submit, and assessment keywords are not developer STOP conditions by themselves',
        'If there is no active protection or security interception, developer mode must not stop because of broad category or keyword matching.',
        'CAPTCHA',
        'human verification',
        'bot challenge',
        'automation detected',
        'script detected',
        'protected desktop',
        'proctoring',
        'lockdown browser',
        'anti-cheat'
    ) 'developer permission contract'
}

Check 'VLM assist contract is provider-gated and bounded' {
    Assert-ContainsAll $contractText @(
        'v1.0.3 supports provider-gated VLM assist.',
        'Probe VLM capability once per large task or session',
        'If `VLM_UNAVAILABLE`, continue Runtime-only visible paths',
        'VLM is assistive perception, not the controller.',
        'Every VLM candidate must be Runtime validated',
        'VLM does not participate in backend fallback.',
        'Active protection or security interception is STOP'
    ) 'VLM assist contract'
    Assert ($contractText -notmatch 'all models support VLM') 'must not claim all models support VLM.'
    Assert ($contractText -notmatch 'VLM may directly click') 'must not allow VLM direct action.'
}

Check 'error handling contract rejects false PASS' {
    Assert-ContainsAll $contractText @(
        'command error, safety denial, ambiguous window, locator failure, verification failure, and fallback discipline violation cannot be reported as PASS',
        'If final state appears successful but evidence shows a disallowed fallback, report failure.',
        'Report the failed command, error_code, whether input was executed, artifacts/report path, and the next minimal repair entry.',
        'Do not broaden title, guess coordinates, click nearby areas, or switch to a backend plan to keep going.'
    ) 'error handling contract'
}

Check 'old absolute locator-stop rule is removed from active Skill contract' {
    foreach ($scope in @(
        @{ Name = 'SKILL.md'; Text = $skill },
        @{ Name = 'VISIBLE_FIRST_CONTRACT.md'; Text = $visibleContract }
    )) {
        Assert ($scope.Text -notmatch 'Stop on every visual locator failure\.') "$($scope.Name) keeps old absolute locator failure stop wording."
        Assert ($scope.Text -notmatch 'If a locator returns .* stop\. Do not guess nearby coordinates or silently switch locator methods\.') "$($scope.Name) keeps old immediate locator stop wording."
    }
}

$lines = @(
    '# Skill Contract Hardening Selftest Report',
    '',
    "- result: $(if ($Failed -eq 0) { 'PASS' } else { 'FAIL' })",
    "- root: $Root",
    "- skill: $SkillPath",
    "- visible_contract: $visibleContractPath",
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
    Write-Host "FAIL skill_contract_hardening_selftest"
    Write-Host "Report: $Report"
    exit 1
}

Write-Host 'PASS skill_contract_hardening_selftest'
Write-Host "Report: $Report"
exit 0
