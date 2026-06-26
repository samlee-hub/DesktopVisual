param(
    [string]$Root = '',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'

function Fail($Message) { throw $Message }

function Invoke-AgentJson([string[]]$CmdArgs, [switch]$AllowFailure) {
    $output = & $WinAgent @CmdArgs 2>&1
    $exit = $LASTEXITCODE
    if ($exit -ne 0 -and -not $AllowFailure) {
        Fail "winagent $($CmdArgs -join ' ') exited $exit with output: $output"
    }
    try {
        return ($output | ConvertFrom-Json)
    } catch {
        Fail "Invalid JSON from winagent $($CmdArgs -join ' '): $output"
    }
}

function Invoke-AgentWithInput([string]$InputText, [string[]]$CmdArgs) {
    $output = $InputText | & $WinAgent @CmdArgs 2>&1
    try {
        return ($output | ConvertFrom-Json)
    } catch {
        Fail "Invalid JSON from piped winagent $($CmdArgs -join ' '): $output"
    }
}

if (-not $SkipBuild) {
    & "$Root\build.ps1" -Root $Root
    if ($LASTEXITCODE -ne 0) { Fail 'Build failed.' }
}

[void](Invoke-AgentJson -CmdArgs @('lock-full-access') -AllowFailure)

$status = Invoke-AgentJson -CmdArgs @('permission-status')
if ($status.data.permission_mode -ne 'DEFAULT') { Fail 'permission-status did not report DEFAULT after lock-full-access.' }
if ($status.data.full_access.active) { Fail 'FULL_ACCESS should not be active after lock-full-access.' }
if (-not ($status.data.full_access.PSObject.Properties.Name -contains 'expired')) { Fail 'permission-status did not include full_access.expired.' }
if (-not ($status.data.full_access.PSObject.Properties.Name -contains 'remaining_ttl_seconds')) { Fail 'permission-status did not include full_access.remaining_ttl_seconds.' }
if (-not ($status.data.full_access.PSObject.Properties.Name -contains 'scope')) { Fail 'permission-status did not include full_access.scope.' }

$nonInteractive = Invoke-AgentJson -CmdArgs @('unlock-full-access', '--ttl', '30', '--scope', 'session-only') -AllowFailure
if ($nonInteractive.ok -or $nonInteractive.error.code -ne 'FULL_ACCESS_REQUIRES_INTERACTIVE_CONFIRMATION') {
    Fail 'Non-interactive unlock-full-access did not require interactive confirmation.'
}

$enterOnly = Invoke-AgentWithInput -InputText '' -CmdArgs @('unlock-full-access', '--ttl', '30', '--scope', 'session-only')
if ($enterOnly.ok -or $enterOnly.error.code -ne 'FULL_ACCESS_REQUIRES_INTERACTIVE_CONFIRMATION') {
    Fail 'Enter-only unlock-full-access did not require interactive confirmation.'
}

$pipedPhrase = Invoke-AgentWithInput -InputText 'ENABLE FULL_ACCESS' -CmdArgs @('unlock-full-access', '--ttl', '30', '--scope', 'session-only')
if ($pipedPhrase.ok -or $pipedPhrase.error.code -ne 'FULL_ACCESS_REQUIRES_INTERACTIVE_CONFIRMATION') {
    Fail 'Piped confirmation phrase should not unlock FULL_ACCESS.'
}

$taskConfirm = Invoke-AgentJson -CmdArgs @('policy-check', '--title', 'External Browser', '--process', 'msedge.exe', '--action', 'external_web', '--permission-mode', 'FULL_ACCESS', '--full-access-session-id', 'ENABLE FULL_ACCESS') -AllowFailure
if ($taskConfirm.ok -or $taskConfirm.error.code -ne 'FULL_ACCESS_SESSION_REQUIRED') {
    Fail 'Task-style confirmation text was accepted as a FULL_ACCESS session.'
}

Get-Process winagent -ErrorAction SilentlyContinue | Stop-Process -Force
$svc = $null
try {
    $svc = Start-Process -FilePath $WinAgent -ArgumentList @('serve', '--max-session-ms', '120000') -NoNewWindow -PassThru
    Start-Sleep -Milliseconds 1000
    if ($svc.HasExited) { Fail "Service exited early with code $($svc.ExitCode)." }

    $request = @{ endpoint = '/unlock-full-access'; body = @{ ttl = 30; scope = 'session-only'; confirmation = 'ENABLE FULL_ACCESS' } } | ConvertTo-Json -Compress
    $pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', 'DesktopVisualService', [System.IO.Pipes.PipeDirection]::InOut)
    $pipe.Connect(5000)
    $writer = New-Object System.IO.StreamWriter($pipe)
    $writer.AutoFlush = $true
    $writer.WriteLine($request)
    $reader = New-Object System.IO.StreamReader($pipe)
    $response = $reader.ReadLine() | ConvertFrom-Json
    $pipe.Close()
    if ($response.ok -or $response.error.code -ne 'INVALID_ARGUMENT') { Fail 'Service should not expose unlock-full-access, even with confirmation text.' }
} finally {
    if ($svc -and -not $svc.HasExited) {
        Stop-Process -Id $svc.Id -Force
    }
}

[void](Invoke-AgentJson -CmdArgs @('lock-full-access'))
$locked = Invoke-AgentJson -CmdArgs @('permission-status')
if ($locked.data.permission_mode -ne 'DEFAULT' -or $locked.data.full_access.active) { Fail 'lock-full-access did not return to DEFAULT.' }

Write-Host 'Permission UX selftest passed.'
