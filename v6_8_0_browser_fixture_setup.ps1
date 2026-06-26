param(
    [string]$FixtureRoot = 'D:\testrepo\testwindow\browser_form_v6_8'
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $FixtureRoot | Out-Null

function Write-Html($Name, $Body) {
    $path = Join-Path $FixtureRoot $Name
    $html = @"
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>DesktopVisual Browser Form v6.8</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 32px; line-height: 1.4; }
    label { display: block; margin-top: 14px; font-weight: 600; }
    input, textarea, select, button { font-size: 16px; padding: 8px; min-width: 260px; }
    .marker { color: #164; font-weight: 700; }
    .spacer { height: 1400px; }
  </style>
</head>
<body>
$Body
</body>
</html>
"@
    Set-Content -LiteralPath $path -Value $html -Encoding UTF8
    return $path
}

Write-Html 'local_form_basic.html' @'
<h1>DesktopVisual Browser Form v6.8</h1>
<p class="marker">DV_BROWSER_FORM_BASIC_MARKER</p>
<label for="first_name">First name</label>
<input id="first_name" name="first_name" aria-label="First name" placeholder="First name">
<label for="last_name">Last name</label>
<input id="last_name" name="last_name" aria-label="Last name" placeholder="Last name">
<button id="submit" aria-label="Submit" onclick="document.getElementById('result').textContent='DV_BROWSER_FORM_SUCCESS_MARKER submitted';">Submit</button>
<p id="result" aria-live="polite"></p>
'@ | Out-Null

Write-Html 'local_form_long_scroll.html' @'
<h1>DesktopVisual Browser Form v6.8</h1>
<p class="marker">DV_BROWSER_FORM_BASIC_MARKER</p>
<div class="spacer">Scroll to the form below.</div>
<label for="scroll_name">Scroll name</label>
<input id="scroll_name" name="scroll_name" aria-label="Scroll name" placeholder="Scroll name">
<button id="submit" aria-label="Submit" onclick="document.getElementById('result').textContent='DV_BROWSER_FORM_SUCCESS_MARKER long scroll submitted';">Submit</button>
<p id="result" aria-live="polite"></p>
'@ | Out-Null

Write-Html 'local_form_missing_field.html' @'
<h1>DesktopVisual Browser Form v6.8</h1>
<p class="marker">DV_BROWSER_FORM_BASIC_MARKER</p>
<label for="present">Present field</label>
<input id="present" name="present" aria-label="Present field" placeholder="Present field">
<button aria-label="Submit">Submit</button>
'@ | Out-Null

Write-Html 'local_form_ambiguous_submit.html' @'
<h1>DesktopVisual Browser Form v6.8</h1>
<p class="marker">DV_BROWSER_FORM_BASIC_MARKER</p>
<label for="first_name">First name</label>
<input id="first_name" name="first_name" aria-label="First name" placeholder="First name">
<button aria-label="Submit">Submit</button>
<button aria-label="Submit">Submit</button>
'@ | Out-Null

Write-Html 'local_form_dynamic_reload.html' @'
<h1>DesktopVisual Browser Form v6.8</h1>
<p class="marker">DV_BROWSER_FORM_BASIC_MARKER</p>
<label for="first_name">First name</label>
<input id="first_name" name="first_name" aria-label="First name" placeholder="First name">
<button id="submit" aria-label="Submit" onclick="document.getElementById('result').textContent='DV_BROWSER_FORM_SUCCESS_MARKER dynamic submitted';">Submit</button>
<p id="result" aria-live="polite"></p>
'@ | Out-Null

Write-Html 'local_form_active_protection_mock.html' @'
<h1>Security verification</h1>
<p class="marker">DV_BROWSER_ACTIVE_PROTECTION_MARKER</p>
<p>CAPTCHA human verification bot challenge</p>
'@ | Out-Null

Write-Html 'local_form_credential_required_mock.html' @'
<h1>Sign in required</h1>
<p class="marker">DV_BROWSER_CREDENTIAL_REQUIRED_MARKER</p>
<label>Password</label>
<input aria-label="Password" type="password">
<p>Verification code required</p>
'@ | Out-Null

Write-Html 'local_form_wrong_page.html' @'
<h1>Wrong page</h1>
<p class="marker">DV_BROWSER_WRONG_PAGE_MARKER</p>
'@ | Out-Null

Write-Html 'local_form_success.html' @'
<h1>Success</h1>
<p class="marker">DV_BROWSER_FORM_SUCCESS_MARKER</p>
'@ | Out-Null

@'
param(
    [string]$Root = 'D:\testrepo\testwindow\browser_form_v6_8',
    [int]$Port = 8768
)
$ErrorActionPreference = 'Stop'
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        $relative = $ctx.Request.Url.AbsolutePath.TrimStart('/')
        if ([string]::IsNullOrWhiteSpace($relative)) { $relative = 'local_form_basic.html' }
        $path = Join-Path $Root $relative
        if (-not (Test-Path -LiteralPath $path)) {
            $ctx.Response.StatusCode = 404
            $bytes = [Text.Encoding]::UTF8.GetBytes('not found')
        } else {
            $ctx.Response.StatusCode = 200
            $ctx.Response.ContentType = 'text/html; charset=utf-8'
            $bytes = [IO.File]::ReadAllBytes($path)
        }
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $ctx.Response.Close()
    }
} finally {
    $listener.Stop()
}
'@ | Set-Content -LiteralPath (Join-Path $FixtureRoot 'localhost_server.ps1') -Encoding UTF8

[pscustomobject]@{
    fixture_root = $FixtureRoot
    created = $true
    files = Get-ChildItem -LiteralPath $FixtureRoot -File | Select-Object -ExpandProperty Name
} | ConvertTo-Json -Depth 5
