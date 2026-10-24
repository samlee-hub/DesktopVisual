# DesktopVisual Current Execution Contract

Current authority: v1.2.0 local-use stable closure.
Current version: 1.2.0.
Current stage: Local-Use Stable Closure.
Current version task: v1.2.0 closes the already validated v1.1.12a state for local use, updates version labels, records evidence, performs protected developer-to-local-use sync, and stops.
Next planned version: none in this action.
Next planned stage: Local user trial; do not enter v1.2.x development in this closure.

This file is the highest-priority entry for current DesktopVisual execution rules. Agents, developers, tests, demos, and local-use runs must read this file before applying older version-line documents. Older v3, v4, v5, v6, and v1.1.x documents are historical lineage only and must not override this v1.2.0 local-use stable closure contract.

Detailed release channel semantics are defined in `docs\RELEASE_CHANNELS.md`. That document is authoritative for release-channel wording when it does not conflict with this current execution contract.

The current startup authority is `docs\LAUNCH_CONTRACT.md`. It requires desktop icon double-click first, keyboard/Start Menu second only with evidence, backend third only with Layer 1 and Layer 2 failure evidence, non-executing visible/action help and bare dry-run handling, and Visual Studio IDE startup convergence before code input.

Latency observability, VLM lazy/cache/degrade report semantics, v1.1.6 core wait-state report semantics, and v1.1.7 workflow wait-state report semantics are defined in `docs\LATENCY_OBSERVABILITY.md`. v1.1.10 targeted VS code-input and evidence closure hardening in `docs\VS_CODE_INPUT_AND_EVIDENCE_HARDENING.md`. v1.1.11 added separated invalid artifact lifecycle rules, scripts, policy, selftests, and evidence in `docs\INVALID_ARTIFACT_LIFECYCLE.md` without changing permission semantics, desktop behavior, VLM behavior, or VLM timeout. v1.1.12 changed launch behavior and CLI discovery behavior only as described in `docs\LAUNCH_CONTRACT.md`. v1.2.0 introduces no new Runtime behavior; it updates version labels and closure status only.

v1.2.0 is not a public release. It does not create public-dist and does not create a public restricted release. The user will use v1.2.0 locally before deciding the next step. The main acceptance basis is the v1.1.12a real Visual Studio brace-safe validation: developer real validation PASS, release real validation PASS, brace-safe input default enabled, auto-pair corruption count = 0, clipboard paste = NO, direct source write = NO, developer/user build/run = PASS, release sync completed, and public release not created.

## Release Channel Definitions

- Canonical name: developer tree.
- Path: `E:\desktopvisualproject\desktopvisual`.
- Meaning: the only active development tree. v1.2.0 closure changes only version labels, status documents, evidence, and protected sync output.
- Permission semantics: developer capability discovery and broad local testing remain active for real apps, ordinary webpages, localhost, IDEs, Explorer, browsers, communication pages, and related authorized local workflows.

- Canonical name: local-use/demo release tree.
- Path: `E:\desktopvisualproject\desktop_release`.
- Meaning: current local-use, demo, recording, experience-testing, and simulated-feedback release tree.
- Current status: not the final restricted public release and not public-dist.
- Synchronization: v1.2.0 performs protected developer-to-local-use sync only after developer closure checks pass. Sync must exclude `.desktopvisual_local`, `developer_versions`, `artifacts\field_task_*`, `artifacts\field_test_*`, `artifacts\release_sync_*`, `local_action_*`, `behavior_action_*`, `public-dist`, `obj`, `build`, `.vs`, `.idea`, `.vscode`, `__pycache__`, `node_modules`, and temporary patch/tmp/debug files.
- v1.2.0 meaning: local-use stable closure only. It does not create a public restricted release by default.
- Local lifecycle state: `.desktopvisual_local` is never mirrored across trees. Developer `developer_versions` state is developer-local only. Local-use release `release_actions` state is release-local only.
- Permission semantics: temporarily aligned with the developer tree until the user explicitly requests a public restricted release.

- Canonical name: future restricted public release.
- Path: not created yet.
- Meaning: a future channel only. The future restricted public release currently does not exist and is not created at v1.2.0 by default.
- Creation rule: it may be created only when the user explicitly says to start creating a public restricted release or to start public restricted release permission reduction.
- Isolation rule: future restricted public policy must not be applied backward to the current developer tree or current local-use/demo release tree.

## Current Permission Semantics

- The developer tree keeps broad developer permissions.
- The current `desktop_release` tree temporarily keeps the same permission semantics as the developer tree.
- The current `desktop_release` tree is not the final restricted public release.
- Do not infer permission reduction from the word `release`.
- Current v1.1.x rules must not narrow developer or local-use release permissions by broad category, page theme, keyword, or guessed purpose.

Ordinary apps, ordinary webpages, HTTPS pages, localhost pages, local HTML pages, IDEs, Explorer, browsers, email, communication pages, code platforms, programming-practice pages, and the words `test`, `exam`, `challenge`, `assessment`, `interview`, `contest`, and `submit` do not trigger STOP or BLOCK by themselves.

