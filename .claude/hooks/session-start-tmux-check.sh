#!/bin/bash
# SessionStart hook: tmux 環境を検出し、自分の pane / session / ユーザー attach 先を Claude に通知する。
# 設定: ~/.claude/settings.json の hooks.SessionStart で起動。
# 出力: SessionStart hookSpecificOutput.additionalContext (Claude の最初のターンに注入される)。

if [ -z "$TMUX" ]; then
  ctx="【tmux 環境検出】tmux 配下ではありません。通常の単独セッションとして動作 (worker 派遣・supervisor ルールは適用外)。"
else
  my_pane="$TMUX_PANE"
  my_session=$(tmux display-message -p '#{session_name}' 2>/dev/null || echo "?")
  # 自分の session にアタッチしているクライアントが存在するか確認
  my_session_client_count=$(tmux list-clients -F '#{client_session}' 2>/dev/null | grep -c "^${my_session}$" || echo 0)
  if [ "$my_session_client_count" -gt 0 ]; then
    # 自分の session にクライアントがいる → ユーザーは同一 session にいる
    user_session="$my_session"
  else
    # 自分の session にクライアントがいない → 他の session を探す
    user_session=$(tmux list-clients -F '#{client_session}' 2>/dev/null | head -1)
    [ -z "$user_session" ] && user_session="(no client attached)"
  fi

  if [ "$my_session" = "$user_session" ]; then
    visibility="✅ 同一 session — 私が tmux split-window で作る pane はユーザーから見える"
  else
    visibility="⚠️ 別 session — 私が tmux split-window で作る pane はユーザーから見えない。worker 派遣前に必ず ユーザー session ($user_session) 内の pane を target にして split するか join-pane で移動すること"
  fi

  # supervisor 判定: 慣例的に %0 が supervisor、または pane title に SUPERVISOR を含む
  my_title=$(tmux display-message -p '#{pane_title}' 2>/dev/null || echo "")
  role_hint=""
  if [ "$my_pane" = "%0" ]; then
    role_hint=" / pane=%0 のため SUPERVISOR の慣例位置"
  elif echo "$my_title" | grep -qi 'supervisor'; then
    role_hint=" / pane title に supervisor を含むため SUPERVISOR 役"
  fi

  # supervisor 役の視覚表示は Claude statusLine 側 (~/.claude/statusline-command.sh) が
  # $TMUX_PANE / pane_title を見て SUPERVISOR バッジを出すので、ここでは tmux 視覚設定を弄らない

  ctx="【tmux 環境検出】配下で稼働中
- my_pane=$my_pane / my_session=$my_session$role_hint
- user_attached_session=$user_session
- $visibility

参照ルール:
- supervisor 役なら memory [[feedback_supervisor_no_code_edit]] 適用 → どんなに小さい変更でも worker 派遣 (supervisor pane でコード編集禁止)
- worker 派遣は skill [[supervising-worker-panes]] の Setup を厳守、特に「ユーザーが見ている session 内で tmux split-window」必須
- 長 bg job (deploy / scan / xcodebuild test) は memory [[feedback_supervisor_use_tmux_for_bg]] により Bash run_in_background ではなく tmux pane を使う"
fi

# Claude Code SessionStart hook 仕様: hookSpecificOutput.additionalContext を JSON で返す
jq -n --arg ctx "$ctx" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
