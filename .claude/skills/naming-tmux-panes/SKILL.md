---
name: naming-tmux-panes
description: Use when working with multiple tmux panes (e.g. a supervisor pane plus worker panes) and they are hard to tell apart because they only show opaque IDs like %0 / %10, or when setting up any multi-pane tmux layout that a human will watch.
---

# Naming tmux Panes

## Overview

tmux panes default to opaque IDs (`%0`, `%10`). A human watching a multi-pane layout can't tell which is the supervisor and which is which worker. Give each pane a **title** and display it on the pane border. Do this at pane-creation time, not as an afterthought.

## Quick Reference

```bash
# 1. Title each pane (do this right after creating it)
tmux select-pane -t "$PANE_ID" -T 'SUPERVISOR (%0)'
tmux select-pane -t "$WORKER_ID" -T 'WORKER #{{ISSUE_NUM}} (wt-{{ISSUE_NUM}})'

# 2. Show titles on the pane border (global, once per session)
tmux set -g pane-border-status top
tmux set -g pane-border-format ' #{pane_title} '

# 3. Stop shells / TUIs from overwriting your titles via OSC escapes
#    Without this, the shell prompt and apps like Claude Code keep rewriting
#    pane_title to whatever they want (e.g. `claude | wt-{{ISSUE_NUM}}*`), defeating
#    your custom labels.
tmux set -g allow-rename off
tmux set -g automatic-rename off

# 4. Optional: name the window too
tmux rename-window '{{PROJECT_NAME}}-#{{ISSUE_NUM}}'

# 5. Verify
tmux list-panes -F '#{pane_id} title=[#{pane_title}] #{pane_current_path}'
```

`split-window` accepts the title inline so naming is never forgotten:

```bash
WORKER_ID=$(tmux split-window -h -P -F '#{pane_id}' -c "$WORKDIR")
tmux select-pane -t "$WORKER_ID" -T "WORKER #{{ISSUE_NUM}} (wt-{{ISSUE_NUM}})"
```

## Naming Convention

Make the title answer "what is this pane for?" at a glance:

- Role + identifier: `SUPERVISOR (%0)`, `WORKER #{{ISSUE_NUM}} (wt-{{ISSUE_NUM}})`
- Include the issue/PR number and worktree dir when relevant — that is what the human is tracking.
- Keep it short; the border truncates.

## Critical Gotcha

**Titles are for humans only. Automation must still key off pane IDs, not titles.** Monitoring/intervention (capture-pane, send-keys) must resolve the target by stored pane ID (e.g. `cat /tmp/wt-pane{{ISSUE_NUM}}.id`), because titles are cosmetic, not unique, and a user may rename them. Renaming a pane title must never break the supervisor's targeting.

## Common Mistakes

- Setting titles but forgetting `pane-border-status top` → titles set but invisible.
- Naming panes "later" → you forget; name at creation in the same step that captures the pane ID.
- Driving send-keys/capture-pane by title or pane index instead of the stored pane ID → breaks when layout or titles change.
- **Forgetting `allow-rename off` / `automatic-rename off`** → your `select-pane -T` titles get overwritten seconds later by the shell's OSC title escape (e.g. `claude | wt-{{ISSUE_NUM}}*`). The title you set survives only until the next prompt or TUI redraw. Disable both options before titling, or accept that your labels won't stick.
