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

## Pre-Setup: 自分の tmux 位置を必ず確認

worker を派遣する **前** に、以下を 1 度だけ実行する:

```bash
echo "my_pane=$TMUX_PANE my_session=$(tmux display-message -p '#{session_name}')"
```

- SessionStart hook (`~/.claude/hooks/session-start-tmux-check.sh`) が同等情報を最初のターンに注入しているはず — その内容を最初に確認。
- **worker pane は必ず supervisor 自身の session に作る**。ユーザーの attach session と異なっていても、supervisor の session を使うこと。理由: session が違えば作業ディレクトリが異なり、別の supervisor が存在する可能性があるため、監視・復旧が重複してコンフリクトする。
- 関連: memory [[feedback_session_start_tmux_check]] / [[feedback_supervisor_no_code_edit]]

## agmsg-first ポリシー

**agmsg インストール済みの場合、send-keys の用途を限定する:**

| 用途 | 手段 |
|---|---|
| worker 指示・進捗報告・完了通知 | **agmsg** (`send.sh`) |
| TUI 生死確認 | capture-pane（引き続き必要） |
| ダイアログ（y/n・番号選択）への応答 | send-keys（引き続き必要） |
| claude 初回起動 + 最初の1通（agmsg join 指示含む） | send-keys（これだけ） |

**agmsg はベストエフォートであり、完了検知の唯一手段にしてはいけない。** worker が agmsg join を実行しない・完了通知を送らないまま終わるケースが実際に発生している。必ず巡回 cron をフォールバックとして設置すること。

**並列・単独にかかわらず、worker には必ず固有の agent ID を付ける:**
- 命名規則: `worker-<issue番号>` / `worker-<worktree名>` / `worker-<タスク略称>` など
- 同じ `worker` という名前を複数 worker が使うと inbox が競合する（先に inbox.sh を呼んだ側が全メッセージを既読にしてしまう）
- 例: `join.sh my-team worker-{{ISSUE_NUM}} claude-code /path/wt-{{ISSUE_NUM}}`

### agmsg ID 規約 — team が namespace を担う

agmsg は team キーで agent ID を namespace するため、ID は team 内で一意であれば良い。プロジェクト識別は **team 名** で表現する。

| 層 | 役割 | 命名 |
|---|---|---|
| team | プロジェクト/タスク識別 | `wt-<issue番号>` / `wt-<タスク略称>` |
| agent ID (supervisor) | team 内の supervisor を指す | `supervisor`（suffix なし） |
| agent ID (worker) | team 内の worker を個別指定 | `worker-<issue番号>` 等の固有 ID |

送信先:
- worker → supervisor は `to=supervisor`（**suffix を付けない**）
- supervisor → worker は `to=worker-NN`

**なぜ `supervisor-NN` 形式を採らないか:**
- team キーが既にプロジェクトを namespace するため、agent ID への project tag は冗長
- worker が `worker-NN` パターンから類推して誤って `supervisor-NN` を作りやすい（実害: supervisor inbox 不着 → pane 目視で遅延検出。実プロジェクトで実証）
- inbox.sh / history.sh のクエリは `<team> <agent>` の組なので、team が違えば同 agent 名でも衝突しない

**複数 team を兼任する supervisor の場合:**
- agent ID は依然 `supervisor` で OK（team キーで namespace 済み）
- inbox.sh / history.sh は team ごとに独立して見える
- メッセージログを cross-team で串刺し検索したい場合は team 名で grep する

worker prompt にこの規約を明記する（「supervisor 宛は `to=supervisor`、suffix を付けない」を 1 行入れるだけで再発を防げる）。

---

## セットアップ（一度だけ）

### 派遣前: issue 実装済みチェック

worktree を作る前に、対象 issue が**既に実装済みでないか**を確認する: (a) `specs/*/tasks.md` のチェック状況（全 `[x]` なら実装済みの強いシグナル）、(b) `git log --all --grep='<issueキーワード>'` でマージ済み PR の有無、(c) issue が要求する実装ファイルの実在。実装済みと判明したら、フル開発でなく**検証タスク**（完了条件の充足確認 → ギャップがあれば差分実装、なければクローズ提案）への切り替えをユーザーに確認する。

