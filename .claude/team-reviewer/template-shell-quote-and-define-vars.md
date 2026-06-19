---
name: template-shell-quote-and-define-vars
description: テンプレート文書のシェル例は変数を一貫してクォートし、同概念の変数名を統一し、参照変数を同スコープで定義／注釈する
polarity: do
severity: MEDIUM
trigger:
  globs:
    - ".claude/**/*.md"
    - "templates/**/*"
    - "**/SKILL.md"
    - "**/README.md"
  keywords:
    - "```bash"
    - "```sh"
    - "git -C"
    - "$REPO"
    - "$PR"
    - "$BRANCH"
source: pr-history
origin: pr-history:template-skill-docs
---

## 観点

テンプレ・skill 文書のシェル例（コードフェンス内）について、以下を満たす:

1. **変数は一貫してダブルクォート**する（`"$REPO"`、`"$PR"`）。空白を含むパスでも壊れない例にする
2. **同じ概念の変数名はファイル内で統一**する（`RUN_ID` と `$RUN` を混在させない、`BRANCH_NAME` と `BRANCH` を混在させない）
3. **参照する変数は同コードフェンス内で定義**するか、定義しないなら「ランタイム値です／呼び出し側で `export` してください」と注釈する

## Why

コードフェンスはそのままコピペされる前提で読まれる。クォート抜け／変数名ブレ／未定義変数があると、空白パス環境や別読者の手元で壊れる。過去 PR で Copilot から「`gh ... -R $REPO` が未クォート」「`RUN_ID` と `$RUN` の混在」「`$WORKER_PANE` が定義されていない」が**繰り返し**指摘されている。

## チェック方法

- 変更ファイル内のコードフェンスを抜き出し、`$[A-Z_]+` の出現について以下を確認:
  - 全箇所で `"$VAR"` クォートされているか
  - 同じ意味の変数が複数命名で書かれていないか（`RUN_ID` vs `$RUN` 等）
  - その変数がコードフェンス内で `VAR=...` で定義されているか、無い場合は本文に「ランタイム値」注釈があるか
- 関連: [[template-no-hardcoded-personal-paths]] / [[doc-cross-platform-tool-assumption]]
