---
name: pr-description-impl-scope-match
description: PR description で宣言したスコープと実装 diff の範囲が一致しているか / 「Aだけ」と書いて B も触ると後追いレビューが追えない
polarity: do
severity: HIGH
trigger:
  globs: []
  keywords:
    - "PR description"
    - "test plan"
    - "out of scope"
    - "本 PR の範囲"
source: pr-history
origin: pr-history:pr-scope-drift
---

## 観点

PR description に書いた「対象範囲」「変えない約束」「test plan」と、実際の diff のファイル群・行群の範囲が乖離していないか確認する。「ファイル A だけ汎用文言に変える」と宣言したのに同じコミットで他ファイルの placeholder 規約まで触っていると、レビュアーは「どこまでが約束で、どこからが追加変更か」を読み取れない。

## Why

PR description は「何を変えたか」のレビュー側の最初のフィルタになる。スコープが乖離していると見落としが発生し、後段の verifier や CI が拾えない退化を本番に通してしまう。過去 PR で Copilot が「PR description によれば X だけのはずだが、Y も変更されている」と複数回指摘している。

## チェック方法

- PR description の test plan / scope 節を読み、`git diff` の touched files と突き合わせる
- スコープを拡張するなら description を先に更新する（実装より先か同時）
- 「out of scope」と明記したものが diff に含まれていないか確認する
- 関連: [[skill-doc-stays-on-purpose]]
