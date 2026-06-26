param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$WinAgent = Join-Path $Root 'bin\winagent.exe'
$TestWindowExe = 'D:\testrepo\testwindow\bin\TestWindow.exe'
$Artifacts = Join-Path $Root 'artifacts\dev4.1.0'
$SourceBmp = Join-Path $Artifacts 'observe2_source.bmp'
$TemplateBmp = Join-Path $Artifacts 'observe2_template.bmp'
$Report = Join-Path $Artifacts 'observe2_provider_selftest_report.md'

function Fail($Message) { throw $Message }

function Invoke-WinAgentJson {
    param([string[]]$WinArgs, [int[]]$AllowedExitCodes = @(0))
    $output = & $WinAgent @WinArgs 2>&1
    $exit = $LASTEXITCODE
    if ($AllowedExitCodes -notcontains $exit) {
        Fail "winagent $($WinArgs -join ' ') exited $exit with output: $output"
    }
    try {
        $json = $output | ConvertFrom-Json
    } catch {
        Fail "Invalid JSON from winagent $($WinArgs -join ' '): $output"
    }
    return @{ exit = $exit; text = [string]$output; json = $json }
}

function New-TemplateFromScreenshot([string]$Source, [string]$Template) {
    Add-Type -AssemblyName System.Drawing
    $bmp = [System.Drawing.Bitmap]::new($Source)
    try {
        $width = [Math]::Min(120, $bmp.Width)
        $height = [Math]::Min(80, $bmp.Height)
        if ($width -le 0 -or $height -le 0) { Fail 'Screenshot dimensions are invalid.' }
        $crop = [System.Drawing.Rectangle]::new(0, 0, $width, $height)
        $templ = $bmp.Clone($crop, $bmp.PixelFormat)
        try {
            $templ.Save($Template, [System.Drawing.Imaging.ImageFormat]::Bmp)
        } finally {
            $templ.Dispose()
        }
    } finally {
        $bmp.Dispose()
    }
}

if (!(Test-Path -LiteralPath $WinAgent)) { Fail "Missing $WinAgent. Run $Root\build.ps1 first." }
if (!(Test-Path -LiteralPath $TestWindowExe)) { Fail "Missing $TestWindowExe. Run $Root\build.ps1 first." }

New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null
Remove-Item -LiteralPath $SourceBmp, $TemplateBmp, $Report -ErrorAction SilentlyContinue

Get-Process TestWindow -ErrorAction SilentlyContinue | ForEach-Object {
    $_.CloseMainWindow() | Out-Null
    Start-Sleep -Milliseconds 300
    if (!$_.HasExited) { Stop-Process -Id $_.Id -Force }
}

$proc = Start-Process -FilePath $TestWindowExe -PassThru
try {
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 250
        $find = Invoke-WinAgentJson -WinArgs @('find', '--title', 'Agent Test Window') -AllowedExitCodes @(0, 1)
    } while ($find.exit -ne 0 -and (Get-Date) -lt $deadline)
    if ($find.exit -ne 0) { Fail 'Agent Test Window did not appear.' }

    $missingTitle = Invoke-WinAgentJson -WinArgs @('observe2') -AllowedExitCodes @(2)
    if ($missingTitle.json.error.code -ne 'INVALID_ARGUMENT') {
        Fail "observe2 without --title should return INVALID_ARGUMENT: $($missingTitle.text)"
    }

    $shot = Invoke-WinAgentJson -WinArgs @('screenshot', '--title', 'Agent Test Window', '--out', $SourceBmp)
    if ($shot.json.ok -ne $true -or !(Test-Path -LiteralPath $SourceBmp)) {
        Fail "Could not create source screenshot: $($shot.text)"
    }
    New-TemplateFromScreenshot -Source $SourceBmp -Template $TemplateBmp

    $observe2 = Invoke-WinAgentJson -WinArgs @(
        'observe2',
        '--title', 'Agent Test Window',
        '--screenshot',
        '--include-uia',
        '--max-elements', '25',
        '--image-template', $TemplateBmp,
        '--tolerance', '0'
    )
    if ($observe2.json.ok -ne $true -or $observe2.json.command -ne 'observe2') { Fail "observe2 failed: $($observe2.text)" }
    if (!$observe2.json.data.screen_frame -or !$observe2.json.data.element_graph -or !$observe2.json.data.locator_candidates) {
        Fail "observe2 missing v4 perception structures: $($observe2.text)"
    }
    if (!$observe2.json.data.providers -or !$observe2.json.data.perception_sources) {
        Fail "observe2 missing providers/perception_sources: $($observe2.text)"
    }

    $providerNames = @($observe2.json.data.providers | ForEach-Object { $_.name })
    foreach ($required in @('uia', 'ocr', 'screen_delta', 'image_template', 'local_visual_provider', 'cloud_vlm', 'agent_provider')) {
        if ($providerNames -notcontains $required) { Fail "Provider registry missing ${required}: $($observe2.text)" }
    }
    $imageProvider = @($observe2.json.data.providers | Where-Object { $_.name -eq 'image_template' })[0]
    if ($imageProvider.status -ne 'available') { Fail "image_template provider should be available: $($observe2.text)" }
    $omniLikeUnavailable = @($observe2.json.data.providers | Where-Object { $_.name -eq 'local_visual_provider' })[0]
    if ($omniLikeUnavailable.status -notin @('unavailable', 'degraded')) {
        Fail "local_visual_provider should degrade gracefully: $($observe2.text)"
    }

    $visualCandidates = @($observe2.json.data.locator_candidates | Where-Object { $_.source -eq 'image_template' })
    if ($visualCandidates.Count -lt 1) { Fail "No image_template locator candidate returned: $($observe2.text)" }
    $candidate = $visualCandidates[0]
    foreach ($field in @('source', 'source_version', 'label', 'role', 'text', 'rect', 'confidence', 'attributes', 'artifact_path', 'provider_latency_ms', 'semantic_status')) {
        if ($null -eq $candidate.$field) { Fail "image_template candidate missing ${field}: $($observe2.text)" }
    }
    if ($candidate.semantic_status -ne 'unresolved') { Fail "visual-only image_template candidate must be unresolved." }
    if (@($observe2.json.data.element_graph.nodes | Where-Object { $_.source -eq 'image_template' }).Count -lt 1) {
        Fail "ElementGraph did not receive image_template node: $($observe2.text)"
    }

    $blocked = Invoke-WinAgentJson -WinArgs @(
        'act',
        '--title', 'Agent Test Window',
        '--selector', 'visual:id=image_template:0',
        '--action', 'click'
    ) -AllowedExitCodes @(1)
    if ($blocked.json.error.code -ne 'ACTION_BLOCKED_SEMANTIC_UNRESOLVED') {
        Fail "visual-only unresolved action was not blocked: $($blocked.text)"
    }

    @(
        '# DesktopVisual observe2 Provider Selftest',
        '',
        '- Result: PASS',
        "- Source screenshot: $SourceBmp",
        "- Template: $TemplateBmp",
        "- Provider count: $($observe2.json.data.providers.Count)",
        "- Image template candidates: $($visualCandidates.Count)",
        "- Visual-only action block: ACTION_BLOCKED_SEMANTIC_UNRESOLVED"
    ) | Set-Content -Encoding UTF8 -LiteralPath $Report

    Write-Host 'observe2 provider selftest passed.'
    Write-Host "Report: $Report"
} finally {
    if ($proc -and !$proc.HasExited) {
        $proc.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 300
        if (!$proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    }
}
