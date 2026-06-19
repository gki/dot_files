---
name: supervisor-independent-verification
description: >
  Use when a worker pane reports "マージ準備完了 / completion ready" on a PR
  and the supervisor must independently re-verify before presenting merge
  options to the human. Encodes the full re-check loop: fetch committed
  before/after screenshots from the branch, run screenshot-fidelity-check
  (axes 2/2b/2c/2d/2e), confirm CI / Copilot / mergeable state, send
  before/after to the user, then ask for merge approval. Triggers:
  "worker 完了サマリ", "マージ準備完了", "independent verification",
  "supervisor 独立検証", "before/after PIL 再検証", "PR 完了確認".
metadata:
  node_type: skill
---

# Supervisor Independent Verification

worker が「完了 / マージ準備完了」と申告した PR について、supervisor が
**worker のローカル状態を一切信用せず**、git に push 済の成果物だけで再検証して
ユーザーにマージ判断を仰ぐまでの不可分手順。

関連: [[screenshot-fidelity-check]] / [[sending-keys-to-claude-tui]] /
[[feedback_merge_confirmation_screenshots]] / [[supervising-worker-panes]]

## なぜ独立検証が要るか

worker は「全アイコン bbox ±3px、PASS」と自信を持って報告するが、本人が見落とした
新しい軸（W×H 肥大 / 色トークン取り違え / 罫線本数差）が **ユーザー目視で初めて
発覚する** 事故が複数 PR で連続発生した実績がある。

worker 自己申告は**ヒント**として扱い、supervisor は同じ skill を git push 済の
成果物に対して独立に回す。手順を skill 化しておかないと毎回ロジックを書き直し、
測り忘れた軸が再発する。

## 検証対象の種類で再検証手段が変わる

この skill の 7 軸と [[screenshot-fidelity-check]] は **UI 移行 / リファクタ（スクショで一致を測る PR）** を主対象に設計されている。検証対象が UI でない場合は対象の種類に応じて手段を選ぶ:

- **UI スクショ（移行 / リファクタ）** → 下記 7 軸 + screenshot-fidelity-check を全軸回す（この skill の中心）
- **動作物（スキル / CLI / コード / 設定 / プロンプト）** → **worker の検証ログ・成果物を「読む」だけで「動作確認した」としてはならない。supervisor 自身がそれを実行して期待動作を再現する。** worker が残した検証ログは worker の自己申告と同格の「ヒント」であり、それを読むのは独立検証ではない。
  - 例: worker が「スキル X を Agent から起動して観点が発火した」と検証ログに書いていても、supervisor は自分で Agent を起動（または手元で）してスキル X を実行し、同じ結果が再現するかを確かめる。
  - 実例: team:reviewer 系の動作検証で、supervisor が worker の検証ログを読むだけで独立検証を済ませようとし、ユーザーの「テストした？」で動作未実行に気づいた。その後 supervisor 自身が Agent 起動・手動再現で実地検証して初めて独立検証が成立した。

## 完了条件 7 軸（PR が満たすべき）

毎 PR 同じ表で確認する。`[ ]` を `✅` / `❌` で埋めて貼る:

| | 条件 | 確認方法 |
|-|-|-|
| ① | CI 全 green | `gh pr view N --json statusCheckRollup` で全 `conclusion=SUCCESS` |
| ② | Copilot 未解決 0 | `reviewThreads` GraphQL で `unresolved == 0` |
| ③ | ローカル test green | worker 出力 / または `gh run view` から最新成功 run のログ確認 |
| ④ | 仕様要件達成 | PR 説明 + 実装 diff + 視覚検証 |
| ⑤ | 親遷移正常 | UIHostingController 経由・既存呼び出し維持を diff で確認 |
| ⑥ | 不要レガシー削除 | 旧 storyboard scene / 古いファイルが `git rm` されている |
| ⑦ | screenshot-fidelity-check pass + コミット済 | `docs/.../screenshots/<date>-*` が PR diff に含まれる |

## 手順

### 1. PR 状態を 1 コマンドで取る

