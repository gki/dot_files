---
name: icon-bbox-must-measure
description: アイコン/SF Symbol の W×H サイズ差は罫線 Y・テキスト帯 Center Y では検出できない / bbox 軸を別途実測
polarity: do
severity: MEDIUM
trigger:
  globs:
    - "**/screenshots/**"
  keywords:
    - "SF Symbol"
    - "Image(systemName"
    - "ToolbarItem"
    - "ボタンアイコン"
    - "icon bbox"
source: memory
origin: memory:icon-rendering-checks
---

## 観点

アイコン/SF Symbol を含む画面の視覚検証で「罫線 Y」「水平 X」「テキスト帯 Center Y」だけで一致を主張しない。アイコン bbox（W×H）の実測を追加する。

## Why

罫線スキャンは全幅罫線、テキスト帯は閾値超ピクセル数で帯を切り出し中心 Y を比較する。どちらも「アイコンが同じ Y に描画されているか」しか見ない。アイコン自体の幅・高さは bbox W/H を取らないと出ない。実プロジェクトで Play/Pause/Stop アイコンが約 2.3 倍に肥大していたが、中心 Y は一致するため worker と supervisor の自動検査をすり抜けた事例がある。

## チェック方法

- 移行や UI 変更でボタン/アイコンを含む画面の検証では、アイコン bbox 軸を追加実測する
  - 閾値 200（白系背景）または 80（暗系背景）で 2 値化 → 各ボタン領域内の min/max XY → W=max-min を出して before/after 比較
  - Δ W/H とも ±3px 以内で合格
- 同種アイコン群（再生系コントロール、ナビバーアイコン等）の中で**一部だけ大きい/小さい**ことに注目すると検出しやすい
- 関連: [[screenshot-diff-uses-tooling]] / [[ui-migration-cumulative-drift]]

> 数値（閾値 200/80、許容差 ±3px）は元の実プロジェクト memory の経験則。プロジェクト初回適用時にキャプチャ条件に合わせて再校正する。
