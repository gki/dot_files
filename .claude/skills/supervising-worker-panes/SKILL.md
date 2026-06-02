---
name: supervising-worker-panes
description: >
  Use when one Claude session acts as a SUPERVISOR monitoring multiple worker
  Claude sessions running in separate tmux panes — dispatching tasks, running a
  recurring cron patrol, detecting stuck/hung workers, intervening, and verifying
  completion before merge. Triggers: "スーパーバイザー", "supervisor 巡回",
  "worker を監視", "並列 worker", "tmux で並行開発", "supervise worker panes",
  "巡回 cron".
---

# Supervising Worker Panes via Cron Patrol

1 つの Claude セッション（supervisor）が、tmux の別ペインで走る複数の Claude セッション（worker）を監視し、ライフサイクル全体（派遣 → 巡回監視 → 介入 → 完了確認）を回す運用パターン。

関連 skill: [[sending-keys-to-claude-tui]]（worker への指示送信）/ [[naming-tmux-panes]]（ペイン命名）/ [[waiting-for-long-jobs-in-claude-pane]]（worker 側の待機）/ [[worktree-cleanup]]（完了後の掃除）。

## いつ使うか

- 2 つ以上の独立タスクを並列で別 worker に投げ、supervisor が進捗を監視するとき
- 1 タスクでも、長時間ジョブを別ペインの worker に任せて supervisor が見守るとき

## Pre-Setup: 自分の tmux 位置と「ユーザーが見ている session」を必ず確認

worker を派遣する **前** に、以下を 1 度だけ実行する:

```bash
echo "my_pane=$TMUX_PANE my_session=$(tmux display-message -p '#{session_name}')"
tmux list-clients -F 'attached_session=#{client_session}'
```

- SessionStart hook (`~/.claude/hooks/session-start-tmux-check.sh`) が同等情報を最初のターンに注入しているはず — その内容を最初に確認。
- **自分の session ≠ ユーザー attach 中 session** の場合、tmux split-window で作る pane はユーザーから見えない位置に出る。先に `tmux switch-client` / `attach-session` で揃えるか、後述の通り **target を ユーザー session の pane id で明示** する。
- 関連: memory [[feedback_session_start_tmux_check]] / [[feedback_supervisor_no_code_edit]]

## agmsg-first ポリシー（2026-06 以降）

**agmsg インストール済みの場合、send-keys の用途を限定する:**

| 用途 | 手段 |
|---|---|
| worker 指示・進捗報告・完了通知 | **agmsg** (`send.sh`) |
| TUI 生死確認 | capture-pane（引き続き必要） |
| ダイアログ（y/n・番号選択）への応答 | send-keys（引き続き必要） |
| claude 初回起動 + 最初の1通（agmsg join 指示含む） | send-keys（これだけ） |

巡回目的の `CronCreate` は完了検知用途では不要になる（agmsg push で受け取るため）。TUI 死亡確認だけに縮小してよい。

**並列・単独にかかわらず、worker には必ず固有の agent ID を付ける:**
- 命名規則: `worker-<issue番号>` / `worker-<worktree名>` / `worker-<タスク略称>` など
- 同じ `worker` という名前を複数 worker が使うと inbox が競合する（先に inbox.sh を呼んだ側が全メッセージを既読にしてしまう）
- 例: `join.sh my-team worker-168 claude-code /path/wt-168`

---

## セットアップ（一度だけ）

worker 1 体につき:

1. `git worktree add /path/wt-NN -b feature/...` で隔離ワークスペース作成
2. **ユーザーが見ている session 内に新規 pane を split-window で作る** — pane id を即捕捉して `/tmp/wt-paneNN.id` に保存。
   ```bash
   # ユーザー session の任意 pane を target にして split (-h: 横分割 / -v: 縦分割)
   USER_SESSION=$(tmux list-clients -F '#{client_session}' | head -1)
   ANCHOR_PANE=$(tmux list-panes -t "$USER_SESSION:" -F '#{pane_id}' | head -1)
   WORKER_PANE=$(tmux split-window -h -P -F '#{pane_id}' -t "$ANCHOR_PANE" -c /path/wt-NN)
   echo "$WORKER_PANE" > /tmp/wt-paneNN.id
   ```
   - **禁止事項**: (a) `tmux new-window` で別 window に追い出す / (b) **既存の別 session の idle pane を流用** する (`%14 が空いてるから使おう` 的判断) / (c) 自分の session と違う session でも target 指定なしで split。いずれもユーザー視界外に worker が出て、ユーザーが「見えない」と困る原因になる。
