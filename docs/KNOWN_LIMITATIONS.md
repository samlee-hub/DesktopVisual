# Known Limitations

Current trusted version: `DesktopVisual 1.1.0` Public Release Permission Alignment, Agent Efficiency, and Release Tree Sync.

Current active development layer: `DesktopVisual 1.1.0 Public Release Permission Alignment, Agent Efficiency, and Release Tree Sync`.

## DesktopVisual 1.1.0 Public Permission And Efficiency Limits

`PUBLIC_DEFAULT` is no longer a disabled public profile. It allows ordinary visible desktop operation, third-party app workflows, browser/https pages, localhost pages, Explorer/file manager workflows, ordinary local file open, cross-window visible workflow, global desktop visible workflow, and validated absolute screen coordinate action.

The public profile still stops on real active protection or security interception: real exam/proctoring/lockdown browser, CAPTCHA/human verification, bot challenge, automation detected, script detected, credential/security handoff, UAC/protected desktop, and anti-cheat mechanisms. Broad content words such as test, exam, challenge, submit, or assessment are not STOP signals by themselves.

Compact output does not reduce evidence. Chat/report progress is compact by default, but full evidence remains in artifacts and failure output expands with error, evidence, and next repair.

## DesktopVisual 1.0.5 Capture/OCR Pipeline Limits

OCR is memory-frame-first in v1.0.5. The normal OCR path reads full-screen frame bytes from the frame registry and reports `ocr_source=memory_frame` or `memory_frame_crop`; it does not read the evidence PNG back from disk.

PNG evidence is still retained for audit. It is saved asynchronously by default and must be flushed before failure, BLOCKED, or final reports. A failed flush is `EVIDENCE_FLUSH_FAILED`, not PASS.

Foreground/window OCR crops from the full-screen frame. It does not make a partial screenshot the source-of-truth. If crop OCR fails, fallback uses full-screen OCR on the same frame.

The Codex CLI VLM provider currently still needs file path image input through `--image <png_path>`. DesktopVisual therefore generates a provider input PNG from the existing frame and marks it as a transport artifact. That artifact is not the OCR input path and is not a new screenshot.

VLM memory bytes/base64 transport is a future provider capability. v1.0.5 does not claim Codex CLI supports memory bytes.

## DesktopVisual 1.0.4 Visual Studio C++ Workflow Limits

v1.0.4 covers the Visual Studio C++ workflow only. PyCharm complex IDE workflow is not in this version.

The Visual Studio desktop icon or shortcut must exist. If VS cannot be opened by visible desktop icon double-click, the workflow is BLOCKED instead of using Start Menu, direct `devenv.exe`, ShellExecute, PowerShell launch, or backend `.sln` open.

`SingleTestProject` is expected under the local Visual Studio default user project location used during the visible creation test. The v1.0.4 acceptance fixture path is `C:\Users\15817\source\repos\SingleTestProject\SingleTestProject`.

Backend cleanup is allowed only after an unrecoverable wrong-project or polluted-project failure. Backend cleanup must not create projects, create source/header files, modify `.vcxproj`, build, run, or substitute for visible IDE work.

The test repository for this run is external to the DesktopVisual source tree: `E:\desktopvisualproject\testrepo`. It is not copied into the project root and is not modified as DesktopVisual source.

## DesktopVisual 1.0.3.1 VLM Limits

The legacy mock VLM commands are retired from normal Agent/Runtime use. They are legacy, deprecated, test-only fixtures that fail by default and require explicit opt-in only for historical selftests. They must not be used as normal VLM assist and must not be counted as real VLM success.

Before v1.0.4, real VLM candidates remain locate/assist evidence only. `vlm-assist-locate` and `vlm-candidate-validate` can accept a candidate for Runtime planning, but that is not click success, input success, action execution, or task success. Future complex IDE use must map image pixel coordinates to screen coordinates, lock the target window rect / hwnd / title / process, prove the point is inside that locked window, let Runtime execute the visible action, and verify the result afterward.

## DesktopVisual 1.0.3 VLM Runtime Bridge Limits

DesktopVisual 1.0.3 depends on the current local CLI/model/toolchain for real VLM support. The accepted provider is the tested Codex CLI path `codex exec <prompt> --image <file>`. Other models, CLIs, accounts, API keys, or environments are not claimed supported unless their capability probe returns available in that session.

VLM is an assistive perception layer only. It can identify visible text, icons, buttons, regions, uncertainty, and candidate bbox/point data from screenshot pixels. It cannot click, type, move the mouse, open programs, run commands, modify files, decide backend fallback, bypass safety policy, or replace Runtime verification.

In v1.0.3.1, real VLM candidate output remains locate/assist and not directly action. `candidate_accepted=true` means the candidate passed Runtime validation for planning; it does not mean click success, input success, action execution, or task completion. Before v1.0.4 can use a VLM candidate for complex IDE action, Runtime must perform coordinate mapping, target window lock, inside-window validation, visible action execution, and post-action verification.

VLM is not called every step. It is eligible only after UIA/OCR/template/image/visible perception or location ambiguity, after deterministic recovery has run or is not applicable, or after keyboard fallback leaves visual state unclear. It is not called for permission denial, active protection, missing target window, low-level input failure, command argument errors, backend fallback, or backend fallback failure.

If the provider is unavailable, times out, returns invalid JSON, returns low confidence, reports no target, or produces a rejected candidate, Runtime records that evidence and continues the v1.0.1 Runtime-only visible fallback policy. It must not fabricate VLM success.

Candidate acceptance depends on current screenshot/frame evidence. Missing image/evidence files, stale screenshot/frame id, out-of-bounds coordinates, semantic mismatch, unsupported coordinate space, or active-protection safety flags reject the candidate.

Complex IDE workflow automation remains v1.0.4 work. Full-screen Capture/OCR Performance Pipeline work, including memory-frame OCR, async PNG, tile hash cache, and OCR cache, is implemented in v1.0.5.

## DesktopVisual 1.0.2 Skill Contract Limits

DesktopVisual 1.0.2 hardens Skill, adapter, shared adapter rules, and usage references only. It does not add new Runtime behavior, connect a real VLM provider, add complex IDE project automation, modify release/public-dist trees, or package a release. DesktopVisual 1.1.0 later aligns `PUBLIC_DEFAULT` ordinary visible capabilities.

The Runtime remains a Windows visible-first desktop runtime, not a background script executor. Agents must use visible-first launch and fallback discipline when using DesktopVisual. A task can fail because the path was illegal even when the final application state appears correct.

Use `visible-app-launch` desktop-first for app, URL, local shortcut, `.lnk`, `.url`, and webpage shortcut launches. Start Menu visible search is a fallback, not the first choice. Backend launch, ShellExecute, direct file open, and background browser navigation are not default paths.

Fallback remains layered: visible UI path, visible keyboard fallback, backend fallback. Shortcut fallback requires at least two bounded visible attempts or strict surface-impossible evidence. Backend fallback additionally requires keyboard fallback failure and a non-convenience reason. `target_not_found`, `uia_not_found`, `ocr_not_found`, and `click_failed` alone are not surface-impossible evidence.

Developer permissions are intentionally broad in `D:\desktopvisual`: ordinary app, ordinary webpage, https, localhost, IDE, browser, file manager, mail page, communication page, coding practice page, test, exam, challenge, submit, and assessment keywords are not developer STOP conditions by themselves. Active protection or security interception still stops.

v1.0.2 does not enable real VLM automatic triggering. If Runtime reports VLM unavailable, mock-only, or not configured, agents must not invent VLM results. Real VLM provider gating is a future v1.0.3 target.

## DesktopVisual 1.0.0 Developer Baseline Limits

DesktopVisual 1.0.0 maps the internal v6.12.1 development line to a frozen developer baseline. Its accepted scope is visible-first Windows desktop automation runtime behavior: real mouse and keyboard execution, global DPI-aware screenshots, target window lock, coordinate mapping, foreground preempt/cache, operation timeline profiling, visible UI latency optimization, structured text input, and Python simple PyCharm current-main acceptance.

The accepted visible path excludes clipboard and backend file writes from PASS evidence.

