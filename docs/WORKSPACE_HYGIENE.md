# DesktopVisual Workspace Hygiene

Current version: `v1.1.12`.

## Purpose

Workspace hygiene keeps the developer tree explainable before field testing. The v1.1.8 evidence remains the historical workspace hygiene baseline; v1.1.10 preserved it while adding VS field-test closure hardening artifacts. v1.1.11 added separated invalid artifact lifecycle state for developer-version quarantine and local-use release action quarantine. v1.1.12 adds launch contract evidence, safe CLI discovery evidence, VS startup convergence fixtures, lifecycle resolver evidence, and protected sync evidence.

Lifecycle rules are defined in `docs\INVALID_ARTIFACT_LIFECYCLE.md`. The local lifecycle state root is `.desktopvisual_local\artifact_lifecycle`, and `.desktopvisual_local` must be gitignored and excluded from future developer-to-release sync.

## Files That Can Be Cleaned

A file can be deleted only when all of these are true:

- It is clearly temporary.
- It is not source code.
- It is not current documentation.
- It is not a selftest or required runner.
- It is not required v1.1.1-v1.1.7 evidence.
- It is not referenced by a test summary, evidence index, or field-test plan.
- Its deletion is recorded in `cleanup_deleted_files.txt`.

Examples include one-off scratch files, accidental editor backups, empty temporary directories, transient HTML pages that are not referenced by evidence, and duplicate local temp copies.

In v1.1.12, clearly invalid files should be quarantined with the lifecycle scripts instead of being manually deleted:

- Developer tree: `.desktopvisual_local\artifact_lifecycle\developer_versions\<version>`.
- Local-use release tree after a future approved sync: `.desktopvisual_local\artifact_lifecycle\release_actions\<action_id>`.

The developer lifecycle must not use `release_actions`; the release action lifecycle must not use `developer_versions`.

## Files That Must Be Retained

Do not delete:

- `src\`, `include\`, `tools\codex_vlm_provider.ps1`, `build.ps1`, `VERSION`, `config\`, or current docs.
- `CURRENT_EXECUTION_CONTRACT.md`, `AGENTS.md`, `README.md`, `COMMAND_PROTOCOL.md`, `CHANGELOG.md`, and v1.1.x selftests.
- `artifacts\dev1.1.1_*` through `artifacts\dev1.1.7_*` required evidence.
- Any `test_summary.md`, build log, selftest log, latency baseline JSON, wait replacement summary, not-replaced report, real UI sanity log, or failure evidence.
- Any ambiguous file whose purpose cannot be confidently classified.
- Experience memory, workflow templates, selector learning, stable window baselines, learned acceleration profiles, user-approved retained feedback, and future self-learning assets.

## Artifacts Retention Strategy

Artifacts are retained by default. Large or noisy artifacts should be indexed, summarized, or marked as retained evidence instead of deleted unless they are clearly temporary and unreferenced.

Accepted evidence remains under its original version directory. v1.1.8 adds `artifacts\EVIDENCE_INDEX.md` as the cross-version index rather than moving or rewriting old evidence.

## Temporary File Identification

Temporary files are candidates only when they have a narrow, one-time purpose and no evidence dependency. Check:

- Is it under a temporary test directory?
- Is it referenced by `test_summary.md`, an evidence index, or a log?
- Does it help reproduce a real UI sanity run?
- Is it a generated VLM raw output sample or baseline artifact?
- Would deleting it make a previous version harder to audit?

When uncertain, keep it.

## Ambiguous File Rule

Ambiguous files must be listed in `ambiguous_files.md` and retained. They must not be deleted to make `git status` shorter.

If a later maintainer identifies an ambiguous file as temporary, it can be cleaned only in a later cleanup run with a recorded reason.

## Evidence Consolidation Rules

- Add an index rather than moving historical evidence.
- Preserve failed, blocked, and inconclusive evidence when it explains a boundary.
- Keep v1.1.7 Explorer and Browser sanity fixtures when they help reproduce the logs.
- Record expected dirty state separately from v1.1.8 changes.
- Record unexpected dirty state as a stop condition, not as cleanup noise.

## Git Status Hygiene

Record `git status --short` before cleanup and after cleanup. Do not fake or script around dirty state. A dirty workspace is acceptable when it is classified and evidence-backed.

Classifications:

- A: expected source changes from v1.1.1-v1.1.7.
- B: required evidence artifacts.
- C: temporary generated files that can be deleted.
- D: ambiguous files retained.
- E: unexpected dirty state that must stop cleanup if present.

## desktop_release Boundary

Do not clean, sync, overwrite, copy into, or version-bump `E:\desktopvisualproject\desktop_release` until v1.1.12 developer validation passes. It remains the local-use/demo/testing tree and not the final restricted public release.

v1.1.12 protected sync may copy project assets, but it must not copy or delete `.desktopvisual_local`, field-test evidence, release-sync evidence, local action evidence, behavior action evidence, build output, IDE folders, caches, or dependency folders. The required `robocopy /MIR` exclusion is:

```text
/XD ".git" ".desktopvisual_local" "obj" "build" ".vs" ".idea" ".vscode" "__pycache__" "node_modules" /XD "field_test_*" "release_sync_*" "local_action_*" "behavior_action_*"
```

This protects developer-local `developer_versions` from being mirrored into `desktop_release`, and protects release-local `release_actions` from being purged by mirror sync.

The sync template must also protect:

- `artifacts\field_test_*`
- `artifacts\release_sync_*`
- `local_action_*`
- `behavior_action_*`
- VLM lazy-cache probe/cache artifacts when present
