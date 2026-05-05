# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 概要

シェル・エディタ・ツールのドットファイルと汎用設定ファイルを管理する個人用リポジトリ。新マシンやプロジェクトへの展開を素早く行うことが目的。

## Git フックの有効化

このリポジトリを新しい環境でクローンした後、必ず次を実行する:

```bash
git config core.hooksPath .githooks
```

有効化しないと pre-push の gitleaks スキャンが動作しない。

## pre-push フック（gitleaks）

`git push` 前に送信予定コミット範囲のシークレットを自動スキャンする。

**前提条件**: `gitleaks` が PATH にあること

```bash
brew install gitleaks  # macOS
```

**制御用環境変数**:

| 変数 | 効果 |
|------|------|
| `GITLEAKS_PRE_PUSH_SKIP=1` | スキャンをスキップ |
| `GITLEAKS_PRE_PUSH_FAIL_OPEN=1` | gitleaks 異常終了時でも push を許可 |
| `GITLEAKS_USE_LEGACY_DETECT=1` | 旧 CLI（`detect` コマンド）を使用 |
| `GITLEAKS_PRE_PUSH_LOG_OPTS_APPEND` | `git log` に追加引数を渡す |

ブロックされた場合はターミナルの gitleaks ログで検出箇所を確認すること（終了コード 1 は「検出」と「エラー」両方を意味する）。

カスタムルール・誤検知除外はリポジトリ直下に `.gitleaks.toml` を置いて対応する。

## テンプレート構成

| パス | 役割 |
|------|------|
| `templates/env/` | `.env` の型ファイル（プレースホルダのみ、実値なし） |
| `templates/vscode/` | VS Code / Cursor の `settings.json` スニペット（JSON断片） |

テンプレートファイルは必ず `something.env.example` のように **`.example` サフィックス** を付ける。これにより `.gitignore` の除外ルール（`.env` は無視、`.env.example` は追跡）が正しく機能する。

実値（API キー・接続文字列など）はこのリポジトリに置かない。各プロジェクトの `.env`（Git 管理外）またはシークレット管理で扱う。