The 1.0.0 baseline does not promise arbitrary complex IDE automated development, Visual Studio C++ multi-file project creation, Android Studio / Java / Kotlin complex project development, arbitrary web or complex app automation, or a fully generalized natural-language-to-mouse/keyboard planner.

Visual Studio C++ multi-file workflow support is deferred to v1.1+. Broader complex IDE visible workflows remain v1.x work. Natural-language-to-workflow planner hardening remains v2.x work.

This developer baseline does not sync `D:\desktopvisual-release`, does not sync `D:\desktopvisual-public-dist`, does not package a public release, and does not upload GitHub.

## v6.12.1 Visible UI Foundation Limits

v6.12.1 hardens core visible UI primitives but does not make every existing legacy command fully deterministic. The new foundation commands and updated `screenshot`, `desktop-click`, `desktop-hotkey`, and `desktop-type` paths expose target lock, coordinate mapping, foreground preempt, and global-frame evidence fields; older workflow wrappers may still need follow-up wiring before they can claim final PASS authority.

`visible-show-desktop` and `visible-window-switch` enforce the default visible operation order, but Windows taskbar grouping and Alt+Tab ordering are still environment-dependent. The command records fallback evidence and stops after the three-stage chain instead of continuing unbounded retries.

PyCharm support is a generic visible workflow policy wrapper over the new primitives. In this scope, backend project writes are forbidden, so a real PyCharm task cannot be converted to PASS unless it runs entirely through visible UI and verifies output from a global DPI-aware frame.

The 165Hz motion profile is best-effort because Windows scheduling, remote desktop, virtual machines, and display refresh can affect actual pacing. Runtime records actual frame timestamps and must not fake PASS when measured frame-rate evidence is below threshold.

This developer-tree update does not inspect `D:\desktopvisual-release` or `D:\desktopvisual-public-dist`, does not generate a public package, and does not upload GitHub.

## Post-v6 Developer Runtime UX Optimization Limits

Foreground preparation is a developer UX improvement, not a public-release permission policy. It can minimize or move the agent host window and activate the target, but Windows foreground restrictions may still prevent activation in some desktop states.

`fast-visible-ui` reduces pacing and retry costs for developer workflows while preserving visible user-level input. It is not a backend automation mode and does not bypass RuntimeContextGuard, safety manifest stops, or verifier-owned PASS requirements.

`pycharm-dev-demo` is restricted to the disposable safe project root `D:\testrepo\pycharm_sanity`. If the visible PyCharm surface is unavailable or not stable enough for deterministic input, it may use backend fallback only in that safe project and must report `backend_fallback_used=true` with the reason.

Command aliases are compatibility support. New agents should prefer canonical command names from `winagent.exe help` and should use `suggested_command` or `closest_matches` after failures.

## Post-v6 F12 Force Exit Limits

F12 force exit stops the current task only. It is not a process kill switch and must report `process_exit=false` with `STOP_USER_FORCE_EXIT_F12`.

The control relies on Runtime polling points in dispatch, waits, input movement, typing, clicking, scrolling, and related execution loops. Code that does not enter those Runtime-controlled loops may only observe F12 at the next available poll point.

This developer-tree change does not implement public-release permission narrowing, default/full_access selection, or an exam/test/quiz keyword denylist.

## v6.12.0 Developer RC Gate and Handoff Limits

v6.12.0 is a Developer RC metadata, integrity, and handoff gate. It does not implement new Explorer, Browser/Form, Communication, VLM, Template, or Memory behavior and does not change RuntimeSession, StepContract, CompiledPlanExecutor, verifier, or safety-intercept semantics.

Developer full access remains the default for this development tree. v6.12.0 does not add an exam/test/interview/contest/LeetCode/OJ/social/email/message keyword denylist, user-selectable permission mode UI, default limited-access mode, public-release permission policy, public-release package, or public-release repository cleanup.

Runtime must still stop and report on real third-party interception, CAPTCHA/human verification, credential handoff, account/security verification, active proctoring, lockdown browser, anti-cheat, anti-automation, and explicit security/risk verification. v6.12.0 does not bypass those mechanisms.

The release-hardening deferred ledger records public-release items as future work and does not make v6.12.0 a public release.

## v6.11.0 Workflow Template and Batch Limits

Workflow Template Learning is a structure extraction and validation layer only. It does not train models, tune prompts automatically, optimize workflows, decide execution paths, repair failures, choose locators, or trigger Runtime execution.

Candidate templates, rejected templates, and deprecated templates are not executable. Validated templates can instantiate StepContract JSON only through `StepContractValidator`; the resulting contracts still depend on RuntimeSession, RuntimeContextGuard, step-level verification, and evidence policies.

The template registry is local JSON plus audit JSONL. It is not a vector database, external database, network service, semantic retrieval engine, or credential store. Communication templates retain redacted references only and do not store full recipients, bodies, credentials, tokens, or verification codes.

Batch acceleration is limited to compile-only, validate-only, and serial mock-safe coordination in the main gate. It does not parallelize real UI, share concurrent RuntimeSession state, continue after verification failure, merge safety boundaries across workflows, or rerun old UI workflows.

v6.11.0 does not implement v6.12 RC gates, public-release permission narrowing, new Explorer/Browser/Communication/VLM runtime capabilities, or old UI workflow replay.

## v6.10.0 Experience Memory Limits

The v6.10.0 Experience Memory layer is an append-only evidence and attribution record layer. It does not plan, optimize, execute, retry, choose locators, change workflow behavior, or recover failed tasks.

Memory records are only as trustworthy as their evidence references. A record with missing evidence, missing source/trusted version, untrusted source flags, sensitive plaintext, Runtime execution influence fields, or `RAW_COMPLETED_UNVERIFIED` marked as success is blocked by the safety boundary.

Communication memory stores hashes/redacted references for recipient and subject-style fields and does not retain full message bodies or private chat content. This reduces audit detail by design.

Failure attribution normalization is a conservative classification layer. Unknown failure codes map to `UNKNOWN_FAILURE`, not success. The normalizer does not generate repair plans or automated suggestions.

The memory store is a local JSONL file plus JSON index. It is not a vector database, external database, network service, or semantic retrieval engine.

v6.10.0 does not implement v6.11 Workflow Template Learning, v6.12 RC gates, public-release permission narrowing, new UI workflows, or old UI workflow replay.

## v6.9.0 System Stabilization Limits

The v6.9.0 system stabilization layer is an evidence, artifact, session, and workflow boundary hardening layer. It does not prove new user-facing workflow capability and does not replay accepted Explorer, Browser/Form, Communication, VLM, PyCharm, QQ, YouTube, or other UI workflows.

Artifact classification is conservative. Final reports, evidence indexes, acceptance gate reports, runtime sessions, and unknown artifacts are not marked safe to delete. Archive recommendations are advisory unless a future explicit archive operation is approved.

Runtime session lifecycle reports infer references from evidence indexes and artifact paths. If a session source cannot be determined, the session is retained. A session marked unreferenced or stale is not proof that deleting it is safe.

Workflow boundary checks are source/evidence structure checks. They can catch missing components, runner-only patterns, and bypass markers, but they do not replace targeted replay when a future source change invalidates accepted behavior evidence.

v6.9.0 system stabilization does not implement Experience Memory, Workflow Templates, v6.12 RC gates, public-release permission narrowing, RuntimeSession semantic changes, StepContract semantic changes, CompiledPlanExecutor semantic changes, or VLM candidate execution boundary changes.

## v6.8.0 Browser/Form Workflow Limits

v6.8.0 Browser/Form workflows are accepted for fixture-safe local file pages, localhost pages, local-safe form fill/submit, long-scroll local forms, wrong-page recovery inside `allowed_url_prefix`, active-protection STOP, credential-required STOP, and ordinary external read-only diagnostics.

v6.8.0 does not accept real external form commit gates, mailbox/message/draft workflows, social platform automation, CAPTCHA solving, credential entry, DOM/JS/WebDriver/CDP/Playwright/Selenium automation, direct coordinate actions, or runner-faked form success evidence. Mail / Message / Draft Workflows are reserved for v6.9.0.

## v6.8.0-preflight Validation Consistency Limits

The v6.8.0 preflight validation consistency layer is an evidence integrity and regression-cost control mechanism only. It does not prove new Browser/Form workflow behavior and does not convert hash checks into execution PASS.

