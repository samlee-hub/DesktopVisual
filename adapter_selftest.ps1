param(
    [string]$Root = '',
    [switch]$SkipLegacySelftest
)

$ErrorActionPreference = 'Stop'
$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$Artifacts = Join-Path $Root 'artifacts'
$Report = Join-Path $Artifacts 'adapter_selftest_report.md'
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$TestRepoRoot = & (Join-Path $Root 'scripts\Resolve-TestRepoRoot.ps1') -Root $Root
$TestWindowRoot = Join-Path $TestRepoRoot 'testwindow'
$TestWindowExe = Join-Path $TestWindowRoot 'bin\TestWindow.exe'
New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null

$checks = New-Object System.Collections.Generic.List[object]
function Add-Check([string]$Name, [bool]$Ok, [string]$Detail) {
    $script:checks.Add([pscustomobject]@{ Name = $Name; Ok = $Ok; Detail = $Detail })
    if ($Ok) { Write-Host "PASS: $Name - $Detail" -ForegroundColor Green }
    else { Write-Host "FAIL: $Name - $Detail" -ForegroundColor Red }
}

function Test-RequiredText([string]$Path) {
    $content = Get-Content -LiteralPath $Path -Raw
    $required = @(
        'observe-locate-act-verify',
        'safety stop rules',
        'no unrestricted desktop control',
        'no sensitive flows'
    )
    foreach ($marker in $required) {
        if ($content.ToLowerInvariant() -notlike "*$marker*") {
            throw "Missing marker '$marker' in $Path"
        }
    }
}

Add-Check 'adapters directory exists' (Test-Path -LiteralPath (Join-Path $Root 'adapters') -PathType Container) 'adapters'
Add-Check 'codex adapter SKILL.md exists' (Test-Path -LiteralPath (Join-Path $Root 'adapters\codex\win-desktop-agent\SKILL.md')) 'adapters\codex\win-desktop-agent\SKILL.md'
Add-Check 'claude-code adapter exists' (Test-Path -LiteralPath (Join-Path $Root 'adapters\claude-code\DESKTOPVISUAL.md')) 'adapters\claude-code\DESKTOPVISUAL.md'
Add-Check 'generic-cli contract exists' (Test-Path -LiteralPath (Join-Path $Root 'adapters\generic-cli\desktopvisual-agent-contract.md')) 'generic-cli contract'
foreach ($file in @('ERROR_HANDLING.md','SAFETY_RULES.md','TASK_FLOW.md','REPORT_READING.md')) {
    Add-Check "shared rule $file exists" (Test-Path -LiteralPath (Join-Path $Root "adapters\shared\$file")) $file
}

foreach ($doc in @(
    'adapters\codex\win-desktop-agent\SKILL.md',
    'adapters\claude-code\DESKTOPVISUAL.md',
    'adapters\generic-cli\README.md',
    'adapters\generic-cli\desktopvisual-agent-contract.md'
)) {
    try {
        Test-RequiredText (Join-Path $Root $doc)
        Add-Check "adapter doc markers $doc" $true 'required safety markers present'
    } catch {
        Add-Check "adapter doc markers $doc" $false $_.Exception.Message
    }
}

try {
    $codexVersion = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'adapters\codex\win-desktop-agent\scripts\desktopvisual-version.ps1') -Root $Root 2>&1
    $codexJson = ($codexVersion | Out-String) | ConvertFrom-Json
    Add-Check 'codex adapter version script' ($codexJson.ok -eq $true -and $codexJson.command -eq 'version') 'version returned ok'
} catch {
    Add-Check 'codex adapter version script' $false $_.Exception.Message
}

try {
    $genericVersion = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'adapters\generic-cli\scripts\desktopvisual-version.ps1') -Root $Root 2>&1
    $genericVersionJson = ($genericVersion | Out-String) | ConvertFrom-Json
    Add-Check 'generic-cli version script' ($genericVersionJson.ok -eq $true) 'normalized version returned ok'
} catch {
    Add-Check 'generic-cli version script' $false $_.Exception.Message
}

$testWindow = $null
try {
    if (-not (Test-Path -LiteralPath $TestWindowExe)) {
        throw "Missing TestWindow.exe: $TestWindowExe"
    }
    Get-Process TestWindow -ErrorAction SilentlyContinue | ForEach-Object {
        $_.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 150
        if (-not $_.HasExited) { Stop-Process -Id $_.Id -Force }
    }
    $testWindow = Start-Process -FilePath $TestWindowExe -PassThru
    Start-Sleep -Milliseconds 800
    $genericObserve = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'adapters\generic-cli\scripts\desktopvisual-observe.ps1') -Root $Root -Title 'Agent Test Window' 2>&1
    $genericObserveJson = ($genericObserve | Out-String) | ConvertFrom-Json
    Add-Check 'generic-cli observe script' ($genericObserveJson.ok -eq $true) 'normalized observe returned ok'
} catch {
    Add-Check 'generic-cli observe script' $false $_.Exception.Message
} finally {
    if ($testWindow -and -not $testWindow.HasExited) {
        $testWindow.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 150
        if (-not $testWindow.HasExited) { Stop-Process -Id $testWindow.Id -Force }
    }
}

if ($SkipLegacySelftest) {
    Add-Check 'legacy skill_template selftest' $true 'skipped by flag'
} else {
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'skill_template\win-desktop-agent\scripts\selftest-skill-template.ps1') -SkipBuild 2>&1 | Out-Null
        Add-Check 'legacy skill_template selftest' ($LASTEXITCODE -eq 0) 'legacy path selftest passed'
    } catch {
        Add-Check 'legacy skill_template selftest' $false $_.Exception.Message
    }
}

$failed = @($checks | Where-Object { -not $_.Ok })
$result = if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# Adapter Selftest Report')
$lines.Add('')
$lines.Add("- Result: $result")
$lines.Add("- Root: $Root")
$lines.Add("- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$lines.Add('')
$lines.Add('| check | result | detail |')
$lines.Add('|---|---|---|')
foreach ($check in $checks) {
    $lines.Add(("| {0} | {1} | {2} |" -f $check.Name, $(if ($check.Ok) { 'PASS' } else { 'FAIL' }), ($check.Detail -replace '\|','/')))
}
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host "Report: $Report"
Write-Host "Overall result: $result"

if ($failed.Count -gt 0) { exit 1 }
exit 0
