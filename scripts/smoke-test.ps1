$ErrorActionPreference = 'Stop'
$Root = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')
$VersionFile = Join-Path $Root 'VERSION'
$Binary = Join-Path $Root 'bin\winagent.exe'
$Protocol = Join-Path $Root 'COMMAND_PROTOCOL.md'
$Skill = Join-Path $Root 'skills\desktopvisual-visible-ui-first\SKILL.md'
$Checksums = Join-Path $Root 'checksums\SHA256SUMS.txt'
$SmokeArtifacts = Join-Path $Root 'artifacts'

function Fail($Message) { throw $Message }
function Remove-SmokeArtifacts { if (Test-Path -LiteralPath $SmokeArtifacts) { Remove-Item -LiteralPath $SmokeArtifacts -Recurse -Force } }
function Join-Private($driveChar, $tail) { return ([string][char]$driveChar) + ':\' + $tail }
function Test-BytesContains([byte[]]$Bytes, [byte[]]$Needle) {
    if ($Needle.Length -eq 0 -or $Bytes.Length -lt $Needle.Length) { return $false }
    for ($i = 0; $i -le $Bytes.Length - $Needle.Length; $i++) {
        $ok = $true
        for ($j = 0; $j -lt $Needle.Length; $j++) {
            if ($Bytes[$i + $j] -ne $Needle[$j]) { $ok = $false; break }
        }
        if ($ok) { return $true }
    }
    return $false
}

Remove-SmokeArtifacts

if (!(Test-Path -LiteralPath $Binary)) { Fail 'Missing binary.' }
if (!(Test-Path -LiteralPath $VersionFile)) { Fail 'Missing VERSION.' }
if ((Get-Content -LiteralPath $VersionFile -Raw).Trim() -ne '1.0.0') { Fail 'VERSION is not 1.0.0.' }

$versionOutput = & $Binary version
if ($LASTEXITCODE -ne 0) { Fail 'version command failed.' }
$versionJson = $versionOutput | ConvertFrom-Json
if ($versionJson.data.version -ne '1.0.0') { Fail 'winagent version did not report 1.0.0.' }
Remove-SmokeArtifacts

if (!(Test-Path -LiteralPath $Protocol)) { Fail 'Missing COMMAND_PROTOCOL.md.' }
if (!(Test-Path -LiteralPath $Skill)) { Fail 'Missing public skill.' }
$skillText = Get-Content -LiteralPath $Skill -Raw
if ($skillText -notmatch '^---\s*\r?\nname:\s*desktopvisual-visible-ui-first\s*\r?\ndescription:') { Fail 'Skill frontmatter is invalid.' }
if (!(Test-Path -LiteralPath $Checksums)) { Fail 'Missing checksums.' }

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Binary).Hash.ToUpperInvariant()
$sumText = Get-Content -LiteralPath $Checksums -Raw
if ($sumText -notmatch [regex]::Escape($hash)) { Fail 'Binary checksum mismatch.' }

$sourceExt = @('.cpp','.h','.hpp','.c','.cc','.cxx','.cs','.java','.kt','.py','.vcxproj','.sln','.pdb','.obj','.ilk','.lib','.exp')
$files = Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Where-Object { $_.FullName -notmatch '\\.git(\\|$)' }
$sourceHits = @($files | Where-Object { $sourceExt -contains $_.Extension.ToLowerInvariant() })
if ($sourceHits.Count -gt 0) { Fail ('Forbidden source-like files found: ' + ($sourceHits.FullName -join '; ')) }

$pathTokens = @('runtime' + '_sessions', ('down' + 'loads'), ('artifacts' + '/raw'), ('artifacts' + '\raw'))
$pathHits = @($files | Where-Object {
    $rel = $_.FullName.Substring($Root.Path.Length + 1).Replace('\','/')
    foreach ($token in $pathTokens) { if ($rel -like ('*' + $token.Replace('\','/') + '*')) { return $true } }
    return $false
})
if ($pathHits.Count -gt 0) { Fail ('Forbidden path names found: ' + ($pathHits.FullName -join '; ')) }

$privatePatterns = @(
    (Join-Private 68 'desktopvisual'),
    (Join-Private 68 ('desktopvisual' + '-release')),
    (Join-Private 68 ('desktopvisual' + '-public-dist')),
    (Join-Private 68 'testrepo'),
    (Join-Private 67 ('Users' + '\' + 'lenovo')),
    ('Python' + '314'),
    ('python' + '-' + '.exe')
)
foreach ($file in $files) {
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    foreach ($pattern in $privatePatterns) {
        $asciiNeedle = [Text.Encoding]::ASCII.GetBytes($pattern)
        $unicodeNeedle = [Text.Encoding]::Unicode.GetBytes($pattern)
        if ((Test-BytesContains $bytes $asciiNeedle) -or (Test-BytesContains $bytes $unicodeNeedle)) {
            Fail ('Private path pattern found in file: ' + $file.FullName)
        }
    }
}

$large = @($files | Where-Object { $_.Length -gt 25MB -and $_.FullName -ne $Binary })
if ($large.Count -gt 0) { Fail ('Unexpected large files found: ' + ($large.FullName -join '; ')) }

Remove-SmokeArtifacts
Write-Output 'PUBLIC_DIST_SMOKE_TEST_PASS'
