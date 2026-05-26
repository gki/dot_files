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

関連: [[screenshot-fidelity-check]] (本 repo 未同梱。別途 user scope 等で導入する前提) /
[[sending-keys-to-claude-tui]] / [[supervising-worker-panes]]

## なぜ独立検証が要るか

worker は「全要素 bbox ±3px、PASS」と自信を持って報告するが、本人が見落とした
新しい軸（W×H 肥大 / 色トークン取り違え / 罫線本数差）が **ユーザー目視で初めて
発覚する** 事故が複数 PR で連続発生した（例: 視覚移行を伴う UI 変更で 2.3 倍肥大の
見落とし）。

worker 自己申告は**ヒント**として扱い、supervisor は同じ skill を git push 済の
成果物に対して独立に回す。手順を skill 化しておかないと毎回ロジックを書き直し、
測り忘れた軸が再発する。

## 完了条件 7 軸（PR が満たすべき）

毎 PR 同じ表で確認する。`[ ]` を `✅` / `❌` で埋めて貼る:

| | 条件 | 確認方法 |
|-|-|-|
| ① | CI 全 green | `gh pr view N --json statusCheckRollup` で全 `conclusion=SUCCESS` |
| ② | Copilot 未解決 0 | `reviewThreads` GraphQL で `unresolved == 0` |
| ③ | ローカル test green | worker 出力 / または `gh run view` から最新成功 run のログ確認 |
| ④ | 仕様要件達成 | PR 説明 + 実装 diff + 視覚検証 |
| ⑤ | 親遷移正常 | 既存呼び出し維持を diff で確認（例: iOS なら {{UI_COMPONENT}} = `UIHostingController` 経由が維持されているか） |
| ⑥ | 不要レガシー削除 | 旧 UI 定義ファイル（例: iOS の storyboard scene）/ 古いファイルが `git rm` されている |
| ⑦ | screenshot-fidelity-check pass + コミット済 | `{{SCREENSHOT_DIR}}/<date>-*` が PR diff に含まれる |

## 手順

### 1. PR 状態を 1 コマンドで取る

```bash
# REPO は owner/repo 形式 (例: gki/dot_files)。$PR は PR 番号。
gh pr view $PR -R $REPO --json statusCheckRollup,mergeable,headRefOid,reviewRequests,reviews \
  --jq '{mergeable, head:.headRefOid[0:7], ci:(.statusCheckRollup//[]|map({n:.name, c:(.conclusion//.status)}))}'

# GraphQL は owner/name を分解して -F field 引数で渡す (-f は string 固定で interpolation できない)。
# first:100 + pageInfo.hasNextPage で取りこぼし検出。100 スレッド超は paging 必須。
gh api graphql \
  -F owner="${REPO%/*}" -F name="${REPO#*/}" -F pr="$PR" \
  -f query='
    query($owner:String!, $name:String!, $pr:Int!) {
      repository(owner:$owner, name:$name) {
        pullRequest(number:$pr) {
          reviewThreads(first:100) {
            nodes{isResolved}
            pageInfo{hasNextPage endCursor}
          }
        }
      }
    }' \
  | python3 -c "import json,sys; d=json.load(sys.stdin); rt=d['data']['repository']['pullRequest']['reviewThreads']; ts=rt['nodes']; un=[t for t in ts if not t['isResolved']]; warn=' WARNING: >100 threads — needs paging via endCursor' if rt['pageInfo']['hasNextPage'] else ''; print(f'total={len(ts)} unresolved={len(un)}{warn}')"
```

CI が SUCCESS でない / unresolved > 0 の段階で「完了条件未達」を worker に
[[sending-keys-to-claude-tui]] で返し、独立検証フェーズには進まない。

> **Paging 注記**: `first:100` は 1 page = 最大 100 thread を見る上限。100 を超える PR では `pageInfo.hasNextPage == true` で WARNING が出るので、`after:$cursor` を加えて全 page を巡る paging ループを別途実装する必要がある。100 thread を超える PR は稀だが、長期 review や巨大変更では起こりうる。

### 2. 成果物を git push 済バージョンから取得

**worker の `/tmp` 等ローカルファイルを使わない**。supervisor が自分で
`git show <branch>:<path>` で取り出す:

```bash
BRANCH=$(gh pr view "$PR" -R "$REPO" --json headRefName --jq -r .headRefName)
git -C "$REPO_DIR" fetch origin "$BRANCH"
mkdir -p "/tmp/sv-verify-$PR"
# {{SCREENSHOT_DIR}} は末尾スラッシュ無しで指定 (`docs/screenshots` 等)。
# パス連結時の `//` を防ぐため SKILL 側も `/` 1 個で結合している。
git -C "$REPO_DIR" show "origin/$BRANCH:{{SCREENSHOT_DIR}}/<date>-<screen>-before.png" \
  > "/tmp/sv-verify-$PR/before.png"
git -C "$REPO_DIR" show "origin/$BRANCH:{{SCREENSHOT_DIR}}/<date>-<screen>-after.png" \
  > "/tmp/sv-verify-$PR/after.png"
ls -la "/tmp/sv-verify-$PR/"
```

PNG が repo にコミットされていなければ ⑦ 未達。worker に追加コミット依頼を送る。

### 3. screenshot-fidelity-check を全軸回す

[[screenshot-fidelity-check]] skill の 2/2b/2c/2d/2e を **全部** 実行する。
worker が報告した軸だけ追試するのではなく、追加軸（特に 2d 要素 bbox W×H と
2e 色 hex）まで毎回回すのが skill 化する意味。

`getbbox` 残差・罫線最大ズレ・テキスト帯最大ズレ・要素 bbox 最大ズレ・色 hex
不一致箇所をそれぞれ数値で出して、PASS/FAIL を 1 行サマリにまとめる。

### 4. 実装 diff の構造確認（④⑤⑥）

```bash
gh pr view $PR -R $REPO --json files --jq '.files[] | "\(.additions)+\(.deletions)- \(.path)"'
```

確認ポイント:
- 共有ファイル（並行 worker 領域）に踏み込んでいないか
- 親 View からの遷移呼び出しが置換されているか
  （例: iOS なら `MenuHostingController` 等の `present(NewHostingController(), animated:)` パターン）
- 旧 UI 定義シーン / 旧 View が `git rm` されているか
- 旧 UI 定義ファイル（例: iOS の `Main.storyboard`）に dangling 参照がないか
  （grep 残存確認）

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
gh pr merge "$PR" -R "$REPO" --squash --delete-branch
git -C "$REPO_DIR" fetch origin main                        # main HEAD 確認
tmux kill-pane -t "$WORKER_PANE"                            # worker pane 撤去
git -C "$REPO_DIR" worktree remove --force "/path/to/wt-$PR" # worktree 撤去
rm "/tmp/wt-pane$PR.id"                                     # pane id ファイル
# 単一 worker 監視 cron なら CronDelete でも削除
```

**事前に main に取り込まれているか** を `git show origin/main:<plan-doc-path>` で確認
してから `worktree remove --force` する（squash merge 後 untracked のままだった
計画書を `--force` で失う事故防止）。

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
