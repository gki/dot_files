---
name: host-init-precedes-data-migration
description: storyboard root の UIHostingController サブクラスの init はアプリ起動時の DB マイグレーション処理より早く走るので、init で永続層を開かない
polarity: dont
severity: HIGH
trigger:
  globs:
    - "**/*.storyboard"
    - "**/*HostingController*.swift"
  keywords:
    - "UIHostingController"
    - "init?(coder"
    - "migrate"
    - "schema version"
    - "didFinishLaunchingWithOptions"
source: memory
origin: memory:storyboard-hosted-vm-init-order
---

## 観点

`UIHostingController` のサブクラス（`init?(coder:rootView:)`）を Storyboard の scene root にしている場合、その `init` は **Storyboard インスタンス化時＝アプリ起動時に `application(_:didFinishLaunchingWithOptions:)` の永続層マイグレーション処理が走るより前**に呼ばれる。init で生成する ViewModel が DB を開くと、未マイグレーション状態（schema version 0）で開いてクラッシュする。

## Why

タブ root の HostingController は旧 UIKit VC（`viewWillAppear` で DB を取得）と違い、ViewModel を `init` で作るため永続層アクセスが起動の最序盤に前倒しされる。タブの relationship segue で root VC が即時生成されるのが原因。実プロジェクトの移行 PR で「Provided schema version 0 is less than last set version 1」クラッシュが実際に発生した。

## チェック方法

- Storyboard root の HostingController が持つ ViewModel は `init` で永続層（Realm / GRDB / CoreData 等）に触れない
- 一覧データの初回ロードは `viewWillAppear` 経由の `refresh()` 等に遅延させる（`init` は空配列で開始）
- 関連: [[db-migration-no-managed-cross-thread]] / [[db-migration-upsert-not-deleteall]]