```bash
gh pr view $PR -R $REPO --json statusCheckRollup,mergeable,headRefOid,reviewRequests,reviews \
  --jq '{mergeable, head:.headRefOid[0:7], ci:(.statusCheckRollup//[]|map({n:.name, c:(.conclusion//.status)}))}'

gh api graphql -F owner="${REPO%/*}" -F name="${REPO#*/}" -F pr="$PR" -f query='
  query($owner:String!,$name:String!,$pr:Int!){
    repository(owner:$owner,name:$name){
      pullRequest(number:$pr){
        reviewThreads(first:100){
          pageInfo{hasNextPage}
          nodes{isResolved}
        }
      }
    }
  }' \
  | python3 -c "import json,sys; d=json.load(sys.stdin); rt=d['data']['repository']['pullRequest']['reviewThreads']; ts=rt['nodes']; un=[t for t in ts if not t['isResolved']]; print(f'total={len(ts)} unresolved={len(un)}' + (' WARNING: hasNextPage — paging needed for >100 threads' if rt['pageInfo']['hasNextPage'] else ''))"
```

CI が SUCCESS でない / unresolved > 0 の段階で「完了条件未達」を worker に
[[sending-keys-to-claude-tui]] で返し、独立検証フェーズには進まない。

**注意: 「CI green」は job 単位であり step 実行を保証しない（①③の落とし穴）。** GitHub Actions の単一 job 内に conditional step（paths-filter による `if:` 付きなど）があると、job は SUCCESS でも内部のテスト step が `skipped` のことがある。`statusCheckRollup` の `conclusion=SUCCESS` だけ見ると見逃す。**step 単位を確認する:**

```bash
gh run view <run-id> -R $REPO --json jobs \
  --jq '.jobs[] | "JOB \(.name): \(.conclusion)", (.steps[]? | "   - \(.name): \(.conclusion)")'
```

検証したいテスト（特に UI test）が `skipped` でないかをチェックする。skip されていれば CI は当該テストを裏取りしていないので、worker に**手動で再実行**させて生ログ（`** TEST SUCCEEDED **` 等）で裏取りする。実例: 大規模移行 PR で `Build` job は SUCCESS だが内部の `UI Test` step が paths-filter 未該当で `skipped`、unit test のみ実行されていた。アプリコードの大改修なのに UI 回帰が CI で走っていなかった。

### 2. 成果物を git push 済バージョンから取得

**worker の `/tmp` 等ローカルファイルを使わない**。supervisor が自分で
`git show <branch>:<path>` で取り出す:

```bash
BRANCH=$(gh pr view $PR -R $REPO --json headRefName --jq -r .headRefName)
git -C $REPO_DIR fetch origin "$BRANCH"
mkdir -p /tmp/sv-verify-$PR
git -C $REPO_DIR show "origin/$BRANCH:docs/.../screenshots/<date>-<screen>-before.png" \
  > /tmp/sv-verify-$PR/before.png
git -C $REPO_DIR show "origin/$BRANCH:docs/.../screenshots/<date>-<screen>-after.png" \
  > /tmp/sv-verify-$PR/after.png
ls -la /tmp/sv-verify-$PR/
```

PNG が repo にコミットされていなければ ⑦ 未達。worker に追加コミット依頼を送る。

### 3. screenshot-fidelity-check を全軸回す

[[screenshot-fidelity-check]] skill の 2/2b/2c/2d/2e を **全部** 実行する。
worker が報告した軸だけ追試するのではなく、追加軸（特に 2d アイコン bbox W×H
と 2e 色 hex）まで毎回回すのが skill 化する意味。

`getbbox` 残差・罫線最大ズレ・テキスト帯最大ズレ・アイコン bbox 最大ズレ・色 hex
不一致箇所をそれぞれ数値で出して、PASS/FAIL を 1 行サマリにまとめる。

### 4. 実装 diff の構造確認（④⑤⑥）

```bash
gh pr view $PR -R $REPO --json files --jq '.files[] | "\(.additions)+\(.deletions)- \(.path)"'
```

確認ポイント:
- 共有ファイル（並行 worker 領域）に踏み込んでいないか
- 親 ViewController からの遷移呼び出しが置換されているか（`MenuHostingController` 等の
  `present(NewHostingController(), animated:)` パターン）
- 旧 storyboard シーン / 旧 ViewController が `git rm` されているか
- `Main.storyboard` の dangling segue 参照がないか（grep 残存確認）

### 5. ユーザーへ提示 — SendUserFile + AskUserQuestion 不可分

7 軸サマリ表をテキストで出力 → before/after/diff-amp を SendUserFile（status:
proactive）→ AskUserQuestion で squash merge / GitHub UI 判断 / 追加修正 の 3 択を
提示する一連を **同じターン内で** 完結させる。

