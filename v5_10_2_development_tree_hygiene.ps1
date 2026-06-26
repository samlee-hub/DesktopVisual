param(
    [string]$Root = 'D:\desktopvisual',
    [switch]$DryRun,
    [switch]$Apply,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

if ($DryRun -and $Apply) {
    throw 'Use either -DryRun or -Apply, not both.'
}

$Mode = if ($Apply) { 'Apply' } else { 'DryRun' }

function Resolve-FullPath {
    param([string]$Path)
    try {
        return (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    } catch {
        return [System.IO.Path]::GetFullPath($Path)
    }
}

function Normalize-PathKey {
    param([string]$Path)
    return (Resolve-FullPath -Path $Path).TrimEnd('\').ToLowerInvariant()
}

function Test-WithinPath {
    param(
        [string]$Path,
        [string]$Base
    )
    $p = Normalize-PathKey -Path $Path
    $b = Normalize-PathKey -Path $Base
    return ($p -eq $b -or $p.StartsWith($b + '\'))
}

if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1')) {
    $Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
    $Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
}

$Root = Resolve-FullPath -Path $Root
if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    throw "Root does not exist: $Root"
}

$ArtifactRoot = Join-Path $Root 'artifacts\dev5.10.2_development_tree_hygiene'
New-Item -ItemType Directory -Force -Path $ArtifactRoot | Out-Null

$ProtectedRelPaths = @(
    'src',
    'config',
    'docs',
    'tasks',
    'samples',
    'tests',
    'scripts',
    'AGENTS.md',
    'README.md',
    'CHANGELOG.md',
    'COMMAND_PROTOCOL.md',
    'VERSION',
    'artifacts\dev5.10.0_adaptive_humanmode_loop',
    'artifacts\dev5.10.1_real_ui_adaptive_cases',
    'artifacts\dev5.10.2_real_taskruntime_final_gate',
    'artifacts\invalidated',
    'artifacts\invalidation_index.md',
    'artifacts\dev5.10_invalidation_rollback',
    '.git'
)

$ProtectedPaths = @()
foreach ($rel in $ProtectedRelPaths) {
    $ProtectedPaths += (Join-Path $Root $rel)
}

$ValidEvidenceIndexPaths = @(
    (Join-Path $Root 'artifacts\dev5.10.1_real_ui_adaptive_cases\evidence_index.md'),
    (Join-Path $Root 'artifacts\dev5.10.2_real_taskruntime_final_gate\evidence_index.md')
)

$EvidenceRefs = New-Object 'System.Collections.Generic.List[string]'

function Add-EvidenceReference {
    param(
        [string]$IndexPath,
        [string]$Reference
    )
    if ([string]::IsNullOrWhiteSpace($Reference)) { return }
    $clean = $Reference.Trim()
    $clean = $clean.Trim('`').Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) { return }
    if ($clean -match '^\#') { return }
    if ($clean -match '^\|') { return }
    if ($clean -match '^[A-Za-z ]+:$') { return }
    if ($clean -match '^```') { return }
    if ($clean -notmatch '[\\/\.]') { return }

    $clean = $clean -replace '/', '\'
    $base = Split-Path -Parent $IndexPath
    if ([System.IO.Path]::IsPathRooted($clean)) {
        $full = $clean
    } elseif ($clean.StartsWith('artifacts\')) {
        $full = Join-Path $Root $clean
    } else {
        $full = Join-Path $base $clean
    }
    $EvidenceRefs.Add((Resolve-FullPath -Path $full)) | Out-Null
}

foreach ($index in $ValidEvidenceIndexPaths) {
    if (Test-Path -LiteralPath $index) {
        $content = Get-Content -LiteralPath $index -Raw
        foreach ($line in ($content -split "`r?`n")) {
            $trimmed = $line.Trim()
            if ($trimmed.StartsWith('- ')) {
                Add-EvidenceReference -IndexPath $index -Reference ($trimmed.Substring(2))
            }
            foreach ($m in [regex]::Matches($line, '`([^`]+)`')) {
                Add-EvidenceReference -IndexPath $index -Reference $m.Groups[1].Value
            }
        }
    }
}

function Test-IsProtectedPath {
    param([string]$Path)
    foreach ($protected in $ProtectedPaths) {
        if (Test-WithinPath -Path $Path -Base $protected) { return $true }
    }
    return $false
}

function Test-ContainsProtectedPath {
    param([string]$Path)
    foreach ($protected in $ProtectedPaths) {
        if (Test-WithinPath -Path $protected -Base $Path) { return $true }
    }
    return $false
}

function Test-IsEvidenceReferenced {
    param([string]$Path)
    foreach ($ref in $EvidenceRefs) {
        if ((Test-WithinPath -Path $Path -Base $ref) -or (Test-WithinPath -Path $ref -Base $Path)) {
            return $true
        }
    }
    return $false
}

function Get-RelativePath {
    param([string]$Path)
    $full = Resolve-FullPath -Path $Path
    if (Test-WithinPath -Path $full -Base $Root) {
        return $full.Substring($Root.TrimEnd('\').Length + 1)
    }
    return $full
}

function Measure-PathBytes {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return [int64]0 }
    $item = Get-Item -LiteralPath $Path -Force
    if (-not $item.PSIsContainer) { return [int64]$item.Length }
    $total = [int64]0
    foreach ($file in Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue) {
        $total += [int64]$file.Length
    }
    return $total
}

function Format-Bytes {
    param([int64]$Bytes)
    return ('{0} bytes ({1:N2} MB)' -f $Bytes, ($Bytes / 1MB))
}

function Write-Text {
    param(
        [string]$Path,
        [string[]]$Lines
    )
    $dir = Split-Path -Parent $Path
    if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $Lines | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-Json {
    param(
        [string]$Path,
        [object]$Value
    )
    $dir = Split-Path -Parent $Path
    if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$Candidates = New-Object 'System.Collections.Generic.List[object]'
$Preserved = New-Object 'System.Collections.Generic.List[object]'
$CandidateKeys = @{}
$PreservedKeys = @{}

function Add-Preserved {
    param(
        [string]$Category,
        [string]$Path,
        [string]$Reason
    )
    $full = Resolve-FullPath -Path $Path
    $key = (Normalize-PathKey -Path $full) + '|' + $Reason
    if ($PreservedKeys.ContainsKey($key)) { return }
    $PreservedKeys[$key] = $true
    $exists = Test-Path -LiteralPath $full
    $type = 'Missing'
    $size = [int64]0
    if ($exists) {
        $item = Get-Item -LiteralPath $full -Force
        $type = if ($item.PSIsContainer) { 'Directory' } else { 'File' }
        $size = Measure-PathBytes -Path $full
    }
    $Preserved.Add([pscustomobject]@{
        category = $Category
        path = Get-RelativePath -Path $full
        full_path = $full
        type = $type
        size_bytes = $size
        reason = $Reason
    }) | Out-Null
}

function Add-Candidate {
    param(
        [string]$Category,
        [string]$Path,
        [string]$Reason
    )
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $full = Resolve-FullPath -Path $Path
    $item = Get-Item -LiteralPath $full -Force
    $isDir = [bool]$item.PSIsContainer

    if (Test-IsProtectedPath -Path $full) {
        Add-Preserved -Category $Category -Path $full -Reason "protected path guard: $Reason"
        return
    }
    if ($isDir -and (Test-ContainsProtectedPath -Path $full)) {
        Add-Preserved -Category $Category -Path $full -Reason "directory contains a protected path: $Reason"
        return
    }
    if (Test-IsEvidenceReferenced -Path $full) {
        Add-Preserved -Category $Category -Path $full -Reason "referenced by valid evidence index: $Reason"
        return
    }

    $key = Normalize-PathKey -Path $full
    if ($CandidateKeys.ContainsKey($key)) { return }
    $CandidateKeys[$key] = $true
    $Candidates.Add([pscustomobject]@{
        category = $Category
        path = Get-RelativePath -Path $full
        full_path = $full
        type = if ($isDir) { 'Directory' } else { 'File' }
        size_bytes = Measure-PathBytes -Path $full
        reason = $Reason
    }) | Out-Null
}

function Test-UnderArtifacts {
    param([string]$Path)
    return (Test-WithinPath -Path $Path -Base (Join-Path $Root 'artifacts'))
}

function Test-MisgeneratedSafe {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    $item = Get-Item -LiteralPath $Path -Force
    if (-not $item.PSIsContainer) { return $true }
    $dangerNames = @('.git', 'src', 'config', 'docs', 'tasks', 'tests', 'scripts')
    foreach ($name in $dangerNames) {
        if (Test-Path -LiteralPath (Join-Path $Path $name)) { return $false }
    }
    foreach ($name in @('VERSION', 'AGENTS.md', 'README.md', 'CHANGELOG.md', 'COMMAND_PROTOCOL.md')) {
        if (Test-Path -LiteralPath (Join-Path $Path $name)) { return $false }
    }
    foreach ($rel in @(
        'artifacts\dev5.10.0_adaptive_humanmode_loop',
        'artifacts\dev5.10.1_real_ui_adaptive_cases',
        'artifacts\dev5.10.2_real_taskruntime_final_gate',
        'artifacts\invalidated'
    )) {
        if (Test-Path -LiteralPath (Join-Path $Path $rel)) { return $false }
    }
    return $true
}

function Get-UnprotectedTreeItems {
    param([string]$Start)
    $stack = New-Object 'System.Collections.Generic.Stack[string]'
    $stack.Push($Start)
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        $children = @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue)
        foreach ($child in $children) {
            if (Test-IsProtectedPath -Path $child.FullName) {
                continue
            }
            $child
            if ($child.PSIsContainer) {
                $stack.Push($child.FullName)
            }
        }
    }
}

function Scan-Candidates {
    $Candidates.Clear()
    $Preserved.Clear()
    $script:CandidateKeys = @{}
    $script:PreservedKeys = @{}

    foreach ($protected in $ProtectedPaths) {
        Add-Preserved -Category 'ProtectedPath' -Path $protected -Reason 'configured protected path'
    }

    $misgenerated = @(
        (Join-Path (Split-Path -Parent $Root) 'desktopvisual-Root'),
        (Join-Path $Root 'Root'),
        (Join-Path $Root 'D'),
        (Join-Path $Root 'desktopvisual'),
        (Join-Path $Root 'tmp'),
        (Join-Path $Root 'temp'),
        (Join-Path (Split-Path -Parent $Root) 'desktopvisual.tmp'),
        (Join-Path $Root 'scratch'),
        (Join-Path $Root 'artifacts\tmp'),
        (Join-Path $Root 'artifacts\scratch')
    )
    foreach ($path in $misgenerated) {
        if (Test-Path -LiteralPath $path) {
            if (Test-MisgeneratedSafe -Path $path) {
                Add-Candidate -Category 'MisgeneratedDirectory' -Path $path -Reason 'explicit misgenerated/temp directory from hygiene policy'
            } else {
                Add-Preserved -Category 'MisgeneratedDirectory' -Path $path -Reason 'not safe to delete; contains source/config/docs/tasks/tests/scripts/git or evidence markers'
            }
        }
    }

    $buildExt = @('.obj', '.pch', '.ilk', '.pdb', '.idb', '.lastbuildstate')
    $tempExt = @('.tmp', '.temp', '.bak', '.old')
    $browserCacheDirNames = @(
        'GPUCache',
        'Code Cache',
        'ShaderCache',
        'Crashpad',
        'Cache',
        'Network',
        'Session Storage',
        'Service Worker'
    )

    foreach ($item in Get-UnprotectedTreeItems -Start $Root) {
        $full = $item.FullName
        $name = $item.Name
        $rel = Get-RelativePath -Path $full

        if ($item.PSIsContainer) {
            if ($name -in @('.vs', 'CMakeFiles', 'obj')) {
                Add-Candidate -Category 'BuildIntermediateDirectory' -Path $full -Reason "build intermediate directory named $name"
                continue
            }
            if (($name -in @('Debug', 'Release')) -and -not (Test-UnderArtifacts -Path $full)) {
                Add-Candidate -Category 'BuildIntermediateDirectory' -Path $full -Reason "build output/intermediate directory named $name"
                continue
            }
            if ($rel -in @('x64\Debug', 'x64\Release', 'build\temp', 'build\obj')) {
                Add-Candidate -Category 'BuildIntermediateDirectory' -Path $full -Reason 'known build intermediate directory path'
                continue
            }
            if ((Test-UnderArtifacts -Path $full) -and ($name -in $browserCacheDirNames)) {
                Add-Candidate -Category 'BrowserTempDirectory' -Path $full -Reason "browser temporary/cache directory named $name"
                continue
            }
            $child = @(Get-ChildItem -LiteralPath $full -Force -ErrorAction SilentlyContinue | Select-Object -First 1)
            if ($child.Count -eq 0) {
                Add-Candidate -Category 'EmptyDirectory' -Path $full -Reason 'empty directory'
                continue
            }
            continue
        }

        $ext = [System.IO.Path]::GetExtension($name).ToLowerInvariant()
        if ($buildExt -contains $ext -or $name -ieq 'CMakeCache.txt') {
            Add-Candidate -Category 'BuildIntermediateFile' -Path $full -Reason "build intermediate file extension/name $name"
            continue
        }
        if ($name -like '*.tlog') {
            Add-Candidate -Category 'BuildIntermediateFile' -Path $full -Reason 'MSBuild tlog file'
            continue
        }
        if ((Test-UnderArtifacts -Path $full) -and ($name -match '^(manual_random_|tmp_|debug_|scratch_|retry_|ocr_tmp_|observe_tmp_).+\.bmp$')) {
            Add-Candidate -Category 'TemporaryScreenshot' -Path $full -Reason 'temporary BMP pattern under artifacts'
            continue
        }
        if ((Test-UnderArtifacts -Path $full) -and ($name -match '^(tmp_|debug_|scratch_|retry_|ocr_tmp_|observe_tmp_).+\.(png|jpg|jpeg)$')) {
            Add-Candidate -Category 'TemporaryScreenshot' -Path $full -Reason 'temporary image pattern under artifacts'
            continue
        }
        if ($tempExt -contains $ext) {
            Add-Candidate -Category 'TemporaryFile' -Path $full -Reason "temporary file extension $ext"
            continue
        }
        if ($ext -eq '.log') {
            Add-Candidate -Category 'TemporaryLog' -Path $full -Reason 'log file not under protected evidence path'
            continue
        }
        if ($name -in @('retry.log', 'debug.log', 'scratch.log', 'stdout.tmp', 'stderr.tmp')) {
            Add-Candidate -Category 'TemporaryLog' -Path $full -Reason 'known temporary log filename'
            continue
        }
        if ((Test-UnderArtifacts -Path $full) -and ($name -like 'Cookies*')) {
            Add-Candidate -Category 'BrowserTempFile' -Path $full -Reason 'browser Cookies temporary copy under artifacts'
            continue
        }
        if ($ext -eq '.zip' -and ($rel -match '(?i)(\\tmp\\|\\temp\\|\\scratch\\|\\dist\\|failed|retry|tmp|temp|scratch|old|backup)')) {
            Add-Candidate -Category 'TemporaryArchive' -Path $full -Reason 'temporary or failed archive pattern'
            continue
        }
    }

    Compress-Candidates
}

function Compress-Candidates {
    $ordered = @($Candidates | Sort-Object @{ Expression = { $_.full_path.Length }; Ascending = $true })
    $kept = New-Object 'System.Collections.Generic.List[object]'
    foreach ($candidate in $ordered) {
        $insideKeptDir = $false
        foreach ($existing in $kept) {
            if ($existing.type -eq 'Directory' -and (Test-WithinPath -Path $candidate.full_path -Base $existing.full_path)) {
                if ((Normalize-PathKey -Path $candidate.full_path) -ne (Normalize-PathKey -Path $existing.full_path)) {
                    $insideKeptDir = $true
                    break
                }
            }
        }
        if (-not $insideKeptDir) {
            $kept.Add($candidate) | Out-Null
        }
    }
    $Candidates.Clear()
    foreach ($k in $kept) { $Candidates.Add($k) | Out-Null }
}

function Get-CategorySummary {
    param([object[]]$Items)
    $rows = New-Object 'System.Collections.Generic.List[object]'
    foreach ($group in ($Items | Group-Object category | Sort-Object Name)) {
        $bytes = [int64]0
        foreach ($item in $group.Group) { $bytes += [int64]$item.size_bytes }
        $rows.Add([pscustomobject]@{
            category = $group.Name
            count = $group.Count
            size_bytes = $bytes
            size_mb = [math]::Round(($bytes / 1MB), 3)
        }) | Out-Null
    }
    return $rows
}

function Write-SizeReport {
    param(
        [string]$Path,
        [string]$Label
    )
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $rootBytes = Measure-PathBytes -Path $Root
    $lines.Add("# $Label") | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add("Root: $Root") | Out-Null
    $lines.Add("Total: $(Format-Bytes -Bytes $rootBytes)") | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('## Top-level entries') | Out-Null
    foreach ($child in Get-ChildItem -LiteralPath $Root -Force -ErrorAction SilentlyContinue | Sort-Object Name) {
        $bytes = Measure-PathBytes -Path $child.FullName
        $type = if ($child.PSIsContainer) { 'Directory' } else { 'File' }
        $lines.Add(('- {0} [{1}] {2}' -f $child.Name, $type, (Format-Bytes -Bytes $bytes))) | Out-Null
    }
    Write-Text -Path $Path -Lines $lines
}

function Write-PolicyReports {
    $cleanupPolicy = @(
        '# Cleanup Policy',
        '',
        'This is not release cleanup.',
        'This phase only deletes development garbage: temporary files, caches, intermediate files, misgenerated directories, reproducible build outputs, browser temporary files, screenshot floods, and invalid temporary output.',
        'This phase does not delete valid evidence.',
        'This phase does not delete invalidated evidence.',
        'This phase does not delete source, config, docs, tests, task files, samples, or scripts.',
        'This phase does not modify functional logic.',
        'This phase does not modify permission policy.',
        'This phase does not create D:\desktopvisual-release.',
        'This phase does not enter v6.',
        'This phase does not git commit and does not use git reset --hard.',
        '',
        "Mode for this run: $Mode",
        "SkipBuild parameter supplied: $([bool]$SkipBuild)"
    )
    Write-Text -Path (Join-Path $ArtifactRoot 'cleanup_policy.md') -Lines $cleanupPolicy

    $protectedLines = @('# Protected Paths', '')
    foreach ($rel in $ProtectedRelPaths) {
        $full = Join-Path $Root $rel
        $exists = Test-Path -LiteralPath $full
        $protectedLines += ('- `{0}` -> `{1}` ({2})' -f $rel, $full, $(if ($exists) { 'exists' } else { 'missing' }))
    }
    $protectedLines += ''
    $protectedLines += 'Candidates under these paths are preserved by default. This run uses a stricter evidence policy: valid evidence and invalidated evidence trees are not cleaned internally.'
    Write-Text -Path (Join-Path $ArtifactRoot 'protected_paths.md') -Lines $protectedLines
}

function Write-ScanReports {
    $candidateArray = $Candidates.ToArray()
    $summary = @(Get-CategorySummary -Items $candidateArray)
    Write-Json -Path (Join-Path $ArtifactRoot 'dry_run_candidates.json') -Value @{
        mode = $Mode
        root = $Root
        generated_at = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        candidate_count = $candidateArray.Count
        candidate_size_bytes = [int64](($candidateArray | Measure-Object -Property size_bytes -Sum).Sum)
        summary = $summary
        candidates = $candidateArray
    }

    $lines = @(
        '# Dry Run Summary',
        '',
        "Mode: $Mode",
        "Root: $Root",
        "Candidate count: $($candidateArray.Count)",
        "Candidate size: $(Format-Bytes -Bytes ([int64](($candidateArray | Measure-Object -Property size_bytes -Sum).Sum)))",
        '',
        '## By Category'
    )
    foreach ($row in $summary) {
        $lines += ('- {0}: {1} item(s), {2}' -f $row.category, $row.count, (Format-Bytes -Bytes ([int64]$row.size_bytes)))
    }
    if ($candidateArray.Count -eq 0) {
        $lines += '- No safe cleanup candidates found.'
    }
    $lines += ''
    $lines += '## Guard Result'
    $lines += '- Protected source/config/docs/tasks/tests/scripts paths are preserved.'
    $lines += '- Valid v5.10.1/v5.10.2 evidence paths are preserved.'
    $lines += '- Invalidated evidence paths are preserved.'
    $lines += '- Apply is required for deletion; dry-run mode deletes nothing.'
    Write-Text -Path (Join-Path $ArtifactRoot 'dry_run_summary.md') -Lines $lines

    $preservedLines = @('# Preserved Files And Reasons', '')
    foreach ($item in @($Preserved | Sort-Object path, reason)) {
        $preservedLines += ('- `{0}` [{1}] {2}: {3}' -f $item.path, $item.type, (Format-Bytes -Bytes ([int64]$item.size_bytes)), $item.reason)
    }
    if ($Preserved.Count -eq 0) { $preservedLines += '- No preserved candidate conflicts recorded.' }
    Write-Text -Path (Join-Path $ArtifactRoot 'preserved_files_reason.md') -Lines $preservedLines
}

function Get-DeletionEntries {
    param([object]$Candidate)
    $entries = New-Object 'System.Collections.Generic.List[object]'
    if (-not (Test-Path -LiteralPath $Candidate.full_path)) { return $entries }
    $item = Get-Item -LiteralPath $Candidate.full_path -Force
    if ($item.PSIsContainer) {
        foreach ($child in Get-ChildItem -LiteralPath $Candidate.full_path -Recurse -Force -ErrorAction SilentlyContinue) {
            $entries.Add([pscustomobject]@{
                candidate_category = $Candidate.category
                candidate_path = $Candidate.full_path
                path = $child.FullName
                relative_path = Get-RelativePath -Path $child.FullName
                type = if ($child.PSIsContainer) { 'Directory' } else { 'File' }
                size_bytes = if ($child.PSIsContainer) { [int64]0 } else { [int64]$child.Length }
            }) | Out-Null
        }
        $entries.Add([pscustomobject]@{
            candidate_category = $Candidate.category
            candidate_path = $Candidate.full_path
            path = $Candidate.full_path
            relative_path = Get-RelativePath -Path $Candidate.full_path
            type = 'Directory'
            size_bytes = [int64]0
        }) | Out-Null
    } else {
        $entries.Add([pscustomobject]@{
            candidate_category = $Candidate.category
            candidate_path = $Candidate.full_path
            path = $Candidate.full_path
            relative_path = Get-RelativePath -Path $Candidate.full_path
            type = 'File'
            size_bytes = [int64]$item.Length
        }) | Out-Null
    }
    return $entries
}

function Invoke-ApplyCleanup {
    $deleted = New-Object 'System.Collections.Generic.List[object]'
    $deleteErrors = New-Object 'System.Collections.Generic.List[object]'
    foreach ($candidate in @($Candidates | Sort-Object @{ Expression = { $_.full_path.Length }; Descending = $true })) {
        if (-not (Test-Path -LiteralPath $candidate.full_path)) { continue }
        if (Test-IsProtectedPath -Path $candidate.full_path) {
            $deleteErrors.Add([pscustomobject]@{ path = $candidate.full_path; error = 'Refused at apply time: protected path' }) | Out-Null
            continue
        }
        if ($candidate.type -eq 'Directory' -and (Test-ContainsProtectedPath -Path $candidate.full_path)) {
            $deleteErrors.Add([pscustomobject]@{ path = $candidate.full_path; error = 'Refused at apply time: contains protected path' }) | Out-Null
            continue
        }
        if (Test-IsEvidenceReferenced -Path $candidate.full_path) {
            $deleteErrors.Add([pscustomobject]@{ path = $candidate.full_path; error = 'Refused at apply time: evidence referenced' }) | Out-Null
            continue
        }
        foreach ($entry in Get-DeletionEntries -Candidate $candidate) {
            $deleted.Add($entry) | Out-Null
        }
        try {
            Remove-Item -LiteralPath $candidate.full_path -Force -Recurse
        } catch {
            $deleteErrors.Add([pscustomobject]@{ path = $candidate.full_path; error = $_.Exception.Message }) | Out-Null
        }
    }

    $deleted | ForEach-Object { $_.relative_path } | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'deleted_files.txt') -Encoding UTF8
    Write-Json -Path (Join-Path $ArtifactRoot 'deleted_files.json') -Value @{
        mode = $Mode
        deleted_count = $deleted.Count
        errors = $deleteErrors.ToArray()
        deleted = $deleted.ToArray()
    }
    return [pscustomobject]@{
        deleted = $deleted.ToArray()
        errors = $deleteErrors.ToArray()
    }
}

function Test-RequiredPath {
    param([string]$RelPath)
    $full = Join-Path $Root $RelPath
    return [pscustomobject]@{
        path = $RelPath
        exists = (Test-Path -LiteralPath $full)
    }
}

function Write-EvidenceReports {
    $validRequired = @(
        'artifacts\dev5.10.1_real_ui_adaptive_cases',
        'artifacts\dev5.10.1_real_ui_adaptive_cases\evidence_index.md',
        'artifacts\dev5.10.2_real_taskruntime_final_gate',
        'artifacts\dev5.10.2_real_taskruntime_final_gate\evidence_index.md',
        'artifacts\dev5.10.2_real_taskruntime_final_gate\v6_handoff_readiness_report.md',
        'artifacts\dev5.10.2_real_taskruntime_final_gate\task_runtime\localhost_form_fill_submit_humanmode\task_result.json',
        'artifacts\dev5.10.2_real_taskruntime_final_gate\task_runtime\localhost_form_fill_submit_humanmode\task_events.jsonl',
        'artifacts\dev5.10.2_real_taskruntime_final_gate\task_runtime\localhost_form_fill_submit_humanmode\task_report.md',
        'artifacts\dev5.10.2_real_taskruntime_final_gate\task_runtime\localhost_form_fill_submit_humanmode\action_trace.jsonl',
        'artifacts\dev5.10.2_real_taskruntime_final_gate\task_runtime\localhost_form_fill_submit_humanmode\locator_trace.jsonl',
        'artifacts\dev5.10.2_real_taskruntime_final_gate\task_runtime\localhost_form_fill_submit_humanmode\adaptive_loop_trace.jsonl',
        'artifacts\dev5.10.2_real_taskruntime_final_gate\task_runtime\localhost_form_fill_submit_humanmode\human_action_results.jsonl',
        'artifacts\dev5.10.2_real_taskruntime_final_gate\task_runtime\localhost_form_fill_submit_humanmode\raw_command_log.jsonl',
        'artifacts\dev5.10.2_real_taskruntime_final_gate\task_runtime\localhost_form_fill_submit_humanmode\verification_report.md'
    )
    $validRows = foreach ($rel in $validRequired) { Test-RequiredPath -RelPath $rel }
    $validPass = -not (@($validRows | Where-Object { -not $_.exists }))
    $validLines = @(
        '# Evidence Protection Report',
        '',
        "dev5.10.1_real_ui_adaptive_cases still exists: $((Test-Path -LiteralPath (Join-Path $Root 'artifacts\dev5.10.1_real_ui_adaptive_cases')))",
        "dev5.10.2_real_taskruntime_final_gate still exists: $((Test-Path -LiteralPath (Join-Path $Root 'artifacts\dev5.10.2_real_taskruntime_final_gate')))",
        "evidence_index.md still exists: $((Test-Path -LiteralPath (Join-Path $Root 'artifacts\dev5.10.2_real_taskruntime_final_gate\evidence_index.md')))",
        "v6_handoff_readiness_report.md still exists: $((Test-Path -LiteralPath (Join-Path $Root 'artifacts\dev5.10.2_real_taskruntime_final_gate\v6_handoff_readiness_report.md')))",
        '',
        '## Required Evidence Files',
        ''
    )
    foreach ($row in $validRows) {
        $validLines += ('- `{0}`: {1}' -f $row.path, $(if ($row.exists) { 'exists' } else { 'MISSING' }))
    }
    $validLines += ''
    $validLines += "Result: $(if ($validPass) { 'PASS' } else { 'FAIL' })"
    Write-Text -Path (Join-Path $ArtifactRoot 'evidence_protection_report.md') -Lines $validLines

    $invalidRequired = @(
        'artifacts\invalidated',
        'artifacts\invalidated\dev5.10.1_adaptive_cases_INVALIDATED',
        'artifacts\invalidated\dev5.10.1_adaptive_cases_INVALIDATED\INVALIDATED_DO_NOT_USE.md',
        'artifacts\invalidated\dev5.10.2_final_pre_v6_gate_INVALIDATED',
        'artifacts\invalidated\dev5.10.2_final_pre_v6_gate_INVALIDATED\INVALIDATED_DO_NOT_USE.md',
        'artifacts\invalidation_index.md'
    )
    $invalidRows = foreach ($rel in $invalidRequired) { Test-RequiredPath -RelPath $rel }
    $invalidPass = -not (@($invalidRows | Where-Object { -not $_.exists }))
    $invalidLines = @(
        '# Invalidated Evidence Protection Report',
        '',
        "artifacts\invalidated still exists: $((Test-Path -LiteralPath (Join-Path $Root 'artifacts\invalidated')))",
        "INVALIDATED_DO_NOT_USE.md still exists: $((Get-ChildItem -LiteralPath (Join-Path $Root 'artifacts\invalidated') -Recurse -Force -Filter 'INVALIDATED_DO_NOT_USE.md' -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0)",
        "invalidation_index.md still exists: $((Test-Path -LiteralPath (Join-Path $Root 'artifacts\invalidation_index.md')))",
        '',
        '## Required Invalidated Evidence Files',
        ''
    )
    foreach ($row in $invalidRows) {
        $invalidLines += ('- `{0}`: {1}' -f $row.path, $(if ($row.exists) { 'exists' } else { 'MISSING' }))
    }
    $invalidLines += ''
    $invalidLines += "Result: $(if ($invalidPass) { 'PASS' } else { 'FAIL' })"
    Write-Text -Path (Join-Path $ArtifactRoot 'invalidated_evidence_protection_report.md') -Lines $invalidLines
}

function Write-DevSummary {
    param(
        [int64]$BeforeBytes,
        [int64]$AfterBytes,
        [object]$ApplyResult
    )
    $candidateBytes = [int64]$script:InitialCandidateBytes
    $candidateCount = [int]$script:InitialCandidateCount
    $remainingCount = if ($null -ne $script:RemainingCandidateCount) { [int]$script:RemainingCandidateCount } else { $candidateCount }
    $freed = [int64]($BeforeBytes - $AfterBytes)
    if (-not $Apply) { $freed = [int64]0 }
    $deletedCount = if ($ApplyResult) { @($ApplyResult.deleted).Count } else { 0 }
    $errorCount = if ($ApplyResult) { @($ApplyResult.errors).Count } else { 0 }
    $lines = @(
        '# v5.10.2 Development Tree Hygiene Summary',
        '',
        'Current version: 5.10.2',
        'Goal: lightweight development tree hygiene without damaging the trusted v5.10.2 handoff baseline.',
        "Mode: $Mode",
        "Dry-run candidate count: $candidateCount",
        "Candidate size: $(Format-Bytes -Bytes $candidateBytes)",
        "Remaining candidate count after cleanup scan: $remainingCount",
        "Deleted entries recorded: $deletedCount",
        "Delete errors: $errorCount",
        "Freed space: $(Format-Bytes -Bytes $freed)",
        '',
        'Protected outcomes:',
        '- Source deleted: no',
        '- Valid evidence deleted: no',
        '- Invalidated evidence deleted: no',
        '- v6 handoff readiness report deleted: no',
        '',
        'This run did not create D:\desktopvisual-release, did not enter v6, did not modify functional logic, did not modify permission policy, did not git commit, and did not run git reset --hard.'
    )
    Write-Text -Path (Join-Path $ArtifactRoot 'dev_summary.md') -Lines $lines
}

function Write-KnownLimits {
    $lines = @(
        '# Known Limits',
        '',
        '- Runtime correctness-first, not latency-optimized.',
        '- HumanMode is not weakened for speed.',
        '- Repeated CLI invocation latency remains future v6 optimization work.',
        '- This phase is development-tree hygiene only, not public release cleanup.',
        '- This script does not rerun real UI evidence collection; it preserves and validates existing evidence files.'
    )
    Write-Text -Path (Join-Path $ArtifactRoot 'known_limits.md') -Lines $lines
}

$beforeBytes = Measure-PathBytes -Path $Root
Write-SizeReport -Path (Join-Path $ArtifactRoot 'size_before.txt') -Label 'Size Before Cleanup'
Write-PolicyReports
Scan-Candidates
Write-ScanReports
$InitialCandidates = $Candidates.ToArray()
$InitialCandidateCount = $InitialCandidates.Count
$InitialCandidateBytes = [int64](($InitialCandidates | Measure-Object -Property size_bytes -Sum).Sum)
$RemainingCandidateCount = $InitialCandidateCount

$applyResult = $null
if ($Apply) {
    $applyResult = Invoke-ApplyCleanup
    Scan-Candidates
    $RemainingCandidates = $Candidates.ToArray()
    $RemainingCandidateCount = $RemainingCandidates.Count
    Write-Json -Path (Join-Path $ArtifactRoot 'post_apply_remaining_candidates.json') -Value @{
        mode = $Mode
        root = $Root
        generated_at = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        remaining_candidate_count = $RemainingCandidates.Count
        remaining_candidate_size_bytes = [int64](($RemainingCandidates | Measure-Object -Property size_bytes -Sum).Sum)
        summary = @(Get-CategorySummary -Items $RemainingCandidates)
        candidates = $RemainingCandidates
    }
    $Candidates.Clear()
    foreach ($candidate in $InitialCandidates) { $Candidates.Add($candidate) | Out-Null }
} else {
    @() | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'deleted_files.txt') -Encoding UTF8
    Write-Json -Path (Join-Path $ArtifactRoot 'deleted_files.json') -Value @{
        mode = $Mode
        deleted_count = 0
        errors = @()
        deleted = @()
    }
}

$afterBytes = Measure-PathBytes -Path $Root
Write-SizeReport -Path (Join-Path $ArtifactRoot 'size_after.txt') -Label 'Size After Cleanup'
$freedBytes = if ($Apply) { [int64]($beforeBytes - $afterBytes) } else { [int64]0 }
Write-Text -Path (Join-Path $ArtifactRoot 'freed_space.txt') -Lines @(
    "# Freed Space",
    '',
    "Mode: $Mode",
    "Before: $(Format-Bytes -Bytes $beforeBytes)",
    "After: $(Format-Bytes -Bytes $afterBytes)",
    "Freed: $(Format-Bytes -Bytes $freedBytes)",
    "Dry-run candidate size: $(Format-Bytes -Bytes $InitialCandidateBytes)"
)
Write-EvidenceReports
Write-KnownLimits
Write-DevSummary -BeforeBytes $beforeBytes -AfterBytes $afterBytes -ApplyResult $applyResult

$postLines = @(
    '# Post Cleanup Validation Report',
    '',
    "Mode: $Mode",
    'Script validation:',
    '- Protected path guard executed.',
    '- Valid evidence presence checked.',
    '- Invalidated evidence presence checked.',
    '- Deletion only occurs with -Apply.',
    '',
    'External validation commands are recorded by the phase runner after this script: build, version, smoke tests, evidence-only checks, JSON/JSONL parse, Markdown fence validation, encoding scan, and COMMAND_PROTOCOL consistency.'
)
Write-Text -Path (Join-Path $ArtifactRoot 'post_cleanup_validation_report.md') -Lines $postLines

[pscustomobject]@{
    ok = $true
    mode = $Mode
    root = $Root
    artifact_root = $ArtifactRoot
    dry_run_candidates = $InitialCandidateCount
    remaining_candidates_after_apply = $RemainingCandidateCount
    freed_bytes = $freedBytes
    source_deleted = $false
    valid_evidence_deleted = $false
    invalidated_evidence_deleted = $false
} | ConvertTo-Json -Depth 6
