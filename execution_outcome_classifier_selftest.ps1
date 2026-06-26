param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$ArtifactRoot = Join-Path $Root 'artifacts\dev6.1.6_dynamic_app_web_full_access_rc_fresh'
$WorkRoot = Join-Path $ArtifactRoot 'execution_outcome_classifier_selftest'
$ReportPath = Join-Path $ArtifactRoot 'execution_outcome_classifier_report.md'
$ResultPath = Join-Path $WorkRoot 'execution_outcome_classifier_selftest_result.json'

function Ensure-Dir([string]$Path) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Save-Json($Value, [string]$Path) {
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { Ensure-Dir $dir }
    $Value | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function U([int[]]$Codes) {
    $chars = foreach ($code in $Codes) { [char]$code }
    return -join $chars
}

function Read-Json([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return $null }
}

function ConvertTo-Arg([string]$Arg) {
    if ($null -eq $Arg) { return '""' }
    $s = [string]$Arg
    if ($s.Length -eq 0) { return '""' }
    if ($s -notmatch '[\s"]') { return $s }
    $result = '"'
    $slashes = 0
    foreach ($ch in $s.ToCharArray()) {
        if ($ch -eq '\') {
            $slashes++
        } elseif ($ch -eq '"') {
            if ($slashes -gt 0) { $result += ('\' * ($slashes * 2)) }
            $result += '\"'
            $slashes = 0
        } else {
            if ($slashes -gt 0) { $result += ('\' * $slashes) }
            $slashes = 0
            $result += $ch
        }
    }
    if ($slashes -gt 0) { $result += ('\' * ($slashes * 2)) }
    $result += '"'
    return $result
}

function Invoke-WinAgentClassifier {
    param(
        [string]$Name,
        [string]$BeforePath,
        [string]$AfterPath,
        [string]$OutPath
    )
    $stdout = Join-Path $WorkRoot "$Name.stdout.log"
    $stderr = Join-Path $WorkRoot "$Name.stderr.log"
    $args = @(
        'classify-execution-output',
        '--profile', 'python',
        '--before', $BeforePath,
        '--after', $AfterPath,
        '--result-json', $OutPath,
        '--expected-start-marker', 'DV616_RUN_START',
        '--expected-end-marker', 'DV616_RUN_END'
    )
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $WinAgent
    $psi.Arguments = (($args | ForEach-Object { ConvertTo-Arg $_ }) -join ' ')
    $psi.WorkingDirectory = $Root
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $p = [System.Diagnostics.Process]::new()
    $p.StartInfo = $psi
    [void]$p.Start()
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    $timedOut = -not $p.WaitForExit(30000)
    if ($timedOut) {
        try { $p.Kill($true) } catch { try { $p.Kill() } catch {} }
    }
    try { $outTask.Wait(3000) | Out-Null } catch {}
    try { $errTask.Wait(3000) | Out-Null } catch {}
    $out = if ($outTask.IsCompleted) { $outTask.Result } else { '' }
    $err = if ($errTask.IsCompleted) { $errTask.Result } else { '' }
    $out | Set-Content -LiteralPath $stdout -Encoding UTF8
    $err | Set-Content -LiteralPath $stderr -Encoding UTF8
    [pscustomobject]@{
        exit_code = if ($timedOut) { 124 } else { $p.ExitCode }
        timed_out = $timedOut
        stdout = $stdout
        stderr = $stderr
        result_json = $OutPath
        outcome = Read-Json $OutPath
    }
}

function Write-Sample([string]$Name, [string]$Before, [string]$After) {
    $dir = Join-Path $WorkRoot $Name
    Ensure-Dir $dir
    $beforePath = Join-Path $dir 'before.txt'
    $afterPath = Join-Path $dir 'after.txt'
    $outPath = Join-Path $dir 'outcome.json'
    $Before | Set-Content -LiteralPath $beforePath -Encoding UTF8
    $After | Set-Content -LiteralPath $afterPath -Encoding UTF8
    [pscustomobject]@{
        name = $Name
        before = $beforePath
        after = $afterPath
        out = $outPath
    }
}

function Test-Expectation($Outcome, [hashtable]$Expected) {
    $failures = New-Object System.Collections.Generic.List[string]
    foreach ($key in $Expected.Keys) {
        $actual = if ($Outcome -and $Outcome.PSObject.Properties.Name -contains $key) { $Outcome.$key } else { $null }
        if ($actual -ne $Expected[$key]) {
            $failures.Add("${key}: expected=$($Expected[$key]) actual=$actual") | Out-Null
        }
    }
    return @($failures.ToArray())
}

Ensure-Dir $ArtifactRoot
Ensure-Dir $WorkRoot

$OutputPrefix = U @(36825,26159,31532)
$OutputSuffix = U @(20010,36755,20986)
$ExitCode0 = (U @(36827,31243,24050,32467,26463,65292,36864,20986,20195,30721,20026)) + ' 0'
$ExitCode1 = (U @(36827,31243,24050,32467,26463,65292,36864,20986,20195,30721,20026)) + ' 1'
$OutputLine1 = "${OutputPrefix}1${OutputSuffix}"
$OutputLine2 = "${OutputPrefix}2${OutputSuffix}"

$samples = @(
    [ordered]@{
        sample = Write-Sample 'python_success' '' @"
C:\Python312\python.exe D:\testrepo\pycharm_sanity\main.py
DV616_RUN_START DV616_RUN_SELFTEST
$OutputLine1
$OutputLine2
DV616_RUN_END DV616_RUN_SELFTEST
$ExitCode0
"@
        expected = @{
            run_triggered = $true
            execution_success = $true
            exit_code = 0
            expected_output_verified = $true
            current_run_verified = $true
            old_output_reuse_detected = $false
        }
    },
    [ordered]@{
        sample = Write-Sample 'python_medium_code_sequence_success' '' @'
C:\Python312\python.exe D:\testrepo\pycharm_sanity\main.py
DV616_RUN_START DV616_CASE2_SELFTEST
DV616_SEQ 1 case2-worker T1:24 score=25
DV616_SEQ 2 case2-worker T2:31 score=33
DV616_SEQ 3 case2-worker T3:22 score=25
DV616_RUN_END DV616_CASE2_SELFTEST
Process finished with exit code 0
'@
        expected = @{
            run_triggered = $true
            execution_success = $true
            exit_code = 0
            expected_output_verified = $true
            current_run_verified = $true
            old_output_reuse_detected = $false
            output_count = 3
        }
    },
    [ordered]@{
        sample = Write-Sample 'python_indentation_error' '' @"
C:\Python312\python.exe D:\testrepo\pycharm_sanity\main.py
  File "D:\testrepo\pycharm_sanity\main.py", line 10
    print("bad")
IndentationError: unexpected indent
$ExitCode1
"@
        expected = @{
            run_triggered = $true
            execution_started = $true
            execution_completed = $true
            execution_success = $false
            error_category = 'SYNTAX_OR_INDENTATION_ERROR'
            current_run_verified = $true
        }
    },
    [ordered]@{
        sample = Write-Sample 'python_syntax_error' '' @'
python.exe D:\testrepo\pycharm_sanity\main.py
  File "D:\testrepo\pycharm_sanity\main.py", line 4
SyntaxError: invalid syntax
Process finished with exit code 1
'@
        expected = @{
            run_triggered = $true
            execution_success = $false
            error_category = 'SYNTAX_ERROR'
        }
    },
    [ordered]@{
        sample = Write-Sample 'not_run_output' '' @'
Project tool window
main.py
No process output is visible.
'@
        expected = @{
            run_triggered = $false
        }
    },
    [ordered]@{
        sample = Write-Sample 'old_output_reuse' @'
python.exe D:\testrepo\pycharm_sanity\main.py
DV616_RUN_START DV616_OLD
这是第1个输出
DV616_RUN_END DV616_OLD
Process finished with exit code 0
'@ @'
python.exe D:\testrepo\pycharm_sanity\main.py
DV616_RUN_START DV616_OLD
这是第1个输出
DV616_RUN_END DV616_OLD
Process finished with exit code 0
'@
        expected = @{
            old_output_reuse_detected = $true
            current_run_verified = $false
        }
    }
)

$results = New-Object System.Collections.Generic.List[object]
$allPass = $true
foreach ($entry in $samples) {
    $sample = $entry.sample
    $run = Invoke-WinAgentClassifier -Name $sample.name -BeforePath $sample.before -AfterPath $sample.after -OutPath $sample.out
    $failures = @()
    if ($run.exit_code -ne 0 -and -not (Test-Path -LiteralPath $sample.out)) {
        $failures += "classifier command failed exit=$($run.exit_code)"
    } else {
        $failures += Test-Expectation $run.outcome $entry.expected
    }
    $status = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
    if ($status -ne 'PASS') { $allPass = $false }
    $results.Add([ordered]@{
        name = $sample.name
        status = $status
        failures = @($failures)
        exit_code = $run.exit_code
        timed_out = $run.timed_out
        result_json = $sample.out
        stdout = $run.stdout
        stderr = $run.stderr
    }) | Out-Null
}

$result = [ordered]@{
    schema_version = 'execution_outcome_classifier.selftest.v1'
    generated_at = (Get-Date).ToString('o')
    status = if ($allPass) { 'PASS' } else { 'FAIL' }
    classifier_command = 'winagent.exe classify-execution-output'
    bottom_layer_required = $true
    cases = @($results.ToArray())
}
Save-Json $result $ResultPath

$caseLines = @($results.ToArray()) | ForEach-Object {
    $failureText = if ($_.failures.Count -gt 0) { ($_.failures -join '; ') } else { 'none' }
    "- $($_.name): $($_.status) exit=$($_.exit_code) failures=$failureText"
}
@(
    '# Execution Outcome Classifier Selftest',
    '',
    "- Result: $($result.status)",
    "- Command: $($result.classifier_command)",
    "- Result JSON: $ResultPath",
    '',
    '## Cases'
) + $caseLines | Set-Content -LiteralPath $ReportPath -Encoding UTF8

if ($allPass) {
    Write-Host 'EXECUTION_OUTCOME_CLASSIFIER_SELFTEST_PASS'
    exit 0
}
Write-Host 'EXECUTION_OUTCOME_CLASSIFIER_SELFTEST_FAIL'
exit 1