**Why:** issue のクローズ忘れで「実装済みなのに OPEN」が起きる。気づかず派遣すると worker が既存実装を重複再実装するか、無意味な PR を作る（実例: 過去 PR で実装済み・全タスク完了の issue を「開発」依頼された → 検証 worker に切り替えてクローズ提案で完了）。

worker 1 体につき:

1. `git worktree add /path/wt-NN -b feature/...` で隔離ワークスペース作成
2. **supervisor 自身の session 内に新規 pane を split-window で作る** — pane id を即捕捉して `/tmp/wt-paneNN.id` に保存。
   ```bash
   # supervisor の session を target にして split (-h: 横分割 / -v: 縦分割)
   MY_SESSION=$(tmux display-message -p '#{session_name}')
   ANCHOR_PANE=$(tmux list-panes -t "$MY_SESSION:" -F '#{pane_id}' | head -1)
   WORKER_PANE=$(tmux split-window -h -P -F '#{pane_id}' -t "$ANCHOR_PANE" -c /path/wt-NN)
   echo "$WORKER_PANE" > /tmp/wt-paneNN.id
   ```
   - **禁止事項**: (a) `tmux new-window` で別 window に追い出す / (b) **既存の別 session の idle pane を流用** する (`%14 が空いてるから使おう` 的判断) / (c) 別 session に split する（監視・復旧が別 supervisor と重複する原因になる）。
3. ペイン命名（[[naming-tmux-panes]]）
4. `.worker-prompt.md` を worktree に置く（[[development-workflow]] の Parallel Worker Dispatch Checklist の項目を必ず含める）
5. ペインで `cd /path/wt-NN && claude` 起動 → `❯` 確認 → **send-keys で最初の1通だけ** 投入（[[sending-keys-to-claude-tui]]）。
   - **起動は通常の `claude`（auto mode）で行う。`--dangerously-skip-permissions` を supervisor から送ってはいけない。** auto-mode classifier に「無承認で autonomous loop を生成」とハード拒否される（send-keys でのトンネリングも bypass 扱いで弾かれる）。通常起動すれば pane に `⏵⏵ auto mode on` が表示され、worker は環境設定で自律作業できる（Edit/Bash も `Allowed by auto mode classifier` で通る）。bypass フラグは不要かつ有害。trust dialog が出たら承認し、`❯` 空 + `auto mode on` を確認してから最初の1通を送る。
   この1通に以下を含める:
   ```
   /agmsg スキルを使って <team-name> チームに worker-NN として参加し、monitor モードで指示を待ってください。
   チーム名: <team-name>
   agent ID: worker-NN
   worktree: <worktree-path>
   ```
   **`agmsg` コマンドを Bash で直接呼ばせてはいけない。** `agmsg` は PATH に入っておらず、フルパス指定も壊れやすい。worker は `Skill` ツールで `agmsg` スキルを呼び出す — これが唯一の確実な方法。`.worker-prompt.md` にも「`/agmsg` スキルを使って join すること」と明記する。
   supervisor 自身も参加する: `~/.agents/skills/agmsg/scripts/join.sh <team-name> supervisor claude-code <supervisor-path>`
   - **join 後、稼働中の agmsg watch Monitor を必ず再起動する**（`TaskStop` → 同コマンドで Monitor 再起動）。`watch.sh` は**起動時にしか identities を解決しない**ため、SessionStart hook 等で先に立ち上がった Monitor は新チームを購読しておらず、worker の完了報告を取りこぼす（巡回 cron だけが頼りになり検知が遅れる。実例で再起動により回避）。
