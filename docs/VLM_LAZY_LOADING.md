# DesktopVisual VLM Lazy Loading

Current version: `v1.1.10`.

Current provider path:

```text
winagent.exe vlm-capability-probe / vlm-assist-locate
  -> RealVlmRuntimeBridge
  -> tools\codex_vlm_provider.ps1
  -> codex exec --image <png>
```

## Why Lazy Loading

Runtime-only commands must not pay VLM provider startup cost. Metadata, no-action latency baseline, ordinary observe, UIA, OCR, foreground snapshot, and Runtime-only workflows can complete without provider discovery, so they report `vlm_probe_attempted=false` and do not start PowerShell or Codex VLM commands.

## Probe Rules

- `vlm_required=true`: explicit VLM capability command may probe.
- `vlm_assist_allowed=true`: explicit VLM assist locate may probe its capability gate.
- `vlm_required=false` and `vlm_assist_allowed=false`: no provider probe.
- Cache hit: no provider probe.
- Runtime-only path: no provider probe.

## Cache Rules

Capability cache is provider/session scoped under `artifacts\vlm_session_cache`.

- Positive cache stores `VLM_AVAILABLE`.
- Negative cache stores `VLM_UNAVAILABLE`, probe failure, invalid response, unsupported provider, or timeout-like failure.
- Positive TTL defaults to 86400 seconds.
- Negative TTL defaults to 300 seconds.
- Cache hit reports `vlm_cache_hit=true` and `vlm_cache_state=positive_hit` or `negative_hit`.
- Cache miss reports `vlm_cache_hit=false` and `vlm_cache_state=positive_miss_written` or `negative_miss_written`.

## Fast Degradation

Provider missing, `codex` missing, unsupported `codex exec --image`, wrapper failure, invalid probe JSON, and probe timeout return `VLM_UNAVAILABLE` quickly and write report evidence. Non-required VLM assist paths set `vlm_degraded_to_runtime_only=true` and do not execute Runtime actions.

## Timeout Rules

Capability probe timeout is separate from actual VLM inference timeout.

- Default capability probe timeout: 12000 ms.
- Default actual VLM locate/inference timeout: 60000 ms.
- Wrapper metadata checks for `codex --version` and `codex exec --help` are bounded by a shorter metadata timeout.
- Capability probe timeout is configurable through `--timeout-ms` on `vlm-capability-probe` and `--probe-timeout-ms` on `vlm-assist-locate`.

## Report Fields

v1.1.5 reports:

- `vlm_probe_attempted`
- `vlm_probe_ms`
- `vlm_cache_hit`
- `vlm_cache_state`
- `vlm_provider_startup_ms`
- `vlm_exec_ms`
- `vlm_total_ms`
- `vlm_unavailable`
- `vlm_timeout`
- `vlm_required`
- `vlm_assist_allowed`
- `vlm_used_for_action`
- `vlm_degraded_to_runtime_only`
- `vlm_probe_reason`
- `vlm_skip_reason`

When VLM is not probed, `vlm_probe_attempted=false` and `vlm_skip_reason` is explicit, such as `not_required`, `runtime_only_path`, `cache_negative`, or `cache_positive_not_needed`.

## Non-Goals

v1.1.10 keeps the v1.1.5 VLM lazy/cache/degrade behavior unchanged. It does not add OpenAI or Anthropic native APIs, does not add daemon/service mode, does not replace the PowerShell provider wrapper, does not change VLM timeout, does not optimize VLM waits, does not reduce permissions, and does not sync `desktop_release`.
