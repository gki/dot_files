---
name: pr-record-self-review
description: >
  Use when recording structured self-review results (code-review / team-reviewer
  findings with fixed/rejected/out-of-scope dispositions) on a GitHub PR as
  inline review comments. Triggers: "セルフレビュー結果を記録", "レビュー記録を投稿",
  "構造化レビュー記録", "record self-review", "self-review record",
  "レビュー結果をPRに記録", "dogfood レビュー記録".
---

# セルフレビュー結果の構造化記録（PR インラインレビュー）

## Core Principle

セルフレビュー（`/code-review` + `team-reviewer`）の指摘を、**Copilot レビューと同一の
reviewThread 構造**で PR に記録する。これにより:

- 指摘ごとの対応（fixed / rejected / out-of-scope）が監査痕跡としてスレッドに残る
- supervisor の独立検証が「未解決スレッド 0 件」という既存の機械判定をそのまま使える

## 前提

- セルフレビューの triage・修正・再レビュー（新規 CRITICAL/HIGH 0 件）が**完了済み**で
  あること。本スキルは結果の**記録**フェーズ
- PR 作者自身でも `event=COMMENT` レビューは投稿可能（`APPROVE` / `REQUEST_CHANGES`
  は 422 拒否されるため使わない）

## 記録フォーマット v1

### サマリ（review body）

```markdown
<!-- self-review-record v1 -->

## セルフレビュー記録（code-review high + team-reviewer）

- 指摘総数: N 件（CRITICAL: n / HIGH: n / MEDIUM: n / LOW: n）
- 対応内訳: fixed: n / rejected: n / out-of-scope: n
- 最終確認: 修正反映後の再レビューで新規 CRITICAL/HIGH 0 件（head <short-SHA>）
```

- 先頭のマーカー `<!-- self-review-record v1 -->` は supervisor 機械検証のアンカー。
  **必ず含める**
- 指摘 0 件の場合も「指摘総数: 0 件」のサマリのみ投稿する（レビューを実施した証跡）

### 指摘ごとのインラインコメント（comments[] の body）

```text
[<レビュー種別>][<severity>] <指摘要約>

対応: fixed(<short-SHA>) | rejected(<理由>) | out-of-scope(<理由> / 追跡: #<issue>)
```

- レビュー種別: `code-review` または `team-reviewer:<criterion名>`
  （例: `team-reviewer:docs-impl-consistency`）
- severity: `CRITICAL` / `HIGH` / `MEDIUM` / `LOW`
- 対応は 3 値のいずれか 1 つ。rejected / out-of-scope は理由を 1〜2 文で必ず書く

記入例:

```text
[code-review][HIGH] catch 節で error が握りつぶされ呼び出し元に伝播しない

対応: fixed(0d69c90)
```

## 手順

### Step 1: 投稿データの準備

```bash
# head SHA（修正 push 後に必ず取り直す）
HEAD_SHA=$(gh pr view <N> --json headRefOid --jq .headRefOid)
```

各指摘の path / line を diff と突き合わせて 3 分類する（`gh pr diff <N>` で確認）:

| 指摘位置                                | 投稿方法                                          |
| --------------------------------------- | ------------------------------------------------- |
| diff 内の行                             | Step 2 の `comments[]`（line 指定）               |
| diff 外の行だが path は diff に含まれる | Step 3 の `subject_type=file` 単発 POST           |
| path 自体が diff に無い                 | サマリ body 末尾に「diff 外指摘」節として箇条書き |

### Step 2: reviews API で一括投稿（サマリ + インライン）

**payload は必ず JSON ファイルを `--input` で渡す。** `-f 'comments[][path]=...'` の
連続フラグ形式は、コメントが複数あると gh のパラメータ解釈が壊れて 422
（`side (Field is not defined on DraftPullRequestReviewComment)` 等）になる
（実プロジェクトの dogfood で実証）。