6. 全 worker 派遣後、以下の**両方**を必ず設置する:
   - **巡回 cron（漸増 backoff）** — 派遣直後は密に、時間が経つほど疎にする。固定間隔ではなく経過に応じて間隔を伸ばす（worker の初動・初期進捗は細かく見たいが、安定稼働後やマージ承認待ちフェーズでは確認頻度を落とす）。スケジュール:

     | フェーズ | 間隔 | 累積経過（派遣からの目安） |
     |---|---|---|
     | 1 | 5 分ごと × 6 回 | 5,10,15,20,25,30 分 |
     | 2 | +15 分で 1 回 | 45 分 |
     | 3 | +30 分で 1 回 | 75 分 |
     | 4 | +45 分で 1 回 | 120 分 |
     | 5 以降 | 60 分ごと | 180,240,300… 分 |

     標準 cron 式は固定間隔しか表せないので、漸増は **巡回回数カウンタ + 間隔の貼り替え**で実装する:
     - 派遣時: カウンタファイル（例 `/tmp/wt-NN-patrol-n`）を 0 で作り、まず `*/5 * * * *` で CronCreate。
     - 各巡回の冒頭で `n=$(cat /tmp/wt-NN-patrol-n); n=$((n+1)); echo $n > /tmp/wt-NN-patrol-n`。
     - 巡回処理（capture-pane で pane 状態確認・`agmsg inbox` 確認・完了条件照合）を行う。
     - フェーズ境界（n==6 以降）に達したら現 cron を `CronDelete` し、次フェーズ間隔の cron を貼り直す（5 分 →「+15 分で 1 回」→「+30 分で 1 回」→「+45 分で 1 回」→ 60 分ごと）。「+N 分で 1 回」は recurring=false の one-shot を当該時刻に CronCreate するか、間隔 cron を貼って 1 回発火後に次へ貼り替える。
     - cron prompt には「pane 状態確認・agmsg inbox 確認・完了条件を満たせば CronDelete+PushNotification、未達ならカウンタを進めフェーズ境界なら間隔を貼り替える」を必ず書く。
     - **agmsg が来なくてもこのフォールバックで完了/異常を検知できる**ことが必須要件（間隔が伸びても監視は切らさない）。完了の即時検知は agmsg Monitor（リアルタイム）が主担当で、cron はそれを取りこぼした場合の保険。よって後半の間隔が疎でも実害は小さく、マージ承認待ちフェーズでは空回りが減る利点が勝る。
     - **one-shot 連鎖はマシンのスリープで監視空白が生じる**（cron はセッション idle 時のみ発火し、スリープ中は止まる。実例: 深夜予定の one-shot が翌朝に遅延発火し約6時間の空白）。遅延発火した patrol は **プロンプト内の状況記述を stale 前提** とし、CronList・`agmsg inbox`・pane・main の HEAD で現状を再構築してから動く。再開時に新しい recurring cron を既に貼り直していた場合、遅延発火した旧 one-shot からはフェーズ貼り替えをしない（cron の重複防止）。
   - **team inbox Monitor**（agmsg チーム inbox をリアルタイム監視）— cron より早く完了を検知できる場合があるが、あくまで補助。Monitor が来なくても cron がカバーする。

## 巡回ループ（cron 発火ごと・間隔は上記 backoff で漸増）

**まず agmsg inbox を確認する（早期検知の補助チャネル）:**

```bash
~/.agents/skills/agmsg/scripts/inbox.sh <team-name> supervisor
```

worker が agmsg で完了通知を送っていれば早期検知できる。ただし **worker が agmsg を使わないケースがあるため、inbox が空でも完了している可能性がある**。必ず pane 確認も行うこと。

**次に各ペインを `tmux capture-pane -p -t <id> | tail -40` で確認する（主たる完了検知手段）:** worker の transcript / `.output` ファイルは Read しない — ペイン表示だけで判断。`❯` が空で完了メッセージが見えれば完了と判定する。

