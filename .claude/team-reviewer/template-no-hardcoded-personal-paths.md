---
name: template-no-hardcoded-personal-paths
description: テンプレート/再利用 doc/skill のサンプル中に個人実パス（/Users/<name>/…）や個人 git user・メールを含めない
polarity: dont
severity: HIGH
trigger:
  globs:
    - ".claude/**/*.md"
    - "templates/**/*"
    - "**/SKILL.md"
    - "**/README.md"
  keywords:
    - "/Users/"
    - "/home/"
    - "C:\\Users\\"
    - "{{HOME}}"
    - "{{REPO}}"
source: pr-history
origin: pr-history:template-skill-docs
---

## 観点

複数環境で読まれることが前提のテンプレート・skill 文書・README で、サンプルコードに個人実パス（`/Users/<name>/...`、`/home/<user>/...`、`C:\Users\<user>\...` 等）や個人 git user 名・メールアドレスを含めない。プレースホルダ（`/path/to/...` / `{{MAIN_REPO}}` / `<HOME>`）か汎用例に置き換える。

## Why

テンプレートは別マシンへコピーして使われる。個人パスや個人 ID が混入していると再利用性が下がるだけでなく、リポジトリ公開時に個人情報の意図せぬ流出になる。過去 PR でも Copilot から繰り返し同種の指摘が入った。

## チェック方法

- `git diff` 内に `/Users/`, `/home/`, `C:\Users\` の文字列が無いか確認（コード例・出力例・コメント全て）
- 個人 git user 名・メアド・マシン名・ホスト名が混入していないか確認
- プレースホルダ表記は同一 PR 内で表記を統一する（[[doc-no-specific-issue-numbers]] と同じく一貫性が大事）
- 関連: [[template-shell-quote-and-define-vars]]
