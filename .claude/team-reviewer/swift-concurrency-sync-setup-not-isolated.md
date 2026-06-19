---
name: swift-concurrency-sync-setup-not-isolated
description: strict concurrency CI で @MainActor XCTestCase の同期 setUp/tearDown が isolated プロパティに触れると失敗 / async override にする
polarity: dont
severity: HIGH
trigger:
  globs:
    - "**/*Tests/**/*.swift"
    - "**/*Test.swift"
  keywords:
    - "@MainActor"
    - "XCTestCase"
    - "override func setUp"
    - "strict concurrency"
    - "main actor-isolated"
source: memory
origin: memory:swift-concurrency
---

## 観点

`@MainActor final class FooTests: XCTestCase` で同期の `override func setUp()` から main-actor 分離のインスタンスプロパティに触れない。strict concurrency を有効化している CI のビルドで「main actor-isolated property ... can not be mutated/referenced from a nonisolated context」エラーになる。

## Why

同期 `setUp()` / `tearDown()` は基底の nonisolated 同期メソッドの override で、分離属性を付けられない。実プロジェクトの CI（strict concurrency 有効）で、ローカル成功でも CI のビルドフェーズだけ失敗し、push → CI 失敗 → 修正 → 再 push のラウンドトリップを浪費する。

## チェック方法

- `@MainActor` XCTestCase で `setUp` / `tearDown` から isolated プロパティを使うなら、`@MainActor override func setUp() async throws { ... }` の async override にする（async override には `@MainActor` を付与でき分離が解決する）
- 同期 `setUp` で済ませたいなら、`UserDefaults.standard` のような共有値を直接使い、テストクラスに isolated stored property を持たせない
- ローカルだけでなく CI と同等の strict concurrency 設定でビルドして裏取りする
