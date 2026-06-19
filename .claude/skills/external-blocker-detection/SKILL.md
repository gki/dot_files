---
name: external-blocker-detection
description: >
  Use when CI / build / tool failures look unusual — failing in seconds with
  no real error, identical reruns failing identically, multiple branches
  failing simultaneously, or tool output mentioning billing / outage /
  account / quota / rate limit. Distinguishes external blockers (GitHub
  Actions billing, Anthropic classifier outage, Apple developer cert expiry,
  package registry outage) from code-level bugs, so workers escalate to the
  human instead of fruitlessly retrying. Triggers: "CI が 2 秒で fail",
  "main も同じく失敗", "billing", "spending limit", "課金問題",
  "classifier 障害", "external outage", "rerun も同じ症状".
metadata:
  node_type: skill
---

# External Blocker Detection

CI/ビルド/ツールの失敗が **コード由来でなく外部要因（課金・障害・期限切れ）** の
場合、worker がコード修正で直そうとしても永遠に直らない。早期に切り分けて人間に
エスカレーションする手順。

関連: [[supervising-worker-panes]] / [[supervisor-independent-verification]] /
[[sending-keys-to-claude-tui]] / 既存 memory `project_ci_strict_concurrency`
（こちらは「コード由来の既知パターン」で本 skill とは対照的）

## なぜ skill 化するか

本番運用中のプロジェクトで GitHub Actions の支出制限到達 で CI が **2 秒で fail**
し続けた時、最初 worker は「コード由来かもしれない」と数巡レビューループに突入
した。実際は repo オーナーの billing 操作が必要で、worker / supervisor が何時間
費やしてもコード側では絶対に解決しない。

外部要因の症状はパターン化されていて、ヒューリスティックで検出できる。**早期検出 →
人間エスカレーション** がコスト最小。

## 外部要因の判定ヒューリスティック（強い順）

ひとつでも当てはまれば外部要因の蓋然性が高い。**複数当てはまるとほぼ確定**:

| # | 兆候 | 典型原因 |
|---|---|---|
| 1 | CI run が **5 秒以内** に終わる（実体未起動） | billing / quota / spending limit |
| 2 | 同一 SHA の rerun も同じく数秒で fail | 同上（一時的では収まらない） |
| 3 | **main など他のブランチも同症状** で CI 失敗 | repo / org 全体の billing or outage |
| 4 | ログ取得が `log not found` / 空 | run 実体未生成（billing が前段で拒否） |
| 5 | ログに `recent account payments have failed` / `spending limit` / `billing` / `quota` / `rate limit` / `429` / `402` | billing / quota 明示 |
| 6 | ログに `outage` / `maintenance` / `unavailable` / `502/503/504` | プロバイダ側障害 |
| 7 | コードを 1 文字も変えずに過去 N 回 green → 直近 N 回連続赤 | 環境変化（外部要因） |
| 8 | 別の独立タスク（別 worker / 別 repo）で同時に同種失敗 | 共通インフラ障害 |
| 9 | `gh api ... 402/403`, `xcrun ... not signed`, certificate expired 文言 | API 認証 / cert |

## 判定 → エスカレーション手順

### 1. 切り分けの 3 コマンド

```bash
# 最新 fail run の所要時間
gh run view $RUN_ID -R $REPO --json startedAt,createdAt,jobs \
  --jq '.jobs[]|{name, conclusion, started_at, completed_at}'
# completed_at - started_at が < 5s なら兆候 #1

# main ブランチでも同症状か
gh run list -R $REPO --branch main --limit 3 \
  --json conclusion,createdAt,workflowName \
  --jq '.[]|"\(.conclusion) \(.workflowName) \(.createdAt)"'

# ログから billing / outage 文言検出
gh run view $RUN_ID -R $REPO --log 2>&1 \
  | grep -iE 'billing|spending|payment|quota|rate.?limit|outage|unavailable|cert.?(expir|invalid)'
```

3 つのうち **2 つ以上が陽性なら外部要因と仮判定**。コード修正サイクルを止める。

### 2. コード修正の試行は禁止（重要）

外部要因仮判定が出たら、**worker にコード修正を発注しない**。「直前に push した
diff を revert すれば直るのでは」「Swift concurrency 設定を見直そう」等の
**正常系のループに入ったら時間と context の浪費**。

worker 側にも、外部要因の蓋然性が高いと判明した段階で `ScheduleWakeup` / cron で
盲目的にリトライさせず、supervisor を経由して人間判断を仰ぐ。

### 3. 人間エスカレーションの定型

`AskUserQuestion` で **3 択**を提示する（外部要因に対する典型対応）:

