---
name: ui-migration-cumulative-drift
description: UI 移行の検証は全画面の全幅罫線を本数+Y で比較する / 部分計測は累積ズレを見逃す
polarity: do
severity: HIGH
trigger:
  globs:
    - "**/screenshots/**"
  keywords:
    - "SwiftUI 移行"
    - "UIKit→SwiftUI"
    - "Storyboard → SwiftUI"
    - "ScrollView+VStack"
    - "tableHeaderView"
    - "section header"
source: memory
origin: memory:ui-migration-verification
---

## 観点

UI 移行（旧スタックから新スタックへ移し替える PR）のレイアウト検証は、画面全体の全幅罫線を上から下まで全数検出して本数一致と Y 座標 diff（±3pt 以内）で判定する。特定要素のサンプル計測で「整合」と結論しない。

## Why

実プロジェクトの移行 PR で、特定要素だけ計測した PIL 検証で「整合」と報告したが、全画面計測で最大 +250px 相当の累積縦ズレが判明し差し戻された事例がある。各セクションの僅かな余白差（+18pt 等）は単体では小さく見えるが、画面を下るほど累積する。

## チェック方法

1. レイアウト検証は画面全体の全幅罫線（separator）を全数検出 → 本数一致 → 各 Y 座標 diff ±3pt を確認
   - 「x 方向のほぼ全幅が明色」の行のみを罫線と判定（局所的な明色は除外、テキスト誤検出回避）
   - 本数がずれると index 対応もずれて diff が無意味になる
2. 旧 grouped UITableView を `ScrollView + VStack` へ移す際の典型バグ 2 種:
   - tableHeaderView 直後のセクション 0 ヘッダーは 0pt（18pt の section header gap は入らない）。最初のセクションに `.padding(.top, 18)` を付けると先頭から 18pt 累積ズレ
   - SwiftUI `Text` はカスタムフォントの行高で旧 UILabel の固定高さ制約より背が高くなりやすい。height 制約があるセル相当は `.frame(height: N)` で同値固定する
3. `.frame(maxWidth: .infinity, height: N)` は SwiftUI でコンパイルできない。`.frame(height: N).frame(maxWidth: .infinity)` と 2 連鎖にする
- 関連: [[screenshot-diff-uses-tooling]] / [[xml-color-not-source-of-truth]]
