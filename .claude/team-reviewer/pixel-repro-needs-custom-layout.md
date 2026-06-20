---
name: pixel-repro-needs-custom-layout
description: 旧 grouped UITableView を SwiftUI で px 単位再現するなら Form/List ではなく ScrollView+VStack 自前
polarity: dont
severity: MEDIUM
trigger:
  globs:
    - "**/*.swift"
  keywords:
    - "Form {"
    - "List {"
    - ".listStyle"
    - "listRowInsets"
    - "ScrollView"
    - "grouped UITableView"
    - "Storyboard 再現"
source: memory
origin: memory:ui-replication-layout-choice
---

## 観点

旧 grouped `UITableView` を SwiftUI で px 単位に再現する設定画面では、`Form` / `List` を使わない。`ScrollView { VStack(spacing: 0) { ... } }` の自前レイアウトに切り替える。

## Why

実プロジェクトのパイロット移行で、`Form` / `List` は `.listStyle(.grouped)` / `.plain` いずれでも content にスタイル固有の左右マージンを足し、`.listRowInsets(EdgeInsets())` / `.alignmentGuide(.listRowSeparator*)` でも完全除去できなかった。ラベル leading / switch trailing / 罫線の描き分け（section 端＝全幅・セル間＝インセット）が px 単位で再現できず、複数バージョン費やした末に ScrollView+VStack 自前に切り替えて初めて一致した。

## チェック方法

- 旧画面の px 単位再現を完了条件に含む SwiftUI 設定画面は最初から ScrollView+VStack で組む
- 確定パターン:
  - 背景は ScrollView 全体に当てる
  - 各 row HStack に `.frame(height: <統一値>)` + background
  - 罫線は `Rectangle().fill(...).frame(height: 1 / displayScale)` を VStack に挟み、section 端／セル間で `.padding(.leading, ...)` を描き分け
  - separator は `1 / displayScale` で物理 1px に固定（0.5pt 固定は @3x で太さがズレる）
  - section header/footer 相当は VStack に `.padding(.vertical, ...)` で再現
- UI test の Toggle 参照は `List` / `VStack` どちらでも `app.switches[...]` でテスト変更不要
- 関連: [[migration-fidelity-design-doc]]

> 「`Form` / `List` で完全除去できない」は元の実プロジェクト memory の経験則（SwiftUI バージョン依存）。プロジェクトで採用前に最新 SwiftUI で再確認する。
