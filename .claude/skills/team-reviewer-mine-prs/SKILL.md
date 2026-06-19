---
name: team-reviewer-mine-prs
description: Use when mining merged PR review threads to draft new team:reviewer knowledge entries. Classifies review comments into accept(do)/reject(suppress)/noise. Triggers: "PR レビューから観点を抽出", "reviewThreads をマイニング", "mine PR reviews for reviewer knowledge".
---

# team-reviewer-mine-prs

マージ済み PR の review thread を分析し、`.claude/team-reviewer/*.md` の観点草案を作る供給スキル（MVP）。

## いつ使うか
- 過去の PR レビューで定着した「採用された指摘」「却下された指摘」を観点として蓄積したいとき
- memory 昇格スキル（`team-reviewer-promote-memory`）と並ぶもう一方の供給経路。memory に残っていない、PR スレッド上の議論から観点を起こす

## 入力

`gh` GraphQL で対象 PR の reviewThreads を取得する（コメント本文・返信・isResolved・diff hunk のパス/行）:

```bash
# 対象 repo の owner/name は cwd から動的取得する（プロジェクト非依存）
OWNER=$(gh repo view --json owner -q .owner.login)
REPO=$(gh repo view --json name -q .name)
gh api graphql -f query='
  query($owner:String!,$repo:String!,$pr:Int!){
    repository(owner:$owner,name:$repo){
      pullRequest(number:$pr){
        reviewThreads(first:100){ nodes{
          isResolved
          path
          line
          comments(first:20){ nodes{ author{login} body } }
        }}
      }
    }
  }' -F owner="$OWNER" -F repo="$REPO" -F pr=<PR番号>
```

## 分類（LLM 判定）

各スレッドを、コメント本文・返信・`isResolved`・後続のコード変更有無から 3 分類する:

- **accept (do)** = 指摘 → コード変更 → resolved。採用された基準 → `polarity: do` の観点草案
- **reject (suppress)** = 指摘 → 反論 → 無変更で resolved。当プロジェクトでは出すべきでない指摘の記録 → `polarity: suppress` の観点草案を作る（B の偽陽性抑制に効く。diff への指摘根拠にはしない）
- **noise** = typo / nitpick / 一過性の質問。観点化しない

## ワークフロー

1. 対象 PR（直近 N 件、または特定 PR 番号）の reviewThreads を取得する
2. 各スレッドを accept / reject / noise に分類する
3. INDEX.md と既存 `.md` を読んで dedup する:
   - 既存観点に近いものは新規作成せず、その `.md` に頻度メモ（「PR#XX でも指摘」）を追記
   - 新規のみ観点草案 `.md` を作成
4. frontmatter は memory 昇格スキル（`team-reviewer-promote-memory`）と同一スキーマ。`source: pr-history`、`origin: PR#<番号>` を付与。author が bot（`copilot-pull-request-reviewer` 等）か人間かは本文の `Why` にメモする（reviewer weight 付けは後続）
5. trigger（globs/keywords）を、指摘が付いた diff hunk の path / 内容から推定して付与する
6. 下記「草案品質ゲート」を全草案に通す
7. **人間レビュー後に commit する**（草案は自動 commit しない）

## 草案品質ゲート

人間レビューに出す前に、各草案へ以下 3 ゲートを必ず通す（初回実行のセルフレビューで実際に検出された品質問題に由来）:

- **(a) 一般則・技術主張の裏取り**: 事例から外挿した一般則・技術主張は、一次ソース（PR スレッド本文・diff）の実証範囲を超えるなら、**repro（`ruby -e` 等の 1 行実証）または repo 内実例で裏取りしてから書く**。
  - 実例（過去 PR で発生した事実誤り 2 件）: 「Actions `run:` は bash デフォルトで pipefail 有効」（誤り — `shell:` 未指定は `bash -e {0}`。手書き `set -o pipefail` している repo が反証）／「Ruby `Array#insert` の負 index はその要素の直前に挿入」（off-by-one — 正しくは**直後**: `ruby -e 'a=[1,2,3]; a.insert(-2,:x); p a'` → `[1, 2, :x, 3]`）
- **(b) trigger の選択性**: trigger は **OR セマンティクス（globs または keywords のどちらかで発火）前提で選択的に**付与する。広 glob（`**/*.swift` 等）＋一般語 keyword（delete / save / Icon / コメント 等）は trigger を実質無効化し、全 PR で deep-read される**常時ロード化**を招くので避ける。
- **(c) 件数・頻度主張の機械集計**: 件数・頻度の主張は **jq 集計の出力をそのまま転記**する（手で数えない）。
  - 実例（過去 PR で発生した手勘定ミス）: 「ある PR で 7 件」（実際 8 件）、「別 PR で各 1 件」（実際 2 件）

## スコープ（MVP）

- 差分自動更新・cron・reviewer weight 付けは **範囲外**
- まず手動トリガで「PR レビュースレッド → 観点草案」を出すところまで
- 関連: 観点の昇格スキーマと INDEX 運用は `team-reviewer-promote-memory` と共通。実体は `.claude/team-reviewer/` に一本化する
- **Out of MVP**: cron 差分自動更新 / reviewer weight 付け / 観点クラスタリング / 既存 .md への自動マージ
