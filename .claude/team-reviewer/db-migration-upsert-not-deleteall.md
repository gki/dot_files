---
name: db-migration-upsert-not-deleteall
description: 起動時 DB マイグレーションは write tx 冒頭で deleteAll しない / 旧データは upsert で取り込みユーザーの新規データを保持する
polarity: do
severity: CRITICAL
trigger:
  globs:
    - "**/Migrator*.swift"
    - "**/*Migration*.swift"
  keywords:
    - "Migrator"
    - "deleteAll"
    - "DELETE FROM"
    - "DROP TABLE"
    - "INSERT OR REPLACE"
    - "ON CONFLICT DO UPDATE"
source: memory
origin: memory:data-migration-merge-strategy
---

## 観点

起動時 DB マイグレーションの write tx 冒頭で `deleteAll`（または `DROP`）してから旧データを書き込む実装を採用しない。旧データ取り込みは id 一致更新の upsert（`save` / `INSERT OR REPLACE`）で行い、ユーザーが既に作った別 id データは保持する。

## Why

冪等性のために `deleteAll` を入れると、移行が一度失敗（rollback・マーク未記録）→ ユーザーが空 DB で新規データ作成 → 次回起動時のマイグレーション成功時の `deleteAll` でユーザー作成データが消える、というデータ損失リスクが残る。atomic tx は失敗時に rollback されるので `deleteAll` で冪等化する必要はそもそもない。upsert なら旧データを id 一致更新するだけになり、ユーザー作成データは保持される。実プロジェクトの全面移行 PR のレビューで採用された方針。

## チェック方法

- Migrator の write tx 内の最初の数行に `deleteAll` / `DELETE FROM` / `DROP TABLE` が無いか確認
- 旧 → 新の書き込みが id をキーにした upsert（`save` / `INSERT OR REPLACE` / `ON CONFLICT DO UPDATE`）になっているか
- 「移行マーク未記録 → 次回再実行」のシナリオでユーザー新規データが消えないかを思考実験する
- 関連: [[db-migration-no-managed-cross-thread]]