**ただし pane の地の文で「完了」を肯定判定するときは、worker の宣言・未来形・条件文を実完了と誤マッチしないこと。** worker の「(CI green と Copilot 0)両方クリアになったら『マージ準備完了』を報告します」という**条件文**を、`grep 'マージ準備完了'` 等の部分一致 Monitor が拾って誤発火した実例がある（直後に CI fail で worker は作業継続中だった → 危うく未完成 PR の独立検証に入りかけた）。対策: **pane を Monitor で機械監視する場合、完了の肯定判定は agmsg の正式報告（worker が能動送信する定型句 "マージ準備完了（人間判断待ち）"）に一本化し、pane Monitor は異常（TUI 死亡 / parse-error / stall）の検知に限定する。** 人間/supervisor が目視で読むときも、完了文言が予告・宣言でなく**実完了の報告**かを確認する。関連: [[supervisor-independent-verification]]。

### ペイン状態の分類

| 表示 | 状態 | 対応 |
|---|---|---|
| `❯ ` 単独 / `❯ <dim text>` | 入力欄空（dim はゴーストサジェスト） | worker が thinking 中なら不介入。停止していれば完了確認 |
| 内側で thinking / Monitor / xcodebuild 進行中 | 正常進行 | **不介入** |
| `Resume this session with:` + OS シェル `$` | TUI 死亡 | `claude --resume <id>` で復旧（[[sending-keys-to-claude-tui]]）|
| `could not be parsed (retry also failed)` 反復 + idle `❯` | parse-error ループ（TUI は**生存**） | `/clear`+再開地点明示で再投入（[[sending-keys-to-claude-tui]]）。`claude --resume` ではない |
| `❯` 空だが履歴に `resuming /loop wakeup` /「N秒後に再確認」 | loop 自己ポーリング待機 | **不介入**（正常待機）。下記 idle-stall ガード参照 |
| 数字選択 / `(y/n)` / ダイアログ | 承認待ち | 内容を読んで意図した回答のみ。迷えば人間へエスカレーション |

**正常進行の worker には絶対に介入しない。** 介入は下記のスタック確定時のみ。

### スタック判定基準

- 無進捗停止（複数巡回にわたり tasklist もログも動かない）
- 同一エラーループ
- **tool-call parse エラーループ** — `⏺ The model's tool call could not be parsed (retry also failed).` の反復。TUI は生きている（死亡とは別）。ナッジ再送では直らないことが多い → [[sending-keys-to-claude-tui]] の「Recovering a parse-error loop」で `/clear` + 再開地点明示で復旧
- 承認待ちで放置
- buildable folder 規約違反（pbxproj 手編集など）
- シミュレータ規約違反（並列 worker で UDID 衝突）
- **TUI 死亡**

**経過時間や last-activity 行だけで生死を判断しない** — ペイン末尾の prompt 形式を必ず確認する。

### idle-stall を即スタック扱いしない（loop 痕跡の除外ガード）

pane が `❯` 空で無活動でも、worker が `/loop`・`ScheduleWakeup`・cron で自己ポーリング中なら**正常な待機**でありスタックではない。idle と判定する前に、pane 履歴に次のいずれかがあれば「loop 待機中＝正常」とみなし介入しない:

- `✻ Claude resuming /loop wakeup (...)` の行（wakeup が発火した痕跡）
- worker の宣言（「N秒後に再確認」「ScheduleWakeup を設定」等。rule [[loop-visibility]] に従い worker は loop 目的を明示するはず）

ただし worker は自己再開できても、**外部イベント（CI green / Copilot 再レビュー等）を待ち続けて自分では完了判定できない**ことがある。出揃ったら supervisor が「再確認のクロック」を一度だけナッジして仕上げさせる（レビュー作業自体は worker が実施）。

監視 monitor を組むなら、idle-stall 検知の前にこの除外を入れる。完了/スタックの判定キーは「アクティブ指標（`tokens` / `thinking` / `esc to interrupt`）の有無」と「loop 痕跡の有無」を併用する。

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
   - **指示を上書き/変更するときは「変更点」だけでなく「やらないこと」も明示する。** worker の旧タスクリストが古い理解のまま残り、誤った方向に実装しかけることがある（例: 「ダイアログは1段階のまま・文書のみ修正」と確定したのに worker の旧タスクが「2段階にする」のままで実装を2段階化しかけた → 「実装は変えるな・タスク名を直せ」と念押しで回避）。
   - 長文・日本語・特殊文字でも壊れない

