# naming-tmux-panes — プレースホルダ一覧

SKILL.md 内の `{{...}}` を、プロジェクトの実際の値に置き換えてください。

| プレースホルダ | 置き換える内容 | 例 |
|--------------|--------------|-----|
| `{{PROJECT_NAME}}` | プロジェクト識別名（tmux window 名に使う） | `myapp`, `myproject` |
| `{{ISSUE_NUM}}` | worker が対応している issue / PR 番号 | `58`, `123` |

## 補足

- worker 1 体に対して 1 つの `{{ISSUE_NUM}}` を割り当てる前提
- supervisor pane は別表記（例: `SUPERVISOR (%0)`）でそのまま使う
- `pane_title` は装飾用、`pane_id` は識別用 — 自動化（capture-pane / send-keys）は必ず pane_id 経由

## 関連スキル

- `supervising-worker-panes` — pane 作成のセットアップ全体
- `sending-keys-to-claude-tui` — 命名済み pane への指示送信
