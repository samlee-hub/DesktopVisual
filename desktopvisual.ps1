param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$ForwardArgs
)

$ErrorActionPreference = 'Stop'

$Root = $PSScriptRoot
$Agent = Join-Path -Path $Root -ChildPath 'bin\winagent.exe'

if (-not (Test-Path -LiteralPath $Agent)) {
    throw "DesktopVisual runtime not found: $Agent"
}

if ($null -eq $ForwardArgs) {
    $ForwardArgs = @()
}

& $Agent @ForwardArgs
exit $LASTEXITCODE
