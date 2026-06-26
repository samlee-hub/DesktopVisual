param(
    [switch]$Help,
    [ValidateSet('probe', 'locate')]
    [string]$Mode = 'probe',
    [string]$Provider = 'codex-cli',
    [string]$ImagePath = '',
    [string]$Target = '',
    [string]$RawOutputPath = '',
    [int]$TimeoutMs = 60000,
    [ValidateSet('', 'unavailable', 'timeout', 'invalid_json', 'valid', 'low_confidence', 'not_found')]
    [string]$Simulation = ''
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\tools\codex_vlm_provider.ps1 -Mode probe|locate -ImagePath <png> -RawOutputPath <path> [-Target <text>] [-TimeoutMs <ms>]'
    exit 0
}

function Write-ProviderText {
    param([string]$Path, [string]$Text)
    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        $parent = Split-Path -Parent $Path
        if (-not [string]::IsNullOrWhiteSpace($parent)) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }
        Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
    }
}

function Get-ImageSize {
    param([string]$Path)
    $result = [ordered]@{ width = 0; height = 0 }
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $img = [System.Drawing.Image]::FromFile($Path)
        try {
            $result.width = [int]$img.Width
            $result.height = [int]$img.Height
        } finally {
            $img.Dispose()
        }
    } catch {
        $result.width = 0
        $result.height = 0
    }
    return $result
}

function ConvertTo-ProviderJson {
    param([hashtable]$Value)
    $Value | ConvertTo-Json -Depth 8 -Compress
}

function Resolve-CodexExecutable {
    param([System.Management.Automation.CommandInfo]$Command)
    $source = $Command.Source
    if ($source -like '*.ps1') {
        $cmdShim = [System.IO.Path]::ChangeExtension($source, '.cmd')
        if (Test-Path -LiteralPath $cmdShim) {
            return $cmdShim
        }
    }
    return $source
}

