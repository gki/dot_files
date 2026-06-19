---
name: doc-no-specific-issue-numbers
description: 汎用テンプレ/再利用 doc に特定 issue/PR 番号を埋め込まない / placeholder 表記を PR 内で統一する
polarity: dont
severity: MEDIUM
trigger:
  globs:
    - ".claude/**/*.md"
    - "templates/**/*"
    - "**/SKILL.md"
    - "**/README.md"
  keywords:
    - "PR #"
    - "issue #"
    - "{{MAIN_REPO}}"
    - "{{REPO}}"
source: pr-history
origin: pr-history:template-skill-docs
---

## 観点

複数環境で再利用される doc（テンプレ・skill 本文・README）に、特定プロジェクトの issue/PR 番号（数桁の `#NNN` 形式）を埋め込まない。本文中での placeholder 表記（`{{REPO}}` / `{{MAIN_REPO}}` / `<PR>` 等）は同一 PR 内で統一する。

## Why

特定 issue 番号は別プロジェクトに転用された瞬間に意味を失い、汎用テンプレを汚す。プレースホルダ表記が PR 内でブレる（例: 同概念に `{{MAIN_REPO}}` と `{{REPO}}` が混在）と、コピペ運用者がどちらが正かを判断できない。過去 PR で Copilot から「PR description には『issue 番号を含めない』とある一方で SKILL.md に多数の `#xxx` が埋まっている」「同 PR で placeholder 命名が一貫しない」と指摘されている。

## チェック方法

- 変更ファイル内に `#<3-4 桁の数字>` が無いか（`grep -E "#[0-9]{2,4}\b"`）。あるなら「過去 PR で実例」等に丸める or 削除
- プレースホルダ命名を PR 内で抜き出して統一されているか確認
- 関連: [[skill-doc-stays-on-purpose]]
