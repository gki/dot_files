---
name: xml-color-not-source-of-truth
description: Storyboard/XIB の色属性は appearance proxy で上書きされ得る / 実描画色は旧ビルドの before スクショで確認する
polarity: dont
severity: MEDIUM
trigger:
  globs:
    - "**/*.storyboard"
    - "**/*.xib"
  keywords:
    - "UIAppearance"
    - "appearance()"
    - "setupAppearances"
    - "Storyboard 色"
source: memory
origin: memory:ui-rendering-runtime-overrides
---

## 観点

旧 UIKit 画面の色を別レイヤ（SwiftUI 等）に写すとき、Storyboard/XIB の XML に書かれた色属性を「実描画色」として扱わない。`UIAppearance.appearance().textColor = ...` のようなランタイム設定で上書きされていることがある。

## Why

実プロジェクトの移行で、Storyboard XML の `detailTextLabel` 色属性（system link blue）を正準値として転記したが、`AppDelegate` 内の appearance 設定で別色に上書きされており実機は明色だった。移行先で青のまま実装してしまい、before/after 比較で初めて気づいた。UIAppearance proxy はビューが window 階層に入る時点で適用され、Storyboard で個別設定した色属性より優先されることがある。

## チェック方法

- XML の色属性は「設計意図の手がかり」までに留め、移行レビューでは旧ビルドを別 worktree でビルドして before スクショの実描画色（RGB サンプリング）と一致させる
- 該当する appearance 系設定（`UILabel.appearance()`、`UINavigationBar.appearance()` 等）の有無を全文検索する
- 関連: [[screenshot-diff-uses-tooling]]（RGB サンプリングは罫線・余白だけでなく色リグレッション検出にも使う）