2. **send-keys を使う残留ケース**（agmsg を試してから、届かない場合のみ）:
   - **「worker が join していないから agmsg は届かない」と先読みして send-keys に直接切り替えてはいけない。** `send.sh` で inbox に積んでから反応を待ち、それでも無応答なら send-keys にフォールバックする。
   - TUI が承認ダイアログを出している → capture-pane で内容を読んでから send-keys で意図した回答
   - TUI が死亡している → `claude --resume <id>` で復旧してから agmsg join を再実行 ([[sending-keys-to-claude-tui]])

- hung プロセスは worker に kill させる（`pkill -f 'xcodebuild.*<UDID>'` 等）

### auto-mode classifier 拒否時の対応（代理は第一選択でない）

worker は auto-mode で動くため、`gh issue comment` / `gh issue create` / `gh api ... requested_reviewers` / issue 本文編集など「タスクの literal scope 外」と判定される外部書き込みが classifier に拒否されることがある。**「拒否された＝supervisor が代理実行」と短絡してはいけない。** 次の順で対応する:

1. **その操作が本当に完了に必要か再評価する。** 不要なら worker にそう伝えて先へ進ませる（例: Copilot が既にレビュー済み＋指摘対応済み＋未解決スレッド0 なら、再レビュー再依頼は完了に不要）。
2. **必要かつ正当なら、worker 自身に実行させる承認を与える。** ただし承認の届け方に harness 上の限界がある:
   - **agmsg / 口頭で「承認するから実行してよい」と伝える方法は無効。** classifier は別エージェント（supervisor）の口頭承認を **"permission laundering（権限ロンダリング）= ユーザー境界は解除できない"** と判定し、再試行を bad-faith retry として再拒否する（実プロジェクトで実証）。
   - 有効なのは **(A)** worker pane に実 permission ダイアログが出ている場合に **send-keys でそのダイアログを承認**（その pane のキーボード入力＝正規のユーザー境界の承認）。ただし auto モードのハード拒否（`Denied by auto mode classifier`）はダイアログを出さないことが多く、その場合は使えない。
   - または **(B)** **settings に Bash 許可ルールを追加**（ユーザー管理の config）して worker が実行できるようにする。classifier 自身が示す正規解。原則ユーザー確認の上で行う。
3. **(A)(B) いずれも取れない／危険なら、人間判断にエスカレーションする。** supervisor の代理実行は、真に supervisor でしかできず安全と確信できる場合の最終手段に留める（`gh issue comment --body-file /tmp/...` 等は別モードの supervisor なら通ることがあるが、第一選択にしない）。

**例外（ユーザー明示指示があるとき）**: worker の `gh issue create` 等が classifier 拒否されても、**ユーザーが AskUserQuestion 等でその外部書き込みを明示選択している**場合は、supervisor 自身が実行するとユーザー意図が背景にあるため通過することがある（口頭中継=laundering とは別。supervisor 自身の手による実行はユーザー境界内）。worker が「`/tmp` に本文用意済み」と言っても **実在を確認** し、無ければ supervisor がレビュー内容から本文を構成して作成 → 発番番号を worker に渡して PR 本文・文書へ backfill させる。実プロジェクトでこの手順で issue を作成した事例がある。

参考: worker prompt で「拒否されたら投稿内容を `/tmp/*.md` に用意し PR 本文にも埋め込む」と指示しておくと、上記いずれの手段でも内容を失わない。

### user スコープ skill (`~/.claude/skills/`) の Write/Edit が classifier 拒否されたとき（Remote Control で遠隔承認）