Evidence fingerprints can detect drift in recorded artifacts, but they cannot prove that the current desktop environment would still replay the old UI workflow. If related source changes, evidence hashes mismatch, final status/gate/evidence index conflicts, old BLOCKED history is lost, or trusted version rolls back, the skip policy requires targeted replay.

Accepted old Explorer/VLM/Runtime/Compiler/Session capabilities can use consistency checks for preflight validation. New v6.8 Browser/Form workflows must still be tested through real execution evidence when implemented.

## v6.7.0 Explorer Agent Workflow Limits

v6.7.0 Explorer Agent Workflows are accepted for local allowed-root Explorer workflows with staged evidence and verifier-owned PASS authority. The accepted scope covers the fixture-safe Explorer cases, destructive confirmation gate, allowed-root scope guard, wrong-folder recovery, context menu workflow, move-file, and scroll-and-locate workflows.

The accepted move workflow uses Explorer UI cut/paste or guarded keyboard fallback after mouse selection and focus verification. PowerShell file operations and direct file APIs are not accepted workflow actions.

The accepted scroll-and-locate workflow requires list-area focus, observable visible-item progress, target visibility/location evidence, and RuntimeContextGuard per iteration. Wheel event count alone is not accepted as scroll progress.

v6.7.0 does not add Browser/Form workflows, email/message/social workflows, new VLM capability, Experience Memory, Workflow Templates, public permission narrowing, or further v6.6/v6.2 optimization. Browser and Web Form Agent Workflows are reserved for v6.8.0.

## v6.6.0 VLM Candidate Handling Limits

v6.6.0 adds only Runtime-owned candidate handling after locator failure. It does not let VLM click, type, scroll, invoke Runtime commands, or provide direct coordinates for immediate execution.

VLM candidates are semantic hints. They must be observation-only, must require Runtime validation, and must be corroborated by Runtime evidence such as UIA, OCR, visible text, element summaries, expected context, viewport, freshness, uniqueness, and risk checks.

`vlm-assisted-locate` and `vlm-assisted-locate-dry-run` do not execute actions. `vlm-assisted-locate-and-click-local-safe` is limited to the local/mock TestWindow safety case and still requires RuntimeContextGuard, mouse-first evidence, and post-action verification.

The external provider hook remains a disabled placeholder. There is no real provider API key UI, mandatory real VLM API integration, Experience Memory, Workflow Template Learning, public-release permission narrowing, or broad real App/Web VLM candidate gate in v6.6.0.

Explorer Agent Workflows are deferred to v6.7.0.

## v6.5.0 VLM Observation Limits

v6.5.0 defines the VLM-assisted observation contract only. It does not call a real VLM provider, does not require API keys, does not add provider account UI, and does not upload screenshots or user data.

VLM results are observation evidence, not action contracts. `possible_targets` are approximate semantic candidates only; they must be `observation_only=true`, must require Runtime validation, and cannot be converted directly into click/type/scroll actions in v6.5.

`safe_for_direct_execution` is always false. VLM output cannot enter `StepContract`, `CompiledPlanExecutor`, `RuntimeSession`, or direct input paths. `vlm-observation-dry-run` writes request/result/validation/boundary evidence only and records `runtime_executed=false`.

Blocked contexts such as active protection or credential-required surfaces may produce observation summaries, but they do not enter the Runtime candidate pipeline and cannot produce executable suggestions.

The external provider hook is a disabled placeholder. It returns `PROVIDER_EXTERNAL_DISABLED` and is not a PASS dependency.

VLM-assisted unknown UI candidate handling is implemented in v6.6.0, still under Runtime validation and execution control.

## v6.4.0 Runtime Task Execution Limits

v6.4.0 executes compiled and validated StepContracts through the controlled local Runtime path. It is not a general natural-language executor and does not allow AgentPlanDraft or free text to bypass PlanCompiler and StepContractValidator.

`execute-local-safe` is intentionally bounded to local/localhost/Explorer/mock-safe workflows for this gate. It does not prove arbitrary external website automation, real account operations, CAPTCHA handling, anti-automation bypass, unfamiliar-screen semantic planning, or public-release safety.

Dry-run validates and adapts contracts but does not execute Runtime actions. A dry-run PASS only proves structure, validation, and session-step conversion with `runtime_executed=false`.

REAL_COMMIT and DESTRUCTIVE actions remain blocked without explicit confirmation evidence. ACTIVE_PROTECTION_BLOCKED and CREDENTIAL_REQUIRED_BLOCKED contracts are non-executable. Developer full access does not bypass these stops.

Recovery is local and policy-bounded. It may resume or replay only from safe checkpoints when the contract permits recovery; it does not bypass active protection, credentials, or failed verification.

v6.4.0 does not develop VLM, Experience Memory, Workflow Templates, public-release permission narrowing, v6.2 latency optimization, or new real external App/Web capability expansion.

## v6.3.0 PlanCompiler Limits

v6.3.0 compiles reviewed `AgentPlanDraft` JSON into v6.3 `StepContract` JSON and emits v6.2 session-compatible dry-run structured steps. It is not Runtime task execution.

`step-contract-dry-run` does not start Runtime sessions, does not call `runtime-session-dispatch`, and does not click, type, scroll, launch apps, open browser pages, or manipulate desktop state. The dry-run output is only structured JSON with `runtime_executed=false`.

The compiler is rule-based over reviewed plan fields. It does not perform natural-language task execution, VLM reasoning, unfamiliar-screen semantic planning, Experience Memory, Workflow Template Learning, or public-release permission narrowing.

High-level compiled actions such as `explorer_open_path` and `browser_open_page` are contract intent labels for the next execution stage. v6.3 can dry-run them into session-step-shaped JSON, but v6.4.0 is responsible for connecting compiled plans to actual Runtime task execution.

Developer full access is only represented as policy metadata inside the contract. It does not remove expected context, verification, recovery, stop, session, or evidence requirements, and it does not bypass active protection or credential-required stops.

## Screen Capture Evidence Boundary

PowerShell full-screen `CopyFromScreen` capture is the default visible-screen evidence method, but it only proves the current visible desktop pixels. If the target app is minimized, off-screen, covered by another window, hidden behind a widget/notification/overlay, or blocked by a protected desktop, the screenshot is not valid target evidence until the target is restored to the visible foreground and recaptured.

`winagent.exe screenshot --title ...` / `PrintWindow` and OCR-derived screenshots can miss custom-rendered or clipped surfaces. They remain diagnostic tools and may support evidence, but they must not overrule a conflicting PowerShell full-screen screenshot for visible UI state.

## v6.2.0 Persistent Runtime Session Limits

v6.2.0 improves repeated Runtime command latency by reusing a session, target hwnd binding, observe cache, locator cache, and structured dispatch. It is not a Planner, PlanCompiler, natural-language executor, VLM path, Experience Memory, Workflow Template learner, or public-release permission pass.

Persistent sessions are same-machine, current-process Runtime state. A session can expire, be closed, or become stale when its bound hwnd closes, hides, minimizes, changes process, changes title beyond the requested target, loses foreground/context, or fails RuntimeContextGuard. Stale sessions must stop; they are not a recovery or rollback mechanism.

Observe and locator caches are acceleration hints only. They cannot replace required verification, target uniqueness, viewport checks, stale-target checks, expected-context checks, or post-action reobserve when required. Any action marks observe/locator cache state as needing revalidation; stale locator reuse must stop or force relocate.

Latency numbers are current-machine evidence from controlled local fixtures. The accepted v6.2.0 comparison shows one-shot average 65 ms / p95 139 ms / 14 process restarts and persistent average 45 ms / p95 78 ms / 1 process restart. These are not cross-machine service-level guarantees.

The Browser Form workflow is a local Edge file mock under `D:\testrepo\testwindow`; it does not prove arbitrary external website automation, real account messaging, real mail sending, CAPTCHA handling, anti-automation bypass, hidden browser control, or unfamiliar-page semantic planning.

## v6.1.6 Accepted Scope Boundary