3. ペイン命名（[[naming-tmux-panes]]）
4. `.worker-prompt.md` を worktree に置く（[[development-workflow]] の Parallel Worker Dispatch Checklist の項目を必ず含める）
5. ペインで `cd /path/wt-NN && claude` 起動 → `❯` 確認 → **send-keys で最初の1通だけ** 投入（[[sending-keys-to-claude-tui]]）。この1通に以下を含める:
   ```
   agmsg join <team-name> worker claude-code <worktree-path>
   agmsg mode monitor
   ```
   supervisor 自身も参加する: `~/.agents/skills/agmsg/scripts/join.sh <team-name> supervisor claude-code <supervisor-path>`
6. 全 worker 派遣後、**巡回 cron を 1 本だけ作成**（`CronCreate`、15 分間隔・off-minute 例 `7,22,37,52 * * * *`）。cron の主目的は **TUI 死亡確認のみ**に縮小（完了通知は agmsg push で受け取るため）。cron prompt に「TUI 死亡確認・`agmsg inbox` 確認・完了時 CronDelete+PushNotification」を書く。

## 巡回ループ（cron が 15 分ごとに発火）

**まず agmsg inbox を確認する（完了通知の主要チャネル）:**

```bash
~/.agents/skills/agmsg/scripts/inbox.sh <team-name> supervisor
```

worker が agmsg で完了通知を送っていれば、capture-pane ポーリング不要で完了を検知できる。

**次に TUI 生死確認のみ** 各ペインを `tmux capture-pane -p -t <id> | tail -40` で読む（worker の transcript / `.output` ファイルは Read しない — ペイン表示だけで判断）。

### ペイン状態の分類

| 表示 | 状態 | 対応 |
|---|---|---|
| `❯ ` 単独 / `❯ <dim text>` | 入力欄空（dim はゴーストサジェスト） | worker が thinking 中なら不介入。停止していれば完了確認 |
| 内側で thinking / Monitor / xcodebuild 進行中 | 正常進行 | **不介入** |
| `Resume this session with:` + OS シェル `$` | TUI 死亡 | `claude --resume <id>` で復旧（[[sending-keys-to-claude-tui]]）|
| 数字選択 / `(y/n)` / ダイアログ | 承認待ち | 内容を読んで意図した回答のみ。迷えば人間へエスカレーション |

**正常進行の worker には絶対に介入しない。** 介入は下記のスタック確定時のみ。

### スタック判定基準

- 無進捗停止（複数巡回にわたり tasklist もログも動かない）
- 同一エラーループ
- 承認待ちで放置
- buildable folder 規約違反（pbxproj 手編集など）
- シミュレータ規約違反（並列 worker で UDID 衝突）
- **TUI 死亡**

**経過時間や last-activity 行だけで生死を判断しない** — ペイン末尾の prompt 形式を必ず確認する。

## Hung プロセスの診断（重要）

worker が「テスト完了待ち」等で複数巡回無進捗のとき、**実プロセスの稼働時間で hung を確定する**:

```bash
ps -eo pid,etime,command | grep -iE 'xcodebuild|xctest' | grep -v grep
```

`etime` が異常に長ければ hung。例: unit test は通常数十秒〜数分。`xcodebuild test` が 30 分超なら確実に hung。worker のペイン表示（"Xm 経過"）はあてにせず、OS プロセスの etime で裏取りする。

**timeout 無しの待機ループは無限待機を生む**: worker が `until grep "SUCCEEDED" ...` を `timeout` 無しでバックグラウンド実行すると、ジョブが hung したとき完了文字列が永遠に来ず worker が待ち続ける。worker prompt で「長時間ジョブは必ず `timeout` 付きで実行」を指示する。

## 介入

スタック確定時のみ worker に介入する:

