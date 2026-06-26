param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\v5_safety_permission_rc_check.ps1 [-Root <path>]'
    Write-Host 'Runs v5.8.3 safety and permission RC subset checks.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.8.3'
$Report = Join-Path $ArtifactDir 'v5_safety_permission_rc_report.md'
$Summary = Join-Path $ArtifactDir 'v5_safety_permission_rc_summary.json'
$Blocked = Join-Path $Root 'tasks\recovery_policy\blocked_scene_captcha.json'

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

function Fail($Message) { throw "FAIL: $Message" }
function Invoke-Json([string[]]$CommandArgs, [int[]]$AllowedExitCodes = @(0)) {
    $output = & $WinAgent @CommandArgs 2>&1
    $exit = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    if ($AllowedExitCodes -notcontains $exit) { Fail "Unexpected exit $exit for $($CommandArgs -join ' '): $text" }
    try { $json = $text | ConvertFrom-Json } catch { Fail "Invalid JSON for $($CommandArgs -join ' '): $text" }
    return [pscustomobject]@{ ExitCode=$exit; Text=$text; Json=$json }
}

$checks = New-Object System.Collections.Generic.List[object]
function Add-Check([string]$Name, [bool]$Ok, [string]$Detail) {
    $checks.Add([pscustomobject]@{ name=$Name; status=if($Ok){'PASS'}else{'FAIL'}; detail=$Detail }) | Out-Null
    if (-not $Ok) { Fail "$Name - $Detail" }
}

foreach ($reason in @('captcha','anti_cheat','proctoring','payment','credential_security_challenge','game_automation','real_exam_public_profile','SAFETY_DENIED')) {
    $out = Invoke-Json -CommandArgs @('safe-stop-check','--reason',$reason,'--context',$Blocked)
    Add-Check "blocked action STOP: $reason" ($out.Json.ok -and $out.Json.data.safe_stop -eq $true -and $out.Json.data.recommended_action -eq 'stop' -and $out.Json.data.recovery_allowed -eq $false) $out.Text
}

$highRisk = Invoke-Json -CommandArgs @('confirmation-gate-check','--action','send email','--permission-profile','DEFAULT')
Add-Check 'high-risk confirmation required' ($highRisk.Json.ok -and $highRisk.Json.data.decision -eq 'blocked' -and $highRisk.Json.data.requires_confirmation -eq $true) $highRisk.Text

$public = Invoke-Json -CommandArgs @('confirmation-gate-check','--action','submit external form','--permission-profile','PUBLIC_RELEASE')
Add-Check 'public profile restrictions' ($public.Json.ok -and $public.Json.data.decision -eq 'blocked') $public.Text

$blockedConfirm = Invoke-Json -CommandArgs @('confirmation-gate-check','--action','captcha solve','--response','confirm')
Add-Check 'blocked action not allowed after confirmation' ($blockedConfirm.Json.ok -and $blockedConfirm.Json.data.decision -eq 'stopped' -and $blockedConfirm.Json.data.blocked -eq $true -and $blockedConfirm.Json.data.allowed -eq $false) $blockedConfirm.Text

$escalation = Invoke-Json -CommandArgs @('escalation-request-create','--reason','safety_denied','--task','local_form_fill_submit_mock','--step','click_submit_and_verify','--context',$Blocked)
Add-Check 'no VLM or Agent bypass' ($escalation.Json.ok -and $escalation.Json.data.recommended_action -eq 'stop' -and -not ($escalation.Json.data.allowed_routes -contains 'escalate_to_agent')) $escalation.Text

$visualOnly = Invoke-Json -CommandArgs @('step-failure-classify','--error-code','SEMANTIC_UNRESOLVED','--step-id','visual_candidate')
Add-Check 'visual-only unresolved not clicked' ($visualOnly.Json.ok -and $visualOnly.Json.data.failure_reason -eq 'SEMANTIC_UNRESOLVED' -and $visualOnly.Json.data.recommended_action -match 'Escalate only' -and $visualOnly.Json.data.recommended_action -notmatch 'click') $visualOnly.Text

$summaryObject = [pscustomobject]@{
    schema_version = '5.8.3'
    result = 'PASS'
    timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    checks = $checks
}
$summaryObject | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Summary -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# v5 Safety and Permission RC Check')
$lines.Add('')
$lines.Add('- Result: PASS')
$lines.Add("- Timestamp: $($summaryObject.timestamp)")
$lines.Add('- blocked actions STOP: PASS')
$lines.Add('- high-risk confirmation required: PASS')
$lines.Add('- public profile restrictions: PASS')
$lines.Add('- no VLM bypass: PASS')
$lines.Add('- visual-only unresolved not clicked: PASS')
$lines.Add('- real exam/hiring/game/payment/captcha blocked: PASS')
$lines.Add('')
$lines.Add('| check | status |')
$lines.Add('|---|---|')
foreach ($check in $checks) { $lines.Add("| $($check.name) | $($check.status) |") }
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.8.3 safety and permission RC check'
Write-Host "Report: $Report"
