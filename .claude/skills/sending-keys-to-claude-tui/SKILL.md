---
name: sending-keys-to-claude-tui
description: Use when injecting a message or command into a Claude Code (or other Ink/React TUI) session running in a tmux pane and it does not submit — text stays in the input box, Enter is absorbed as a literal newline, or a supervisor's instruction to a worker pane is silently lost.
---

# Sending Keys to a Claude Code TUI in tmux

## agmsg-first ポリシー（2026-06 以降）

**agmsg がインストール済みの場合、send-keys の用途を以下に限定する:**

- TUI 生死確認（capture-pane で `❯` の有無を確認）
- ダイアログ・選択肢への応答（y/n、番号入力）
- claude 初回起動コマンド送信
- **worker への最初の1通**（agmsg join 指示を含む）

**それ以外の全メッセージは agmsg 経由で送る（短文でも同様）。**

理由: SQLite 経由で長文・日本語・特殊文字が壊れない。履歴が残る。非同期で溜められる。

### agmsg の使い方

```bash
# supervisor から worker へ送信
~/.agents/skills/agmsg/scripts/send.sh <team> supervisor worker "<メッセージ>"

# 受信確認
~/.agents/skills/agmsg/scripts/inbox.sh <team> supervisor
```

worker 初回起動テンプレート（send-keys で送る **最初の1通** に含める）:

```
agmsg join <team-name> worker claude-code <worktree-path>
agmsg mode monitor
```

agmsg インストール確認: `ls ~/.agents/skills/agmsg/scripts/send.sh 2>/dev/null && echo installed || echo not installed`

---

## Overview

`tmux send-keys -t PANE "text" Enter` in a **single call** does NOT submit in Claude Code's TUI. The TUI debounces paste-like input; the trailing `Enter` arrives before the input box has committed the text, so it is absorbed (treated as a newline / dropped) and the message sits unsubmitted in the input box.

**Core principle: send the text, pause, then send Enter as a SEPARATE call.**

## STOP: Check Pane State BEFORE Sending (Critical)

`send-keys` blindly injects keystrokes. If the target pane is showing an **interactive dialog** (AskUserQuestion selection menu, permission prompt, y/n confirmation, `Select an option`), your text becomes filter input and your `Enter` **selects an option** — silently making a decision nobody authorized.

**Always `capture-pane` first and classify the state:**

| Pane bottom shows | State | Action |
|---|---|---|
| `❯ ` alone (empty input box) | Normal input | Safe to send |
| `❯ Press up to edit queued messages` | Busy, queue OK | Safe to send (queues) |
| Numbered choices / `Select` / `❯ 1.` / `(y/n)` / `Do you want to proceed?` | **Interactive dialog** | **DO NOT send.** Sending will mis-select. |
| `Interrupted · What should Claude do instead?` | Awaiting redirect | Safe to send |
| `Resume this session with: claude --resume <id>` + OS shell prompt (`$` / `%`) | **TUI exited (dead)** | **DO NOT keep sending instructions to a dead TUI.** Recover with `claude --resume <id>` first (see below). |

If a dialog is showing, the worker is **asking for a decision**. Read the question, decide deliberately, then send the *intended* answer — never let a generic instruction land as an accidental selection. If unsure, escalate to the human; do not guess by sending keys.

### Ghost suggestion: dimmed text after `❯` is NOT real input

`capture-pane -p` (plain) **strips all color**. A pane bottom like `❯ #108 に着手して` looks like the worker typed pending text into the input box — but it may be a **ghost suggestion** (autocomplete hint) the Claude Code TUI displays *when the input box is empty*. The input buffer is actually **empty**; the suggestion is just a visual hint.

Ghost suggestions render in **dim / faint** mode (SGR `\033[2m`). Real typed input renders at normal brightness. To tell them apart, capture **with escape sequences** and inspect:

```bash
tmux capture-pane -e -p -t "$P" | grep '❯' | od -c | head -20
```

Read the SGR codes around the text after `❯ `:

