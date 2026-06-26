# AUDIT_CHAIN

Current status: v5.8.7 pre-v6 Runtime hardening and revalidation.

## Encoding Recovery Notice

The previous `AUDIT_CHAIN.md` content was mojibake/corrupted and could not be reliably restored as historical prose during Phase 1. To avoid inventing or rewriting historical audit content, the corrupted legacy file was preserved as:

```text
AUDIT_CHAIN_LEGACY_CORRUPTED.md
```

This new readable audit chain records only the current documented state and Phase 0+ revalidation evidence. Historical claims must be checked against existing artifacts, reports, git history, and the legacy corrupted file where possible.

## Current Boundary

- v5.x is a Task-Level Desktop Execution Runtime.
- v5.8.7 is a pre-v6 hardening and revalidation pass.
- v6 has not started.
- v6 is reserved for the future Initial Desktop Agent System boundary and provider architecture phase.
- v5 does not depend on VLM.
- Runtime is the only action executor.
- SafetyPolicy, PermissionProfile, HumanConfirmation, blocked-action rules, StepContract, Verification, and AuditTrail boundaries must not be bypassed.

## Release Status

- `D:\desktopvisual` is the internal development tree.
- This tree is not a public release tree.
- Public release requires a later Release Normalization Pass and release hygiene review.
- Missing historical artifacts must be reported as gaps, not fabricated.

## Phase 0 Baseline

Phase 0 artifacts:

```text
artifacts\dev5.8.7_revalidation\phase_00_baseline\
```

Known Phase 0 findings:

- mandatory top-level and docs files existed and were UTF-8 readable.
- previous `AUDIT_CHAIN.md` had severe mojibake.
- `docs\ROADMAP.md` was stale relative to v5.8.6.
- historical artifact directories were missing for referenced v5.6.1 through v5.6.5 and v5.7.1.
- the dirty internal development tree blocks public-release use.

## Phase 1 Documentation Skeleton Sync

Phase 1 artifacts:

```text
artifacts\dev5.8.7_revalidation\phase_01_docs_sync\
```

Phase 1 updates VERSION to 5.8.7 and synchronizes the global document skeleton for pre-v6 v5 revalidation. It does not add Runtime features, VLM providers, Agent behavior, release packaging, or historical artifact backfill.
