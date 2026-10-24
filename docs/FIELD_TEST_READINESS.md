# DesktopVisual Field Test Readiness

Current version: `v1.2.0`.

## Field Test Purpose

Field testing validates the current developer tree or explicitly approved release tree against realistic local UI workflows. For v1.2.0, the full Visual Studio C++ projectdd field task is not rerun. The local stable closure relies on the already completed v1.1.12a real Visual Studio brace-safe validation and performs only build, selftest, boundary, cleanliness, and protected sync checks.

## Field Test Prerequisites

- `VERSION` is `1.2.0`.
- `CURRENT_EXECUTION_CONTRACT.md` names v1.2.0 as Local-Use Stable Closure.
- `docs\LAUNCH_CONTRACT.md` is present and is the startup authority.
- `docs\INVALID_ARTIFACT_LIFECYCLE.md` is present.
- `docs\WORKSPACE_HYGIENE.md` and this document are present.
- `docs\VS_CODE_INPUT_AND_EVIDENCE_HARDENING.md` is present.
- v1.1.12a real validation evidence exists and remains valid input to v1.2.0 closure.
- `workspace_hygiene_selftest.ps1` and all v1.1.x regression selftests pass.
- `artifact_lifecycle_selftest.ps1` passes.
- `desktop_release` remains untouched during developer closure until v1.2.0 developer checks pass and protected sync dry-run evidence is recorded.
- `config\safety_manifest.json` and `config\safety.conf` remain unchanged.
- `.desktopvisual_local` is excluded from future sync and must not be mirrored across developer/release trees.

## Required Clean Workspace Checks

Before field testing, record:

- `git status --short`.
- Workspace file classification with expected dirty state, retained evidence, deleted temporary files, ambiguous files, and unexpected dirty state.
- `desktop_release` untouched check.
- Public restricted release and public-dist absence check.
- `.desktopvisual_local` sync exclusion check.
- Developer `developer_versions` and release `release_actions` isolation check.
- Launch contract consistency check.
- Safe CLI non-execution check.
- VS startup convergence fixture check.
- Lifecycle path resolver check.

Expected dirty state from v1.1.1 through v1.1.7 can remain dirty when it is documented. Unexpected dirty source or config state must stop field testing until it is explained.

## Required Selftests Before Field Test

Run and save logs for:

- `.\build.ps1`
- `.\current_contract_selftest.ps1`
- `.\documentation_entry_selftest.ps1`
- `.\release_channel_semantics_selftest.ps1`
- `.\latency_observability_selftest.ps1`
- `.\vlm_lazy_cache_selftest.ps1`
- `.\core_wait_state_selftest.ps1`
- `.\workflow_wait_state_selftest.ps1`
- `.\workspace_hygiene_selftest.ps1`
- `.\vs_code_input_hardening_selftest.ps1`
- `.\vs_field_test_closure_selftest.ps1`
- `.\artifact_lifecycle_selftest.ps1`
- `.\launch_contract_consistency_selftest.ps1`
- `.\safe_cli_non_execution_selftest.ps1`
- `.\vs_launch_preflight_selftest.ps1`
- `.\artifact_lifecycle_path_resolver_selftest.ps1`

Any failure must be recorded as FAIL or BLOCKED with the exact command, exit code, and log path.

## What Can Be Tested

- Explorer workflows in temporary test directories only.
- Browser workflows on local HTML, localhost, or ordinary read-only HTTPS pages.
- Visual Studio, PyCharm, VS Code, Notepad, or another local editor when the environment is stable and the workflow is non-destructive.
- Local communication mock or safe substitute pages that do not send real messages.
- Active-protection simulated STOP pages that do not attempt bypass.
- Observation, foreground readiness, wait-state evidence, and no-destructive-action sanity checks.

## What Must Not Be Tested

- Real accounts, real email sending, credential handoff, CAPTCHA, human verification, proctoring, anti-cheat, lockdown browser, protected desktop, UAC, or payment flows.
- User real files outside temporary test directories.
- Public packaging, public restricted release creation, public-dist generation, or unvalidated `desktop_release` sync.
- Modifying or cleaning real `desktop_release\.desktopvisual_local\artifact_lifecycle\release_actions`.
- Permission changes, PermissionManager changes, public release creation, direct file write source-code fallback, clipboard-paste defaulting, Visual Studio UI bypass, or VLM provider changes.
- Automatic Visual Studio field task execution during v1.2.0 local stable closure or sync.

## STOP Conditions

Stop immediately and record BLOCKED when any of these appear:

- CAPTCHA, hCaptcha, reCAPTCHA, Turnstile, bot challenge, automation/script detection, or human verification.
- Login credential handoff, account recovery, or security verification.
- UAC, protected desktop, active proctoring, lockdown browser, Secure Exam Browser, or anti-cheat.
- Any task would modify real user data outside the declared temporary test scope.
- The current app surface no longer matches the approved test scenario.
- Any launch command reports `launch_contract_violation=true`.
- Visual Studio Installer is selected as the VS IDE target.
- More than one VS IDE window matches the target and the workflow has not visibly converged to one target.
- Required evidence capture fails and cannot be repaired without changing the scenario.

## Evidence Required During Field Test

Each field-test run must save:

- Command transcript or stdout/stderr log.
- Runtime result JSON when available.
- Screenshot or visible UI evidence for real UI steps.
- Input/output temp directory path for Explorer tests.
- Local HTML or localhost fixture path for Browser tests.
- Failure classification and environment/runtime attribution when a test does not pass.
- `git status --short` after the run.

## How To Record Failures

Use a short failure record with:

- Scenario name.
- Command run.
- Exit code.
- Visible surface observed.
- Expected state.
- Actual state.
- Evidence files.
- Classification: `runtime_gui_failure`, `code_input_policy_failure`, `selector_ambiguity_failure`, `runner_wrapper_failure`, `codex_orchestration_failure`, `test_harness_failure`, `environment_failure`, `user_visible_stop_condition`, `build_compile_failure`, `program_correctness_failure`, or `inconclusive`.
- Whether any user data was touched.

Do not convert SKIP, BLOCKED, INCONCLUSIVE, or missing evidence into PASS.

## Environment Failure Vs Runtime Failure

Use `environment_failure` when the local machine lacks a stable target app, required IDE, browser install, OCR facility, or permission to open a safe test fixture.

Use `runtime_gui_failure` when the target environment is stable but DesktopVisual produces the wrong visible action, wrong wait evidence, wrong verification result, wrong STOP behavior, or missing required Runtime evidence.

Use `blocked_by_active_protection` when an active security/protection surface appears. This is not a Runtime failure if DesktopVisual stops and records the block.

Use `runner_wrapper_failure` when the runner or wrapper fails before a Runtime GUI action is issued, including missing command or wrapper variable errors.

## Feed Into Repeat VS Field Test

After v1.2.0 local user trial and explicit future user approval, any repeat VS field test or release action should consume v1.1.10, v1.1.11, v1.1.12, and v1.1.12a development evidence to decide:

- Whether `desktop_release` sync is safe.
- Whether future sync excludes `.desktopvisual_local` with `/XD ".git" ".desktopvisual_local" "obj" "build" ".vs" ".idea" ".vscode" "**pycache**" "node_modules"`.
- Whether release-local `release_actions` state will survive mirror sync and developer-local `developer_versions` state will not be copied.
- Whether the projectdd C++ code-input path avoids quote, brace, vector, template, and `main` false positives.
- Whether selector ambiguity and timeline overlap evidence are materially improved.
- Whether wait saved totals are de-duplicated.
- Whether wrapper/test harness failures are separated from Runtime GUI failures.
