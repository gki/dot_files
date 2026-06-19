---
name: pr-check-review-threads
description: >
  Use when checking or monitoring unresolved review threads on a GitHub PR.
  Triggers: "PRの未解決コメントを確認", "レビュー指摘を確認", "未解決スレッドを調べる",
  "PRにレビューが来たか確認", "review threads", "unresolved comments",
  "レビュー監視", "PR review check", "check if there are new review comments".
---

# PR未解決スレッドの確認と対応ワークフロー

## Core Principle

**REST APIのレビュー件数は信頼できない。GraphQLの未解決スレッド数だけを信頼する。**

## 全体フロー（必ずこの順序で実行）

```
1. Copilotのレビュー状態を確認（pending/in_progress の場合は待機）
2. GraphQLで未解決スレッドを取得
3. 未解決スレッドがない → 何もしない（終了）
4. 未解決スレッドがある → 各スレッドを評価（Step A）
5. 評価結果に応じて「対応しない」「対応する」に分類（Step B）
6. 「対応しない」スレッドを一括処理（Step C）
7. 「対応する」スレッドを実装・テスト・プッシュして処理（Step D）
8. 全スレッド処理後 → /pr-request-rereview で再レビュー依頼（必須）
```

**重要**: 指摘を解消した場合は必ず再レビューを依頼すること。依頼なしで終了しない。

---

## Step 1: Copilotレビュー状態の確認

まず REST API でCopilotの最新レビューが完了しているか、および「no new comments」サマリかを確認する。

**⚠️ 必ず `--paginate` を付けること。** レビュー件数が多いPRではページネーションにより最新レビューが漏れる。

```bash
gh api repos/OWNER/REPO/pulls/PR/reviews --paginate \
  --jq '[.[] | select(.user.login | ascii_downcase | contains("copilot"))] | last | {state: .state, submitted_at: .submitted_at, body: .body}'
```

**stateの解釈**:
- **`PENDING`** → レビュー中。まだ未提出。`sleep 60` して再確認する
- **`COMMENTED`** → レビュー完了 → bodyを確認する（下記）
- **`APPROVED`** → 承認。指摘なし → Step 2で念のため未解決スレッド確認
- **出力なし** → Copilotがまだレビューを開始していない → `sleep 60` して再確認する

**PENDING または出力なしの場合は絶対に未解決スレッド確認をスキップし、1分待って再実行すること。**

### bodyの解釈（COMMENTEDの場合）

`body` フィールドに以下のようなサマリが含まれる場合は **終了**（再レビュー依頼不要）:

```
"Copilot reviewed N out of M changed files in this pull request and generated no new comments."
```

このサマリが返っている = Copilotは全ファイルをスキャンして新規指摘なし。
**この場合はStep 2に進まず、そのままループを終了する。**

bodyにサマリがなく通常の指摘コメントである場合 → Step 2へ。

---

## Step 2: GraphQL reviewThreads API（レビュー完了後のみ実行）

`last: 100` で最新のスレッドから取得し、jqで `isResolved == false` をフィルタする。

```bash
gh api graphql -f query='
query {
  repository(owner: "OWNER", name: "REPO") {
    pullRequest(number: PR_NUM) {
      reviewThreads(last: 100) {
        nodes {
          id
          isResolved
          comments(first: 1) {
            nodes {
              databaseId
              body
              author { login }
              createdAt
            }
          }
        }
      }
    }
  }
}' --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false) | {id: .id, cid: .comments.nodes[0].databaseId, author: .comments.nodes[0].author.login, created: .comments.nodes[0].createdAt, body: .comments.nodes[0].body[:200]}'
```

### 出力の読み方

- **出力が空** → 未解決スレッド0件（全て対応済み）→ **終了**
- **出力あり** → 未対応の指摘が存在 → Step A（評価フェーズ）へ

---

## Step A: 各スレッドの妥当性評価

未解決スレッドを1件ずつ以下の観点で評価し、「対応する」「対応しない」に分類する。

### 評価観点

#### 1. YAGNI（You Aren't Gonna Need It）チェック
現時点で不要な将来的拡張・抽象化の提案を検出する。

- 「将来的に〜になる可能性がある」「〜に対応できるよう」という表現が含まれる
- 現在の要件・仕様に照らして不要な汎化・インタフェース化の提案
- 現在存在しない利用者・ユースケースを前提とした提案

→ **対応しない**（YAGNI原則に基づき対応不要と判断）

#### 2. DRY（Don't Repeat Yourself）チェック
既存コードの重複指摘が実際に適用可能かを検証する。