| Escape sequence around the text | Meaning |
|---|---|
| `\033[2m` or `\033[0;2m` … `\033[0m` (faint) | **Ghost suggestion** — input box is EMPTY |
| normal brightness (no faint SGR) | **Real typed text** — input box has pending content |

Implications:
- `❯ <dimmed text>` classifies the same as `❯ ` alone → **empty input box, safe to send**. No need to clear it first.
- `❯ <normal-brightness text>` → real pending content; clear it (see Stale-frame probe below) before sending a fresh instruction, or your text appends to it.
- Do not assume a worker "self-prompted" the next task just because plain `capture-pane` shows task-like text after `❯` — verify the brightness first.

## Recovering a Dead TUI

A long-running Claude TUI inside a tmux pane can exit on prolonged inactivity, or hard-crash (e.g. `ENOSPC` writing `~/.claude.json` when disk fills). The tell is the pane's last frame: `Resume this session with: claude --resume <session-id>` immediately followed by a plain OS shell prompt (`$` or `%`, no `❯`). The stale "Cooked for Xm Ys" line above it is the **last frame before exit**, not live activity — do not read it as alive.

Background bash children of the dead session are typically **killed too** (orphaned). Any "I started X in the background and was waiting" plan is gone with the session.

### Symptom variant: `^[c` left as literal text (farewell not visible yet)

A hard-crashed TUI sometimes leaves the **terminal reset escape sequence** (`ESC c`, rendered as `^[c`) sitting as literal text at the bottom of the pane, with **no shell prompt and no `Resume this session with:` line visible** (capture-pane returns just a JS stack trace ending with `^[c` and many blank lines). The TUI process is gone, but the shell hasn't redrawn its prompt yet.

To surface the farewell line:

```bash
tmux send-keys -t "$P" C-c    # nudge the shell to re-prompt
sleep 0.5
tmux send-keys -t "$P" Enter
sleep 0.5
tmux capture-pane -p -t "$P" | tail -5
# Now you should see:
#   ^C
#   Resume this session with:
#   claude --resume <session-id>
#   HH:MM:SS ~/path $   <-- live OS shell prompt
```

Once the shell prompt is visible and the session id is known, proceed with the normal `claude --resume <id>` recovery below.

### Standard recovery

```bash
# 1. Confirm the session id from the pane's farewell line
tmux capture-pane -p -t "$P" | grep -A1 'Resume this session with' | tail -2

# 2. Re-launch the same session in-place (preserves todos, plan, transcript)
tmux send-keys -t "$P" -l 'claude --resume <session-id>'; sleep 0.5
tmux send-keys -t "$P" Enter

# 3. If a "Resume from summary (recommended) / Resume full session" dialog
#    appears, the `❯` arrow defaults to option 1 (summary) — Enter alone
#    confirms it and saves tokens. Do not send other keys.

# 4. After the TUI reappears (capture-pane shows `❯` again), send a recovery
#    instruction that explicitly tells the worker which background jobs were
#    killed and what to redo. The worker has NO way to know its previous bg
#    process is gone.
```

`claude --resume` reconstitutes the conversation; it does NOT resurrect killed child processes. State that gap in the recovery message.

## The Reliable Pattern

```bash
P=$(cat /tmp/wt-pane{{NN}}.id)            # target pane id
tmux send-keys -t "$P" -l "$MSG"         # -l = literal: text only, no Enter
sleep 0.5
tmux send-keys -t "$P" Enter             # separate call submits it
sleep 0.5
tmux send-keys -t "$P" Enter             # second Enter: harmless, covers slow debounce
```

- `-l` sends the string literally (safe for backticks, Japanese, punctuation; no key-name parsing).
- The `sleep` between text and Enter is mandatory — without it the Enter is absorbed.
- A second Enter is a cheap safety net and does nothing if already submitted.

## Long / Multi-line Text: prefer `load-buffer` + `paste-buffer`

`send-keys -l "$MSG"` has two practical limits as `$MSG` grows:

1. Command-line argument size limit (`ARG_MAX`) — typically 256 KB on macOS, but
   shell expansion and quoting overhead reduces the usable size unpredictably.
