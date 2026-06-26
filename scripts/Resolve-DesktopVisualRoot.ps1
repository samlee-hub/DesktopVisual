param(
    [string]$Root = '',
    [string]$StartPath = ''
)

function Resolve-DesktopVisualRoot {
    param(
        [string]$Root = '',
        [string]$StartPath = ''
    )

    if ($Root) {
        return [System.IO.Path]::GetFullPath($Root)
    }

    if ($env:DESKTOPVISUAL_ROOT) {
        return [System.IO.Path]::GetFullPath($env:DESKTOPVISUAL_ROOT)
    }

    $cursor = if ($StartPath) { $StartPath } elseif ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $cursor = [System.IO.Path]::GetFullPath($cursor)
    if (Test-Path -LiteralPath $cursor -PathType Leaf) {
        $cursor = Split-Path -Parent $cursor
    }

    while ($cursor) {
        $version = Join-Path $cursor 'VERSION'
        $src = Join-Path $cursor 'src'
        if ((Test-Path -LiteralPath $version -PathType Leaf) -and
            (Test-Path -LiteralPath $src -PathType Container)) {
            return $cursor
        }

        $parent = Split-Path -Parent $cursor
        if (!$parent -or $parent -eq $cursor) {
            break
        }
        $cursor = $parent
    }

    Write-Warning 'DesktopVisual root was not found from -Root, DESKTOPVISUAL_ROOT, or script path. Falling back to D:\desktopvisual.'
    return 'D:\desktopvisual'
}

Resolve-DesktopVisualRoot -Root $Root -StartPath $StartPath
