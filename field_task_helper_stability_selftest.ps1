param()

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root

$ArtifactDir = Join-Path $Root "artifacts\dev1.2.0_helper_stability_selftest"
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

$helperGlobs = @(
    "adapters\codex\win-desktop-agent\scripts\*.ps1",
    "adapters\generic-cli\scripts\*.ps1",
    "adapters\claude-code\scripts\*.ps1",
    "skill_template\win-desktop-agent\scripts\*.ps1",
    "desktopvisual.ps1",
    "serve_start.ps1",
    "serve_stop.ps1"
)

$helperFiles = @()
foreach ($glob in $helperGlobs) {
    $parent = Split-Path -Parent (Join-Path $Root $glob)
    $leaf = Split-Path -Leaf $glob
    if (Test-Path -LiteralPath $parent) {
        $helperFiles += @(Get-ChildItem -LiteralPath $parent -Filter $leaf -File -ErrorAction SilentlyContinue)
    }
}
$helperFiles = @($helperFiles | Sort-Object FullName -Unique)

if ($helperFiles.Count -gt 0) {
    Add-Pass "helper script set discovered"
} else {
    Add-Failure "no helper scripts discovered"
}

$badArgs = @()
$badNameColon = @()
$badDesktopClick = @()
$badEmptyCommand = @()

foreach ($file in $helperFiles) {
    $relative = $file.FullName.Substring($Root.Length + 1)
    $text = Get-Content -Raw -LiteralPath $file.FullName
    if ($text -match '(?m)^\s*\$args\s*=') {
        $badArgs += $relative
    }
    if ($text -match '(?s)desktop-(click|double-click|move)[^\r\n]*--x|(?s)--x[^\r\n]*desktop-(click|double-click|move)') {
        $badDesktopClick += $relative
    }
    if ($text -match '(?m)&\s*\$WinAgent\s+@\(\s*\)|&\s*\$Agent\s+@\(\s*\)|&\s*\$WinAgent\s*$|&\s*\$Agent\s*$') {
        $badEmptyCommand += $relative
    }
}

if ($badArgs.Count -eq 0) {
    Add-Pass "helper scripts avoid `$args local variable collision"
} else {
    Add-Failure "helper scripts use `$args as a local variable: $($badArgs -join ', ')"
}

if ($badDesktopClick.Count -eq 0) {
    Add-Pass "desktop mouse helpers use --screen-x/--screen-y instead of --x/--y"
} else {
    Add-Failure "desktop mouse helpers may use --x/--y: $($badDesktopClick -join ', ')"
}

if ($badEmptyCommand.Count -eq 0) {
    Add-Pass "helpers do not call winagent with an empty command"
} else {
    Add-Failure "helpers may call winagent with an empty command: $($badEmptyCommand -join ', ')"
}

foreach ($file in $helperFiles) {
    $parseErrors = $null
    $tokens = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
    $relative = $file.FullName.Substring($Root.Length + 1)
    $expandableStrings = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.ExpandableStringExpressionAst] }, $true)
    foreach ($stringAst in $expandableStrings) {
        if ($stringAst.Value -match '(?<!`)\$[A-Za-z_][A-Za-z0-9_]*:') {
            $badNameColon += $relative
            break
        }
    }
    if ($parseErrors.Count -eq 0) {
        Add-Pass "PowerShell parses $($file.Name)"
    } else {
        Add-Failure "PowerShell parse errors in $($file.FullName): $($parseErrors[0].Message)"
    }
}

if ($badNameColon.Count -eq 0) {
    Add-Pass "helper scripts avoid `$name: PowerShell parse hazard"
} else {
    Add-Failure "helper scripts contain `$name: parse hazard: $($badNameColon -join ', ')"
}

$Report | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $ArtifactDir "helper_stability_report.md")

if ($Failures.Count -eq 0) {
    Write-Host "Field task helper stability selftest PASS"
    exit 0
}

Write-Host "Field task helper stability selftest FAIL: $($Failures.Count) failure(s)"
exit 1
