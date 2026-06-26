# Repository Hygiene

Current version: `v3.7.0`.

DesktopVisual keeps source, documentation, examples, and reviewed configuration in Git. Runtime evidence and local operator data stay out of Git.

## Goes In Git

- `src/`
- `scripts/`
- root PowerShell scripts
- `docs/`
- `cases/`
- `tasks/`
- `config/safety.conf`
- `dogfood/`
- `skill_template/`
- `samples/` example files
- `README.md`, `CHANGELOG.md`, `COMMAND_PROTOCOL.md`, `VERSION`, release notes, and repository metadata

## Stays Out Of Git

- `artifacts/`
- `bin/`
- `dist/`
- `obj/`
- `logs/`
- release archives such as `*.zip` and `*.7z`
- screenshots, bitmap captures, browser caches, generated browser profiles, and temporary files
- raw motion trajectory files under `artifacts/motion_profile/**/raw/`
- local browser profiles such as `edge_profile/`, `debug_profile/`, `browser_profile/`, and `profile/`
- browser state files/directories such as `Cookies`, `History`, `Login Data`, `Web Data`, `Local Storage/`, `Session Storage/`, and `IndexedDB/`
- local operator profile `config/operator_motion_profile.json`

Sample profiles are allowed only under `samples/` and must be synthetic or clearly marked sample data.

## Build From Clone

```powershell
git clone <repo-url> DesktopVisual
cd DesktopVisual
.\build.ps1
.\selftest.ps1
```

For a clone in another path:

```powershell
$env:DESKTOPVISUAL_ROOT = (Get-Location).Path
.\build.ps1 -Root $env:DESKTOPVISUAL_ROOT
.\selftest.ps1 -Root $env:DESKTOPVISUAL_ROOT
```

## Release Packaging

`D:\desktopvisual` is the local development/evaluation tree and must not be submitted directly as the public release project. Public release must be prepared in a separate restricted tree:

```text
D:\desktopvisual-release
```

Create a clean source package only after the release tree has the restricted permission policy for exam, interview assessment, hiring test, certification, rated-contest, proctored, and similar workflows:

```powershell
.\package_source.ps1 -Root (Get-Location).Path
```

The default output is:

```text
artifacts\release\DesktopVisual-v<VERSION>-source.zip
```

The source zip excludes generated runtime directories, binaries, browser profiles, browser state files, raw motion data, and release archives. It includes `SOURCE_PACKAGE_MANIFEST.md` at the package root.

## Cleanup

Preview generated files:

```powershell
.\clean_artifacts.ps1 -DryRun
```

Delete generated files:

```powershell
.\clean_artifacts.ps1 -DeleteGenerated
```

## Upload Checklist

- `git status` shows only intended source and documentation changes.
- `.\public_repo_check.ps1` passes.
- `.\package_source.ps1` produces the source zip.
- No files from `artifacts/`, `bin/`, `dist/`, `obj/`, browser profiles/state, raw motion data, or local operator profiles are staged.
- Public release is prepared from `D:\desktopvisual-release`, not by directly submitting `D:\desktopvisual`.
- The release tree contains restricted permissions for assessment/exam-like workflows.
