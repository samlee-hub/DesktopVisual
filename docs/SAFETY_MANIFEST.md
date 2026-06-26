# Safety Manifest

Current internal version: `v5.10.2`.

## v5.10.2 REBUILT TaskRuntime Evidence Safety

Rebuilt v5.10.2 does not change the permission model. It repairs TaskRuntime evidence integrity by requiring real winagent HumanMode command output, raw traces, field/status verification, local-only `127.0.0.1` binding, and independent verifier judgment. The old invalidated v5.10.2 artifacts remain non-evidence.

The real TaskRuntime localhost mock mail flow is not a permission expansion. Active protection remains a hard STOP, and ordinary content words such as test, exam, assessment, quiz, problem, challenge, mail, submit, localhost, local HTML, and ordinary external web are not blocked by words alone.

## v5.10.1 REBUILT Real UI Evidence Safety

Rebuilt v5.10.1 does not change the permission model. It repairs evidence integrity by requiring real winagent HumanMode command output plus independent verifier judgment for Case D/E/F. The old invalidated v5.10.1 and v5.10.2 artifacts remain non-evidence.

The runner/verifier split is a safety rule: the runner cannot self-certify PASS, cannot write synthetic traces as evidence, and cannot convert diagnostic/mock output into final PASS. The verifier must fail synthetic evidence, placeholder screenshots, hardcoded hwnd/rect, backend/direct-launch actions, JS/DOM/WebDriver/CDP, UIA InvokePattern/ValuePattern actions, and active-protection bypass attempts.

Developer capability discovery remains open for ordinary Chrome / Edge, Explorer, This PC, D: drive, local HTML, localhost, ordinary external webpages, ordinary apps, ordinary forms, and ordinary test/exam/assessment/challenge/problem/submit/mail pages when no concrete active-protection signal is present. CAPTCHA, reCAPTCHA, hCaptcha, Turnstile, human verification, bot challenge, automation/script detection, anti-cheat, lockdown/secure exam browsers, active proctoring, and bypass requests still STOP.

## v5.10.1/v5.10.2 Invalidated Evidence Safety

v5.10.1 and v5.10.2 are invalidated without changing the permission model. v5.10.1 synthetic Adaptive HumanMode case evidence and v5.10.2 hardcoded/simulated TaskRuntime browser form evidence must not be used as PASS evidence or v6 handoff evidence.

The current trusted baseline is v5.10.0 Adaptive HumanMode Control Loop Core. Synthetic evidence, placeholder screenshots, hardcoded rectangles, and simulated PASS output are not valid safety or runtime evidence. Real Explorer/browser/localhost/TaskRuntime UI evidence remains required.

v5 remains a known/local/profile-bound Runtime. v6 has not started.

## v5.9.3 Explorer Mouse Target Strictness Safety

v5.9.3 does not change the permission model. It only requires Explorer Case D strict evidence to prove that the real cursor is inside each target item rect before the real double-click. Incremental search may be used only as locator assistance; incremental search + Enter, keyboard-assisted/default selection opens, Explorer address-bar path input, direct file open, ShellExecute, Start-Process, Invoke-Item, UIA InvokePattern/ValuePattern, and backend opens are not strict PASS actions.

Developer capability discovery remains open for ordinary Chrome / Edge, Explorer, local HTML, localhost, ordinary webpages, ordinary apps, and ordinary forms. Concrete active-protection signals still STOP and must not be bypassed.

v5.x is an internal engineering stage number for the Task-Level Desktop Execution Runtime. v6 has not started in this tree. v5 does not rely on VLM. Before public release, a Version Normalization Pass will map this internal stage to a `0.x.x` prerelease version; the first formal public stable release remains `1.0.0`.

DesktopVisual uses `config\safety_manifest.json` plus `config\safety.conf` to record consent, permission modes, denied categories, and audit settings. The manifest cannot loosen `safety.conf`.