```
question: "<外部要因の要約>。どう進めますか？"
options:
  - {label: "外部要因を解消", description: "billing 設定確認/cert 更新/etc. の手動操作。解決後 worker が gh run rerun で再試行"}
  - {label: "外部要因を待たずに人間判断でマージへ", description: "②〜⑦ の他完了条件達成済なら例外的に手動マージ。CI 復旧後に追加 push で green 確認"}
  - {label: "worker を一旦停止して外部要因解消後に再開", description: "worker context を温存したまま session 維持。解消後に supervisor が再起動指示"}
```

選択肢には **必ず根拠（worker の他完了条件状況）を添える** こと。例:
> Copilot 0/N・ローカル test green・視覚検証 PASS。CI のみ billing で blocked。

### 4. supervisor 自身の独立確認

worker が「課金問題」と申告した時、supervisor は**鵜呑みにせず**独立に判定 9 軸を
回す（worker の自己申告 unreliable 原則）。

```bash
# run 所要時間
gh run view <RUN> -R $REPO --json startedAt,createdAt \
  --jq '"\(.startedAt) → \(.createdAt)"'

# main も同症状か独立確認
gh run list -R $REPO --branch main --limit 5 --json conclusion --jq '[.[].conclusion]'

# ログメッセージ独立確認
gh run view <RUN> -R $REPO --log-failed 2>&1 | head -30
```

判定一致なら自信を持ってエスカレーション、不一致なら worker と合わせて再調査。

## アンチパターン

- 「とりあえず rerun」を 3 回以上繰り返す → 外部要因なら無駄、コード由来ならログ
  を読む方が早い。**rerun は最大 2 回まで**、それで治らなければ判定軸で切り分け
- worker が「課金問題」「障害」と言ったので supervisor もそのまま信じてユーザーに
  転送 → ヒューリスティック独立確認なしの転送は誤誘導リスク
- 外部要因確定後もコード修正ループを継続 → 時間と context の浪費
- 外部要因と判明したのに `AskUserQuestion` 3 択を出さず「待ってください」だけ →
  ユーザーが何をすべきかわからない。**具体的な解消アクションへのリンク**
  （GitHub billing 設定 URL 等）を選択肢の description に書く
- 9 軸全部当てはまっても worker prompt にコード修正リトライを書き続ける → skill 違反

## 既知の外部要因タイプ別チェックリスト

| 外部要因 | 一次判定 | 解消アクション |
|---|---|---|
| GitHub Actions billing | run < 5s + main も fail + ログに `recent account payments have failed` | https://github.com/settings/billing/spending_limit |
| Anthropic classifier outage | tool_use が `auto mode classifier 拒否` で連続失敗 / 障害ステータス | https://status.anthropic.com |
| Apple Developer cert 期限切れ | xcodebuild が `code signing` で失敗 / cert 期限ログ | Xcode / Apple Developer 設定 |
| Package registry outage | `pod install` / `npm` / `pip` が DNS or 502/503 | プロバイダ status |
| GitHub API rate limit | `gh api` が 403 + `rate limit exceeded` | `gh auth refresh` or 待機 |
| Copilot レビュー停止（quota/サブスク/repo 設定） | レビュー依頼 POST が **200 を返すのに `requested_reviewers` に無反映**（`Copilot` / `copilot-pull-request-reviewer[bot]` 両名義で再現）。裏取り: 直近マージ済み PR のレビュー実績を `gh pr view N --json reviews` で確認し、ある時点以降 **repo 全体でレビューなし**なら外部要因確定 | リトライ停止 → 人間に Copilot サブスク/quota/repo 設定の確認を依頼。マージ判断は「レビューなしマージ（過去 PR と同運用）」を選択肢として提示 |
| GitHub API 障害の回復期残滓（GraphQL のみ 401） | `gh auth status` 正常 + githubstatus は復旧済みなのに特定 gh サブコマンド（`gh pr merge` / `gh pr checks` 等）だけ 401 連発 | REST 等価エンドポイントで貫通を試す（下記） |

### GraphQL のみ 401 が残る回復期パターン

GitHub の認証系障害は「status ページ復旧後も GraphQL API にだけ 401 残滓が残る」ことがある（実例: 復旧宣言後も `gh pr merge` が 5 回連続 401、REST は全て 200）。`gh pr merge` / `gh pr checks` などのサブコマンドは内部で GraphQL を使うため、この残滓に巻き込まれる。

**「auth は正常・status は復旧済み・特定 gh コマンドだけ 401」のときはコード/認証起因を疑わず、REST 等価エンドポイントを試す:**

```bash
# gh pr merge の代替
gh api -X PUT repos/OWNER/REPO/pulls/N/merge -f merge_method=merge
# gh pr checks の代替（check-runs API）
gh api repos/OWNER/REPO/commits/SHA/check-runs --jq '.check_runs[]|{name,conclusion}'
```

REST が通れば作業は止めずに完了できる。リトライ待機（数十分）より先にこの貫通を試す。