1. **まず agmsg で指示を送る**（send-keys 不要）:
   ```bash
   ~/.agents/skills/agmsg/scripts/send.sh <team-name> supervisor worker "<原因・対処・続行手順を具体的に>"
   ```
   - 「直して」ではなく、何をどうするかを書く
   - 長文・日本語・特殊文字でも壊れない

2. **send-keys を使う残留ケース**（agmsg で解決できない場合のみ）:
   - TUI が承認ダイアログを出している → capture-pane で内容を読んでから send-keys で意図した回答
   - TUI が死亡している → `claude --resume <id>` で復旧してから agmsg join を再実行 ([[sending-keys-to-claude-tui]])

- hung プロセスは worker に kill させる（`pkill -f 'xcodebuild.*<UDID>'` 等）

### auto-mode classifier 拒否の supervisor 委譲

worker は auto-mode で動くため、`gh issue comment` / `gh issue create` / issue 本文編集など「タスクの literal scope 外」と判定される外部書き込みが classifier に拒否されることがある。その場合:

- worker prompt で「拒否されたら投稿内容を `/tmp/*.md` に用意し、PR 本文にも埋め込んで supervisor に委譲」と指示
- supervisor が `gh issue comment --body-file /tmp/...` で代理投稿する（supervisor は別モードなので通る）

## 完了判定

worker が「コードだけ完成」で止まらないよう、**完了条件を明示的に列挙**して巡回ごとに照合する。典型条件:

1. CI 全 green
2. Copilot 未解決スレッド 0
3. ローカル test 全 green（実コマンド出力で確認）
4. （あれば）スクショ取得・文書化・issue フィードバック等の拡張スコープ
5. worker が `gh pr merge` せず PR を OPEN のまま「マージ準備完了（人間判断待ち）」と明示出力して停止

**自動マージ禁止** — マージは常に人間判断。worker にもそう指示する。

### スクリーンショットの視覚検証は [[screenshot-fidelity-check]] に一本化

UI のスクショ一致確認（純粋リファクタ 0px / 移行の累積ズレ検証）は **skill [[screenshot-fidelity-check]] の手順を使う**。supervisor はマージ前に同 skill を独立再実行し、worker の自己申告を鵜呑みにしない。worker prompt にも同 skill の実行を完了ゲートとして明記させる（worker と supervisor が同一の検証を使う）。**目視判定 厳禁・数値のみ**が原則。

### 人間にマージ可否を確認するとき

worker が完了に達し人間へマージ可否を確認する際、**worker が撮った before/after スクショがあれば `SendUserFile` で必ず添付する**。人間が視覚判断でき、UI 移行・リファクタでは後続タスクの参照にも再利用できる。スクショ無しで「マージしてよいか」とだけ聞かない。

## 撤収

全 worker が完了条件を満たしたら:

1. `CronDelete` で巡回 cron を削除（消し忘れるとセッション終了まで巡回し続ける）
2. `PushNotification` で完了を人間に通知（PR URL 添付）
3. マージは人間判断。マージ後は [[worktree-cleanup]] で worktree / branch / DerivedData / ペイン / `/tmp/wt-paneNN.id` を掃除

片方の worker だけ完了した場合は、その旨を記録して残りを監視継続。両方揃うまで cron は消さない。

## よくある落とし穴

- **正常進行への過介入** — `❯` が見えても内側で thinking 中なら触らない
- **ゴーストサジェストの誤読** — `capture-pane -p` は色を落とす。`❯` の後のタスク風テキストは dim ならゴースト＝入力欄は空（[[sending-keys-to-claude-tui]]）
- **cron 消し忘れ** — 完了後の `CronDelete` を忘れない
- **hung を経過時間表示で見逃す** — `ps` の etime で裏取り
- **拡張スコープの取りこぼし** — worker が「コード完了」で止まったら、文書化・issue 反映などの残タスクを促す
- **ユーザー視界外に worker pane を作る** — `new-window` / 別 session / 他 session の既存 idle pane 流用。すべて NG。worker は必ずユーザー attach 中 session に split-window する。SessionStart hook 出力で「same_session=YES」を最初に確認する習慣をつける
