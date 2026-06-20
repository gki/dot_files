---
name: skill-doc-stays-on-purpose
description: skill 文書に主責務外の節を入れない / 別 skill に移すべき内容は cross-reference で繋ぐ
polarity: dont
severity: MEDIUM
trigger:
  globs:
    - ".claude/skills/**/*.md"
    - ".claude/team-reviewer/**/*.md"
  keywords:
    - "Out of MVP"
    - "scope 外"
    - "主責務"
source: pr-history
origin: pr-history:skill-scope
---

## 観点

skill 文書（`SKILL.md` / 観点 `.md`）に、その skill の主責務から逸脱した節を入れない。別 skill に属する内容は「関連: `[[other-skill]]`」のリンクで繋ぎ、本文には書かない。

## Why

skill は description で「いつ使うか」を宣言する。本文がその宣言から逸脱すると description-本文の整合が崩れ、レビュアーも将来の利用者も「この skill は何の責務か」を読み取れなくなる。過去 PR で「PR レビュー未解決スレッド確認」を主責務にする skill に Copilot login 表記揺れの節が混ざっており、責務逸脱を指摘された。

## チェック方法

- 各節（`##` 見出し）が skill description / 観点 description で宣言した主責務に紐づくか確認
- 紐づかない節は別 skill に切り出すか、リンク参照（`[[other-skill]]`）に置き換える
- 同種：「Out of MVP」「scope 外」を本文に明記しておくと将来の節追加レビューがしやすい
- 関連: [[pr-description-impl-scope-match]] / [[doc-no-specific-issue-numbers]]
