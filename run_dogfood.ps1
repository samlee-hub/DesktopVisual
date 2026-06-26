param(
    [string]$Root = '',
    [switch]$Help,
    [int]$TimeoutSeconds = 10
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\run_dogfood.ps1 [-TimeoutSeconds <seconds>]'
    Write-Host 'Runs the legacy Notepad dogfood case when a clean target is available.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgent = Join-Path $Root 'bin\winagent.exe'
$Artifacts = Join-Path $Root 'artifacts'
$CaseTemplate = Join-Path $Root 'cases\real_app_dogfood.case'
$ResolvedCase = Join-Path $Artifacts 'real_app_dogfood_resolved.case'
$Report = Join-Path $Artifacts 'real_app_dogfood_report.md'
$BeforeBmp = Join-Path $Artifacts 'real_app_before.bmp'
$AfterBmp = Join-Path $Artifacts 'real_app_after.bmp'

function New-ZhNotepadTitle {
    return -join @(
        [char]0x65E0, [char]0x6807, [char]0x9898,
        ' - ',
        [char]0x8BB0, [char]0x4E8B, [char]0x672C
    )
}

function New-ZhNotepadAppTitle {
    return -join @([char]0x8BB0, [char]0x4E8B, [char]0x672C)
}

function Write-DogfoodFailureReport {
    param(
        [string]$Reason,
        [string[]]$FindAttempts
    )

    New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null
    $lines = @(
        '# Real App Dogfood Report',
        '',
        '- Result: FAILED',
        '- App: notepad.exe',
        "- Reason: $Reason",
        "- Before screenshot: $BeforeBmp",
        "- After screenshot: $AfterBmp",
        '',
        '## Find Attempts',
        ''
    )
    if ($FindAttempts.Count -eq 0) {
        $lines += '- No find attempts were recorded.'
    } else {
        foreach ($attempt in $FindAttempts) {
            $lines += "- $attempt"
        }
    }
    $lines += @(
        '',
        '## Notes',
        '',
        '- No file was saved.',
        '- The script did not close the real application window.'
    )
    $lines | Set-Content -Encoding UTF8 -LiteralPath $Report
}

function Invoke-WinAgentFind {
    param([string]$Title)

    $output = & $WinAgent find --title $Title 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    $json = $null
    try {
        if ($text) {
            $json = $text | ConvertFrom-Json
        }
    } catch {
        $json = $null
    }
    return @{
        ExitCode = $exitCode
        Text = $text
        Json = $json
    }
}

if (!(Test-Path -LiteralPath $WinAgent)) {
    Write-DogfoodFailureReport -Reason "Missing $WinAgent. Run $Root\build.ps1 first." -FindAttempts @()
    throw "Missing $WinAgent. Run $Root\build.ps1 first."
}

if (!(Test-Path -LiteralPath $CaseTemplate)) {
    Write-DogfoodFailureReport -Reason "Missing dogfood case template: $CaseTemplate" -FindAttempts @()
    throw "Missing dogfood case template: $CaseTemplate"
}

New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null

$startedProcess = $null
try {
    $startedProcess = Start-Process -FilePath 'notepad.exe' -PassThru
    Write-Host "Started notepad.exe. PID: $($startedProcess.Id)"
} catch {
    Write-DogfoodFailureReport -Reason "Could not start notepad.exe: $($_.Exception.Message)" -FindAttempts @()
    throw
}

$candidateTitles = @(
    @{ Title = 'Untitled - Notepad'; RequireStartedPid = $true; RequireExactTitle = $true },
    @{ Title = (New-ZhNotepadTitle); RequireStartedPid = $true; RequireExactTitle = $true },
    @{ Title = 'Notepad'; RequireStartedPid = $true; RequireExactTitle = $true },
    @{ Title = (New-ZhNotepadAppTitle); RequireStartedPid = $true; RequireExactTitle = $true }
)

$selectedTitle = ''
$findAttempts = New-Object System.Collections.Generic.List[string]
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
do {
    foreach ($candidate in $candidateTitles) {
        $title = [string]$candidate.Title
        $find = Invoke-WinAgentFind -Title $title
        if ($find.ExitCode -eq 0 -and $find.Json -and $find.Json.ok -eq $true) {
            $matchedTitle = [string]$find.Json.target.title
            if ($candidate.RequireStartedPid -and [int]$find.Json.target.pid -ne [int]$startedProcess.Id) {
                $findAttempts.Add("title='$title' result=pid_mismatch matched_pid=$($find.Json.target.pid) started_pid=$($startedProcess.Id)")
                continue
            }
            if ($candidate.RequireExactTitle -and $matchedTitle -ne $title) {
                $findAttempts.Add("title='$title' result=title_mismatch matched_title='$matchedTitle'")
                continue
            }
            $selectedTitle = $matchedTitle
            break
        }

        $code = ''
        if ($find.Json -and $find.Json.error) {
            $code = [string]$find.Json.error.code
        } elseif ($find.ExitCode -ne 0) {
            $code = "exit_$($find.ExitCode)"
        } else {
            $code = 'invalid_json'
        }
        $findAttempts.Add("title='$title' result=$code")
    }

    if ($selectedTitle) {
        break
    }
    Start-Sleep -Milliseconds 300
} while ((Get-Date) -lt $deadline)

if (!$selectedTitle) {
    $reason = 'Could not uniquely match the blank Notepad window started by this script. Common causes: localized title not covered, Notepad restored an existing file, multiple matching Notepad windows, or Notepad did not open in time.'
    Write-DogfoodFailureReport -Reason $reason -FindAttempts $findAttempts.ToArray()
    Write-Host "Dogfood failed: $reason"
    Write-Host "Report: $Report"
    Write-Host 'If notepad.exe was opened by this script, it was left open. Close it manually if you do not need it.'
    exit 1
}

$templateText = Get-Content -Raw -LiteralPath $CaseTemplate
$resolvedText = $templateText.Replace('{{TARGET_TITLE}}', $selectedTitle)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($ResolvedCase, $resolvedText, $utf8NoBom)

Write-Host "Matched Notepad title: $selectedTitle"
Write-Host "Running dogfood case: $ResolvedCase"
& $WinAgent run-case --file $ResolvedCase --report $Report
$caseExit = $LASTEXITCODE

Write-Host "Report: $Report"
Write-Host "Before screenshot: $BeforeBmp"
Write-Host "After screenshot: $AfterBmp"
Write-Host 'No Notepad file was saved. The Notepad window was left open; close it manually if you do not need it.'

exit $caseExit