## v5.9.2 Active Protection STOP Policy

v5.9.2 is not a permission narrowing pass. It keeps `DEVELOPER_CAPABILITY_DISCOVERY` open for ordinary Runtime exploration of Chrome / Edge, browser navigation, Explorer, ordinary apps, local HTML, localhost, ordinary external webpages, ordinary forms, buttons, and mock mail/local fixtures.

Ordinary content words are not active protection signals by themselves: test, exam, assessment, quiz, problem, challenge, homework, coding, OJ, submit, mail, message, recipient, hiring, recruitment, interview, localhost, local HTML, ordinary external web, ordinary form, ordinary button, browser, Chrome, Explorer, PyCharm, VS Code, and ordinary app names remain allowed under the developer profile when no concrete protection signal is present.

Concrete active-protection signals must STOP in developer mode: CAPTCHA, reCAPTCHA, hCaptcha, Turnstile, human verification, bot challenge/check, automation or script detection, suspicious automation, anti-cheat process/service names, lockdown / secure exam browsers, active proctoring, screen monitoring protection, and explicit bypass requests. The runtime stops and reports `STOP_ACTIVE_PROTECTION` / `BLOCKED_BY_ACTIVE_PROTECTION`; it does not bypass, hook, inject, patch, hide automation, or disable protection.

## v5.5 File / Attachment Safety

File and attachment workflows are local and metadata-only by default. `FilePathResolver` is default-deny without explicit allowed roots and rejects traversal, missing files, files outside allowed roots, disallowed extensions, and files over policy size. File workflow reports must not include file contents.

`FilePickerFlow` is the preferred controlled route for mock attachment selection. Desktop drag/drop is not the default. `CrossWindowTaskContext` must verify the child picker returns to the parent task window before continuing.

Local mail mock attachment flows can verify upload completed or failed, but they must not send real email or upload to real accounts. External upload, sensitive file exfiltration, credentials, payment-like flows, and public assessment submissions remain blocked safety categories. v5.5 file picker and attachment verification remain local mock/fixture workflows, not general product-grade external upload support.

## v5.3 Confirmation Alignment

Risk-controlled actions are constrained by code-level confirmation gates:

- High-risk actions require `ConfirmationRequest` plus accepted `ConfirmationResult`.
- Rejected or timed-out confirmation stops the action.
- Blocked actions cannot be approved by confirmation.
- Agent/VLM escalation cannot bypass confirmation or SafeStop.
- Public release profiles must stop assessment/exam/hiring/certification/rated-contest submission workflows instead of relying on confirmation.

## High-Risk Actions

- send email
- submit external form
- delete file
- overwrite file
- external upload
- external download
- account setting change
- public posting
- payment-like action

## Blocked Actions

- captcha
- anti-automation challenge
- anti_cheat
- proctoring
- real_exam
- real_hiring_assessment
- certification or rated-contest submission
- payment_confirmation
- credential_security_challenge
- game_cheating
- phishing
- bulk harassment
- unconfirmed external send
- protected desktop or elevated/admin prompt

Blocked actions must STOP. They cannot be approved by confirmation and cannot be routed through VLM, Agent, prompt, template, config, service request, or provider escalation as a bypass.

## Development vs Public Release

`D:\desktopvisual` may contain local mock benchmarks and broad development fixtures. `D:\desktopvisual-release` must use restricted public permissions and must not expose high-risk public assessment workflows as confirmable actions.

## v5.9.0-a Developer Runtime Permission Reset

`D:\desktopvisual` now defaults to `DEVELOPER_CAPABILITY_DISCOVERY` for internal Runtime capability discovery. Developer mode allows audited ordinary desktop UI primitives, browser, Explorer, third-party apps, local HTML, localhost, ordinary external web navigation, ordinary form filling, local problem/mock OJ pages, frontend test pages, local mail mocks, and mock recruitment forms.

