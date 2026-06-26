# DesktopVisual v3.0.2 Release Notes

v3.0.2 finishes Portable Root and GitHub Hygiene work.

## Highlights

- Added portable root resolution for scripts and `winagent.exe`.
- Added `DESKTOPVISUAL_ROOT` support.
- Added `project_root` to `winagent version`.
- Added `${PROJECT_ROOT}` expansion for `config\safety.conf` and case paths.
- Added `portable_root_selftest.ps1`.
- Added repository hygiene documentation and source package manifest generation.
- Source package output defaults to `artifacts\release\DesktopVisual-v3.0.2-source.zip`.

## Compatibility

The legacy `D:\desktopvisual` path remains supported as the final fallback. Existing commands and JSON envelopes remain compatible.

## Verification

Run:

```powershell
.\build.ps1
.\selftest.ps1
.\portable_root_selftest.ps1
.\public_repo_check.ps1
.\package_source.ps1
.\rc_check.ps1
.\release.ps1
.\verify_release.ps1
```
