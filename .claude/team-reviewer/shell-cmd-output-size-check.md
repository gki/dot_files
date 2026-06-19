---
name: shell-cmd-output-size-check
description: ファイル抽出系シェルコマンドの exit 0 と中身の正しさは別物 / wc -c 等で出力サイズを裏取りしてから使う
polarity: do
severity: MEDIUM
trigger:
  globs:
    - "**/*.sh"
    - "**/*.md"
  keywords:
    - "git show"
    - "git archive"
    - "curl -o"
    - "wget -O"
source: memory
origin: memory:shell-output-validation
---

## 観点

`git show <ref>:path > file` のような抽出系リダイレクトの成功（`exit 0` / `echo OK` 出力）を、中身検証なしに信じない。抽出直後に `wc -c` 等でサイズを裏取りしてから使う。

## Why

シェル変数経由の ref（例: `$BR=origin/feat/...`）が壊れていても抽出コマンドは 0 バイトファイルを生成しつつ exit 0 で抜けることがある。空の Python は exit 0・無出力で実行され、後段の検証ツールが「ツールが壊れた」と誤読する事故が起きる。実プロジェクトの検証 PR でこの誤読が実際に発生した。

## チェック方法

- 抽出系は full ref をインラインで書く（リビジョンをシェル変数に入れて連結しない／入れるなら直後に検証）
- 抽出直後に `wc -c < file`（または `ls -la`）でバイト数を確認し、0／想定外なら再取得
- スクリーンショット等のバイナリも同様（壊れた PNG は 0 バイトのことがある）
- 「コマンドが成功した（exit 0 / echo OK）」と「中身が正しい」は別事象として扱う
