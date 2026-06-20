---
name: doc-cross-platform-tool-assumption
description: テンプレ doc が OS 依存ツール（timeout(1) 等）を前提にしない / 注記または代替コマンドを併記する
polarity: do
severity: LOW
trigger:
  globs:
    - ".claude/**/*.md"
    - "templates/**/*"
    - "**/SKILL.md"
    - "**/README.md"
  keywords:
    - "timeout(1)"
    - "gtimeout"
    - "coreutils"
    - "pnpm test --"
source: pr-history
origin: pr-history:template-skill-docs
---

## 観点

テンプレ doc のシェル例で OS 依存ツールを前提にしないか、前提にする場合はその旨を注記する。具体例:

- `timeout(1)` は macOS にデフォルト未収録（Homebrew coreutils の `gtimeout` 等が必要）。「macOS では `brew install coreutils` または `gtimeout` を使う」と注記する
- `pnpm <script> --runInBand` のようにスクリプトへ引数を渡す例は、`pnpm` では `--` 区切り（`pnpm <script> -- --runInBand`）が必要なケースがある（pnpm のバージョン依存）。`--` の有無を明示する
- Markdown 表内に書いた `xcodebuild\|xctest` の `\|` は表のエスケープ表記であり、`grep -E` パイプには使えない。コード例は表から分離して書く

## Why

doc は別 OS／別パッケージマネージャ環境にコピペされる前提で読まれる。前提が暗黙だとそれを満たさない環境で「コマンド not found」「`Unknown option: --xxx`」等の不一致が起きる。過去 PR で Copilot から複数指摘がある。

## チェック方法

- `timeout `、`pnpm `、Markdown 表内の `\|` 等 OS／PM 依存のコマンドを抜き出して、注記または代替が併記されているか確認
- 「macOS で動かないコマンドが Mac 開発前提テンプレに混入」を特に警戒
- 関連: [[template-shell-quote-and-define-vars]]