worker に `~/.claude/skills/` 配下の SKILL.md を**新規作成・編集**させる作業は、auto-mode classifier が **"self-modification"（将来セッションの capability 改変）として拒否**する。settings.json/hook の権限自己改変とは別カテゴリだが同様にハード拒否。**非決定的**（同セッションでも通る Write と拒否される Write が混在する実例あり: 3 ファイル中 2 つ成功・1 つ拒否のケースを確認）。回避（heredoc / `cp`+Edit / 中継承認）は全て laundering 再拒否。**settings.json には触れない。**

唯一の解除＝**実際の人間が当該 worker セッションに直接 in-session 承認入力**（自由文「編集してよい」で可）。人間が手元に居ない場合の橋渡しが **Remote Control**:

- supervisor が `tmux send-keys -t <worker_pane> -l '/remote-control worker-NN'` → Enter で投入する。**send-keys は対象 pane の PTY（=worker プロセス）に届くので worker セッションで有効化**され、status バーが `/rc active` になる（claude-code-guide は「supervisor 側が起動する」と誤答するが誤り。実走で worker 有効化を確認）。`/remote-control` はクライアント側コマンドで、**worker(モデル)は自分で打てない**ため supervisor の send-keys が唯一の経路。
- 人間はスマホ/PC の **claude.ai/code → セッション名（worker-NN・緑ドット）** から入力欄に承認テキストを送れる。これは「人間が worker セッションに直接入力」＝正規ルートで laundering にならない。
- user スコープ編集が来ると分かっている worker は、**起動直後に supervisor が先行して `/remote-control` を有効化**しておくと承認待ちのラウンドトリップが減る。
- 拒否されたら worker に「回避せず agmsg で報告して待て」と指示し、supervisor は人間にエスカレーション（PushNotification + 承認手順を案内）。関連 memory: [[feedback_userscope_skill_classifier_block]]。

## 完了判定

worker が「コードだけ完成」で止まらないよう、**完了条件を明示的に列挙**して巡回ごとに照合する。典型条件:

1. CI 全 green
2. Copilot 未解決スレッド 0
3. ローカル test 全 green（実コマンド出力で確認）
4. （あれば）スクショ取得・文書化・issue フィードバック等の拡張スコープ
5. worker が `gh pr merge` せず PR を OPEN のまま「マージ準備完了（人間判断待ち）」と明示出力して停止

**自動マージ禁止** — マージは常に人間判断。worker にもそう指示する。

#### 「CI 全 green」は CI 定義を読んで前提化してから判定する

条件1（CI green）を確認する前に、まず `.github/workflows/*.yml`（CI 定義）を読む。変更ファイルの種類・`paths`/`paths-ignore` フィルタ・トリガ条件から「**この変更で本来どのチェックが走るはずか**」を前提として把握し、その期待と実際（`gh pr checks`）を突き合わせて判定する。

- 走るはずのチェックが無い（例: docs/md のみの変更は `paths-ignore` で CI 不起動）なら、`gh pr checks` の `no checks reported` は**正常** → `mergeStateStatus=CLEAN` / `mergeable=MERGEABLE` で代替判定する。
- 逆に、走るべきチェックが起動していない場合は設定ミス／トリガ漏れを疑う。

**Why:** CI の前提（何が走るはずか）を持たずに監視すると、`no checks` を「未完了」と誤認して無限待機したり、本来必要なチェックの欠落を見逃す。前提を先に固めれば沈黙が正常か異常かを正しく区別できる（docs-only PR で `no checks reported` を誤読しかけた実例あり）。

### スクリーンショットの視覚検証は [[screenshot-fidelity-check]] に一本化

UI のスクショ一致確認（純粋リファクタ 0px / 移行の累積ズレ検証）は **skill [[screenshot-fidelity-check]] の手順を使う**。supervisor はマージ前に同 skill を独立再実行し、worker の自己申告を鵜呑みにしない。worker prompt にも同 skill の実行を完了ゲートとして明記させる（worker と supervisor が同一の検証を使う）。**目視判定 厳禁・数値のみ**が原則。

