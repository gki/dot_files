---
name: screenshot-diff-uses-tooling
description: スクショの一致判定は目視禁止 / PIL ピクセル差分・増幅可視化・座標数値測定で行う
polarity: do
severity: MEDIUM
trigger:
  globs:
    - "**/screenshots/**"
  keywords:
    - "PIL"
    - "Pillow"
    - "ImageChops"
    - "getbbox"
    - "before/after スクショ"
source: memory
origin: memory:visual-diff-tooling
---

## 観点

before/after スクリーンショットが一致するかを判定するときは、IDE/閲覧ツールに表示される縮小画像を目視で見比べて結論しない。必ずツールで数値測定する。

## Why

実プロジェクトでの検証で、同じ before/after ペアに対し目視判定するたびに違う誤結論を出した（「セル罫線が右端で止まっている」→「完全一致」→「ヘッダが約 10px 下」と二転三転）。最終的にツールで罫線 Y 座標を測ると全本数 0〜3px 内で一致（＝サブピクセル変動・実差分なし）と判明。閲覧ツール表示は縮小されており目視 px 判定は再現性がない。

## チェック方法

- 寸法一致を確認 → `PIL.ImageChops.difference` → `getbbox()`（None なら完全一致）
- 差分があれば `diff.point(lambda p: min(255, p*10))` で 10 倍増幅画像を保存して位置を把握
- 該当領域を高解像度クロップ（macOS なら `sips -c <h> <w> --cropOffset <top> <left>` 等）して確認
- セパレータ等は Y 座標を数値測定して比較。**0〜3px のズレはキャプチャ間のサブピクセル変動＝実差分ではない**。ステータスバー時計差も無視
- 「ほぼ」「完全一致」を印象で言わない。getbbox / 差分 px 数 / 座標ズレの数値を根拠にする
- 全画面・全罫線で測る — サンプル測定は累積ドリフトを隠す（[[ui-migration-cumulative-drift]] 参照）
