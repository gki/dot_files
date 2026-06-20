---
name: db-migration-no-managed-cross-thread
description: 移行 Migrator は旧 ORM の managed object を別スレッド write クロージャに持ち込まない / 同スレッドで値型に変換してから渡す
polarity: dont
severity: CRITICAL
trigger:
  globs:
    - "**/Migrator*.swift"
    - "**/*Migration*.swift"
  keywords:
    - "Migrator"
    - "dbQueue.write"
    - "managed object"
    - "Realm.objects"
    - "NSManagedObjectContext"
source: memory
origin: memory:data-migration-thread-safety
---

## 観点

旧 ORM（例: Realm）→ 新 ORM（例: GRDB）の Migrator で、旧側の managed object を新側の write クロージャ（別スレッドで実行される）に持ち込んでプロパティアクセスしない。旧側を開いたスレッド上で値型レコードへ `.map` 変換してから、値型のみを write クロージャに渡す。

## Why

旧 ORM の managed object はスレッド制約を持つ（Realm はスレッド固有、CoreData は context 固有等）。新 ORM の write は専用 serial queue（別スレッド）で実行されることが多い。クロージャ内で旧 managed object のプロパティに触れると即クラッシュする。in-memory のテストでは再現せず本番ディスクで顕在化することがあり、テスト緑でも潜在バグが残る。実プロジェクトの全面移行 PR で実際にレビューで指摘・修正された。

## チェック方法

- Migrator 内で「旧 ORM を開く」「`.map { ... }` で値型に変換」「クロージャに値型のみ渡す」の 3 段を分ける
- 新 ORM の write クロージャ内で旧型の参照を探す（`grep -E "(Realm|managed)" Migrator*.swift` 等）
- 関連: [[db-migration-upsert-not-deleteall]] / [[host-init-precedes-data-migration]]