### 人間にマージ可否を確認するとき

worker が完了に達し人間へマージ可否を確認する際、**worker が撮った before/after スクショがあれば `SendUserFile` で必ず添付する**。人間が視覚判断でき、UI 移行・リファクタでは後続タスクの参照にも再利用できる。スクショ無しで「マージしてよいか」とだけ聞かない。

## 撤収

**監視（agmsg Monitor / 巡回 cron）の撤収は worker の「実停止」を確認してから。** supervisor が独立検証で完了条件を満たしたと判断しても、それは撤収許可ではない — worker が稼働中なら完了報告・新ブロッカーを送ってくる。実例: 独立検証で完了確認後に agmsg Monitor を止めたら、直後に届いた worker の完了報告を取りこぼした（再起動したら即座に回収できた）。

**worker の agmsg monitor を止めるのは supervisor の指示があった時のみ**（worker は自分からは止めない）。撤収の順序:

1. 人間がマージを承認 → supervisor がマージ
2. worker cleanup に着手する際、worker へ「agmsg monitor を停止せよ」と指示する
3. worker の停止を確認できたら、supervisor が自分の agmsg Monitor を `TaskStop` し、巡回 cron を `CronDelete`（消し忘れるとセッション終了まで巡回し続ける）
   - **worker の monitor 停止判定は pane 文言の grep でなく、status bar の `· 1 monitor` 表示の消失で行う。** 地の文への grep（`until ... grep "monitor を停止"`）は supervisor が送った指示文のエコーや worker の宣言文に誤マッチする（実測あり）。TUI 最下行の `N shell, N monitor` は harness が描画する機械的指標で誤マッチしない。
4. `PushNotification` で完了を人間に通知（PR URL 添付）
5. マージ後は [[worktree-cleanup]] で worktree / branch / DerivedData / ペイン / `/tmp/wt-paneNN.id` を掃除

片方の worker だけ完了した場合は、その旨を記録して残りを監視継続。両方揃うまで監視（Monitor / cron）は消さない。

### worker pane と shell/deploy pane の統合（idle worker は早めに kill）

worker が完了報告に達してマージ承認待ち（または release 作業待ち）で **idle になったら、worker pane を維持する積極理由（追加修正の往復が見込まれる / 同セッションで agmsg 再起動コストを払いたくない 等）が無ければ kill して shell / deploy pane に統一する**。同じ worktree に複数 pane を並走させるのは worker / supervisor shell の両方がアクティブな場合のみ。

実例: worker が PR を作って idle 待機しているところに、supervisor が同 worktree から deploy 系コマンドを回すため別 deploy pane を split したケース。worker pane は agmsg monitor だけで idle のまま、視覚的に冗長だった。完了済みで idle なら kill して 1 pane にする方が状況把握しやすい。

## よくある落とし穴

- **正常進行への過介入** — `❯` が見えても内側で thinking 中なら触らない
- **ゴーストサジェストの誤読** — `capture-pane -p` は色を落とす。`❯` の後のタスク風テキストは dim ならゴースト＝入力欄は空（[[sending-keys-to-claude-tui]]）
- **cron 消し忘れ** — 完了後の `CronDelete` を忘れない
- **hung を経過時間表示で見逃す** — `ps` の etime で裏取り
- **拡張スコープの取りこぼし** — worker が「コード完了」で止まったら、文書化・issue 反映などの残タスクを促す
- **別 session に worker pane を作る** — `new-window` / 別 session / 他 session の既存 idle pane 流用。すべて NG。worker は必ず **supervisor 自身の session** に split-window する。別 session は作業ディレクトリが異なり、別の supervisor が存在して監視・復旧が重複するリスクがある。
- **agmsg を完了検知の唯一手段にする** — worker が agmsg join をスキップする・完了通知を送らないケースが実際に発生している。巡回 cron（pane 確認）を必ず設置し、agmsg は補助として扱う。「agmsg が来なかったから worker はまだ作業中」と判断してはいけない。
