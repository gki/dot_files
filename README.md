# dot_files

コーディング作業で使うシェル・エディタ・ツール周りのドットファイルや、汎用性の高い設定ファイルを集めた個人用リポジトリです。知見をそのまま再現可能な形で置いておき、新しいマシンやプロジェクトでも同じ土台をすばやく揃えられるようにします。

## 置くものの目安

- シェル（`zsh` / `bash` など）のプロファイルや補完
- エディタ・IDE（例: Neovim、VS Code / Cursor のユーザー設定の断片）
- 言語・ツールチェーン用のグローバル設定（内容はプロジェクトに依存させない範囲で）
- 共有したいスニペットやテンプレート、スクリプト
- **汎用テンプレ**（下記 `templates/`）

**秘匿値とテンプレの区別**: 実際の API キーや接続文字列など **実値が入るもの** は、各プロジェクトの `.env`（Git 対象外）やシークレット管理で扱う。ここに置くのは **変数名・コメント・ダミー値だけのひな形** にとどめる。

## `templates/` — `.env` と `settings.json` の汎用化

新規プロジェクトやチーム展開のときにコピーして使う **型だけ** を置く場所です。

| ディレクトリ | 置くもの |
|--------------|----------|
| `templates/env/` | アプリ・スタックごとの **`.env` の型**。例: `web.env.example` のようにリネームし、中身は `YOUR_API_KEY=` のようにプレースホルダか空。 |
| `templates/vscode/` | **VS Code / Cursor の `settings.json` の断片**（JSON）。フォーマット方針、推奨拡張のコメント、言語別の最小セットなど。プロジェクトの `.vscode/settings.json` にマージするか丸ごとコピーする前提。 |

JSON は **完全なユーザー設定のコピペではなく**、「よく使うキーだけ抜き出したスニペット」にすると、プロジェクト固有の上書きと衝突しにくいです。

リポジトリ直下の `.gitignore` で、`.env` や `.env.local` など **実値が入りがちな名前** を誤コミットしにくくしてあります（テンプレ用の `.env.example` は追跡対象に含められるように除外しています）。テンプレファイルは `something.env.example` のように **`.example` を付ける** と区別しやすいです。

## Git pre-push（gitleaks）

`git push` の直前に **[gitleaks](https://github.com/gitleaks/gitleaks)** を実行し、**今回送るコミット範囲**（`git log -p` に相当する差分）に API キー・トークン・秘密鍵などが含まれていないかを静的ルールで走査します。

フック内では `gitleaks git`（v8.19 以降の推奨コマンド）を使い、`--log-opts` に `git log` 用の rev 範囲（公式 README の例どおり `--all` と組み合わせ）を渡しています。まだ `detect` しかない古い CLI の場合は `GITLEAKS_USE_LEGACY_DETECT=1` を指定してください。

gitleaks の終了コードは **1 が「漏洩検出」と「エラー」の両方** に使われるため、ブロックされたらターミナルに出た gitleaks のログを確認してください。

### インストール例（macOS）

```bash
brew install gitleaks
```

### 有効化（このリポジトリ内）

リポジトリのルートで次を一度実行します（`.githooks` を Git のフックとして使う設定です）。

```bash
git config core.hooksPath .githooks
```

### 環境変数

| 変数 | 意味 |
|------|------|
| `GITLEAKS_PRE_PUSH_SKIP=1` | pre-push での gitleaks を実行しない |
| `GITLEAKS_PRE_PUSH_FAIL_OPEN=1` | gitleaks の終了コードが **0 でも 1 でもない** とき（実行エラーなど）だけ push を止めない |
| `GITLEAKS_PRE_PUSH_LOG_OPTS_APPEND` | `git log` に追加で渡す引数（空白区切り）。既定は `--all <rev-range>` のみ |
| `GITLEAKS_USE_LEGACY_DETECT=1` | `gitleaks detect --source …` を使う（非推奨コマンドだが環境に合わせる用途） |

### 前提

- `gitleaks` が `PATH` にあること。無い場合はフックが失敗し push はブロックされます。急ぎのときは `GITLEAKS_PRE_PUSH_SKIP=1 git push` を使います。
- リポジトリ直下に [設定ファイル](https://github.com/gitleaks/gitleaks#configuration)（例: `.gitleaks.toml`）を置けば、ルールの調整や誤検知の除外ができます。

## ライセンス

[MIT License](LICENSE)