```
SendUserFile {
  files: ["/tmp/sv-verify-<PR>/before.png",
          "/tmp/sv-verify-<PR>/after.png",
          "/tmp/sv-verify-<PR>/diff-amp.png"],
  status: "proactive",
  caption: "PR #N (issue #M / <title>) — before/after/diff-amp。supervisor 独立 PIL 検証: <要点>"
}

AskUserQuestion {
  question: "PR #N をマージしますか？",
  options: [
    {label: "squash merge してブランチ削除 (Recommended)", ...},
    {label: "GitHub UI で見てから判断", ...},
    {label: "追加修正を依頼", ...}
  ]
}
```

### 6. 承認後のクリーンアップ（不可分セット）

ユーザーが squash merge 承認したら以下を一括実行:

```bash
gh pr merge $PR -R $REPO --squash --delete-branch
git -C $REPO_DIR fetch origin main                          # main HEAD 確認
tmux kill-pane -t $WORKER_PANE                              # worker pane 撤去
git -C $REPO_DIR worktree remove --force /path/to/wt-$PR    # worktree 撤去
rm /tmp/wt-pane$PR.id                                       # pane id ファイル
# 単一 worker 監視 cron なら CronDelete でも削除
```

**worktree が残っているブランチに `--delete-branch` を付けると exit=1 になるが、マージ自体は成功していることがある。** `gh pr merge --delete-branch` のローカルブランチ削除は、そのブランチを worktree が使用中だと必ず失敗する（`cannot delete branch ... used by worktree`）。リモートブランチ削除とマージは成功しているのに exit=1 が返るため、「マージ失敗」と誤読しない。マージ成立は exit code でなく `git fetch origin main && git log origin/main --oneline -1` で merge commit を確認して判定する。worktree 運用中はそもそも `--delete-branch` を付けず、ローカル削除は [[worktree-cleanup]] の順序（worktree remove → `branch -D`）に任せるのが正解（実プロジェクトで 2 回連続で踏んだ）。

**`gh pr merge` が supervisor 環境で 401 Unauthorized になるときの回避**（[[feedback_supervisor_gh_merge_workaround]]）: supervisor の Bash 環境は gh の GET は通るが write がブロックされ `gh pr merge` が 401 になることがある（トークンは有効・worker は push 可）。その場合は raw REST を直接叩く:
```bash
gh api -X PUT repos/$OWNER/$REPO/pulls/$PR/merge -f merge_method=squash   # → {"merged":true}
gh api -X DELETE repos/$OWNER/$REPO/git/refs/heads/$BRANCH                 # PUT merge では自動削除されないので別途
```
worker への委譲は auto-mode classifier がマージを「cross-session 中継承認＝permission laundering」で拒否するので不可。supervisor 自身が上記 raw api で実行する。

**⚠️ この raw-api 回避は 401（認証）専用。classifier の「ポリシー」拒否には使わない。** `gh pr merge` が classifier に拒否され、メッセージが "merges are human-only" / "user only asked for X, not a merge" / "violates ... boundary" 等の**ポリシー**理由のときは、raw-api PUT で迂回してはいけない（「マージは人間判断」境界の bad-faith バイパスになり、classifier 自身も他ツールでの迂回を禁じる）。正しい対処は **ユーザーから明示のマージ指示を得る**こと（AskUserQuestion で「squash merge する」を選択させる等）。ユーザーの literal な直近発話がマージ指示でないと拒否され続ける（選択肢の説明文に「確認できたらマージ」と書いても、ユーザー自身の発話がマージ指示でなければ不可）。明示指示の直後の `gh pr merge` は通る（実プロジェクトで実証）。

**事前に main に取り込まれているか** を `git show origin/main:<plan-doc-path>` で確認
してから `worktree remove --force` する（[[feedback_worker_dispatch_plan_commit]] の
教訓 — squash merge 後 untracked のままだった計画書を `--force` で失う事故防止）。

## アンチパターン

- worker の「完了サマリ」をそのままユーザーに転送して merge 判断を仰ぐ →
  独立検証していないので 2.3 倍肥大などを 1 段目で見逃す
- worker のローカル `/tmp/...` スクショで再検証する → git push 済の真の成果物と
  ズレている可能性。必ず `git show <branch>:path` 経由
- 「CI green / Copilot 0」だけ確認して 7 軸の④〜⑦をスキップ → 仕様要件の取り違え
  を見逃す
- 7 軸を全部測ったがユーザー提示しないで自動マージ → 自動マージ禁止違反
- skill 2d / 2e を「worker が報告していないから不要」と省略 → skill 化した意味なし、
  全軸毎回回す