function Invoke-WithTimeout {
    param(
        [string]$Exe,
        [string[]]$ArgumentList,
        [string]$StdinText,
        [int]$Timeout
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = (($ArgumentList | ForEach-Object { Quote-ProcessArgument $_ }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = (Get-Location).Path

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    try {
        [void]$proc.Start()
        if (-not [string]::IsNullOrEmpty($StdinText)) {
            $proc.StandardInput.Write($StdinText)
        }
        $proc.StandardInput.Close()
        $completed = $proc.WaitForExit($Timeout)
        if (-not $completed) {
            try {
                $proc.Kill()
            } catch {
            }
            return [pscustomobject]@{
                timed_out = $true
                output = ''
                stderr = ''
                exit_code = 124
            }
        }
        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()
        return [pscustomobject]@{
            timed_out = $false
            output = [string]$stdout
            stderr = [string]$stderr
            exit_code = [int]$proc.ExitCode
        }
    } catch {
        return [pscustomobject]@{
            timed_out = $false
            output = ''
            stderr = [string]$_.Exception.Message
            exit_code = 255
        }
    } finally {
        $proc.Dispose()
    }
}

function New-CodexExecInvocation {
    param(
        [System.Management.Automation.CommandInfo]$Command,
        [string]$Prompt,
        [string]$Image,
        [string]$LastMessagePath
    )
    $source = Resolve-CodexExecutable -Command $Command
    $promptArg = (($Prompt -replace '[\r\n]+', ' ') -replace '\s{2,}', ' ').Trim()
    return [pscustomobject]@{
        exe = $source
        argument_list = @('exec', '--image', $Image, '--output-last-message', $LastMessagePath, $promptArg)
    }
}

function Quote-ProcessArgument {
    param([string]$Value)
    if ($null -eq $Value) {
        return '""'
    }
    if ($Value -notmatch '[\s"]') {
        return $Value
    }
    $escaped = $Value -replace '\\(?=\\*")', '$&$&'
    $escaped = $escaped -replace '"', '\"'
    return '"' + $escaped + '"'
}

function Get-CodexVersion {
    param([System.Management.Automation.CommandInfo]$Command)
    try {
        $source = Resolve-CodexExecutable -Command $Command
        $version = & $source --version 2>$null
        return ([string]$version).Trim()
    } catch {
        return ''
    }
}

function Get-CodexExecHelp {
    param([System.Management.Automation.CommandInfo]$Command)
    try {
        $source = Resolve-CodexExecutable -Command $Command
        $help = & $source exec --help 2>$null
        return ([string]$help)
    } catch {
        return ''
    }
}

function New-ProbePrompt {
    @'
You are a visual capability probe for DesktopVisual.
Analyze only the attached image. Do not perform actions. Do not decide backend fallback. Do not bypass safety mechanisms.
Return JSON only with keys: ok, image_input_observed, visible_text, reason.
Set image_input_observed=true only if you can see image content.
'@
}

function New-LocatePrompt {
    param([string]$RequestedTarget, [int]$Width, [int]$Height)
    @"
You are DesktopVisual's assistive visual locator. You can only analyze the attached image.
You cannot execute actions, move the mouse, click, type, run commands, decide backend fallback, or bypass safety mechanisms.
Return JSON only. Do not include markdown or natural language outside JSON.
Use screenshot pixel coordinates. If unsure, set target_found=false or use low confidence.
Requested target: $RequestedTarget
Image size: ${Width}x${Height}
Return one JSON object with keys ok, target_found, target_label, target_type, confidence, bbox, point, coordinate_space, image_width, image_height, reason, visible_text, uncertainty, safety_flags, requires_human_review.
target_type must be one of button, icon, text, menu, input, window, region, unknown.
bbox must be an object with numeric x, y, w, h in image pixels.
point must be an object with numeric x and y in image pixels.
coordinate_space must equal image_pixels.
"@
}

if ($Provider -ne 'codex-cli') {
    Write-ProviderText -Path $RawOutputPath -Text "provider '$Provider' is not supported by codex_vlm_provider.ps1"
    ConvertTo-ProviderJson @{
        ok = $false
        provider = $Provider
        provider_status = 'VLM_UNAVAILABLE'
        codex_cli_version = ''
        image_input_supported = $false
        raw_output_path = $RawOutputPath
        reason = 'unsupported provider'
        exit_code = 127
    }
    exit 0
}

if ($Simulation -eq 'unavailable') {
    Write-ProviderText -Path $RawOutputPath -Text 'simulated provider unavailable'
    ConvertTo-ProviderJson @{
        ok = $false
        provider = $Provider
        provider_status = 'VLM_UNAVAILABLE'
        codex_cli_version = ''
        image_input_supported = $false
        raw_output_path = $RawOutputPath
        reason = 'simulated provider unavailable'
        exit_code = 127
    }
    exit 0
}

if ($Simulation -eq 'timeout') {
    Write-ProviderText -Path $RawOutputPath -Text 'simulated provider timeout'
    ConvertTo-ProviderJson @{
        ok = $false
        provider = $Provider
        provider_status = 'VLM_TIMEOUT'
        codex_cli_version = ''
        image_input_supported = $true
        raw_output_path = $RawOutputPath
        reason = 'simulated provider timeout'
        exit_code = 124
    }
    exit 0
}

if ([string]::IsNullOrWhiteSpace($ImagePath) -or -not (Test-Path -LiteralPath $ImagePath)) {
    Write-ProviderText -Path $RawOutputPath -Text 'image not found'
    ConvertTo-ProviderJson @{
        ok = $false
        provider = $Provider
        provider_status = 'VLM_UNAVAILABLE'
        codex_cli_version = ''
        image_input_supported = $false
        raw_output_path = $RawOutputPath
        reason = 'image not found'
        exit_code = 2
    }
    exit 0
}

$codex = Get-Command codex -ErrorAction SilentlyContinue
if (-not $codex) {
    Write-ProviderText -Path $RawOutputPath -Text 'codex command not found'
    ConvertTo-ProviderJson @{
        ok = $false
        provider = $Provider
        provider_status = 'VLM_UNAVAILABLE'
        codex_cli_version = ''
        image_input_supported = $false
        raw_output_path = $RawOutputPath
        reason = 'codex command not found'
        exit_code = 127
    }
    exit 0
}

$codexVersion = Get-CodexVersion -Command $codex
$execHelp = Get-CodexExecHelp -Command $codex
$imageSupported = $execHelp -match '--image'

if (-not $imageSupported) {
    Write-ProviderText -Path $RawOutputPath -Text 'codex exec --image is not supported'
    ConvertTo-ProviderJson @{
        ok = $false
        provider = $Provider
        provider_status = 'VLM_UNAVAILABLE'
        codex_cli_version = $codexVersion
        image_input_supported = $false
        raw_output_path = $RawOutputPath
        reason = 'codex exec --image is not supported'
        exit_code = 2
    }
    exit 0
}

$size = Get-ImageSize -Path $ImagePath

if ($Mode -eq 'locate') {
    if ($Simulation -eq 'valid') {
        $x = [Math]::Max(0, [Math]::Min(120, [Math]::Max(0, $size.width - 2)))
        $y = [Math]::Max(0, [Math]::Min(70, [Math]::Max(0, $size.height - 2)))
        $w = [Math]::Max(1, [Math]::Min(150, $size.width - $x))
        $h = [Math]::Max(1, [Math]::Min(50, $size.height - $y))
        $raw = @{
            ok = $true
            target_found = $true
            target_label = $Target
            target_type = 'button'
            confidence = 0.91
            bbox = @{ x = $x; y = $y; w = $w; h = $h }
            point = @{ x = [int]($x + ($w / 2)); y = [int]($y + ($h / 2)) }
            coordinate_space = 'image_pixels'
            image_width = $size.width
            image_height = $size.height
            reason = 'simulated valid provider locate response'
            visible_text = @($Target)
            uncertainty = ''
            safety_flags = @()
            requires_human_review = $false
        } | ConvertTo-Json -Depth 8 -Compress
        Write-ProviderText -Path $RawOutputPath -Text $raw
        ConvertTo-ProviderJson @{
            ok = $true
            provider = $Provider
            provider_status = 'VLM_AVAILABLE'
            codex_cli_version = $codexVersion
            image_input_supported = $true
            raw_output_path = $RawOutputPath
            reason = 'simulated valid response'
            exit_code = 0
        }
        exit 0
    }
    if ($Simulation -eq 'invalid_json') {
        Write-ProviderText -Path $RawOutputPath -Text 'this is not json'
        ConvertTo-ProviderJson @{
            ok = $true
            provider = $Provider
            provider_status = 'VLM_AVAILABLE'
            codex_cli_version = $codexVersion
            image_input_supported = $true
            raw_output_path = $RawOutputPath
            reason = 'simulated invalid JSON response'
            exit_code = 0
        }
        exit 0
    }
    if ($Simulation -eq 'low_confidence') {
        $raw = @{
            ok = $true
            target_found = $true
            target_label = $Target
            target_type = 'button'
            confidence = 0.2
            bbox = @{ x = 10; y = 10; w = 80; h = 30 }
            point = @{ x = 50; y = 25 }
            coordinate_space = 'image_pixels'
            image_width = $size.width
            image_height = $size.height
            reason = 'simulated low confidence'
            visible_text = @($Target)
            uncertainty = 'low confidence simulation'
            safety_flags = @()
            requires_human_review = $false
        } | ConvertTo-Json -Depth 8 -Compress
        Write-ProviderText -Path $RawOutputPath -Text $raw
        ConvertTo-ProviderJson @{
            ok = $true
            provider = $Provider
            provider_status = 'VLM_AVAILABLE'
            codex_cli_version = $codexVersion
            image_input_supported = $true
            raw_output_path = $RawOutputPath
            reason = 'simulated low confidence response'
            exit_code = 0
        }
        exit 0
    }
    if ($Simulation -eq 'not_found') {
        $raw = @{
            ok = $true
            target_found = $false
            target_label = $Target
            target_type = 'unknown'
            confidence = 0.0
            bbox = @{ x = 0; y = 0; w = 0; h = 0 }
            point = @{ x = 0; y = 0 }
            coordinate_space = 'image_pixels'
            image_width = $size.width
            image_height = $size.height
            reason = 'simulated target not found'
            visible_text = @()
            uncertainty = 'target not visible'
            safety_flags = @()
            requires_human_review = $false
        } | ConvertTo-Json -Depth 8 -Compress
        Write-ProviderText -Path $RawOutputPath -Text $raw
        ConvertTo-ProviderJson @{
            ok = $true
            provider = $Provider
            provider_status = 'VLM_AVAILABLE'
            codex_cli_version = $codexVersion
            image_input_supported = $true
            raw_output_path = $RawOutputPath
            reason = 'simulated not found response'
            exit_code = 0
        }
        exit 0
    }
}

$prompt = if ($Mode -eq 'probe') {
    New-ProbePrompt
} else {
    New-LocatePrompt -RequestedTarget $Target -Width $size.width -Height $size.height
}

$lastMessagePath = if ([string]::IsNullOrWhiteSpace($RawOutputPath)) {
    [System.IO.Path]::GetTempFileName()
} else {
    "$RawOutputPath.last_message.txt"
}

$invocation = New-CodexExecInvocation -Command $codex -Prompt $prompt -Image $ImagePath -LastMessagePath $lastMessagePath
$run = Invoke-WithTimeout -Exe $invocation.exe -ArgumentList $invocation.argument_list -StdinText '' -Timeout $TimeoutMs

$modelOutput = ''
if (Test-Path -LiteralPath $lastMessagePath) {
    $modelOutput = Get-Content -LiteralPath $lastMessagePath -Raw -ErrorAction SilentlyContinue
}
if ([string]::IsNullOrWhiteSpace($modelOutput)) {
    $modelOutput = [string]$run.output
}
if ([string]::IsNullOrWhiteSpace($modelOutput) -and -not [string]::IsNullOrWhiteSpace($run.stderr)) {
    $modelOutput = [string]$run.stderr
}

Write-ProviderText -Path $RawOutputPath -Text $modelOutput

$status = 'VLM_AVAILABLE'
$reason = 'provider returned output'
if ($run.timed_out) {
    $status = 'VLM_TIMEOUT'
    $reason = 'provider timed out'
} elseif ($run.exit_code -ne 0) {
    $status = 'VLM_UNAVAILABLE'
    $reason = "provider exited with code $($run.exit_code)"
} elseif ([string]::IsNullOrWhiteSpace($modelOutput)) {
    $status = 'VLM_UNKNOWN'
    $reason = 'provider returned empty output'
}

ConvertTo-ProviderJson @{
    ok = ($status -eq 'VLM_AVAILABLE')
    provider = $Provider
    provider_status = $status
    codex_cli_version = $codexVersion
    image_input_supported = $imageSupported
    raw_output_path = $RawOutputPath
    reason = $reason
    exit_code = $run.exit_code
    image_width = $size.width
    image_height = $size.height
}
