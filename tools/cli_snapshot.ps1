param(
  [string]$Root = '',
  [string]$Spec = '',
  [ValidateSet('Capture','Compare','Update')][string]$Mode = 'Compare'
)
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
if (-not $Spec) { $Spec = Join-Path $Root 'tools\snapshot_specs\core_cli.json' }

$specJson = Get-Content -LiteralPath $Spec -Raw -Encoding UTF8 | ConvertFrom-Json
$baseDrop = @('timestamp','duration_ms')
if ($specJson.drop) { $baseDrop = @($specJson.drop) }

$baselineDir = Join-Path $Root ('artifacts\snapshot_baseline\' + $specJson.name)
$runDir      = Join-Path $Root ('artifacts\build\snapshot_run\' + $specJson.name)
New-Item -ItemType Directory -Force -Path $baselineDir | Out-Null
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$exe = Join-Path $Root 'bin\winagent.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw "winagent.exe not found: $exe" }

# Baselines live in both trees (developer + desktop_release), so every absolute
# project path is folded to a token; otherwise the same contract reads as a diff.
$script:rootToken = $Root.TrimEnd('\')

function Normalize-Node($node, $drop) {
  if ($null -eq $node) { return $null }
  if ($node -is [System.Management.Automation.PSCustomObject]) {
    $o = [ordered]@{}
    foreach ($p in $node.PSObject.Properties) {
      if ($drop -contains $p.Name) { continue }
      $o[$p.Name] = Normalize-Node $p.Value $drop
    }
    return [pscustomobject]$o
  }
  if ($node -is [System.Collections.IEnumerable] -and -not ($node -is [string])) {
    return @(foreach ($i in $node) { Normalize-Node $i $drop })
  }
  if ($node -is [string] -and $script:rootToken) {
    return $node.Replace($script:rootToken, '<ROOT>')
  }
  return $node
}

function Project-Keep($obj, $keep) {
  $o = [ordered]@{}
  $o['ok'] = $obj.ok
  $o['command'] = $obj.command
  $d = [ordered]@{}
  foreach ($k in $keep) { $d[$k] = $obj.data.$k }
  $o['data'] = [pscustomobject]$d
  return [pscustomobject]$o
}

# Both sides go through the same JSON round trip so PowerShell shape quirks
# (empty array -> null, single element -> scalar) cannot create false diffs.
function Get-Canonical($node) {
  if ($null -eq $node) { return $null }
  return (($node | ConvertTo-Json -Depth 40) | ConvertFrom-Json)
}
function Get-CanonicalText($node) {
  if ($null -eq $node) { return 'null' }
  return ($node | ConvertTo-Json -Depth 40 -Compress)
}

function Compare-Node($exp, $act, $path, $diffs) {
  if ($null -eq $exp -and $null -eq $act) { return }
  $expIsObj = $exp -is [System.Management.Automation.PSCustomObject]
  $actIsObj = $act -is [System.Management.Automation.PSCustomObject]
  if ($expIsObj -or $actIsObj) {
    if (-not ($expIsObj -and $actIsObj)) { $diffs.Add("$($path) : object/scalar type mismatch") | Out-Null; return }
    $names = New-Object System.Collections.ArrayList
    foreach ($p in $exp.PSObject.Properties) { [void]$names.Add($p.Name) }
    foreach ($p in $act.PSObject.Properties) { if (-not $names.Contains($p.Name)) { [void]$names.Add($p.Name) } }
    foreach ($n in $names) {
      $hasExp = $null -ne $exp.PSObject.Properties[$n]
      $hasAct = $null -ne $act.PSObject.Properties[$n]
      if (-not $hasAct) { $diffs.Add("$($path).$($n) : baseline has value, actual key missing") | Out-Null; continue }
      if (-not $hasExp) { $diffs.Add("$($path).$($n) : actual has extra key") | Out-Null; continue }
      Compare-Node $exp.$n $act.$n "$($path).$($n)" $diffs
    }
    return
  }
  $expIsArr = $exp -is [System.Collections.IEnumerable] -and -not ($exp -is [string])
  $actIsArr = $act -is [System.Collections.IEnumerable] -and -not ($act -is [string])
  if ($expIsArr -or $actIsArr) {
    if (-not ($expIsArr -and $actIsArr)) { $diffs.Add("$($path) : array/scalar type mismatch") | Out-Null; return }
    $e = @($exp); $a = @($act)
    if ($e.Count -ne $a.Count) { $diffs.Add("$($path) : length baseline=$($e.Count) actual=$($a.Count)") | Out-Null }
    $n = [Math]::Min($e.Count, $a.Count)
    for ($i = 0; $i -lt $n; $i++) { Compare-Node $e[$i] $a[$i] "$($path)[$($i)]" $diffs }
    return
  }
  if ("$exp" -ne "$act") { $diffs.Add("$($path) : baseline=$exp actual=$act") | Out-Null }
}

function Get-Magic([string]$path) {
  $b = [IO.File]::ReadAllBytes($path)
  if ($b.Length -lt 8) { return 'too-small' }
  if ($b[0] -eq 0x89 -and $b[1] -eq 0x50 -and $b[2] -eq 0x4E -and $b[3] -eq 0x47) { return 'png' }
  if ($b[0] -eq 0x42 -and $b[1] -eq 0x4D) { return 'bmp' }
  return 'unknown'
}

$failed = 0
$checked = 0
$rows = @()

foreach ($entry in $specJson.entries) {
  $checked++
  $drop = @($baseDrop)
  if ($entry.drop) { $drop = @($drop) + @($entry.drop) }
  $argv = @()
  foreach ($a in $entry.args) { $argv += [string]$a }
  $outFile = $null
  if ($entry.out_ext) {
    $outFile = Join-Path $runDir ($entry.name + '.' + $entry.out_ext)
    if (Test-Path -LiteralPath $outFile) { Remove-Item -LiteralPath $outFile -Force }
    $argv += @('--out', $outFile)
  }

  $raw = & $exe @argv 2>$null | Out-String
  $problems = New-Object System.Collections.ArrayList
  $obj = $null
  try { $obj = $raw | ConvertFrom-Json } catch {
    $problems.Add("stdout is not JSON: " + $raw.Substring(0, [Math]::Min(160, $raw.Length))) | Out-Null
  }
  if ($null -ne $obj -and $obj.ok -ne $true -and -not $entry.allow_not_ok) { $problems.Add("response ok=false") | Out-Null }

  $norm = $null
  if ($null -ne $obj) {
    $norm = Normalize-Node $obj $drop
    if ($entry.keep) { $norm = Project-Keep $norm @($entry.keep) }
    $norm = Get-Canonical $norm
  }

  if ($entry.out_ext -and $outFile) {
    if (-not (Test-Path -LiteralPath $outFile)) { $problems.Add("output file not created: $outFile") | Out-Null }
    else {
      $len = (Get-Item -LiteralPath $outFile).Length
      if ($len -le 0) { $problems.Add("output file empty") | Out-Null }
      $magic = Get-Magic $outFile
      if ($magic -ne $entry.out_ext) { $problems.Add("output magic=$($magic) expected=$($entry.out_ext)") | Out-Null }
    }
  }
  if ($entry.expect -and $norm) {
    foreach ($p in $entry.expect.PSObject.Properties) {
      $actual = $norm.data.($p.Name)
      if ("$actual" -ne "$($p.Value)") { $problems.Add("expect $($p.Name): got '$actual' expected '$($p.Value)'") | Out-Null }
    }
  }

  if ($norm) {
    Set-Content -LiteralPath (Join-Path $runDir ($entry.name + '.json')) -Value (Get-CanonicalText $norm) -Encoding UTF8
  }

  $baselinePath = Join-Path $baselineDir ($entry.name + '.json')
  if ($Mode -eq 'Capture' -or $Mode -eq 'Update') {
    if ($norm) { Set-Content -LiteralPath $baselinePath -Value (Get-CanonicalText $norm) -Encoding UTF8 }
    if ($problems.Count -gt 0) { $status = 'FAIL'; $failed++ } else { $status = 'CAPTURED' }
  }
  else {
    if (-not (Test-Path -LiteralPath $baselinePath)) {
      $problems.Add("no baseline: $baselinePath (run -Mode Capture)") | Out-Null
    }
    else {
      $baseText = Get-Content -LiteralPath $baselinePath -Raw -Encoding UTF8
      $baseObj = Get-Canonical ($baseText | ConvertFrom-Json)
      if ((Get-CanonicalText $baseObj) -ne (Get-CanonicalText $norm)) {
        $diffs = New-Object System.Collections.ArrayList
        Compare-Node $baseObj $norm '$' $diffs
        foreach ($d in $diffs) { $problems.Add($d) | Out-Null }
      }
    }
    if ($problems.Count -gt 0) { $status = 'DIFF'; $failed++ } else { $status = 'PASS' }
  }
  $rows += [pscustomobject]@{ name = $entry.name; status = $status; problems = @($problems) }
}

Write-Output ("snapshot spec={0} mode={1} entries={2}" -f $specJson.name, $Mode, $checked)
foreach ($r in $rows) {
  Write-Output ("  {0,-9} {1}" -f $r.status, $r.name)
  foreach ($p in $r.problems) { Write-Output ("            - {0}" -f $p) }
}
Write-Output ("result: {0}/{1} clean" -f ($checked - $failed), $checked)
if ($failed -gt 0) { exit 1 }
exit 0
