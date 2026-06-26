# Known Limitations

Current version: `DesktopVisual 1.0.4`.

## DesktopVisual v1.0.4 Visual Studio C++ Limits

v1.0.4 covers Visual Studio C++ workflow only. PyCharm complex IDE workflow and the Capture/OCR performance pipeline are deferred.

The VS desktop icon must exist. If VS cannot be opened by visible desktop icon double-click, the workflow is BLOCKED instead of using Start Menu or backend launch. Backend cleanup is allowed only for wrong/polluted project cleanup, not as project/file/build/run substitution.

## DesktopVisual 1.0.3.1 VLM Limits

The normal VLM path is the v1.0.3+ real bridge path: `vlm-capability-probe`, `vlm-assist-locate`, and `vlm-candidate-validate`. Legacy mock VLM commands are deprecated test-only fixtures and must not be used for normal Agent work or counted as real VLM success.

VLM candidates are locate-only until Runtime owns the action. If `VLM_UNAVAILABLE`, continue Runtime-only visible paths and normal fallback policy. VLM must not directly operate the computer, participate in backend fallback, run after backend fallback starts, or bypass active protection. v1.0.4 complex IDE work must use `RealVlmRuntimeBridge` / the real VLM bridge path and must add coordinate mapping, target-window lock, Runtime visible action execution, and post-action verification before any accepted candidate can influence an action.

## DesktopVisual 1.0.2 Skill Contract Limits

DesktopVisual 1.0.2 hardens Skill and adapter contracts only. It does not expand Runtime behavior, connect a real VLM provider, add complex IDE project automation, modify release/public-dist trees, or package a release. DesktopVisual v1.1.0 later aligns `PUBLIC_DEFAULT` for ordinary visible desktop operations while preserving real active-protection STOP boundaries.

DesktopVisual is a Windows visible-first desktop runtime, not a background script executor. The agent's goal is not the fastest path; it must prefer visible, auditable, human-like desktop operations. Every input action must have observe / locate / act / verify evidence, or an equivalent task/visible command evidence chain. A task can fail because the path was illegal even when the final application state appears correct.

Use visible-app-launch for app, URL, local shortcut, .lnk, .url, and webpage shortcut launches. visible-app-launch is desktop-first. Start Menu visible search is a fallback, not the first choice. backend launch, ShellExecute, direct file open, and background browser navigation are not default launch paths.

The fallback order remains Layer 1: visible UI path, Layer 2: visible keyboard fallback, Layer 3: backend fallback. Entering shortcut fallback requires at least two bounded visible attempts or strict surface-impossible evidence. Entering backend fallback requires visible path failure plus keyboard fallback failure. The backend fallback reason must be non-empty and must not be convenience, speed, or test shortcut. target_not_found, uia_not_found, ocr_not_found, and click_failed alone are not surface-impossible evidence.

The developer tree uses `DEVELOPER_CAPABILITY_DISCOVERY` / `DEVELOPER_FULL_RUNTIME` style permissions. ordinary app, ordinary webpage, https, localhost, IDE, browser, file manager, mail page, communication page, coding practice page, test, exam, challenge, submit, and assessment keywords are not developer STOP conditions by themselves. If there is no active protection or security interception, developer mode must not stop because of broad category or keyword matching.

Active protection or security interception is STOP, not fallback. CAPTCHA, human verification, bot challenge, automation detected, script detected, security verification, protected desktop, proctoring, lockdown browser, secure exam browser, anti-cheat, ACE, EasyAntiCheat, Vanguard, BattlEye, `CredentialUIBroker`, and `Consent.exe` remain stop boundaries.

v1.0.3 supports provider-gated VLM assist, but availability depends on the current CLI, model, authentication, toolchain, and image input support. `VLM_UNAVAILABLE`, timeout, invalid JSON, or rejected candidates are normal degraded states. In those states Runtime must continue Runtime-only visible paths and fallback policy without fake candidates.

VLM is not a controller. It must not directly operate the computer, decide backend fallback, run after backend fallback starts, or bypass active protection. It is used only for frontend perception/locate assistance and optional keyboard-state visual interpretation.

command error, safety denial, ambiguous window, locator failure, verification failure, and fallback discipline violation cannot be reported as PASS. If final state appears successful but evidence shows a disallowed fallback, report failure. Report the failed command, error_code, whether input was executed, artifacts/report path, and the next minimal repair entry. Do not broaden title, guess coordinates, click nearby areas, or switch to a backend plan to keep going.

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
