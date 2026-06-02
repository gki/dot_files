#!/bin/sh
input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd')

# role バッジ: agent.name が supervisor を含む場合、または tmux pane が supervisor の場合に表示
role_badge=""
is_supervisor=0

# 1) --agent フラグで起動した場合: JSON の agent.name を確認
agent_name=$(echo "$input" | jq -r '.agent.name // empty')
case "$agent_name" in
  *[Ss][Uu][Pp][Ee][Rr][Vv][Ii][Ss][Oo][Rr]*) is_supervisor=1 ;;
esac

# 2) tmux 環境: マーカーファイル・pane %0・タイトルに supervisor を含む場合
if [ "$is_supervisor" = "0" ] && [ -n "$TMUX_PANE" ]; then
  if [ -f "/tmp/claude-supervisor-$TMUX_PANE" ]; then
    is_supervisor=1
  elif [ "$TMUX_PANE" = "%0" ]; then
    is_supervisor=1
  else
    pane_title=$(tmux display-message -p -t "$TMUX_PANE" '#{pane_title}' 2>/dev/null)
    case "$pane_title" in
      *[Ss][Uu][Pp][Ee][Rr][Vv][Ii][Ss][Oo][Rr]*) is_supervisor=1 ;;
    esac
  fi
fi

if [ "$is_supervisor" = "1" ]; then
  role_badge=$'\033[41;37;1m SUPERVISOR \033[0m '
fi

# ホームディレクトリを ~ に置換
home="$HOME"
display_cwd=$(echo "$cwd" | sed "s|^$home|~|")

# git ブランチ情報（オプショナル）
branch=""
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    branch=" [$branch]"
  fi
fi

time_str=$(date +%H:%M:%S)

# コンテキストウィンドウ使用率
ctx_used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
ctx_str=""
if [ -n "$ctx_used" ]; then
  ctx_str=$(printf " ctx:%.0f%%" "$ctx_used")
fi

# 5時間トークン制限
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_str=""
if [ -n "$five_pct" ]; then
  five_str=$(printf " 5h:%.0f%%" "$five_pct")
fi

# 7日間トークン制限
week_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
week_str=""
if [ -n "$week_pct" ]; then
  week_str=$(printf " 7d:%.0f%%" "$week_pct")
fi

printf "%s\033[38;5;7m%s\033[0m %s\033[36m%s\033[0m\033[33m%s%s%s\033[0m" "$role_badge" "$time_str" "$display_cwd" "$branch" "$ctx_str" "$five_str" "$week_str"