v6.1.6 closes the v6.1 series with a deliberately narrowed scope: Case1 QQ Mail fresh machine evidence PASS/frozen, bottom-layer StepCompletionGate PASS, and Case2 PyCharm visible UI execution closure. Case3/Case4, WeChat, TikTok, and the old integrated sequence are deferred and are not current gate blockers.

Case2 output closure uses a PowerShell full-screen CopyFromScreen screenshot to prove the visible PyCharm foreground and Run tool-window region. In the accepted closure, the screenshot does not itself show expanded console text; the output sequence and exit-code proof are recorded through paired current-run console text for the same run id. Future visible-output proof should prefer a PowerShell full-screen capture after the console body is expanded enough to show `DV616_SEQ`, `DV616_RUN_END`, and exit code text directly.

Deep self-drawn App UI testing is deferred to the VLM/visual candidate stage.

v6.1.6 does not implement Persistent Runtime, PlanCompiler, VLM, Experience Memory, broad language/IDE execution profiles, or generalized visual Run-icon targeting. These remain future work starting with v6.2.0 Persistent Runtime Session and Latency Gate.

## v6.1.6 Scope Reset Content1 Historical Limit

The historical v6.1.6 scope-reset content1 closure preserved Case1 QQ Mail fresh machine evidence PASS/frozen and implemented bottom-layer StepCompletionGate as a generic C++ runtime capability exposed through `winagent.exe step-completion-evaluate`.

That content1 result was not full v6.1.6 acceptance by itself. Full v6.1.6 acceptance now comes from the later Case2 PyCharm closure recorded in `artifacts/dev6.1.6_scope_reset_step_completion_closure/`.

StepCompletionGate proves step gating semantics for required content1 selftests, including generic failure modes and PyCharm editor/code/run gate contracts. It does not by itself prove full dynamic App/Web automation, full PyCharm workflow success, full ExecutionOutcomeClassifier coverage, Persistent Runtime, PlanCompiler, VLM, or Experience Memory.

`current_trusted_version` remained v6.1.5a after content1 only. After the Case2 closure, `current_trusted_version` advances to v6.1.6 and v6.2.0 may start.

## v6.1.5a Mouse-First Supplement Limits

v6.1.5a is a supplement to accepted v6.1.5. It proves visible mouse-first interaction evidence for selected desktop/browser/local mock workflows and does not redo the v6.1.5 keyboard-capable diagnostic scope.

The accepted scope is locate -> mouse move -> click -> focus/context verification for visible targets, with keyboard use allowed only for text entry or explicitly recorded auxiliary selection after mouse focus. Keyboard-only launch, keyboard-only address focus, Tab focus chains, Enter-only search, backend page opens, and unrecorded fixed coordinates are not accepted as mouse-first PASS evidence.

The real web portion is intentionally narrow: it proves current desktop/Chrome/UIA conditions can mouse-click a search box, mouse-click a search button, and mouse-click a visible result/link. It is not the full Dynamic App/Web Developer FULL_ACCESS Automation RC. Real message sending, email sending, real code submission, broad exam/test/practice workflows, and broader app/web automation remain v6.1.6 scope.

External browser UIA exposure, search result layout, desktop icon visibility, display scaling, foreground rules, and local browser state can vary. A missing visible target, failed focus verification, fallback-only path, wrong-field input, wrong-context continuation, or unmarked fixed coordinate must block mouse-first PASS instead of being silently accepted.

v6.1.5a does not enter v6.2 and does not develop Persistent Runtime Session, PlanCompiler, VLM, or Experience Memory.

## v6.1.4 Dynamic App/Web Limits

v6.1.4 is accepted only for Runtime Guard and Browser Baseline Stabilization before v6.1.5. It does not develop Persistent Runtime Session, PlanDraft to StepContract Compiler, Runtime natural-language execution, VLM Provider integration, real VLM calls, Experience Memory, Workflow Template behavior, public release permission narrowing, or developer permission direction changes.

The accepted scope is Runtime-level context guard, `browser-open-url-human`, conservative browser surface normalization, v6.1.2 baseline replay, v6.1.3 scroll gate replay, and v6.1.4 runtime guard gate. It is not a PASS for PyCharm, WeChat, QQ Mail, real Internet pages, or real account workflows.

The deferred dynamic diagnostic cases depend on visible desktop shortcuts, a safe PyCharm test project, logged-in WeChat, logged-in QQ Mail, and no login/security/human-verification blockers. If any required environment is absent in v6.1.5 diagnostics, the result must be diagnostic failure or environment failure rather than a blocker for this accepted v6.1.4 runtime stabilization.

F12 emergency stop is configured in `config\safety.conf` and enforced by existing HumanMode input checks plus the v6.1.4 runner. If F12 is pressed, the run is USER_INTERRUPTION / EMERGENCY_STOP and cannot be PASS.

The earlier v6.1.4 dynamic App/Web rerun remains historical blocked evidence. The accepted v6.1.4 runtime stabilization does not reuse that dynamic evidence as PASS. PyCharm, WeChat, QQ Mail, and real Internet App/Web workflows remain deferred to v6.1.5 diagnostics and later acceptance work.

The v6.1.4 runner is intentionally bounded. A command step that exceeds 60 seconds, a case that exceeds its configured limit, a global run over 45 minutes, or a 60 second no-progress condition must block the stage and leave partial artifacts rather than silently continuing.

WeChat and QQ Mail cases intentionally do not add a send-confirmation popup, because an extra modal can stale the page and change action continuity. The replacement safety requirement is strict target/content/window/page verification before send. WeChat is limited to `文件传输助手`; QQ Mail is limited to `https://mail.qq.com` and `1581782307@qq.com`.

## v6.1.3 Mouse Wheel Scroll Limits

v6.1.3 is a real mouse wheel input and scroll-and-locate repair version before v6.2. It does not develop Persistent Runtime Session, PlanDraft to StepContract Compiler, Runtime natural-language execution, VLM Provider integration, real VLM calls, Experience Memory, Workflow Template behavior, public release permission narrowing, or developer permission direction changes.

Strict scroll PASS is intentionally narrow. It proves `SendInput` plus `MOUSEEVENTF_WHEEL` can move visible content and that `scroll-and-locate` can find initially invisible targets on controlled local long-page, mock contact-list, and Explorer-list fixtures. It does not prove arbitrary app semantic understanding, hidden virtualized-list support in every application, CAPTCHA or anti-automation bypass, protected desktop behavior, or unfamiliar-screen autonomy.

If the visible Windows desktop, browser, Explorer, UIA, OCR, screenshot capture, or input permission environment cannot produce real wheel evidence, the result is BLOCKED or SKIP_ENVIRONMENT_BLOCKING, not PASS. v6.2 cannot start without required real wheel evidence and fresh v6.1.2 baseline replay.

## v6.1.2 Real UI Baseline Gate Limits

v6.1.2 is a real UI baseline revalidation gate before v6.2, not a StepContract Compiler version. It does not develop new Agent Planner functionality, Runtime natural-language execution, VLM Provider integration, real VLM calls, Experience Memory, Workflow Template behavior, public release permission narrowing, or developer permission direction changes.

The required PASS scope is intentionally narrow: real Explorer navigation to `D:\testrepo\testwindow\desktopvisual_mail_mock.html`, real Browser Mail Mock form fill/send from `file://D:/testrepo/testwindow/desktopvisual_mail_mock.html`, one repeat browser run, and required regressions. It does not prove arbitrary webpage semantic understanding, real email sending, account messaging, CAPTCHA handling, anti-automation bypass, protected desktop behavior, or unfamiliar-screen autonomy.

If Explorer or browser real UI cannot run in the current interactive Windows desktop, the result is BLOCKED or SKIP_ENVIRONMENT_BLOCKING, not PASS. v6.2 cannot start without required real UI evidence.

## v6.1.1 Acceptance Repair Limits

v6.1.1 is an acceptance repair and evidence integrity stage for v6.1, not v6.2. v6.1.0 remains a BLOCKED attempt until current v6.1.1 raw tests, verified JSON, regression logs, evidence pointer checks, and acceptance gate output prove otherwise.

HumanMode pacing acceptance depends on fresh current-stage raw logs. Old v6.1.0 blocked evidence can support triage only; it cannot be reused as v6.1.1 PASS evidence. Missing required logs, missing evidence pointers, missing raw output, missing verifier output, SKIP, NOT_RUN, or diagnostic-only evidence blocks acceptance.