Authorized local development and testing may perform visible desktop exploration and UI testing in ordinary app, ordinary web, local page, HTTPS, localhost, IDE, Explorer, browser, and communication environments.

## Required STOP Boundary

The Runtime must STOP when a concrete, real, active third-party protection or security interception is present, including:

- CAPTCHA, reCAPTCHA, hCaptcha, Turnstile, human verification, bot challenge, automation detected, or script detected.
- Credential handoff or account security verification.
- UAC or protected desktop.
- Proctoring, lockdown browser, Secure Exam Browser, or active exam security client.
- Anti-cheat systems such as ACE, EasyAntiCheat, BattlEye, Vanguard, Xiao Lan Xiong, or equivalent active protection.
- Any other explicit active interception, risk-control, identity-verification, or security-protection mechanism.

One-line contract:

> If there is no real security interception, the developer tree and current local-use release may enter ordinary app, ordinary web, local page, IDE, Explorer, browser, and communication environments for visible desktop exploration and testing. Once real active protection appears, accept the block and STOP.

## Version Scope

v1.2.0 is a local-use stable closure of the v1.1.12a validated state. It may update `VERSION`, the Runtime version label, current status documents, selftest version assertions, evidence directory names, and v1.2.0 closure/sync evidence. It may run build, selftests, boundary checks, cleanliness checks, and protected developer-to-release sync. It does not add features, modify Runtime behavior beyond version labels, change input strategy, change Launch Contract behavior, change PermissionManager, modify `config\safety_manifest.json`, modify `config\safety.conf`, change VLM behavior, change VLM timeout, create public-dist, create a public restricted release, reduce permissions, enter v1.2.x follow-up development, rerun the full Visual Studio field task, delete valid evidence, sync `.desktopvisual_local`, sync `developer_versions`, or delete release-local `release_actions`.

v1.1.1 was a contract-unification version only. v1.1.2 focused on documentation entry slimming and historical isolation without Runtime behavior changes. v1.1.3 focused only on release channel semantic cleanup. v1.1.4 focused on latency observability and first-action baseline. v1.1.5 focused on VLM lazy loading, capability cache, negative cache, and fast unavailable degradation. v1.1.6 focused on core wait-state hardening. v1.1.7 focused on workflow wait-state hardening. v1.1.8 focused on workspace hygiene, evidence consolidation, and field-test readiness. v1.1.9 focused on VS Code input, timeline, wait accounting, selector disambiguation, and failure classification hardening exposed by the v1.1.8 Visual Studio C++ projectdd field test. v1.1.10 targeted the v1.1.9 repeat field-test residuals: real C++ payload regression, keyboard-safe segmentation, target lock preflight, code-input integrity v2, timeline v2.1 no-overlap evidence, command discovery separation, locator miss/disambiguation evidence, and first-action proxy closure. v1.1.11 established separated invalid artifact lifecycles for developer-version quarantine state and local-use release action quarantine state. v1.1.12 unifies the launch contract, safe CLI discovery, Visual Studio startup convergence, lifecycle path resolver behavior, and protected local-use sync.

v1.1.12 may add or update `docs\LAUNCH_CONTRACT.md`, launch-related Runtime argument handling and evidence fields, VS preflight fixture logic, lifecycle path resolver scripts, current documentation pointers, selftests, version metadata, and v1.1.12 development/sync evidence.

v1.1.12 does not reduce permissions, change PermissionManager semantics, change `config\safety_manifest.json` permission semantics, change `config\safety.conf` permission semantics, create a public restricted release, create a public-dist tree, enter v1.2.0, make clipboard paste the default input path, make direct file writes the default fallback, bypass Visual Studio UI for code input, lower STOP conditions, change VLM behavior, change VLM timeout, run a Visual Studio field test, delete real source/docs/config/evidence, or remove prior evidence. PermissionManager semantics unchanged.

After v1.2.0 local stable closure, stop. Do not repeat the Visual Studio field test, enter v1.2.1 or later development, create public restricted release artifacts, create public-dist, or run release action cleanup against the real `desktop_release` tree.

## Invalid Artifact Lifecycle Isolation

v1.1.11 and v1.1.12 preserve two separate lifecycle mechanisms:

- Developer-version invalid artifacts live only under `E:\desktopvisualproject\desktopvisual\.desktopvisual_local\artifact_lifecycle\developer_versions\<version>`.
- Local-use release action invalid artifacts live only under `E:\desktopvisualproject\desktop_release\.desktopvisual_local\artifact_lifecycle\release_actions\<action_id>`.

The rules, scripts, docs, and config policy are project assets and may be synchronized in a future approved developer-to-release sync. The `.desktopvisual_local` directory is local state and must never be copied, mirrored, or deleted by a future sync. Future `robocopy /MIR` sync commands must include:

```text
/XD ".git" ".desktopvisual_local" "obj" "build" ".vs" ".idea" ".vscode" "**pycache**" "node_modules"
```

This prevents developer `developer_versions` state from reaching `desktop_release` and prevents release-local `release_actions` state from being deleted by mirror sync.
