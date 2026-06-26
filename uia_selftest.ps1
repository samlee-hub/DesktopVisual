param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$TestRepoRoot = & (Join-Path $Root 'scripts\Resolve-TestRepoRoot.ps1') -Root $Root
$TestWindowRoot = Join-Path $TestRepoRoot 'testwindow'
$TestWindowExe = Join-Path $TestWindowRoot 'bin\TestWindow.exe'

function Fail($Message) {
    Write-Host "FAIL: $Message"
    exit 1
}

function Invoke-AgentJson {
    param([string[]]$WinArgs)

    $output = & $WinAgent @WinArgs
    $exit = $LASTEXITCODE
    if ($exit -ne 0) {
        Fail "winagent $($WinArgs -join ' ') exited $exit with output: $output"
    }

    try {
        return $output | ConvertFrom-Json
    } catch {
        Fail "Invalid JSON from winagent $($WinArgs -join ' '): $output"
    }
}

& (Join-Path $Root 'build.ps1') -Root $Root -TestRepoRoot $TestRepoRoot
if ($LASTEXITCODE -ne 0) {
    Fail "build.ps1 failed with exit $LASTEXITCODE"
}

if (!(Test-Path -LiteralPath $WinAgent)) {
    Fail "Missing $WinAgent"
}
if (!(Test-Path -LiteralPath $TestWindowExe)) {
    Fail "Missing $TestWindowExe"
}

Get-Process TestWindow -ErrorAction SilentlyContinue | ForEach-Object {
    $_.CloseMainWindow() | Out-Null
    Start-Sleep -Milliseconds 300
    if (!$_.HasExited) {
        Stop-Process -Id $_.Id -Force
    }
}

$proc = Start-Process -FilePath $TestWindowExe -PassThru
try {
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 250
        $find = & $WinAgent find --title 'Agent Test Window'
        $findExit = $LASTEXITCODE
    } while ($findExit -ne 0 -and (Get-Date) -lt $deadline)

    if ($findExit -ne 0) {
        Fail "Agent Test Window did not appear."
    }

    $tree = Invoke-AgentJson -WinArgs @('uia-tree', '--title', 'Agent Test Window')
    if ($tree.ok -ne $true -or $tree.command -ne 'uia-tree') {
        Fail 'uia-tree did not return a successful unified JSON envelope.'
    }
    if ($null -eq $tree.data.elements -or $tree.data.elements.Count -le 0) {
        Fail 'uia-tree returned no elements.'
    }

    $clickMe = $tree.data.elements | Where-Object { $_.name -eq 'Click Me' } | Select-Object -First 1
    if ($null -eq $clickMe) {
        Fail 'uia-tree did not include the Click Me button.'
    }

    $found = Invoke-AgentJson -WinArgs @('uia-find', '--title', 'Agent Test Window', '--name', 'Click Me')
    if ($found.ok -ne $true -or $found.command -ne 'uia-find') {
        Fail 'uia-find did not return a successful unified JSON envelope.'
    }
    if ($found.data.name -ne 'Click Me') {
        Fail "uia-find returned unexpected name: $($found.data.name)"
    }
    if ($null -eq $found.data.rect -or $null -eq $found.data.rect.left -or $null -eq $found.data.rect.right) {
        Fail 'uia-find did not return a rect.'
    }

    Write-Host 'PASS: UI Automation selftest passed.'
    Write-Host "uia-tree element_count: $($tree.data.elements.Count)"
    Write-Host "uia-find: name=$($found.data.name) control_type=$($found.data.control_type) rect=($($found.data.rect.left),$($found.data.rect.top),$($found.data.rect.right),$($found.data.rect.bottom))"
}
finally {
    if ($proc -and !$proc.HasExited) {
        $proc.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (!$proc.HasExited) {
            Stop-Process -Id $proc.Id -Force
        }
    }
}
