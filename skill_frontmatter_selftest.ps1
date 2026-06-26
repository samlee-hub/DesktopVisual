param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root

$Skill = 'C:\Users\lenovo\.agents\skills\desktopvisual-visible-ui-first\SKILL.md'
$ArtifactDir = Join-Path $Root 'artifacts\dev_post_v6_runtime_ux_optimization'
$Report = Join-Path $ArtifactDir 'skill_frontmatter_report.md'
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

function Fail([string]$Message) { throw $Message }

if (-not (Test-Path -LiteralPath $Skill)) { Fail "Skill file not found: $Skill" }

$bytes = [IO.File]::ReadAllBytes($Skill)
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    Fail 'SKILL.md must be UTF-8 without BOM.'
}

$text = [Text.Encoding]::UTF8.GetString($bytes)
if ($text.Length -gt 0 -and [int][char]$text[0] -eq 0xFEFF) { Fail 'SKILL.md has BOM character.' }
$firstLine = ($text -split "`r?`n", 2)[0]
if ($firstLine -ne '---') { Fail 'First line of SKILL.md must be --- with no preceding whitespace.' }
if ($text -notmatch "(?ms)^description:\s*[|>]") { Fail 'description must use a YAML block scalar.' }
if ($text -notmatch 'foreground preparation') { Fail 'Skill must mention foreground preparation before visible UI tasks.' }
if ($text -notmatch [regex]::Escape('D:\desktopvisual\bin\winagent.exe')) { Fail 'Skill must prefer developer D:\desktopvisual runtime.' }
if ($text -notmatch 'fast-visible-ui') { Fail 'Skill must mention --latency-profile fast-visible-ui.' }
if ($text -notmatch 'pycharm-dev-demo') { Fail 'Skill must mention PyCharm fast path command.' }
if ($text -notmatch 'suggested_command') { Fail 'Skill must instruct reading suggested_command after command failure.' }

@(
    '# Skill Frontmatter Report',
    '',
    '- Result: PASS',
    '- first_line_is_frontmatter_delimiter: true',
    '- utf8_no_bom: true',
    '- description_block_scalar: true',
    '- foreground_preparation_guidance: true',
    '- developer_runtime_preferred: true',
    '- fast_visible_ui_guidance: true',
    '- pycharm_fast_path_guidance: true'
) | Set-Content -LiteralPath $Report -Encoding UTF8

Write-Host 'SKILL_FRONTMATTER_SELFTEST_PASS'
Write-Host "Report: $Report"
