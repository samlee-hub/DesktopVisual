param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\v5_task_latency_rc_check.ps1 [-Root <path>]'
    Write-Host 'Records v5.8.4 task latency RC metrics from controlled local commands.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.8.4'
$Report = Join-Path $ArtifactDir 'v5_task_latency_rc_report.md'
$Summary = Join-Path $ArtifactDir 'v5_task_latency_rc_summary.json'
$TaskFile = Join-Path $Root 'tasks\session_schema\local_form_fill_submit_mock_audit.task-session.json'
$VerificationContract = Join-Path $Root 'tasks\step_contract\valid_local_form_submit.step.json'
$VerifyBefore = Join-Path $Root 'tasks\step_contract\verification_before_submit.json'
$VerifyAfter = Join-Path $Root 'tasks\step_contract\verification_after_success.json'
$RecoveryPolicy = Join-Path $Root 'tasks\recovery_policy\valid_standard_recovery_policy.json'
$RecoveryContext = Join-Path $Root 'tasks\recovery_policy\delayed_button_not_ready.json'

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

function Invoke-TimedJson([string]$Name, [string[]]$CommandArgs, [int[]]$AllowedExitCodes = @(0)) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $output = & $WinAgent @CommandArgs 2>&1
    $exit = $LASTEXITCODE
    $sw.Stop()
    $text = ($output | Out-String).Trim()
    if ($AllowedExitCodes -notcontains $exit) { throw "Unexpected exit $exit for $($CommandArgs -join ' '): $text" }
    $json = $text | ConvertFrom-Json
    return [pscustomobject]@{ name=$Name; latency_ms=[int]$sw.ElapsedMilliseconds; exit_code=$exit; ok=$json.ok; output=$json }
}

$task = Invoke-TimedJson 'run-task TaskSession' @('run-task','--file',$TaskFile)
if (-not $task.ok) { throw 'run-task latency case failed' }
$taskId = [string]$task.output.data.task_id

$verification = Invoke-TimedJson 'step verification' @('step-verify','--contract',$VerificationContract,'--before',$VerifyBefore,'--after',$VerifyAfter,'--timeout-ms','1000','--elapsed-ms','50')
if (-not $verification.ok) { throw 'step verification latency case failed' }

$recovery = Invoke-TimedJson 'recovery evaluation' @('recovery-evaluate','--policy',$RecoveryPolicy,'--failure-reason','TARGET_NOT_READY','--context',$RecoveryContext,'--attempt','1')
if (-not $recovery.ok) { throw 'recovery latency case failed' }

$events = Invoke-TimedJson 'task events read' @('task-events','--task-id',$taskId)
if (-not $events.ok) { throw 'task-events latency case failed' }

$perStep = @()
foreach ($eventLine in ($events.output.data.content -split "`n")) {
    if ([string]::IsNullOrWhiteSpace($eventLine)) { continue }
    $cleanLine = $eventLine.Trim()
    if ($cleanLine.Length -gt 0 -and $cleanLine[0] -eq [char]0xfeff) { $cleanLine = $cleanLine.Substring(1) }
    if ([string]::IsNullOrWhiteSpace($cleanLine) -or $cleanLine[0] -ne '{') { continue }
    $event = $cleanLine | ConvertFrom-Json
    $perStep += [pscustomobject]@{
        step_id = $event.step_id
        state = $event.state
        latency_ms = 0
        measured = $false
        note = 'per-step event does not carry duration in v5 local mock runner'
    }
}

$summaryObject = [pscustomobject]@{
    schema_version = '5.8.4'
    result = 'PASS'
    timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    task_id = $taskId
    task_total_latency_ms = $task.latency_ms
    per_step_latency_ms = $perStep
    verification_latency_ms = $verification.latency_ms
    recovery_latency_ms = $recovery.latency_ms
    confirmation_wait = [pscustomobject]@{ excluded = $true; separately_recorded = $true; latency_ms = 0 }
    llm_vlm_call_count = 0
    cache_hit_ratio = $null
    cache_hit_ratio_available = $false
    measurements = @($task, $verification, $recovery, $events | ForEach-Object { [pscustomobject]@{ name=$_.name; latency_ms=$_.latency_ms; ok=$_.ok } })
}
$summaryObject | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $Summary -Encoding UTF8

$lines = @(
    '# v5 Task Latency RC Check',
    '',
    '- Result: PASS',
    "- Timestamp: $($summaryObject.timestamp)",
    "- task_total_latency_ms: $($summaryObject.task_total_latency_ms)",
    "- verification_latency_ms: $($summaryObject.verification_latency_ms)",
    "- recovery_latency_ms: $($summaryObject.recovery_latency_ms)",
    '- confirmation_wait: excluded and separately recorded',
    '- llm/vlm_call_count: 0',
    '- cache_hit_ratio: unavailable for this local mock subset',
    "- Summary: $Summary"
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.8.4 task latency RC check'
Write-Host "Report: $Report"
Write-Host "Summary: $Summary"