Developer mode does not block by content category or ordinary words. `test`, `exam`, `assessment`, `quiz`, `homework`, `problem`, `challenge`, `submit`, `mail`, `hiring`, `recruitment`, and `coding` are not active protection signals by themselves.

The STOP boundary is active protection and bypass behavior: captcha, human verification, automation/script detection, active anti-cheat, active proctoring/lockdown browser, protected desktop/UAC, and any attempt to hook, inject, patch memory, hide automation, disable protection, or bypass third-party protection. These return `STOP_ACTIVE_PROTECTION` / `BLOCKED_BY_ACTIVE_PROTECTION` style status.

`PUBLIC_DEFAULT` is retained for future public release narrowing. Do not apply public release restrictions to internal developer capability discovery.


## v5.9.0-b HumanMode Visible UI Safety

v5.9.0-b remains v5 and adds HumanMode visible UI Case Runner evidence. Developer mode allows basic desktop UI exploration for Chrome/Edge, Explorer, Program Manager/Desktop, ordinary third-party apps, local HTML, localhost, ordinary external navigation, and local mock forms without FULL_ACCESS. It does not block ordinary words such as test, exam, assessment, quiz, problem, challenge, submit, mail, hiring, or recruitment.

HumanMode actions are real visible mouse and keyboard events only. UIA/OCR/ElementGraph are locator and verification sources. Direct launch, ShellExecute, DOM mutation, JavaScript, UIA InvokePattern, UIA ValuePattern, Selenium, Playwright, WebDriver, CDP, backend typing, and no-open mocks are not HumanMode actions.

Active protection still stops: CAPTCHA, human verification, automation/script/bot detection, active anti-cheat, active proctoring/lockdown browser, protected desktop/UAC, and bypass requests return STOP_ACTIVE_PROTECTION / BLOCKED_BY_ACTIVE_PROTECTION style outcomes.

## v5.9.0-c Strict Case B/D/C Safety

v5.9.0-c does not change the permission model. It only tightens script evidence for browser address-bar navigation, Explorer local HTML opening, and safe third-party GUI App target resolution. Creating temporary test shortcuts and local HTML fixtures is setup evidence only; PASS actions must be real visible mouse/keyboard input and must not use ShellExecute, Start-Process, Invoke-Item, WebDriver, CDP, DOM mutation, UIA InvokePattern, or UIA ValuePattern as actions.

## v5.9.0-d Case D Explorer Locator Safety

v5.9.0-d does not change the permission model. It only tightens Case D Explorer content-area locator evidence. Creating the local HTML fixture and This PC shortcut remains setup only. PASS actions must be visible mouse/keyboard input through Explorer UI. Explorer address-bar path input, ShellExecute, Start-Process, Invoke-Item, direct file open, WebDriver, CDP, DOM mutation, UIA InvokePattern, and UIA ValuePattern remain invalid as PASS actions.

## v5.9.0-e HumanMode Pacing Safety

v5.9.0-e does not change the permission model. It only requires HumanMode mouse actions to be visible, ordered, and auditable. `desktop-click` and `desktop-double-click` must move the cursor in visible steps, verify target epsilon, dwell before click, then send real mouse input. Instant movement is not valid HumanMode PASS evidence.

HumanMode action results must expose backend/direct-launch/fallback flags and return `ok=false` with `error.code` on failure. Active protection stops remain unchanged and must not be bypassed by motion pacing, delays, scripts, browser automation, UIA InvokePattern, UIA ValuePattern, DOM actions, or direct file state changes.

## v5.9.1 Pre-v6 Handoff Safety

v5.9.1 does not change the permission model. It rechecks that ordinary development terms such as test, exam, assessment, quiz, problem, challenge, submit, mail, localhost, and local HTML are allowed for developer capability discovery, while active protection signals such as captcha, human verification, automation/script/bot detection, anti-cheat, active proctoring, lockdown browsers, protected desktop/UAC, and bypass requests still STOP.

