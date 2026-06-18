# Command Protocol

This public package exposes the public runtime binary at `bin\winagent.exe`.

Key smoke-test commands:

```powershell
.\bin\winagent.exe version
.\bin\winagent.exe public-release-safety-check --title "Public Tutorial" --process browser.exe --action read --user-request "Summarize" --context "This page says test and quiz but has no assistance restriction."
```

Stop codes relevant to this public package:

- `STOP_USER_FORCE_EXIT_F12`: user pressed F12 or the test harness simulated F12; current task only; process remains alive.
- `STOP_PUBLIC_RELEASE_EXAM_INTEGRITY_POLICY`: explicit formal assessment integrity risk detected.
- `STOP_ACTIVE_PROTECTION_OR_LOGIN_BLOCK`: active protection, human verification, anti-automation, or related blocked context detected.
- `STOP_CREDENTIAL_REQUIRED`: credential or account sign-in requirement detected.

Runner output must not convert STOP results into PASS. Public release safety STOP and F12 STOP are distinct.
