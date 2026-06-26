# DesktopVisual v3.0.5 Release Notes

## Safety Manifest And Consent Layer

v3.0.5 upgrades DesktopVisual safety from documentation-only boundaries to a machine-readable manifest and dry-run consent layer.

## Added

- `config\safety_manifest.json`
- `src\winagent\SafetyManifest.h`
- `src\winagent\SafetyManifest.cpp`
- `winagent.exe safety-report`
- `winagent.exe policy-check`
- `winagent.exe consent-check`
- Service endpoints `/safety-report`, `/policy-check`, and `/consent-check`
- `safety_manifest_selftest.ps1`
- `docs\SAFETY_MODEL.md`

## Safety Behavior

- `safety.conf` remains the hard allowlist boundary.
- The Safety Manifest cannot loosen `safety.conf`.
- Sensitive categories such as password, credential, payment, protected desktop, admin elevation, anti-cheat, and captcha are denied.
- `run-task` rejects `allow_unrestricted_desktop` and writes Safety Manifest summaries into task reports.

## Verification

Run:

```powershell
D:\desktopvisual\build.ps1
D:\desktopvisual\safety_manifest_selftest.ps1
D:\desktopvisual\rc_check.ps1
```
