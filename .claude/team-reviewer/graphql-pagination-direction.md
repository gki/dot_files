---
name: graphql-pagination-direction
description: 「未解決件数の網羅判定」に reviewThreads(last:N) は使わない / 取りこぼし回避には first:N で先頭から取る
polarity: do
severity: HIGH
trigger:
  globs:
    - "**/*.md"
    - "**/*.sh"
    - ".github/workflows/**/*.yml"
  keywords:
    - "gh api graphql"
    - "reviewThreads"
    - "(last:"
    - "pageInfo"
    - "isResolved"
source: pr-history
origin: pr-history:graphql-pagination
---

## 観点

GitHub GraphQL の `reviewThreads(first/last:N)` や類似の paginatable connection で、**未解決件数の網羅判定**を `last:N` で行わない。先頭から `first:100`（最大）で取る。1 ページに収まらないなら pageInfo+cursor で続きを取る。

## Why

`last:50` 指定では新しい方から 50 件しか返らず、古い未解決スレッドを取りこぼす。「未解決＝0」と誤判定し、本来 wait すべきフェーズで PR 完了とみなして次工程へ進めてしまう。過去 PR で Copilot から指摘されている。

## チェック方法

- 「網羅判定」「unresolved=0 で完了」のような条件を回す GraphQL は `first:` を使う
- `last:` を使ってよいのは「最新 N 件だけ取得したい」用途に限定
- 1 ページの最大は connection 型に依存（多くは 100）。それを超え得る場面は pageInfo を見て続きを取る
- 関連: [[gh-cli-jq-camelcase]]