`v6_1_1_humanmode_regression_triage.ps1` can classify available evidence and request a real UI rerun, but it cannot prove HumanMode PASS without the required HumanMode pacing regression runs. `v6_1_1_evidence_acceptance_gate.ps1` is the independent acceptance authority and may keep `current_trusted_version` at v6.0.0 when any required gate fails.

## v6.1.0 Task Intent Planner Limits

v6.1.0 implements only minimal `TaskIntent` parsing and non-executable `AgentPlanDraft` generation. It is not a full Planner and does not execute desktop actions.

`AgentPlanDraft` is not a `StepContract`. It must remain `is_executable=false`, `compile_required=true`, and `executor=runtime`; future compilation to executable Runtime `StepContract` is reserved for v6.3.0 after the accepted v6.2.0 Persistent Runtime baseline.

VLM-Assisted Mode is still assistive only. v6.1.0 does not call a real VLM provider, does not store provider API keys, and does not add provider account UI.

The intent parser is intentionally minimal and rule-based. It covers the v6.1.0 seed intents (`explorer_open_path`, `explorer_open_file`, `explorer_delete_file`, `browser_open_page`, `browser_fill_form`, `local_mock_mail_fill`, and `unknown`) but does not claim arbitrary natural-language understanding, unfamiliar-screen semantic generalization, task repair, Experience Memory, Failure Attribution, or batch task acceleration.

HumanMode and active-protection STOP behavior are unchanged. Active-protection bypass semantics classify as blocked at the planner boundary and must not be routed into execution.

## v6.0.0 Agent Boundary Limits

v6.0.0 establishes validation boundaries only. It does not implement a full Planner, real VLM provider calls, Provider API key UI/account system, Experience Memory, batch task acceleration, public release normalization, HumanMode changes, or active-protection STOP changes.

VLM-Assisted Mode is not a provider integration. It is a validated mode label for future planning assistance. VLM/LLM/Agent output may propose or explain, but it is not an executor. Runtime remains the only action executor.

AgentPlan validation confirms minimal structure and rejects direct non-Runtime execution, malformed JSON, missing fields, empty steps, and JS/DOM/WebDriver/CDP/UIA Invoke/Value HumanMode actions. It does not produce a complete task plan and does not prove arbitrary unfamiliar-screen autonomy.

## v6 Preparation Runtime Latency Known Limit

Runtime correctness is prioritized over latency. The current Runtime is correctness-first and not latency-optimized.

HumanMode must not be weakened for speed. Repeated CLI invocation latency is known and accepted for the current v5.10.2 handoff baseline.

Future optimization directions include persistent Runtime session, task-level batching, hwnd-targeted commands, observe/UIA/screenshot cache, locator candidate cache, reduced process roundtrips, act-and-verify primitives, context-menu primitives, and better scheduling.

This latency limit is not a v6.0 blocker unless it causes task failure, timeout, UI state expiration, VLM cost explosion, or unacceptable task runtime for v6 workflows.

## v5.10.2 REBUILT TaskRuntime Gate Limits

Rebuilt v5.10.2 remains a v5 real TaskRuntime integration and final gate stage, not v6. It does not add VLM, an Agent Planner, arbitrary webpage semantic understanding, public release permission narrowing, or a developer permission direction change.

The real TaskRuntime browser flow is a controlled localhost mock mail scenario bound to `127.0.0.1`. It is not proof of arbitrary external web automation, real account messaging, CAPTCHA handling, anti-automation bypass, or unfamiliar-screen semantic planning. PASS requires independent verifier and final gate evidence.

## v5.10.1 REBUILT Real UI Adaptive Case Limits

Rebuilt v5.10.1 remains a v5 real UI evidence rerun, not v6. It does not add VLM, an Agent Planner, arbitrary webpage semantic understanding, public release permission narrowing, or a developer permission direction change.

Case D/E/F PASS depends on a visible interactive Windows desktop, stable Explorer and Chrome/Edge UIA/OCR exposure, normal input permissions, available D: drive fixtures, local browser file handling, localhost binding to `127.0.0.1`, and screenshot/cursor evidence. If any target rect is missing, the cursor is outside the current target rect before click, a Send button candidate is ambiguous, a field cannot be verified, a window relocation invalidates coordinates, or raw command evidence is incomplete, the verifier must return FAIL or SKIP_ENVIRONMENT instead of PASS.

The old invalidated v5.10.1/v5.10.2 artifacts remain non-evidence. Synthetic evidence, placeholder screenshots, hardcoded hwnd/rect, runner self-PASS, backend/direct launch, JS/DOM/WebDriver/CDP, and UIA InvokePattern/ValuePattern actions are invalid PASS evidence.

## v5.10.1/v5.10.2 Invalidated Limits

v5.10.1 and v5.10.2 are invalidated. Their evidence cannot be used to claim Case D/E/F PASS, TaskRuntime browser-flow PASS, or v6 readiness.

Current known limits are narrowed by rebuilt v5.10.1 and v5.10.2 evidence: real Case D/E/F and one real TaskRuntime localhost browser form flow can be counted only from their independent verifier reports. Synthetic evidence, placeholder screenshots, hardcoded rectangles, and simulated PASS output remain invalid evidence.

## v5.10.0 Adaptive HumanMode Control Loop Limits

v5.10.0 remains a v5 Runtime control-loop core. It is not v6, not a VLM provider pass, not an Agent Planner, not a public release permission narrowing pass, and not a complete Explorer or browser-form case completion claim.

The adaptive loop improves the foundation from stale coordinate scripts to current observe/locate/validate/action/verify/retry behavior. It still depends on available UIA/OCR/ElementGraph or deterministic local mock geometry, stable foreground windows, normal Windows input permission, visible target rects, and correct coordinate mapping. If a target rect is missing, offscreen, in a forbidden region, stale, ambiguous, low confidence, or belongs to the wrong hwnd, the loop stops or retries within budget instead of guessing.

The core does not use VLM and does not perform semantic generalization over arbitrary unfamiliar screens. v6 remains the future semantic Agent boundary. Developer mode remains `DEVELOPER_CAPABILITY_DISCOVERY`: ordinary Chrome/Edge, Explorer, D: drive, local HTML, localhost, ordinary external pages, ordinary apps, forms, and ordinary test/exam/assessment/challenge/problem/submit/mail pages are not blocked by content words alone. Concrete active protection signals still STOP.

## v5.9.3 Explorer Mouse Target Strictness Limits

v5.9.3 is a v5 Case D strictness fix only. It does not enter v6, add VLM, develop an Agent Planner, narrow public release permissions, change developer permission direction, fix Case E/F, or integrate TaskRuntime HumanMode browser flow.

`STRICT_MOUSE_TARGET_HUMANMODE_PASS` depends on the current machine exposing reliable Explorer/Desktop item rects through UIA/OCR/selection evidence, a visible interactive desktop, stable display scaling, and a visible D: drive path. If any path level lacks a target rect, if selected item rect is missing after incremental search, if the cursor is not inside the target rect before click, or if Enter/default selection/backend open is used, the result is not strict PASS. v5.9.0-d and v5.9.1 Case D evidence can remain useful locator or handoff context, but it is not strict mouse-target evidence.

## v5.9.2 Active Protection STOP Limits

v5.9.2 is a v5 hotfix for active-protection STOP classification. It is not v6, not a VLM provider pass, not an Agent Planner pass, not a public release permission narrowing pass, and not a HumanMode locator fix.

Developer mode still allows ordinary browser/app/Explorer/local HTML/localhost/ordinary form exploration. Words such as test, exam, assessment, quiz, problem, challenge, mail, submit, hiring, recruitment, coding, and login are not blocked by themselves. The runtime stops only when concrete protection signals appear, such as CAPTCHA / human verification, bot challenge, automation or script detection, anti-cheat process/service names, lockdown or secure exam browsers, active proctoring, screen monitoring protection, or explicit bypass requests.

## v5.8.7 Pre-v6 Runtime Limitations

