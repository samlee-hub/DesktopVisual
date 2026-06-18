# DesktopVisual 1.0.0 Public

DesktopVisual is a local Windows desktop automation runtime for visible UI workflows.

This public package is intended for authorized local desktop automation, browser form workflows, local file workflows, communication drafts, developer tests, and personal tasks where automation is permitted.

Do not use this package to violate explicit rules for exams, assessments, interviews, contests, or platform evaluations. Do not use it to bypass CAPTCHA, human verification, credential or account checks, proctoring, lockdown browser, anti-cheat, anti-automation, or third-party security controls.

The public release policy is context based. It is not a keyword-only blocker. Words such as test, quiz, exam, OJ, or LeetCode do not stop automation by themselves.

F12 stops the current task only and returns STOP_USER_FORCE_EXIT_F12. It does not close winagent.

Run the package smoke checks:

```powershell
.\selftest.ps1
.\f12_force_exit_selftest.ps1
.\public_release_safety_policy_selftest.ps1
.\public_release_exam_integrity_policy_selftest.ps1
.\public_release_allowed_context_selftest.ps1
.\public_release_acceptance_gate.ps1
```

The default/full_access user mode selector is deferred in this release candidate.
