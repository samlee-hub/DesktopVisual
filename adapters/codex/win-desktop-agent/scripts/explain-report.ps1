param(
    [Parameter(Mandatory = $true)]
    [string]$ReportFile
)

$ErrorActionPreference = 'Stop'

if (!(Test-Path -LiteralPath $ReportFile)) {
    throw "Missing report file: $ReportFile"
}

$content = Get-Content -Raw -LiteralPath $ReportFile

$result = ''
if ($content -match '(?m)^- Result:\s*(.+?)\s*$') {
    $result = $Matches[1].Trim()
}

$errorCode = ''
if ($content -match '(?m)^- Failure error_code:\s*`([^`]*)`') {
    $errorCode = $Matches[1].Trim()
}

$failureMessage = ''
if ($content -match '(?m)^- Failure message:\s*(.*?)\s*$') {
    $failureMessage = $Matches[1].Trim()
}

$explanation = switch ($errorCode) {
    'WINDOW_NOT_FOUND' { 'The target window does not exist or is not open.' }
    'WINDOW_NOT_UNIQUE' { 'The window title match is not unique.' }
    'ASSERTION_FAILED' { 'The actions ran, but the verification condition was not satisfied.' }
    'INVALID_ARGUMENT' { 'The case file or command arguments are invalid.' }
    'SEND_INPUT_FAILED' { 'Input injection failed, likely due to permissions or focus.' }
    'SCREENSHOT_FAILED' { 'Screenshot capture failed, possibly because the window is minimized or the capture API failed.' }
    '' { 'The report does not contain a failure error code.' }
    default { "Unmapped error code: $errorCode" }
}

Write-Output "Report: $ReportFile"
Write-Output "Result: $result"
Write-Output "error_code: $errorCode"
Write-Output "Explanation: $explanation"
if ($failureMessage) {
    Write-Output "Failure message: $failureMessage"
}
Write-Output 'Action: Do not continue unauthorized actions. Ask the user for confirmation before continuing.'

if ($result -eq 'FAILED' -and !$errorCode) {
    exit 1
}

exit 0