v5.x is an internal engineering stage number for the Task-Level Desktop Execution Runtime. v5.8.7 is a pre-v6 hardening and revalidation pass. v6 has not started in this tree. Before public release, a later Version Normalization Pass must map internal v5.x stage numbers to `0.x.x` prerelease versions before any formal `1.0.0` stable release, and a Release Normalization Pass must prepare a separate public release tree.

v5 can execute, verify, recover, confirm, audit, template-bind, handle controlled file workflows, run task-level dogfood, and expose task APIs through CLI/service for known App Profiles and controlled local tasks. It does not depend on VLM. It is not a complete Agent. It does not promise unfamiliar-screen semantic generalization, real account automation, or real high-risk external operations. Real exam, hiring assessment, certification, proctored workflow, payment, captcha, anti-cheat, game automation, credential/security challenge, phishing, bulk harassment, unconfirmed external send, and sensitive exfiltration workflows are blocked or stopped.

File picker and attachment flows remain controlled local/mock workflows and still need real product-grade UX, app-specific robustness, and public-release safety review before any production claim. Service protocol v1 remains a local runtime protocol and still needs v6 provider/auth/product-layer architecture before external provider or product API claims.

DesktopVisual v3.0.1 extends the v1.x command baseline with Case v2, Windows OCR, named-pipe service mode, dogfood scripts, task orchestration, and local Operator Motion Profile support. These capabilities are bounded and environment-dependent.

