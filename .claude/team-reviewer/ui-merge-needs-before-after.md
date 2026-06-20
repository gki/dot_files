---
name: ui-merge-needs-before-after
description: UI 変更のマージ判断時は before/after スクショ実物を提示する / 「マージしてよいか」とだけ聞かない
polarity: do
severity: MEDIUM
trigger:
  globs:
    - "**/screenshots/**"
  keywords:
    - "before/after スクショ"
    - "マージ可否を確認"
    - "視覚検証"
source: memory
origin: memory:merge-confirmation-evidence
---

## 観点

UI を変える PR をマージしてよいか確認するときは、撮ってある before/after スクリーンショットを必ず提示する。文字情報だけで「マージしてよいですか」と判断を求めない。

## Why

UI のマイグレーションやリファクタでは、判断者が視覚で可否を見られないと意思決定の根拠が言葉になり再現性が落ちる。撮ったスクショは後続タスク（次画面の移行の before 基準等）でそのまま再利用できる。

## チェック方法

- 純粋リファクタなら 0px 検証結果（[[screenshot-diff-uses-tooling]] / [[icon-bbox-must-measure]]）も併記
- 移行なら累積崩れの検証結果（[[ui-migration-cumulative-drift]]）も併記
- 検証用キャプチャ（`docs/.../screenshots/` や一時保存先）を消す前に判断者へ送る／添付する
