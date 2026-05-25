# supervising-worker-panes — プレースホルダ一覧

SKILL.md 内の `{{...}}` を、プロジェクトの実際の値に置き換えてください。

| プレースホルダ | 置き換える内容 | 例 |
|--------------|--------------|-----|
| `{{HUNG_PROCESS_PATTERN}}` | `ps` / `pkill` に渡す hung プロセス検出パターン | iOS: `xcodebuild\|xctest` (kill 時: `xcodebuild.*<UDID>`)<br>Node: `node.*jest`<br>Rust: `cargo test` |

`/tmp/wt-paneNN.id` の `NN` は worker 1 体ごとに割り当てる識別番号（issue / PR 番号など）です。

## 適用例: iOS / Xcode プロジェクトでの使い方

### hung 判定

```bash
ps -eo pid,etime,command | grep -iE 'xcodebuild|xctest' | grep -v grep
```

unit test が数十秒〜数分の想定で `etime` が 30 分超なら確実に hung。worker pane 表示の経過時間は参考にせず、OS プロセスで裏取り。

### hung プロセスの kill（worker に指示する例）

```bash
pkill -f 'xcodebuild.*<UDID>'
```

### 並列 worker でのシミュレータ UDID 衝突回避

- 各 worker prompt に専有 UDID を埋める（`.worker-prompt.md` テンプレに必須項目として明記）
- DerivedData は別 path に分けるか、`xcodebuild -derivedDataPath` で隔離

## 前提

- `tmux` と複数 pane が使える
- `naming-tmux-panes`, `sending-keys-to-claude-tui`, `waiting-for-long-jobs-in-claude-pane`, `worktree-cleanup` skill が同 repo に導入されている
- `CronCreate` / `CronDelete` / `PushNotification` / `SendUserFile` が使える環境
- supervisor 自身は `~/.claude/CLAUDE.md` / memory でコード編集禁止が定められていることが多い（任せた worker に編集させる）

## 関連スキル

- `naming-tmux-panes` — pane タイトル付け
- `sending-keys-to-claude-tui` — worker への指示送信
- `waiting-for-long-jobs-in-claude-pane` — worker 側の待機戦略（supervisor は別ルール）
- `supervisor-independent-verification` — worker 完了サマリ受領後の独立検証
- `worktree-cleanup` — 完了後の撤収
- `external-blocker-detection` — 「課金問題」「障害」を worker と独立確認
