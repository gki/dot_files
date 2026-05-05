---
name: pr-resolve-review-thread
description: >
  Use when replying to a PR review comment and marking the thread as resolved.
  Triggers: "レビュー指摘に返信", "スレッドをresolve", "コメントに対応した旨を返信",
  "レビューコメントを解決済みにする", "resolve review thread", "reply to review comment",
  "対応済みとしてマーク", "スレッドを閉じる", "修正をレビュアーに伝える".
---

# レビュースレッドへの返信とresolve

## Core Principle

対応完了後は必ず **返信 → resolve** の順で実行する。resolveだけでは指摘者に通知が届かない。

## 必要な情報

`/pr-check-review-threads` の出力から取得する:

- `cid` → COMMENT_ID（返信のin_reply_toに使用）
- `id` → THREAD_NODE_ID（resolveのthreadIdに使用）

## 手順

### Step 1: 返信（in_reply_toでスレッドに紐づけ）

```bash
gh api repos/OWNER/REPO/pulls/PR/comments \
  -X POST \
  -f body="修正しました。対応コミット: COMMIT_SHA" \
  -F in_reply_to=COMMENT_ID \
  --jq '.id'
```

### Step 2: スレッドをresolve（GraphQL mutation）

```bash
gh api graphql -f query='
mutation {
  resolveReviewThread(input: {threadId: "THREAD_NODE_ID"}) {
    thread { id isResolved }
  }
}'
```

`isResolved: true` が返れば成功。

## ID の区別（重要）

| 変数 | 形式 | 使用場面 |
|------|------|---------|
| THREAD_NODE_ID | `PRRT_xxx`（GraphQL node ID） | resolveReviewThread mutation |
| COMMENT_ID | 数値（REST API ID） | in_reply_to パラメータ |

REST APIのcomment IDとGraphQLのthread IDは**別物**。混同するとエラーになる。

## よくあるミス

| ミス | 正しい方法 |
|------|-----------|
| resolveだけしてコメントなし | 返信→resolveの順で必ず両方実行 |
| comment IDをthreadIdに使う | GraphQLのthread node ID（PRRT_xxx）を使う |
| GraphQL IDをin_reply_toに使う | REST APIのdatabaseId（数値）を使う |

## 次のステップ

全スレッドのresolve後 → `/pr-request-rereview` でCopilotに再レビューを依頼
