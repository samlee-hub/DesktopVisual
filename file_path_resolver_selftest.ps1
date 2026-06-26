param(
    [string]$Root = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\file_path_resolver_selftest.ps1 [-Root <path>]'
    Write-Host 'Validates v5.5.1 FilePathResolver behavior.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactDir = Join-Path $Root 'artifacts\dev5.5.1'
$Report = Join-Path $ArtifactDir 'file_path_resolver_selftest_report.md'
$AllowedRoot = Join-Path $ArtifactDir 'allowed'
$ValidFile = Join-Path $AllowedRoot 'mock_attachment.txt'
$LargeFile = Join-Path $AllowedRoot 'large_attachment.txt'
$MissingFile = Join-Path $AllowedRoot 'missing.txt'
$OutsideFile = Join-Path $Root 'VERSION'

New-Item -ItemType Directory -Force -Path $AllowedRoot | Out-Null
Set-Content -LiteralPath $ValidFile -Encoding UTF8 -Value 'mock attachment content'
Set-Content -LiteralPath $LargeFile -Encoding UTF8 -Value ('x' * 32)

if (-not (Test-Path -LiteralPath $WinAgent)) {
    throw "Missing winagent.exe. Run build.ps1 first: $WinAgent"
}

function Invoke-JsonCommand {
    param([string[]]$Arguments, [int[]]$AllowedExitCodes = @(0))
    $output = & $WinAgent @Arguments 2>&1
    $exit = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    if ($AllowedExitCodes -notcontains $exit) {
        throw "Unexpected exit $exit for $($Arguments -join ' '): $text"
    }
    $json = $text | ConvertFrom-Json
    return [pscustomobject]@{ ExitCode = $exit; Text = $text; Json = $json }
}

$valid = Invoke-JsonCommand @('file-path-resolve', '--path', $ValidFile, '--allowed-roots', $AllowedRoot, '--extensions', '.txt,.md', '--max-bytes', '4096')
if (-not $valid.Json.ok -or $valid.Json.data.exists -ne $true -or $valid.Json.data.file_name -ne 'mock_attachment.txt') {
    throw "Expected valid file resolution. output=$($valid.Text)"
}
if ($valid.Json.data.content_preview -or $valid.Json.data.content) {
    throw 'File metadata must not leak content.'
}

$noRoots = Invoke-JsonCommand @('file-path-resolve', '--path', $ValidFile, '--extensions', '.txt') -AllowedExitCodes @(1)
if ($noRoots.Json.ok -or $noRoots.Json.error.code -ne 'FILE_ALLOWED_ROOTS_REQUIRED') {
    throw "Expected explicit allowed roots requirement. output=$($noRoots.Text)"
}

$missing = Invoke-JsonCommand @('file-path-resolve', '--path', $MissingFile, '--allowed-roots', $AllowedRoot, '--extensions', '.txt') -AllowedExitCodes @(1)
if ($missing.Json.ok -or $missing.Json.error.code -ne 'FILE_PICKER_FILE_NOT_FOUND') {
    throw "Expected missing file failure. output=$($missing.Text)"
}

$outside = Invoke-JsonCommand @('file-path-resolve', '--path', $OutsideFile, '--allowed-roots', $AllowedRoot, '--extensions', '.txt,.md') -AllowedExitCodes @(1)
if ($outside.Json.ok -or $outside.Json.error.code -ne 'FILE_PATH_OUTSIDE_ALLOWED_ROOT') {
    throw "Expected outside root failure. output=$($outside.Text)"
}

$traversal = Invoke-JsonCommand @('file-path-resolve', '--path', (Join-Path $AllowedRoot '..\mock_attachment.txt'), '--allowed-roots', $AllowedRoot, '--extensions', '.txt') -AllowedExitCodes @(1)
if ($traversal.Json.ok -or $traversal.Json.error.code -ne 'FILE_PATH_TRAVERSAL_DENIED') {
    throw "Expected traversal failure. output=$($traversal.Text)"
}

$extension = Invoke-JsonCommand @('file-path-resolve', '--path', $ValidFile, '--allowed-roots', $AllowedRoot, '--extensions', '.json') -AllowedExitCodes @(1)
if ($extension.Json.ok -or $extension.Json.error.code -ne 'FILE_EXTENSION_DENIED') {
    throw "Expected extension policy failure. output=$($extension.Text)"
}

$size = Invoke-JsonCommand @('file-path-resolve', '--path', $LargeFile, '--allowed-roots', $AllowedRoot, '--extensions', '.txt', '--max-bytes', '8') -AllowedExitCodes @(1)
if ($size.Json.ok -or $size.Json.error.code -ne 'FILE_TOO_LARGE') {
    throw "Expected file size policy failure. output=$($size.Text)"
}

$lines = @(
    '# v5.5.1 File Path Resolver Selftest Report',
    '',
    '- Result: PASS',
    "- Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    '- valid file: PASS',
    '- explicit allowed roots required: PASS',
    '- missing file: PASS',
    '- outside allowed root: PASS',
    '- path traversal: PASS',
    '- extension policy: PASS',
    '- file size policy: PASS',
    '- metadata without content leak: PASS',
    '',
    '## Valid Output',
    '',
    '```json',
    $valid.Text,
    '```'
)
$lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host 'PASS: v5.5.1 file path resolver selftest'
Write-Host "Report: $Report"
