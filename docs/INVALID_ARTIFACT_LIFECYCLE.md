# DesktopVisual Invalid Artifact Lifecycle

Current version: `v1.1.12`.

This document defines two permanently separated invalid artifact lifecycle mechanisms. It is not a unified garbage box and it does not manage project assets.

Startup behavior is governed separately by `docs\LAUNCH_CONTRACT.md`; lifecycle scripts must not redefine launch fallback rules.

## Developer-version lifecycle

Developer invalid artifact state is local to the developer tree:

```text
E:\desktopvisualproject\desktopvisual\.desktopvisual_local\artifact_lifecycle\developer_versions\<version>
```

The v1.1.12 developer folder is:

```text
E:\desktopvisualproject\desktopvisual\.desktopvisual_local\artifact_lifecycle\developer_versions\1.1.12
```

Invalid files created by developer version `n` are placed under `developer_versions\n`. Version `n` remains during version `n+1`. After `n+1` closes, and before `n+2`, the `n` folder may be deleted only when its manifest exists and says it is safe to delete. No-manifest folders are retained and reported for review.

The developer lifecycle never reads or writes `release_actions`.

## Local-use release action lifecycle

Release action invalid artifact state is local to the local-use release tree:

```text
E:\desktopvisualproject\desktop_release\.desktopvisual_local\artifact_lifecycle\release_actions\<action_id>
```

Release action ids are behavior sequence ids such as `0001`, `0002`, and `0003`, not project versions. Action `n` remains during action `n+1`. After `n+1` closes, and before `n+2`, action `n` may be deleted only when its manifest exists and says it is safe to delete. No-manifest action folders are retained and reported for review.

The release action lifecycle never reads or writes `developer_versions`.

## Sync isolation rules

Project assets may sync from developer to local-use release:

- `scripts\artifact_lifecycle\`
- `docs\INVALID_ARTIFACT_LIFECYCLE.md`
- `config\artifact_lifecycle_policy.json`

Local state must never sync:

```text
.desktopvisual_local
```

Developer-to-`desktop_release` sync commands must exclude local lifecycle state and local evidence. The robocopy template is:

```text
robocopy <source> <target> /MIR /XD ".git" ".desktopvisual_local" "obj" "build" ".vs" ".idea" ".vscode" "__pycache__" "node_modules" /XD "field_test_*" "release_sync_*" "local_action_*" "behavior_action_*" /XF "*.tmp" "*.bak" "*.orig" "*.log.tmp" "PowerShell_transcript*.txt"
```

This exclusion prevents developer `developer_versions` state from being copied into `desktop_release` and prevents `/MIR` from deleting `desktop_release\.desktopvisual_local\artifact_lifecycle\release_actions`.

## Path Resolver Rule

All lifecycle state paths must use the resolver functions in `scripts\artifact_lifecycle\common_artifact_lifecycle.ps1`:

- `Resolve-ArtifactLifecycleRoot`
- `Resolve-DeveloperVersionLifecyclePath`
- `Resolve-ReleaseActionLifecyclePath`
- `Resolve-ReleaseActionSequencePath`

Scripts must build good paths with `Join-Path` through these resolver functions. Do not handwrite `$Root.desktopvisual_local`, `$ProjectRoot.desktopvisual_local`, or equivalent sibling paths.

If a bad sibling path such as `E:\desktopvisualproject\desktop_release.desktopvisual_local` exists, scripts must report it as `orphan_bad_lifecycle_path` and must not delete it without a later explicit user instruction.

## Asset protection rules

Allowed quarantine candidates are limited to clearly invalid transient artifacts:

- transient scratch
- one-time debug dumps
- unreferenced raw temp logs
- accidental root temp files
- PowerShell transcript temp files
- empty temp directories
- duplicate temp copies
- orphan runner output
- failed intermediate JSON not referenced by evidence
- temporary HTML not referenced by evidence
- stale raw screenshots not referenced by evidence
- old temp zips not referenced by evidence
- `.tmp`, `.bak`, and `.orig` files
- temporary command request/response files

The lifecycle scripts must not move or delete:

- real source changes
- current docs
- valid config
- build scripts
- selftests
- evidence index
- version test summaries
- field test evidence
- project snapshots
- valid dev artifacts
- release evidence zip
- persistent learning
- workflow templates
- experience memory
- stable window baselines
- selector learning
- user-approved feedback
- future self-learning artifacts
- ambiguous files

## Persistent learning protection

Experience memory, selector learning, workflow templates, stable machine/window baselines, future learned acceleration profiles, skill iteration outputs, and user-approved retained feedback are protected project assets. They are not invalid artifacts merely because they are local, generated, or version-specific.

## Ambiguous file policy

Ambiguous files are written to an `ambiguous_files` manifest field or review report. They are not moved and they are not deleted. They wait for a user decision or a later explicit classification.

## Manifest policy

Every quarantine folder has a `manifest.json`. Developer manifests use `scope = developer_version`; release action manifests use `scope = release_action`.

Required manifest fields include:

- scope
- version or action_id
- created_at
- source_context or behavior_instruction_summary
- files
- file_count
- total_bytes
- classification
- reason
- moved_from
- moved_to
- referenced_by
- safe_to_delete_after_version or safe_to_delete_after_action
- retained_for_next_version or retained_for_next_action
- delete_policy
- protected_assets_checked
- ambiguous_files
- notes

## Cleanup timing

Developer cleanup keeps the current version and previous version. Older folders are deleted only when the manifest is present and safe. Release cleanup keeps the current action and previous action. Older action folders are deleted only when the manifest is present and safe.

## Non-goals

- No unified garbage box.
- No shared state lifecycle between developer and release trees.
- No Runtime desktop behavior change.
- No PermissionManager semantic change.
- No VLM behavior or timeout change.
- No permission reduction.
- No public restricted release.
- No public-dist tree.
- No v1.2.0 entry.
- No Visual Studio field test.
