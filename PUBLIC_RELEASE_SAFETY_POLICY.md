# Public Release Safety Policy

The public release build must not assist automation that violates explicit exam, test, assessment, interview, contest, or platform rules.

This is not a simple keyword denylist. The words test, quiz, exam, OJ, LeetCode, or similar terms do not trigger a stop by themselves.

The release build stops when a clear risk is present, such as:

- a formal exam, assessment, interview evaluation, online test, or proctored environment
- explicit rules prohibiting cheating, external assistance, AI assistance, scripts, automation, third-party tools, or answer delegation
- active proctoring, lockdown browser, exam security monitoring, anti-cheat, anti-automation, CAPTCHA, human verification, account security verification, or credential-required surfaces
- a user request to answer, submit, fill answers, complete the assessment, or bypass restrictions in that context

Exam integrity stop code:

- `STOP_PUBLIC_RELEASE_EXAM_INTEGRITY_POLICY`

F12 force-exit stop code:

- `STOP_USER_FORCE_EXIT_F12`

Allowed ordinary contexts include normal web search, code learning, local OJ simulation, personal practice, user-created test pages, developer test windows, ordinary web forms, mail/message drafts, and public tutorials.
