# Hybrid Perception Runtime

Current version: `v4.7.0`.

DesktopVisual v4.x is a Hybrid Screen Perception Runtime. It combines local Windows runtime signals into structured, auditable perception records. It is not a complete autonomous Agent and does not claim complete understanding of arbitrary screens.

## Scope

v4.x provides:

- `ScreenFrame`
- `ElementGraph`
- `LocatorCandidate`
- `SceneState`
- `ChangeEvent`
- `observe2`
- Provider Registry and `perception_sources`
- Screen Delta and Perception Cache accounting
- ROI OCR hooks
- image-template visual source candidates
- `observe-loop` JSONL event streams
- Dynamic UI Recovery routes
- App Profile metadata integration

v4.x does not provide:

- Full v5 task-level continuous execution.
- Real VLM integration.
- OmniParser, YOLO, UGround, ONNX, GPU, Python, or model-weight deployment.
- Real-account web benchmarks.
- Permission bypass through visual or profile metadata.

## observe2 Contract

`observe2` is read-only. It returns the normal command envelope and a `data` object containing:

```json
{
  "schema_version": "4.4.0",
  "screen_frame": {},
  "element_graph": {
    "nodes": []
  },
  "locator_candidates": [],
  "scene_state": {
    "status": "normal"
  },
  "change_events": [],
  "providers": [],
  "perception_sources": []
}
```

The schema version is the perception-output contract version, not necessarily the product version.

## Provider Registry

The registry reports local and future provider availability. v4.7 expects these names to be stable:

- `uia`
- `ocr`
- `screen_delta`
- `image_template`
- `local_visual_provider`
- `cloud_vlm`
- `agent_provider`

Provider status may be `available`, `unavailable`, or `degraded`. Missing OmniParser/YOLO/UGround/VLM providers must degrade gracefully and must not crash `observe2`.

## Visual Candidate Contract

Visual source candidates must normalize into `ElementGraph` nodes or `LocatorCandidate` entries with at least:

- `source`
- `source_version`
- `label`
- `role`
- `text`
- `rect`
- `confidence`
- `attributes`
- `artifact_path`
- `provider_latency_ms`
- `semantic_status`

Image-template candidates are visual-only and unresolved by default unless another source or explicit profile context provides semantic support.

## SceneState

Known scene states are:

- `normal`
- `loading`
- `dialog_open`
- `error`
- `success`
- `blocked`
- `unknown`

`blocked` is a hard stop. `unknown` is not safe to auto-click.

## ChangeEvent

Known v4 event types include:

- `window_changed`
- `foreground_changed`
- `region_changed`
- `text_changed`
- `element_appeared`
- `element_disappeared`
- `dialog_opened`
- `dialog_closed`
- `loading_started`
- `loading_finished`
- `error_appeared`
- `success_appeared`
- `element_moved`
- `element_enabled`
- `element_disabled`
- `target_ready`
- `safety_blocked`

Events are evidence for upper layers. They do not authorize input by themselves.

## Action Gate

Visual providers and App Profiles can produce candidates and metadata only. They cannot click, type, submit, send, browse, unlock permissions, or change Safety Manifest behavior.

The ActionExecutor gate must block unresolved visual-only selectors:

```text
ACTION_BLOCKED_SEMANTIC_UNRESOLVED
```

Captcha, anti-cheat, protected desktop, credential, payment, and high-risk authentication surfaces stop. They are not routed to VLM for bypass.

## App Profiles

App Profiles can add application-specific locators, ROIs, visual strategy, OCR strategy, recovery hints, and confirmation nodes. They are not Permission Profiles and cannot grant permissions.

Profile-derived locator metadata uses:

```text
action_gate=requires_runtime_safety_policy
```

## Release Boundary

`D:\desktopvisual` is the local development and evaluation tree. Public release must be prepared separately under `D:\desktopvisual-release`, with restricted public permissions and without large generated artifacts, browser profiles, private paths, model weights, or broad developer-only assessment permissions.