```bash
jq -n \
  --arg body "$(cat /tmp/self-review-summary.md)" \
  --arg sha "$HEAD_SHA" \
  --arg c1 '[code-review][HIGH] 〜の null 参照

対応: fixed(abc1234)' \
  '{
    event: "COMMENT",
    commit_id: $sha,
    body: $body,
    comments: [
      {path: "src/foo.ts", line: 42, side: "RIGHT", body: $c1}
    ]
  }' > /tmp/self-review-payload.json
# comments[] に指摘ごとの {path, line, side, body} を列挙する

gh api repos/OWNER/REPO/pulls/<N>/reviews --input /tmp/self-review-payload.json
```

- **422 が返ったら** エラーメッセージを確認する。line 起因（diff 外）の場合は該当指摘を
  Step 3 へ回し、残りで再実行する
- 通知は 1 レビュー = 1 通にまとまる（指摘ごとに単発 POST しない理由）

### Step 3: diff 外指摘のフォールバック（ファイルレベルコメント）

reviews API の `comments[]` は `subject_type` 非対応のため単発 POST する:

```bash
gh api repos/OWNER/REPO/pulls/<N>/comments \
  -f body='[team-reviewer:docs-impl-consistency][MEDIUM] 〜 / 対応: rejected(〜)' \
  -f commit_id="$HEAD_SHA" \
  -f path=<file> \
  -f subject_type=file
```

### Step 4: 全スレッドを reply + resolve

投稿した各インラインコメント（Step 2・3）はスレッドになる。`/pr-check-review-threads`
の GraphQL クエリで thread id / comment id を取得し、`/pr-resolve-review-thread` の
手順で **reply → resolve** する:

- **resolve してよいのは今回自分が投稿した記録スレッドのみ**（author が自分かつ本文が
  `[<レビュー種別>][<severity>]` で始まるもの）。他レビュアー（Copilot 等）の未解決
  スレッドが同居していても触れない — それらは通常のレビュー対応フローで処理する

- fixed: 「修正反映済み（<short-SHA>）」
- rejected / out-of-scope: 「本文記載の判断のとおりクローズ」

> 記録の本文に対応が書かれていても resolve は省略しない。「未解決スレッド 0 件」が
> worker / supervisor 共通の完了判定だからである。

### Step 5: 未解決スレッド 0 件の最終確認

```bash
gh api graphql -f query='
query {
  repository(owner: "OWNER", name: "REPO") {
    pullRequest(number: <N>) {
      reviewThreads(last: 100) {
        nodes { isResolved }
      }
    }
  }
}' --jq '[.data.repository.pullRequest.reviewThreads.nodes[]
         | select(.isResolved == false)] | length'
```

`0` が返れば記録完了。

## supervisor の機械検証

supervisor（または人間）は以下 2 点で記録の存在と完了を機械確認できる:

```bash
# 1) マーカー付き記録レビューが存在する（>= 1）
gh api repos/OWNER/REPO/pulls/<N>/reviews --paginate \
  --jq '.[] | select(.body | contains("<!-- self-review-record v1 -->")) | .id' | wc -l

# 2) 未解決スレッドが 0 件（Step 5 と同一クエリ）
```

> `--paginate` と `--jq` の併用は **jq がページごとに適用される**。`[...] | length` 形式は
> ページごとの件数が複数行出力されるため使わない（マッチ行を出力して `wc -l` で合算する）。

## 禁止事項

- マーカー `<!-- self-review-record v1 -->` なしで投稿する（機械検証不能になる）
- スレッドを resolve せず放置する（完了条件「未解決スレッド 0 件」に反する）
- `event=APPROVE` / `REQUEST_CHANGES` を使う（PR 作者自身は 422）
- `gh pr comment` のみで済ませる（スレッド化されず resolve 不可・監査痕跡が残らない。
  使ってよいのは path 自体が diff に無い指摘のサマリ内記載のみ）