2. Long argv strings sometimes get chunked by tmux in ways that interact badly
   with the TUI's paste debounce, splitting one logical paste into multiple
   bracketed paste events.

For **multi-line content**, **content containing real newlines**, or any
prompt longer than ~2 KB, route the payload through tmux's paste buffer
instead — it goes via stdin and avoids both limits:

```bash
P=$(cat /tmp/wt-pane{{NN}}.id)
printf '%s' "$MSG" | tmux load-buffer -        # stdin → tmux buffer 0
tmux paste-buffer  -t "$P"                     # buffer 0 → pane (bracketed paste)
sleep 0.5
tmux send-keys -t "$P" Enter
sleep 0.5
tmux send-keys -t "$P" Enter                   # safety-net Enter (same as -l pattern)
```

Notes:
- Use `printf '%s'` not `echo` — `echo` adds a trailing newline that becomes a
  premature submit on multi-line content.
- `paste-buffer` triggers tmux's bracketed-paste mode, which the Claude TUI
  reliably treats as a single paste event. Less likely to be split mid-stream
  than a giant `-l` argv.
- The pane-state check (empty `❯` vs dialog vs dead TUI) and the `Always
  Verify` capture-pane afterwards are still required — paste-buffer is a
  delivery mechanism, not a state-aware sender.
- For short single-line text (a slash command, a one-liner instruction),
  the `-l` pattern above is simpler — reach for `load-buffer` only when
  size or newlines justify it.

## Always Verify

Submission is not assumed — confirm it:

```bash
tmux capture-pane -p -t "$P" | tail -12
```

| Pane shows | Meaning |
|---|---|
| `❯ <your text>` still in input box | NOT submitted — send Enter again |
| `❯ Press up to edit queued messages` | Submitted, queued (worker busy) — success |
| input box empty / new activity | Submitted and processing — success |

A worker that is mid-turn will **queue** the message (`Press up to edit queued messages`) and process it after the current turn — this is success, not a stuck state.

### Stale frame: input box display ≠ actual input buffer

Occasionally `capture-pane` shows a leftover input string (e.g. `❯ rm -rf build && retry tests`) that backspace / `C-u` / `C-a`+`C-k` appear to NOT clear — but the buffer is actually empty and the line is just a stale frame the TUI hasn't redrawn.

To distinguish stale display from a real residual buffer, **probe with a single test character**:

```bash
tmux send-keys -t "$P" "X"; sleep 0.5
tmux capture-pane -p -t "$P" | tail -3
# If display now shows `❯ X` (just the probe char) → buffer was empty all along
# If display shows `❯ <old text>X` → buffer really did still have the old text
```

After confirming, BSpace once to remove the probe and proceed. Otherwise long instructions get prefixed with `X` or, worse, appended after the stale string and submit a wrong command.

## Common Mistakes

- **One-shot `send-keys "text" Enter`** → the original bug. Always split.
- **No delay** → Enter races the debounce and is lost.
- **Not verifying** → silent loss; the supervisor believes the worker was instructed when it wasn't.
- **Using `"$MSG"` without `-l`** when the message contains key names (`Enter`, `C-c`) or starts with `-` → tmux misparses. Prefer `-l`.
- **Embedded real newlines in `$MSG`** → each newline can submit early. Send multi-line instructions as one line, or send body with `-l`, then a single Enter.

## Red Flags

- "I sent it, moving on" without a capture-pane check → STOP, verify.
- Text visible after `❯` in the captured pane → NOT submitted, send Enter again.
- Sending without a capture-pane check FIRST → you may blast keys into a dialog and auto-select. Always check state before sending.
- Pane shows a question/menu and you send a generic instruction anyway → that instruction becomes an answer to a question you didn't read. STOP, read the dialog, answer deliberately.
- **Judging liveness by elapsed time / last activity line alone** (e.g. "Cooked for 35m, 1 shell running") → the pane's status line is whatever was on screen *when the TUI exited*. Always check the **bottom-most line** for `❯` (alive) vs OS shell prompt + `Resume this session with:` (dead). Time-based liveness checks miss session timeouts.
