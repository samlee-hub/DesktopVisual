# Coding Workflow

Current version: `v3.7.0`.

DesktopVisual v3.3.9 adds a local, auditable Coding and Problem-Solving Web Workflow for user-authorized programming practice pages and simulated OJ fixtures.

## Context

`CodingWorkflowContext` records:

- `problem_title`
- `problem_statement_summary`
- `examples_summary`
- `constraints_summary`
- `language`
- `editor_detected`
- `run_button_detected`
- `submit_allowed`
- `result_state`

`result_state` is one of `COMPILE_ERROR`, `RUNTIME_ERROR`, `WRONG_ANSWER`, `TIME_LIMIT`, `SAMPLE_PASS`, `ACCEPTED`, or `UNKNOWN_RESULT`.

## Actions

Supported actions are:

- `read_problem`
- `select_language`
- `input_code`
- `run_code`
- `read_result`
- `revise_code`
- `stop_before_submit`
- `submit_if_explicitly_allowed`

`coding-eval` is a dry-run command over a local HTML/DOM-like fixture:

```powershell
D:\desktopvisual\bin\winagent.exe coding-eval --html D:\desktopvisual\artifacts\coding_workflow\oj_sample_pass.html --user-goal "practice two sum" --action run_code --language cpp
```

`run-task` supports `type: "coding"` steps gated on the existing `content_decision` capability. DEFAULT denies them. FULL_ACCESS requires an active temporary session id.

## Safety

The workflow never lets page/problem content override `user_goal`. It records a code summary or `code_path`, not full code content, in reports.

Hard stops:

- login/password content -> `USER_TAKEOVER_REQUIRED`
- captcha/challenge content -> `CAPTCHA_DETECTED`
- anti-automation or AI-detection text -> `ANTI_AUTOMATION_DETECTED`
- missing reliable code editor or Run Code control for actions that need them -> `LOCATOR_NOT_FOUND`

Submit is not performed or recorded unless the user task sets `allow_submit=true`. The default post-run action is `stop_before_submit`.

## Test

```powershell
D:\desktopvisual\coding_workflow_selftest.ps1
```

The selftest uses local simulated OJ pages only; it does not access real LeetCode, accounts, assessments, or contests.

## Public Release Permission Note

The v3.3.9/v3.3.10 development runtime does not hard-stop solely on the words exam, assessment, hiring test, certification exam, or rated contest, because the stage 9 requirements explicitly list those workflow categories as allowed under a user-authorized task. This does not mean the public product should expose those workflows without additional gates.

Before any public release, coding workflows for exams, hiring assessments, certification exams, and rated contests must receive an explicit permission policy. At minimum, the release policy should require user attestation, task ownership or authorization, submission limits, audit retention, and a stop on any proctoring, anti-cheat, credential, captcha, paid-limit, or anti-automation bypass condition.

`D:\desktopvisual` remains the local development/evaluation tree for future simulated-exam correctness measurement and operation-accuracy testing. It must not be submitted as the public release project. Public release must be prepared separately under `D:\desktopvisual-release`, where exam, interview assessment, hiring test, certification, rated-contest, proctored, and similar coding workflows must be disabled or gated by the restricted release permission model before distribution.