- 指摘された重複が実際に存在するか確認
- 既存パターンへの統合が副作用なく可能か確認
- 現実的でない抽象化を強いる場合は対応不要

→ 実際に適用可能 → **対応する**  
→ 強引な抽象化を要求 → **対応しない**

#### 3. 「〜の可能性が高い」指摘の顕在化チェック
「〜になる可能性がある」「〜のリスクがある」「〜が起きやすい」という仮定ベースの指摘を検出し、その問題が実際に顕在化しているかを評価する。

**顕在化していないと判断できる根拠（どれか1つ以上あれば対応不要）:**

- **現在正常動作している** — 問題が既に発生していれば動いていないはず。今動いているなら顕在化していない
- **公式ドキュメントに記載がない** — 公式ドキュメント・リリースノートを確認し、実際に問題とされていない
- **公式ドキュメントが安全と明記** — 指摘された使い方が公式にサポート済み・推奨とされている
- **再現条件が非現実的** — 指摘された問題が発生するための前提条件がこのアプリの実態と合わない

**確認方法:**

1. 現在の動作確認（テスト実行 or 手動確認）
2. Context7 / 公式ドキュメントで該当APIや挙動を検索
3. 問題が顕在化するシナリオがアプリの実態と合致するか判断

→ 顕在化していない / 公式に問題とされていない → **対応しない**（理由を明記して返信）  
→ 顕在化している / 公式が問題を認めている → **対応する**

#### 4. 循環変更チェック
過去のレビューラウンドで既に対応した変更を「元に戻せ」と指摘している、または A→B→A→B... のように同じ箇所への変更が往復している状態を検出する。

- 今回の指摘が「前回の修正コミット以前の状態に戻す」変更を求めていないか確認する
- PR のコメント履歴・コミット履歴を遡り、同一箇所で同じ議論が繰り返されていないか確認する

→ 循環と判断した場合 → **対応しない**（循環の経緯を1〜2文で説明してresolve）

#### 5. 対応済み指摘との矛盾チェック
既に対応済みの別指摘と方向性が矛盾していないか確認する。

- 「A方式にせよ」という済み指摘があるのに「B方式にせよ」という新規指摘
- 既に対応した変更を元に戻すよう求める指摘
- 別スレッドで既に決着した設計方針と逆方向の提案

→ **対応しない**（矛盾を明記して理由を説明）

#### 6. 明らかなバグ・品質問題
上記に該当しないバグ修正、型安全性向上、可読性改善、セキュリティ問題

→ **対応する**

---

## Step B: 分類リストの作成

評価結果を以下の2リストに整理する（実装前に頭の中で整理する）:

```
対応しないリスト:
  - thread_id: PRRT_xxx, 理由: YAGNI（〜という将来的拡張は現在不要）
  - thread_id: PRRT_yyy, 理由: 矛盾（スレッドXXXで採用済みのA方式と逆行）

対応するリスト:
  - thread_id: PRRT_zzz, 概要: 〜のバグ修正
  - thread_id: PRRT_www, 概要: 型安全性の改善
```

---

## Step C: 「対応しない」スレッドの処理

各スレッドに対して **返信 → resolve** の順で実行する。

### C-1: 返信（理由を明記）

```bash
gh api repos/OWNER/REPO/pulls/PR/comments \
  -X POST \
  -f body="このご指摘は現時点では対応しない方針です。\n\n理由: [YAGNI原則 / DRY適用不可 / 対応済み指摘との矛盾] のため。\n[具体的な理由を1〜2文で記載]" \
  -F in_reply_to=COMMENT_ID \
  --jq '.id'
```

**返信文のガイドライン**:
- 理由を明確に1〜2文で説明する
- 「将来必要になった時点で対応します」など前向きな表現を添える
- 批判的にならず、指摘への感謝を示す

### C-2: スレッドをresolve

```bash
gh api graphql -f query='
mutation {
  resolveReviewThread(input: {threadId: "THREAD_NODE_ID"}) {
    thread { id isResolved }
  }
}'
```

---

## Step D: 「対応する」スレッドの処理

### D-1: 対応方針の調査

- 指摘内容・対象ファイル・周辺コードを読み込む
- 修正方針を決定する（複数案があれば最もシンプルな方法を選ぶ）
- 関連するドキュメント（`{{CODING_RULES_DOC}}`、CLAUDE.md）を確認する

### D-2: 実装

- 対応方針に従って修正を実施する
- {{CODING_RULES}} を守る