1. WinDesktopAgent can reliably control only normal user-permission windows.
2. Administrator windows and elevated processes are not supported.
3. Protected desktops, protected games, and security-sensitive software are not supported.
4. OCR uses Windows built-in WinRT OCR when available. If the OCR runtime or user-profile language support is unavailable, OCR commands return `OCR_UNAVAILABLE` or `OCR_LANGUAGE_UNAVAILABLE`.
5. UI Automation tree, find, click, and type are implemented for normal user-permission windows.
6. Image/template matching is implemented only for small uncompressed BMP templates and is not suitable for dynamic complex scenes.
7. Task recovery is limited to explicit, bounded strategies. It is not general autonomous recovery.
8. The platform is intended for authorized test windows and developer GUI verification.
9. The dogfood matrix is a bounded confidence check, not a guarantee that arbitrary Windows software is controllable.
10. The public GitHub baseline does not include local historical `artifacts`, build outputs, screenshots, browser profiles, caches, or release archives. Users must build locally and generate their own artifacts.
11. Operator Motion Profile quality depends on local sample count, direction coverage, distance coverage, display scaling, and pointing device behavior. Synthetic selftest samples verify the pipeline but do not represent a real user's movement.
12. `operator-human` is not a detection-bypass feature and does not expand the safety boundary. It still requires authorized windows, focus verification, exact final coordinates, and F12 interruption.
13. A `source=human` operator motion profile is local to the current device context. DPI, monitor layout, pointer speed, mouse hardware, and input settings can change how representative the profile is.
14. Synthetic and sample profiles are test artifacts only. They prove the calibration/synthesis path works, but they do not represent a local human operator.
15. Adapter wrappers are host-specific instructions around the same CLI. They do not expand DesktopVisual permissions or bypass Windows foreground input limits.
16. Benchmark evidence is task-scoped. A PASS proves the listed benchmark behavior on the current machine; it does not prove arbitrary Windows software control. SKIPPED is not PASS.
17. Safety Manifest decisions are policy checks, not OS-level sandboxing. They make DesktopVisual's boundary machine-readable and auditable, but they do not grant permission to control protected desktops, elevated windows, credential prompts, payment flows, captcha flows, or anti-cheat protected software.
18. `policy-check` and `consent-check` are dry-run checks. They do not replace the per-action focus verification and SafetyPolicy checks performed by input commands.
19. `automation_id` and `class_name` selectors depend on the target application exposing stable UI Automation metadata. Missing metadata returns `LOCATOR_NOT_FOUND`; DesktopVisual does not infer coordinates.
20. `class_name` is an auxiliary UIA filter and should be combined with name, role/type, target process, or window title context.
21. `relative:` and `near_text:` selectors are first-stage geometry filters over UIA elements. They do not provide complex visual layout understanding and still require explicit `nth` when multiple candidates remain.
22. `chain:` fallback tries selectors in order and records failures, but it does not relax safety policy, broaden target windows, or choose ambiguous results.
23. WindowSession DPI and monitor data are diagnostic metadata from Windows APIs. They help audit coordinate transforms but do not guarantee that every custom renderer or mixed-DPI application exposes stable UIA geometry.
24. WindowSession foreground confirmation still depends on Windows foreground rules. If another process, secure desktop, UAC prompt, full-screen app, or protected environment blocks focus, DesktopVisual returns a focus/window error rather than forcing background control.
25. Title-change detection is conservative. TaskRunner stops when the previously selected hwnd no longer matches the requested title; callers should re-observe and supply a stable title/process pair.
26. Task templates are deterministic step expanders, not autonomous planners. They cannot infer missing selectors, launch arbitrary executables, browse remote URLs, or bypass target-window safety.
27. Template parameter substitution is intentionally simple and supports explicit string placeholders in template step JSON. Complex loops, conditional branches, and arbitrary nested data transforms are out of scope for v3.3.0.
28. `open_app`, `open_local_html`, and `run_local_test_page` templates confirm or interact with already authorized windows/pages. They do not grant permission to start arbitrary apps or access remote content.
29. FULL_ACCESS is a permission gate and audit mechanism, not a protected OS sandbox. It can relax DEFAULT title/process/action policy decisions only after a temporary session is unlocked.
30. FULL_ACCESS sessions are local artifacts with TTL and scope. They are not encrypted secrets and should be treated as local runtime state.
31. FULL_ACCESS does not support administrator windows, UAC, protected desktops, credential prompts, captcha flows, anti-cheat protected software.
32. Service mode can use an already unlocked FULL_ACCESS session when the request includes its session id, but service mode cannot unlock FULL_ACCESS by itself.
33. `unlock-full-access` requires a real local interactive console and exact phrase confirmation. Non-interactive CI can verify refusal paths but cannot create a FULL_ACCESS session without a human at the terminal.
34. `launch-app` is a visible normal-user launch helper, not a hidden app controller. It requires a unique visible target window after launch and may return `WINDOW_NOT_VISIBLE`, `WINDOW_NOT_UNIQUE`, or `WINDOW_SPAWN_LOOP` in noisy desktop environments.
35. `browser-nav` is a visible browser navigation helper, not a hidden browser automation engine. It can open or simulate URLs and record basic navigation results, but it does not provide DOM extraction, login automation, payment confirmation, captcha solving, anti-bot bypass, or guaranteed browser control across all browser vendors.
36. v3.3.5 form semantics use deterministic local HTML/DOM-like hints for selftests and task reports. UIA/OCR/relative-locator form fusion is represented in the abstraction but remains limited.
37. v3.3.5 does not implement communication actions; those remain later v3.3.x stages.
38. v3.3.6 Decision Engine decisions read deterministic local HTML/DOM-like hints. It chooses one action for one resolved control and is not an autonomous planner; it does not generate goals, infer missing selectors, browse remote URLs, or unlock FULL_ACCESS.
39. v3.3.6 decision tasks require the `content_decision` capability. DEFAULT denies them with `SAFETY_POLICY_DENIED`; FULL_ACCESS requires a valid unlocked session id created by local interactive confirmation.
40. v3.3.6 `decision-eval` is a dry-run decision check. It does not click, type, focus, or inspect a live window and does not replace the per-action focus and SafetyPolicy checks performed during `run-task` execution.
41. v3.3.6 instruction-injection detection is a conservative deny/ignore filter over page text. It flags and ignores recognized override phrases so content cannot change the user goal; it is not a general adversarial-content classifier.
42. v3.3.7 checkpoints are observable audit anchors, not rollback. They cannot undo sent messages, submitted forms, browser-side state, remote service changes, or external application changes.
43. v3.3.7 loop guard detection depends on task-level action keys, URLs, window-open markers, and observed summaries. It is conservative and may stop a task that is technically recoverable so the user can inspect the latest checkpoint.
44. v3.3.8 communication actions are task-runtime records over local simulated targets in selftests. Real app/browser send flows still depend on existing visible-window control and FULL_ACCESS boundaries.
45. v3.3.8 supports one explicit target per communication step. Group/multi-target send requires future reviewed semantics and currently stops with `USER_TAKEOVER_REQUIRED`.
46. v3.3.8 records content summaries and hashes, not full sensitive content. A poor caller-supplied summary may be less useful for audit than a carefully reviewed one.
47. v3.3.9 coding workflows read deterministic local HTML/DOM-like OJ fixtures. `coding-eval` does not execute code, browse remote URLs, or inspect a live browser.
48. v3.3.9 coding task steps require the `content_decision` capability. DEFAULT denies them with `SAFETY_POLICY_DENIED`; FULL_ACCESS requires a valid unlocked session id.
49. v3.3.9 records code summaries or `code_path`, not full code text, in task reports.
50. v3.3.9/v3.3.10 does not hard-stop solely on exam/proctored/online-assessment/hiring-test/certification/rated-contest keywords in the local development runtime, because those categories were explicitly allowed in the stage 9 requirements. Public releases must add explicit permission restrictions for these categories before exposing them outside controlled local development.
51. v3.3.9 does not support high-frequency batch submission, problem-set scraping, paid-limit bypass, captcha bypass, or anti-automation bypass.
52. v3.3.10 Full Access benchmark results are reproducible local evidence, not certification that arbitrary third-party software or public websites will be controllable.
53. v3.3.10 marks non-interactive FULL_ACCESS unlock as SKIPPED by design; only a real local console can create a FULL_ACCESS session.
54. v3.3.10 benchmark scenarios use safe local fixtures and deterministic simulations for communication, coding, form, decision, and web workflows.
55. v3.3.10 evidence packs intentionally exclude real account data, real communications, browser profiles, raw motion data, build outputs, and sensitive logs.
56. Assessment, hiring, certification, and rated-contest workflow support remains policy-incomplete for public distribution until a dedicated permission model is added.
57. v3.4.0 Recovery Strategy Engine is finite and configured for known error classes only. It is not a general planner and does not infer new goals, invent selectors, choose ambiguous targets, or broaden window scope.
58. `SAFETY_POLICY_DENIED` is not recoverable. Any report record for that error must show `stop_immediately` with no recovery attempt.
59. OCR fallback in recovery depends on Windows OCR availability and a text probe derived from the original selector or task text; it may stop without recovery when no reliable text probe exists.
60. v3.5.0 Service Protocol v1.0 stabilizes the local response envelope but does not change the named-pipe transport into a remote API or security sandbox.
61. Service mode cannot unlock FULL_ACCESS or provide interactive confirmation. Callers must create FULL_ACCESS sessions locally through the CLI before passing a session id.
62. `/health-check` verifies service responsiveness and session counters only; it is not a benchmark or proof of desktop-control capability.
63. v3.6.0 dogfood covers only the declared local developer-tool scenarios. PASS does not prove arbitrary app control, and SKIPPED is not PASS.
64. Local HTML dogfood is a generated fixture for form semantics; it is not evidence of external website automation.
65. PowerShell dogfood is limited to local non-admin read-only/test output under artifacts and does not authorize arbitrary shell execution.
66. v3.7.0 is a release-candidate consolidation pass. It does not implement v4 Hybrid Screen Perception Engine, general visual reasoning, or arbitrary custom-rendered UI understanding.
67. `D:\desktopvisual` is the broad local development/evaluation tree and must not be submitted as the public release project. Public release must be prepared separately under `D:\desktopvisual-release` with restricted permissions for exam, interview assessment, hiring test, certification, rated-contest, proctored, and similar workflows.
68. v4.1.0 adds `observe2` provider-ready perception reports, not full visual intelligence. It does not run OmniParser, YOLO, UGround, VLM, GPU, Python, ONNX, or cloud model pipelines.
69. v4.1.0 image-template candidates are visual-only and unresolved by default. They can be inspected in `ElementGraph` and `LocatorCandidate` output, but `act` blocks `visual:` unresolved selectors with `ACTION_BLOCKED_SEMANTIC_UNRESOLVED`.
70. `screen_delta` in v4.1.0 reports degraded initial-frame status only; persistent cross-call perception cache and rich delta fusion remain future work.
71. v4.2.0 `observe-loop` is an event stream, not a complete task state machine. It does not perform clicks, typing, task planning, cross-app autonomy, or VLM monitoring.
72. v4.2.0 changed-region screenshots are artifact evidence tied to changed rounds; they are not a full computer-vision segmentation pipeline.
73. `text_changed`, loading, error, success, and dialog events depend on available Windows OCR/UIA signals and conservative heuristics. Missing OCR/UIA support can reduce event richness without making the loop unsafe.
74. `observe-loop` stop-file support is local file based. Ctrl+C process interruption is supported by the console, but no remote unattended stop service is added in v4.2.0.
75. v4.3.0 latency benchmark results are current-machine evidence only. They are not cross-machine SLAs and must not be used as uncontrolled claims against other tools.
76. `element_graph_build_ms` is measured through the graph-producing `observe2` command because an internal graph-only timer is not exposed in v4.3.0.
77. `act_to_verify_latency_ms` uses a safe UIA click followed by UIA verification in TestWindow. It is evidence for the local action-verify path, not a guarantee for arbitrary applications.
78. v4.4.0 Dynamic UI Recovery is not a full v5 task state machine. It produces finite recovery routes and router decisions, but it does not plan cross-app workflows.
79. `dynamic-ui-recovery` local HTML fixtures are deterministic safety tests, not evidence of real public website automation.
80. Dialog classification in v4.4.0 is conservative. Dialogs do not authorize underlay clicks and may require user confirmation.
81. Unknown scene state is not considered safe to auto-click. Blocked scene state stops immediately and must not be routed to VLM for bypass.
82. v4.5.0 App Profiles are adapter metadata only. They can provide common locators, ROIs, and strategy hints, but they cannot grant permissions, relax Safety Manifest stops, or bypass visual-only unresolved candidate blocking.
83. Built-in v4.5.0 profiles are local and safe fixtures or normal local app adapters. They are not real Gmail, Outlook, real account, public assessment, hiring test, certification, proctored, rated-contest, or production communication profiles.
84. Profile JSON validation in v4.5.0 is a lightweight runtime check for required fields and common locators, not a full standards-compliant JSON Schema engine.
85. v4.6.0 visual dogfood is bounded evidence for local developer workflow fixtures only. PASS does not prove arbitrary app control or generalized visual understanding.
86. v4.6.0 `local_mail_mock` verifies only mock upload completion and mock sent-state detection. It does not send email, access real accounts, or validate production mail clients.
87. v4.6.0 `local_problem_page_run_and_read_result` is a development benchmark fixture, not real exam, interview assessment, hiring test, certification, proctored, or rated-contest automation.
88. v4.6.0 Notepad dogfood skips if an existing Notepad process is present to avoid typing into or closing a user session.
89. v4.7.0 is a release-candidate consolidation pass. It does not add a complete v5 task state machine, real VLM integration, model weights, GPU requirements, or real-account benchmarks.
90. v4.x Hybrid Screen Perception Runtime produces structured candidates, events, routes, and evidence. It does not fully understand arbitrary screens, and ambiguous or unresolved semantic targets must stop or require escalation rather than click.
91. Public release preparation must remain separate from `D:\desktopvisual`; `D:\desktopvisual-release` must exclude local developer broad permissions, model weights, browser profiles, large generated artifacts, private paths, and unrestricted exam/assessment permissions.

## v3.0.1 Motion Profile Findings

1. Fewer than 12 valid raw samples cannot generate a profile.
2. 12/32/64 valid samples are classified as `low`, `usable`, and `good`; low-quality profiles may look less natural.
3. Profiles store aggregate statistics, not complete raw traces, but raw samples under `artifacts\motion_profile\raw` may reveal local cursor behavior and should be treated as local artifacts.
4. A profile generated on one display/DPI/mouse setup may not match another setup.
5. Motion synthesis preserves final target accuracy, so the last segment may include a visible endpoint correction when samples are sparse or noisy.

## v1.0.0 Release Candidate Findings

