# DesktopVisual Command Protocol

This document describes the public command surface included in the DesktopVisual 1.0.0 public release candidate package. It is intended for users running the published binary package from GitHub Releases.

DesktopVisual is a local Windows desktop automation runtime for visible UI workflows. Commands run on the local machine and are bounded by the public release safety policy.

## Run From Package Root

Extract the public release zip and run commands from the extracted package root:

```powershell
.\bin\winagent.exe version
.\bin\winagent.exe serve --help
.\selftest.ps1
```

The public documentation repository is not the runnable package. Do not expect `git clone` or GitHub `Code > Download ZIP` to include `winagent.exe`.

## Version

```powershell
.\bin\winagent.exe version
```

Prints runtime version and build metadata. This is the lowest-risk command to confirm the binary starts correctly.

## Service Help

```powershell
.\bin\winagent.exe serve --help
.\bin\winagent.exe serve /?
```

Shows service help and exits with code `0`. The help path must not enter the long-running service loop and must not create a persistent runtime session.

The help text covers:

- Service purpose.
- Start command.
- Stop behavior.
- Default behavior.
- F12 force-exit behavior.
- Public release safety policy behavior.
- Example commands.

## Service Mode

```powershell
.\bin\winagent.exe serve
```

Starts the local DesktopVisual runtime service. Service mode is intended for local use only. It does not bypass runtime policy, F12 handling, active-protection stops, credential stops, or public release safety boundaries.

Stop the service from the terminal that launched it with `Ctrl+C`, or close the terminal when appropriate.

## F12 Force Exit

F12 stops the current task only and does not terminate the `winagent.exe` process. Runtime evidence records the forced stop as:

```text
STOP_USER_FORCE_EXIT_F12
user_force_exit = true
force_exit_key = F12
force_exit_scope = current_task_only
process_exit = false
```

The user-facing message is:

```text
用户已按 F12 强制结束当前任务，Agent 已停止本次行为。
```

## Public Release Safety Policy

The public release stops automation in explicit exam-integrity restricted contexts, such as formal assessment environments that clearly prohibit external assistance, AI assistance, cheating, scripts, automation tools, proctoring bypass, lockdown browser bypass, anti-cheat bypass, or similar restricted conduct.

The policy is not a simple keyword block. Ordinary occurrences of words such as `test`, `quiz`, or `exam` are not stop conditions by themselves.

Safety stop code:

```text
STOP_PUBLIC_RELEASE_EXAM_INTEGRITY_POLICY
```

## Selftests

The public package includes focused selftests:

```powershell
.\selftest.ps1
.\serve_help_selftest.ps1
.\f12_force_exit_selftest.ps1
.\f12_force_exit_runtime_integration_selftest.ps1
.\public_release_safety_policy_selftest.ps1
.\public_release_exam_integrity_policy_selftest.ps1
.\public_release_allowed_context_selftest.ps1
.\public_release_acceptance_gate.ps1
```

These tests are designed for the public package and do not run legacy UI workflow gates.

## Safety Boundaries

DesktopVisual does not automate or bypass:

- CAPTCHA or human verification.
- Account security verification.
- Credential entry or credential extraction.
- Proctoring or lockdown browser restrictions.
- Anti-cheat or anti-automation controls.
- Payment confirmation.
- Protected desktop or elevated administrator prompts.
- Tasks that violate explicit exam, assessment, interview, contest, or platform rules.

## Source Availability

The 1.0.0 public release candidate is a closed-source public binary release. Source code is not included in the public repository or public zip package.
