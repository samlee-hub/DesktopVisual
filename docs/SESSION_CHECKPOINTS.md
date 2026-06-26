# Session Checkpoints

Current version: `v3.3.7`.

DesktopVisual v3.3.7 adds task-session checkpoints and loop guard stops for long-running `run-task` workflows.

Checkpoint records are audit anchors, not rollback guarantees. Actions that already sent a message, submitted a form, changed a remote service, or modified external state cannot be automatically undone by a checkpoint.

## SessionCheckpoint

Each checkpoint records:

- `checkpoint_id`
- `timestamp`
- `permission_mode`
- `task_id`
- `step_index`
- `window_title`
- `process_name`
- `url`
- `screenshot_path`
- `observed_summary`
- `recent_actions`
- `form_state_summary`
- `suggested_recovery_actions`

Temporary checkpoint files are written during the task and removed at session end when `cleanup_on_end=true`. The Markdown task report keeps the summary under `## Session Checkpoints`.

## Triggers

TaskRunner records checkpoints:

- at session start
- every configured `checkpoint.interval_ms`
- when a `checkpoint` task step is executed
- after a completed page marker (`page_id`)
- before submit, send, or window-switch actions
- before unsupported or unknown task states
- when a loop guard stops the task

## Loop Guard

TaskRunner stops instead of continuing when it detects:

- same action repeated beyond `loop_guard.repeated_action_limit` -> `REPEATED_ACTION_LIMIT`
- same URL repeated beyond `loop_guard.url_redirect_limit` -> `URL_REDIRECT_LOOP`
- same observed summary repeated beyond `loop_guard.no_progress_limit` -> `NO_PROGRESS_DETECTED`
- repeated window-open marker beyond `loop_guard.window_spawn_limit` -> `WINDOW_SPAWN_LOOP`
- scroll with no new observed summary beyond `loop_guard.scroll_no_progress_limit` -> `SCROLL_NO_PROGRESS`
- exceeded task `budget.max_steps` or `budget.max_duration_ms` -> `LOOP_GUARD_STOP`

Loop guard stops are final for the current run. The user or calling agent should read the latest checkpoint summary, re-observe the target, and resume only with an explicit corrected task plan.