1. The safety whitelist uses window titles and executable names. It is not a replacement for OS-level permission controls.
2. Window titles can change with language, document state, and application state, so allowed titles must be configured deliberately.
3. The emergency stop key is checked during DesktopVisual-driven input loops; it cannot interrupt external application hangs or operating-system protected desktops.
4. Administrator windows, elevated processes, protected environments, and security-control bypass scenarios are unsupported.
5. Absolute full-screen clicking remains unavailable by design.

## v0.1.5 Dogfood Findings

1. Real application window titles can vary by system language.
2. Real application window position and DPI can affect coordinate clicks.
3. Without UI Automation, WinDesktopAgent can only rely on coordinates and is not suitable for complex real applications.
4. Without OCR, WinDesktopAgent cannot automatically locate targets from screen text.
5. The current dogfood only verifies the real input and report loop against a real Windows window.

## v2.0 OCR Findings

1. Windows native OCR requires a stable WinRT OCR image pipeline and installed OCR language support.
2. UI Automation should be preferred over OCR whenever a control tree is available.
3. OCR is intended only as a supplemental locator for authorized test windows, self-drawn UI, or windows without accessible controls.
4. OCR must not be used for security-control bypass, credential extraction, or unauthorized workflow automation.
5. OCR accuracy is inherently dependent on font, language, DPI, contrast, and window rendering.
6. OCR bounding boxes are reported in window-bitmap coordinates; click paths convert them to target-window client coordinates before input.

## v3.6.0 Dogfood Findings

1. Dogfood tasks must declare safety boundary, expected result, and SKIPPED condition.
2. Dogfood covers Notepad, Calculator, Explorer under artifacts, local HTML, local PowerShell read-only/test output, and VS Code when installed.
3. Dogfood must not access external web, real accounts, browser profiles, payments, passwords, captcha, social apps, games, anti-cheat, UAC, or administrator windows.
4. Dogfood reports write `artifacts\dogfood\dogfood_report.md` and `dogfood_summary.json`; the legacy `dogfood_matrix_report.md` remains a compatibility copy.
5. A PASS is bounded evidence for one scripted scenario, not a general desktop-control guarantee.

## v2.1 Dogfood Findings

1. Dogfood results are environment-dependent. Missing Edge, VS Code, OCR, UIA, or app-specific focus behavior may produce `SKIPPED`.
2. A PASS only covers the scripted workflow for that application. It does not prove general automation support for every dialog or custom UI in that app.
3. Dogfood scripts operate only under `D:\desktopvisual\artifacts\dogfood` and should skip rather than interact with pre-existing user windows.
4. Browser dogfood opens a generated local HTML file and does not access external websites, logins, or user browser data.
5. Explorer dogfood verifies filesystem effects only in its temporary artifacts directory and cleans that directory after the run.

## v0.3.3 Image Template Findings

1. Template matching supports uncompressed 24-bit and 32-bit BMP only.
2. DPI, scaling, theme, font, antialiasing, and window rendering changes can break matches.
3. Template matching is intended as a supplement after UI Automation and OCR, not as the preferred locator.
4. Dynamic or complex visuals can create zero matches or multiple matches.
5. The current matcher is simple pixel tolerance matching and is not optimized for large images or large templates.




## v5.9.0-a Developer Permission Reset Limits

v5.9.0-a is a developer permission model reset, not v6 and not a public release permission normalization pass. v5 still does not promise VLM-level screen understanding, arbitrary custom UI control, protected desktop control, hidden browser automation, or complete desktop-agent autonomy.

Developer mode can explore ordinary desktop UI, Chrome/Edge/browser navigation, Explorer, third-party apps, local HTML, localhost, ordinary external web navigation, local problem/mock pages, and mock mail/form workflows. External real websites can still fail because of dynamic UI, accessibility gaps, browser state, network conditions, or active protection.

When captcha, human verification, automation/script detection, active anti-cheat, active proctoring/lockdown browser, protected desktop/UAC, or protection-bypass requirements appear, Runtime stops and records the boundary. It does not bypass those mechanisms.


## v5.9.0-b HumanMode Limits

v5.9.0-b proves visible HumanMode cases on the current machine; it is not a complete desktop Agent, does not enter v6, and does not introduce VLM. PASS evidence is environment-specific and depends on installed browsers/apps, interactive desktop state, UIA/OCR availability, browser profile state, and network reachability.

`HUMANMODE_FALLBACK_PASS` still uses real visible input but records a fallback path such as Ctrl+L, Win+E, Start Menu search, or Explorer address-bar entry. `SKIP_ENVIRONMENT` is not PASS. Direct launch, script input, DOM mutation, UIA InvokePattern/ValuePattern, Selenium/Playwright/WebDriver/CDP, and no-open mocks are not HumanMode proof.

## v5.9.0-c Strict Case B/D/C Limits

v5.9.0-c strict results remain local desktop evidence. Case B depends on browser UIA/OCR/toolbar geometry being usable enough to derive an address-bar coordinate. Case D depends on Explorer exposing or visibly rendering This PC, D:, `testrepo`, `testwindow`, and the HTML file. Case C depends on at least one safe GUI App target being installed or explicitly supplied. If these cannot be established, the runner records FAIL or SKIP evidence instead of faking PASS.

## v5.9.0-d Case D Explorer Locator Limits

v5.9.0-d remains local desktop evidence for Case D only. It improves Explorer content-area locator robustness with a locked foreground hwnd, content-rect filtering, view normalization, scroll retry, and current-folder incremental search. It still depends on Windows Explorer exposing enough UIA/OCR or selection evidence and on a visible interactive desktop. Explorer address-bar path input remains disallowed as strict PASS, while reading address/breadcrumb text is allowed only for verification.

## v5.9.0-e HumanMode Pacing Limits

v5.9.0-e fixes HumanMode motion visibility and action result auditability; it does not add arbitrary-screen understanding, VLM, v6 Agent behavior, or permission-model changes. Visual pacing depends on the active Windows desktop, display scaling, system input latency, and foreground application behavior.

Instant mode may exist for explicit diagnostics with `--humanmode false`, but it is not valid HumanMode PASS evidence. A HumanMode PASS still depends on successful locator-derived or explicitly marked coordinates and must stop on active protection signals.

## v5.9.1 Pre-v6 Handoff Limits

v5.9.1 is a validation gate, not v6. It may conclude that v6 should not start yet if localhost HumanMode, repeated stability, service exposure, or TaskSession/StepContract integration evidence is incomplete. NOT_RUN, SKIP, and environment-dependent results remain explicit limits and are not converted into PASS.

## v6.1.4 State Guard Limits

v6.1.4 state-guard remediation proves that the runner can stop a local mock mail action on wrong browser context before click/type/send. Full dynamic App/Web acceptance remains blocked until baseline replay no longer reports v6.1.2 local mock mail `STOP_WRONG_CONTEXT`, v6.1.3 scroll gate no longer fails through baseline replay, and the PyCharm/WeChat/QQ Mail real dynamic cases are rerun with the guard active.

## v6.1.5 Safe Context Recovery and Dynamic Diagnostics Limits

v6.1.5 safe recovery is bounded to explicit low-risk targets: local file mocks, localhost mocks, `D:\testrepo\testwindow`, Explorer test directories, explicit browser-open-url-human test URLs, local long/mock pages, and `D:\testrepo\pycharm_sanity` when present. It must not recover through CAPTCHA, human verification, bot/script detection, account security verification, credential entry, anti-cheat, active proctoring, or unclear targets.

Checkpoint/resume evidence can require replay from a safe checkpoint when page or input state may have been lost. It is not a persistent runtime session and does not preserve remote state across arbitrary web apps.

Developer Dynamic Diagnostics in v6.1.5 are diagnostic evidence only. They attempt real App/Web targets and require failure attribution, but they are not full Dynamic App/Web Developer FULL_ACCESS Automation RC. That RC remains v6.1.6. v6.1.5 does not enter v6.2, Persistent Runtime, PlanCompiler, VLM, or Experience Memory.

Real App/Web results remain environment dependent. Installed app availability, current browser profile/login state, network reachability, accessibility exposure, active protection, and page layout can change outcomes. Ordinary words such as test, exam, contest, interview, challenge, OJ, submit, code, and race remain non-blocking unless paired with an actual active-protection or credential/security signal.

