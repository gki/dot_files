---
name: migration-fidelity-design-doc
description: 移行画面の視覚検証は統一値（DESIGN.md 等の正準）が基準 / 不統一な旧画面に pixel-match 追従しない
polarity: do
severity: MEDIUM
trigger:
  globs:
    - "docs/DESIGN.md"
    - "**/DESIGN.md"
    - "**/Components/**"
  keywords:
    - "DESIGN.md"
    - "cell-label-inset"
    - "デザイントークン"
    - "pixel-match"
    - "移行画面の視覚検証"
source: memory
origin: memory:design-doc-as-source-of-truth
---

## 観点

旧 UI からの移行（リファクタや UIKit→SwiftUI 等）の視覚検証では「旧画面との完全 pixel-match」を絶対基準にしない。プロジェクトの正準（DESIGN.md / 共有 Components / デザイントークン）が基準であり、旧画面自体の不統一には追従しない。一方、累積縦ズレ・行高崩れ・セクション構成といった**レイアウトの崩れ**は厳密に直す。

## Why

実プロジェクトの移行 PR で、旧 Storyboard 側のラベルが行ごとに inset がバラバラだったが、移行後は全行を統一 inset（正準値）に揃えていた。これは正しい改善だったが、不統一な旧側に合わせ直すレビュー指摘が来ると「不統一の再生産」になり退化する。

## チェック方法

- 差分を見たら「バグか／旧画面の不統一に由来する微差か」を切り分ける
  - 同種要素（例 セルラベル）の X/Y を複数測り、旧側がバラついていれば後者
  - 「どの inset 値が使われているか」はピクセル測定でなくコード（`.padding(.leading, N)`）と Storyboard XML（`<constraint constant>`）を読んで確定する。ピクセルの行検出はノイズが多い
- 純粋リファクタ（同じ実装の言い換え）は **0px 完全一致**が期待値
- 移行（実装スタックそのものを差し替える）は**累積崩れゼロ**が基準。旧の不統一由来の微差は許容（むしろ改善）
- 関連: [[ui-migration-cumulative-drift]] / [[pixel-repro-needs-custom-layout]]