### D-3: 変更部分のテスト

修正したコードに対応するテストを実行・確認する:

```bash
# 型チェック（必須）
{{TYPE_CHECK_CMD}}

# lint（必須）
{{LINT_CMD}}

# 単体テストがある場合
{{TEST_CMD}}

# E2Eテストがある場合（対象機能のみ）
{{E2E_TEST_CMD}}
```

テストが通らない場合は実装を修正して再実行する。

### D-4: ノンデグレードテスト

変更が既存機能に影響していないことを確認する:

```bash
# 全体の型チェック
{{TYPE_CHECK_CMD}}

# 全体のlint
{{LINT_CMD}}

# 全体の単体テスト（存在する場合）
{{TEST_CMD_ALL}}
```

失敗したテストがある場合は実装を見直す。

### D-5: 変更のプッシュ

```bash
git add <変更ファイル>
git commit -m "fix: [指摘内容の要約]"
git push
```

コミットメッセージはConventional Commitsに従う（feat/fix/refactor/docs/test/chore）。

### D-6: 指摘スレッドへの返信とresolve

**返信**:

```bash
gh api repos/OWNER/REPO/pulls/PR/comments \
  -X POST \
  -f body="修正しました（COMMIT_SHA）。\n\n[変更内容を1〜2文で説明]" \
  -F in_reply_to=COMMENT_ID \
  --jq '.id'
```

**resolve**:

```bash
gh api graphql -f query='
mutation {
  resolveReviewThread(input: {threadId: "THREAD_NODE_ID"}) {
    thread { id isResolved }
  }
}'
```

---

## Step 8: 再レビュー依頼

全スレッドの処理完了後、必ず `/pr-request-rereview` を実行する。

**重要**: 1件でも対応（返信+resolve）したスレッドがあれば再レビュー依頼は必須。

---

## 禁止事項

```bash
# ❌ --paginateなしでレビュー取得 - レビューが多いPRで最新レビューが漏れる
gh api repos/OWNER/REPO/pulls/PR/reviews --jq '...'

# ❌ REST APIのレビュー件数カウント - ページネーション漏れ、キャッシュでズレる
gh api repos/OWNER/REPO/pulls/PR/reviews --jq '... | length'

# ❌ first: Nで取得 - 古い順から取得されるため新しい指摘を見逃す
reviewThreads(first: 50)

# ❌ 指摘を解消して再レビュー依頼なしで終了 - レビュアーに通知が届かない

# ❌ 妥当性評価をスキップして全指摘を機械的に対応 - YAGNI/矛盾指摘を取り込んでしまう

# ❌ 対応しない場合に返信なしでresolve - 指摘者への説明がなく不透明
```

## ID の区別（重要）

| 変数 | 形式 | 使用場面 |
|------|------|---------|
| THREAD_NODE_ID | `PRRT_xxx`（GraphQL node ID） | resolveReviewThread mutation |
| COMMENT_ID | 数値（REST API ID） | in_reply_to パラメータ |

REST APIのcomment IDとGraphQLのthread IDは**別物**。混同するとエラーになる。

## Copilot login の表記揺れ（よくある失敗）

同じ Copilot を指す `login` がエンドポイントごとに別表記になる。monitor やフィルタを `=="Copilot"` の完全一致で組むと **永久に検知漏れ**する。

| 取得元 | `login` の値 |
|---|---|
| `gh api .../pulls/N/reviews` の `.user.login` | `copilot-pull-request-reviewer[bot]` |
| GraphQL `reviewThreads...comments.author.login` | `copilot-pull-request-reviewer`（`[bot]` なし） |
| `requested_reviewers` / PR UI | `Copilot` |

- reviews を数える monitor: `select(.user.login=="copilot-pull-request-reviewer[bot]")`、または `ascii_downcase | contains("copilot")` で表記揺れを吸収する。
- 再レビュー依頼の DELETE/POST は `--raw-field 'reviewers[]=copilot-pull-request-reviewer[bot]'`（`[bot]` 必須・`-f` だと 422）。
- monitor / フィルタを組む前に、実 login を1回 API で確認する（実プロジェクトで実証）。

## 次のステップ早見表

| 状態 | 次のアクション |
|------|--------------|
| CopilotがPENDINGまたは未開始 | `sleep 60` して再実行 |
| Copilotが「generated no new comments」 | **終了**（再レビュー依頼不要） |
| 未解決スレッドなし | **終了** |
| 未解決スレッドあり | Step A〜Step 8を順番に実行 |
