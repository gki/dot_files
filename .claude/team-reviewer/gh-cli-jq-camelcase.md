---
name: gh-cli-jq-camelcase
description: gh CLI の --json フィールドは camelCase / startedAt であり started_at ではない / --jq は単一フィルタ文字列のみ受ける
polarity: do
severity: MEDIUM
trigger:
  globs:
    - "**/*.md"
    - "**/*.sh"
    - ".github/workflows/**/*.yml"
  keywords:
    - "gh api"
    - "gh run"
    - "gh pr"
    - "--json"
    - "--jq"
source: pr-history
origin: pr-history:gh-cli-usage
---

## 観点

`gh ... --json field1,field2 --jq '<filter>'` の使い方に以下を満たす:

1. `--json` で指定するフィールド名は **camelCase**（`startedAt`、`createdAt`、`headRefName` 等）。snake_case（`started_at` / `head_ref_name`）は無効
2. `--jq` は **単一の jq フィルタ文字列**を取る。`--jq -r .foo` のように別フラグを差し込めない（`-r` は jq オプションだが `--jq` の中には書けない）。raw 出力は `--jq '.foo'` のまま指定すれば適切に整形される

## Why

`gh ... --json started_at` は空フィールド扱いになり、後段の jq が「該当値なし」のまま進む。誤った時系列推定や CI 状態の誤判定につながる。過去 PR で Copilot から両パターンとも指摘されている。

## チェック方法

- `gh ... --json` の右辺に snake_case が混じっていないか確認（`grep -E "gh .*--json [a-z_]*_[a-z_]+"`）
- `gh ... --jq` の引数が複数トークンになっていないか（`--jq -r .field` 形は不可）
- 公式の field 名は `gh api repos/X/Y/issues/1 -q '.' | jq 'keys'` 等で確認できる
- 関連: [[graphql-pagination-direction]]
