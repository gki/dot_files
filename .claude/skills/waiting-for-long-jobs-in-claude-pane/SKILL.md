---
name: waiting-for-long-jobs-in-claude-pane
description: Use when a Claude Code session running inside a tmux pane must wait minutes (long build / full test regression, CI poll, long deploy) for a command to finish, and the temptation is to background-and-idle-wait — because a Claude TUI in a tmux pane can time out and exit during long inactivity, taking its background children with it.
---

# Waiting for Long Jobs Inside a Claude TUI Pane

## Overview

A Claude TUI hosted in a tmux pane can **exit on prolonged inactivity** (e.g. 30+ minutes of "waiting for a background job to finish"). When it exits, its child bash processes are typically **orphaned and killed**, so the very job you were waiting on disappears with you. Recovery costs another full test cycle.

**Core principle: never pure-idle-wait. Either keep the TUI active with a stream of events (Monitor), or block synchronously and accept the timeout.**

## When This Bites

You launched something like:

```
Bash({{LONG_BUILD_COMMAND}})  # run_in_background: true
```

and then said "I'll wait for the harness to wake me when it finishes." 5–10 minutes is usually fine. 30+ minutes is where sessions start dying. The bottom of the pane shows `Cooked for 35m, 1 shell still running` — then the next time you look it's an OS shell prompt and `Resume this session with: claude --resume <id>`. The "1 shell still running" became zero somewhere along the way.

## Worker vs Supervisor Context (Critical Distinction)

This skill's "no pure-idle-wait" rule is for **worker sessions** — implementation Claude TUIs hosted in tmux panes that go untouched by humans for tens of minutes at a time. They die from inactivity. Patterns A/B/C apply.

A **supervisor session** is different: it is the user-facing Claude that the human is actively conversing with. The conversation itself keeps it alive — every user turn and tool call resets the inactivity clock. From a supervisor, `Bash(run_in_background: true)` for a long job is **safe**, because:

- the harness notifies the supervisor on completion as a `<task-notification>` event,
- the user's ongoing conversation prevents the supervisor from timing out before that event arrives, and
- the supervisor can do useful parallel work in the meantime (checking PR status, drafting next steps).

Quick self-classification:

| Signal | You are |
|---|---|
| You were dispatched into a worktree with a self-contained prompt and no user is talking to you | Worker — apply Patterns A/B/C |
| The user is in the loop, sending messages, and you sometimes await their input | Supervisor — `run_in_background` + parallel work is fine |
| You run inside a tmux pane a separate supervisor monitors via `tmux capture-pane` | Worker |
| You launch other Claude sessions and watch them via tmux | Supervisor |

If unsure, default to the worker discipline — it's strictly safer.

## The Three Safe Patterns (worker context)

Pick by how the underlying command behaves.

### A. Foreground with `timeout` — preferred for bounded commands

```bash
timeout 600 {{LONG_BUILD_COMMAND}} 2>&1 | tail -200
```

You block (via the OS `timeout(1)` coreutils command — not the Bash tool's own timeout), the TUI is treated as actively running a tool call, the harness keeps the session alive. Use this whenever the upper bound is known and ≤ the Bash tool's own timeout cap (default 2 min, max 10 min). The OS `timeout` wrapper bounds the child process so it dies if it overruns; the Bash tool's cap bounds the parent invocation. Both need to be respected — match `timeout 600` to a Bash tool call run with the explicit `timeout: 600000` parameter. Simplest, hardest to get wrong.

> **macOS note**: BSD userland does not ship `timeout(1)`. Install via `brew install coreutils` (provides `gtimeout`, which you can alias as `timeout`), or skip the OS wrapper and rely on the Bash tool's `timeout: 600000` parameter alone. Without the OS wrapper the child can still overrun until the parent tool call is killed; with it, the child dies precisely at the deadline.

### B. Monitor on a streaming stdout — preferred for >10 min jobs that emit progress

```
Monitor(
  command="{{LONG_BUILD_COMMAND}} 2>&1 | grep --line-buffered -E '{{PROGRESS_PATTERN}}|PASS|FAIL|error:|elapsed'",
  description="long-running job progress",
  persistent: true
)
```

Each matching line becomes a `<task-notification>`. Your TUI receives events at roughly the job's emission rate, so it never sits idle long enough to time out. Cover failure signatures, not just success — `grep "PASS"` alone goes silent on a crash. See the Monitor tool's own "Coverage — silence is not success" guidance.

### C. `until`-loop polling — for binary state changes (file exists, status flips)

```bash
# Test on jq's stdout ("true"/"false"), NOT on the command exit status.
# `gh pr checks` returns exit 0 even while runs are still pending, which would
# make a `>/dev/null` form exit the loop on the very first iteration.
until [ "$(gh pr checks {{PR_NUM}} --json bucket --jq 'all(.[]; .bucket!="pending")')" = "true" ]; do
  sleep 30
done
```

Block in foreground, polling at a sensible interval. Same liveness story as Pattern A.

## Anti-Patterns to Reject

| Pattern | Why it's wrong |
|---|---|
| **(worker)** `Bash(run_in_background: true)` + "wait for harness wake" with no Monitor armed | The harness wakes you on completion *if you survive that long*. 30+ min idle → session timeout → child killed → nothing wakes. **(Supervisor with active user conversation: this is fine, see context section.)** |
| `sleep 30 && check ...` chains | The harness blocks these; even if it didn't, you'd still be idle between checks. |
| Plain `cmd &` in a Bash tool call | Detached from the tool, no notification, no liveness. Worst of all worlds. |
| **(worker)** "I'll just check back in 20 minutes" with no scheduled tick | You may not be alive in 20 minutes. **(Supervisor: ok if the user keeps the conversation moving.)** |

## Red Flags

- **(worker)** The thought "the harness will wake me when it's done" — only true if something is actively streaming events (Monitor) or you're blocking in foreground. Bare `run_in_background` does not keep you alive.
- **(worker)** Pane bottom shows `Cooked for Xm Ys · N shells still running` for many minutes with no `Monitor event:` lines or new `⏺` activity above — you're idle-waiting and at risk.
- **(worker)** Background bash you started ≥ 15 minutes ago and you've made no other tool calls since — either start a Monitor on its log or switch to a blocking re-invocation.
- "I'm probably a supervisor, so the rules don't apply" without confirming via the quick self-classification table — when in doubt, default to worker discipline.

## If You're Already Dead

If a supervisor wakes you with "your previous session exited and your background job was killed," do not assume the job's results are recoverable. Re-run the verification step from scratch using Pattern A or B. See `sending-keys-to-claude-tui` for the supervisor side of dead-TUI detection and `claude --resume` recovery.
