# Public Release Safety Policy

DesktopVisual public release builds include a minimal exam integrity policy.

## Core Rule

The release build must not assist automation that violates explicit exam, test, assessment, interview, contest, or platform rules.

The policy is not a simple keyword denylist. The words `test`, `quiz`, `exam`, `OJ`, `LeetCode`, or similar terms do not trigger a stop by themselves.

## Stop Conditions

The release build stops when a clear risk is present, such as:

- a formal exam, assessment, interview evaluation, online test, or proctored environment
- explicit rules prohibiting cheating, external assistance, AI assistance, scripts, automation, third-party tools, or answer delegation
- active proctoring, lockdown browser, exam security monitoring, anti-cheat, anti-automation, CAPTCHA, human verification, account security verification, or credential-required surfaces
- a user request to answer, submit, fill answers, complete the assessment, or bypass restrictions in that context

Exam integrity stop code:

- `STOP_PUBLIC_RELEASE_EXAM_INTEGRITY_POLICY`

User message:

- The release build stops and asks the user to continue only in environments where automation assistance is allowed.

## Allowed Contexts

The policy allows ordinary contexts, including:

- normal web search
- code learning
- local OJ simulation
- personal practice questions
- user-created test pages
- developer test windows
- ordinary web forms
- mail/message drafts
- pages that merely contain `test`, `quiz`, or `exam` without explicit integrity or assistance restrictions
- public tutorials or explanations

## Safety Boundaries

The release build must not bypass:

- CAPTCHA or human verification
- credential or account verification
- proctoring
- lockdown browser
- anti-cheat
- anti-automation
- third-party security or automation interception

default/full_access user mode selector = deferred.
