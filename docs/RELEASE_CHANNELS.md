# DesktopVisual Release Channels

Current version: `v1.1.12`.
Current authority: `CURRENT_EXECUTION_CONTRACT.md`.
Launch authority: `docs\LAUNCH_CONTRACT.md`.

This file is the durable release channel semantics reference for DesktopVisual v1.1.x. Its priority is lower than `CURRENT_EXECUTION_CONTRACT.md`.

## Purpose

Keep the developer tree, the current local-use/demo release tree, and the future restricted public release separate so later agents, developers, docs, and tests do not collapse them into one release concept.

## Current Canonical Release Channels

- `developer tree`
- `local-use/demo release tree`
- `future restricted public release`

## Developer Tree Definition

Canonical name: developer tree.

Path:

```text
E:\desktopvisualproject\desktopvisual
```

Meaning:

- Current only active development tree.
- v1.1.1 through v1.1.12 develop first in this tree.
- Keeps developer capability discovery and broad local testing permission semantics.
- Used for authorized development and testing of real apps, ordinary webpages, localhost, IDEs, Explorer, browsers, communication pages, code platforms, and related local workflows.
- Ordinary page categories or keywords do not trigger STOP by themselves.
- Only concrete active protection or security interception triggers STOP.

## Local-Use/Demo Release Tree Definition

Canonical name: local-use/demo release tree.

Path:

```text
E:\desktopvisualproject\desktop_release
```

Meaning:

- Current `desktop_release` is a local-use/demo/testing release tree.
- Current `desktop_release` is not the final restricted public release.
- Current `desktop_release` is not public-dist.
- It is for local machine use, demos, recording, experience testing, and simulated user feedback.
- v1.1.12 synchronizes this tree only after developer validation passes.
- desktop_release sync is part of v1.1.12 only as a protected local-use/demo sync with dry-run evidence and exclusions.
- v1.2.0 is not entered by v1.1.12.
- v1.2.0 does not create public restricted release by default.
- Current permission semantics stay aligned with the developer tree until the user explicitly requests a public restricted release.

## Future Restricted Public Release Definition

Canonical name: future restricted public release.

Path: not created yet.

Meaning:

- The future restricted public release is not created yet.
- It is not created at v1.2.0 by default.
- It can be created only after the user explicitly says to start creating a public restricted release or to start public restricted release permission reduction.
- Stricter public safety hardening is allowed only for that future channel after explicit user request.
- Future restricted public policy must not apply backward to the current developer tree or current local-use/demo release tree.

## Synchronization Policy

- v1.1.1 through v1.1.12 develop first in `E:\desktopvisualproject\desktopvisual`.
- Synchronize `E:\desktopvisualproject\desktop_release` during v1.1.12 only after developer validation passes.
- v1.1.12 desktop_release sync is local-use/demo only and must preserve target local state and evidence.
- v1.2.0 is not entered by this version and is not a public restricted release creation step.
- Do not create a public-dist tree during v1.1.x release channel cleanup.

## Lifecycle Local State Sync Isolation

The invalid artifact lifecycle has project assets and local state:

- Project assets that may sync after a future explicit approval: `scripts\artifact_lifecycle\`, `docs\INVALID_ARTIFACT_LIFECYCLE.md`, and `config\artifact_lifecycle_policy.json`.
- Developer-local state that must not sync: `E:\desktopvisualproject\desktopvisual\.desktopvisual_local\artifact_lifecycle\developer_versions\`.
- Release-local state that must not sync or be deleted by mirror sync: `E:\desktopvisualproject\desktop_release\.desktopvisual_local\artifact_lifecycle\release_actions\`.

Developer-to-`desktop_release` synchronization must exclude `.desktopvisual_local` and local evidence. The `robocopy /MIR` template must include:

```text
/XD ".git" ".desktopvisual_local" "obj" "build" ".vs" ".idea" ".vscode" "__pycache__" "node_modules" /XD "field_test_*" "release_sync_*" "local_action_*" "behavior_action_*"
```

This rule prevents developer `developer_versions` state from being copied into the release tree and prevents release `release_actions` state from being deleted during mirror synchronization.

## Permission Policy Relationship

- The developer tree keeps `DEVELOPER_CAPABILITY_DISCOVERY` semantics.
- The current local-use/demo release tree keeps the same permission semantics as the developer tree.
- Do not infer permission reduction from the word release.
- Permission narrowing starts only for a future restricted public release after explicit user request.
- Future restricted public policy must not be applied to current v1.1.x developer or local-use/demo trees.

## Forbidden Interpretations

- Do not treat `desktop_release` as the current final restricted public release.
- Do not synchronize `desktop_release` before v1.1.12 developer validation passes.
- Do not automatically create a public restricted release at v1.2.0.
- Do not apply future restricted public policy to the current developer tree.
- Do not apply future restricted public policy to the current local-use/demo release tree.
- Do not infer permission reduction from the word release.

## Allowed Future Transition Only By Explicit User Request

A future restricted public release may start only after the user explicitly says that public restricted release creation or public restricted release permission reduction may begin. Until then, the developer tree and current local-use/demo release tree keep the current v1.1.x permission contract.
