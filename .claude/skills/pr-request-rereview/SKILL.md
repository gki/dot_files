---
name: pr-request-rereview
description: >
  Use when requesting a re-review on a PR after addressing review comments,
  especially for Copilot or bot reviewers.
  Triggers: "再レビューを依頼", "Copilotにレビューを頼む", "re-review", "レビュー依頼",
  "コードレビューを再依頼", "request review again", "Copilotでレビュー",
  "全指摘対応後に再レビュー", "レビュアーにレビュー依頼".
---

# Copilot再レビュー依頼（スレッドresolveを含む完全フロー）

## Core Principle

**再レビュー依頼の前に、対応済みの全スレッドを必ずresolveすること。**
resolveしないままだと古い指摘がCopilotの再レビュー対象に残り、循環する。

## 完全フロー

```
1. 未解決スレッドを確認（GraphQL）
2. 対応済みスレッドを全件 返信 → resolve
3. Copilotを再レビュアーとして登録（DELETE → POST）
4. Copilotがrequestedに追加されたか確認
```

---

## Step 1: 未解決スレッドを確認

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
}' --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false) | {id: .id, cid: .comments.nodes[0].databaseId, body: .comments.nodes[0].body[:120]}'
```

**出力が空** → Step 3へスキップ  
**出力あり** → 各スレッドに対して Step 2 を実行

---

## Step 2: 各スレッドに返信してresolve

### 2a: 返信（修正済みコミットを明示）

```bash
gh api repos/OWNER/REPO/pulls/PR_NUM/comments \
  -X POST \
  -f body="修正しました（COMMIT_SHA）" \
  -F in_reply_to=COMMENT_ID \
  --jq '.id'
```

### 2b: スレッドをresolve

```bash
gh api graphql -f query='
mutation {
  resolveReviewThread(input: {threadId: "THREAD_NODE_ID"}) {
    thread { id isResolved }
  }
}'
```

`isResolved: true` が返れば成功。全スレッド分繰り返す。

---

## Step 3: Copilotを再レビュアーとして登録

```bash
# DELETE（既存リクエストを除去）
gh api repos/OWNER/REPO/pulls/PR_NUM/requested_reviewers \
  --method DELETE \
  -f 'reviewers[]=copilot-pull-request-reviewer'

# POST（再登録）
gh api repos/OWNER/REPO/pulls/PR_NUM/requested_reviewers \
  -X POST \
  --raw-field 'reviewers[]=copilot-pull-request-reviewer[bot]'
```

**重要**: `--raw-field` を使い、ログイン名は `[bot]` サフィックスつきで指定すること。  
`-f` や `[bot]` なしでは 422 エラーになる。

---

## Step 4: 登録確認

```bash
gh api repos/OWNER/REPO/pulls/PR_NUM/requested_reviewers \
  --jq '.users[].login'
```

`Copilot` が表示されればレビュー待ち状態。

---

## よくあるミス

| ミス | 正しい方法 |
|------|-----------|
| スレッドを resolveせずに再レビュー依頼 | Step 2 で全スレッドを先にresolveする |
| `-f` フラグを使う | `--raw-field` を使う |
| `[bot]` サフィックスなし | `copilot-pull-request-reviewer[bot]` と指定する |
| PRコメントで `@copilot review` を送る | Step 3 の API 操作を使う |
| THREAD_NODE_ID に REST API の数値IDを使う | GraphQL の `PRRT_xxx` 形式を使う |
