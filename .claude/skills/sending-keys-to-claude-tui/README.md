# sending-keys-to-claude-tui — プレースホルダ一覧

SKILL.md 内の `{{...}}` を、プロジェクトの実際の値に置き換えてください。

| プレースホルダ | 置き換える内容 | 例 |
|--------------|--------------|-----|
| `{{NN}}` | worker / issue 番号（pane id ファイル名に埋め込む） | `/tmp/wt-pane58.id` なら `58` |

## 補足

- `/tmp/wt-pane{{NN}}.id` というファイル命名規約は supervisor 側 (`supervising-worker-panes` skill) と揃える
- `$P`, `$MSG`, `$WORKDIR` などは shell 変数で実行時に埋める
- `<session-id>`, `<path>` などはランタイム値（`claude --resume` 復旧時に pane の farewell 行から取り出す）

## 関連スキル

- `naming-tmux-panes` — pane の見た目だけのタイトル付け（実行ターゲットは必ず pane id）
- `supervising-worker-panes` — supervisor 側で本 skill を呼ぶ場面
