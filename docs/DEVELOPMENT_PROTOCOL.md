# Development Protocol

This file stores durable development rules that are too detailed for AGENTS.md.
AGENTS.md remains the control entrypoint and pointer owner.

## Run Initialization

Every development run MUST reload AGENTS.md, VERSION, CHANGELOG.md, COMMAND_PROTOCOL.md, docs/ROADMAP.md, docs/KNOWN_LIMITATIONS.md, and every existing pointer in AGENTS.md Current Development State.

Every run MUST create `artifacts/dev<target_version>_<stage>/agent_context_digest.md` before implementation, code edits, documentation edits, test execution, or completion reporting.

If AGENTS.md conflicts with the current user request, STOP and report the conflict.

## File Discovery

- Confirm a file exists before editing it.
- If a requested path is missing, search by filename and semantic role.
- Use a replacement only when it satisfies the same architectural purpose.
- Create a new file only when no existing file satisfies the purpose.
- Report requested files, existing files, missing files, replacements, new files, and reasons.
- Do not write nonexistent path pointers into AGENTS.md.

## Evidence Integrity

- Runners collect evidence; verifiers decide PASS/FAIL.
- Runner self-PASS is forbidden.
- Synthetic, mock, diagnostic-only, placeholder, file-existence-only, documentation-only, NOT_RUN, SKIP, SKIP_ENVIRONMENT, NOT_IMPLEMENTED, and PARTIAL results are not PASS.
- Missing evidence is FAIL_EVIDENCE_MISSING.
- Inconclusive validation is INCONCLUSIVE.
- Invalidated evidence cannot support current PASS or readiness.

## Completion Criteria

A requested feature is complete only when required code/config/docs are updated, command/API/schema integration exists if applicable, targeted local tests pass, version-level regression does not break trusted behavior, and artifacts record the result.

Partial work MUST be reported as PARTIAL or NOT_IMPLEMENTED with reason.

## Testing Protocol

For multi-feature versions:

1. Implement one feature.
2. Run its targeted test.
3. Record the result.
4. Continue feature by feature.
5. Run version-level tests after all features are complete.

Version-level tests SHOULD include build, version, relevant command/API tests, positive tests, negative tests, malformed input tests, boundary tests, regression tests, JSON/JSONL parsing where applicable, markdown fence validation, encoding/mojibake scan, COMMAND_PROTOCOL consistency, evidence integrity scan where applicable, and git status snapshot.

SKIP_ENVIRONMENT is allowed only with an explicit environment reason and MUST NOT be marked PASS.

## Runner / Verifier Split

Evidence-generating scripts SHOULD write raw command output, logs, traces, screenshots, result JSON, and timestamps.

Verifier/selftest scripts SHOULD independently inspect the evidence and write a verifier report or selftest report.

Final version readiness MUST be based on verifier/selftest outcome, not runner intent.

## Final Report Protocol

Every final report MUST state:

- current version
- stage objective
- modified files
- completed features
- incomplete features
- features not implemented
- blockers
- tests and command results
- file discovery summary
- pointer validation result
- evidence pointer result
- artifacts path
- git status summary

