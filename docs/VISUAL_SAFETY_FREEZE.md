# Visual Safety Freeze

Current version: `v3.0.5`.

Status: frozen-compatible with real Windows OCR in v2.0.0.

This document freezes the safety boundary and failure-stop rules for visual locator features, including UI Automation, OCR, and image/template location.

## Allowed Use

1. Authorized developer test windows.
2. User-confirmed Windows application windows.
3. UI testing, report generation, and reproducible case execution.
4. OCR only as a supplemental locator for self-drawn UI or windows without accessible controls.
5. Image/template location only when it keeps these rules.

## Prohibited Use

1. Security-control bypass or human-verification bypass.
2. Unauthorized game automation or platform risk-control bypass.
3. Unauthorized classroom or workflow automation.
4. Credential extraction, security-control bypass, or protected desktop automation.
5. Controlling windows that the user has not authorized.

## Locator Priority

1. Prefer case files and deterministic assertions.
2. Prefer UI Automation over OCR.
3. Use OCR only when UI Automation is unavailable or insufficient.
4. Use image/template matching only when UIA and OCR cannot represent the target and the user has authorized the window.

## Required Match Rules

1. The target window title must resolve to exactly one visible top-level window.
2. UIA element lookup must resolve to exactly one element.
3. OCR text lookup must resolve to exactly one text box.
4. Image/template lookup must resolve to exactly one match.
5. Zero matches or multiple matches are failures.
6. OCR commands must first resolve a unique authorized target window and pass the configured title/process safety policy before reading or clicking text.

## Failure Stop Rules

0. Stop on every visual locator failure.
1. On any locator failure, the agent must stop.
1. Do not click nearby positions to guess intent.
2. The agent must not click nearby positions to guess intent.
3. The agent must not retry with broader titles, alternate windows, or different locator methods unless the user confirms.
4. The agent must not switch from UIA to OCR or from OCR to image/template matching after failure without user confirmation.
5. The agent must not perform any input action after a locator failure.

## Required Failure Report Fields

Every visual locator failure must preserve enough detail for review:

1. `error_code`
2. `locator_method`
3. requested window title
4. requested element, text, or template target
5. match count if known
6. whether any input action was executed
7. report path or artifact path

## Skill Behavior

1. Read command JSON and case reports before summarizing.
2. Treat any non-empty `error.code` or report `error_code` as a stop condition.
3. Explain the failure in user-facing language.
4. Preserve report and artifact paths.
5. Request user confirmation before continuing.

## v0.3.3 Entry Gate

Do not start Image Template Location until:

1. this document exists in the release package,
2. `docs\SAFETY.md` references these rules,
3. `docs\AGENT_USAGE_GUIDE.md` references these rules,
4. the Skill template references these rules,
5. selftest verifies the freeze text is present.
