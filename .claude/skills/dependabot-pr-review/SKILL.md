---
name: dependabot-pr-review
description: Use when reviewing and merging Dependabot PRs — listing open PRs, assessing version change risk against actual codebase usage, and resolving lock file merge conflicts after sequential merges.
---

# Dependabot PR Review

## Overview

Dependabot PRs require risk assessment based on actual usage, not just version bump size. The workflow is: **list → investigate in parallel → present analysis → merge → resolve conflicts**.

## Workflow

### Step 1: List open Dependabot PRs

```bash
gh pr list --author "app/dependabot" --state open \
  --json number,title,headRefName,createdAt,url
```

### Step 2: Gather context in parallel

Run these simultaneously for all PRs:

```bash
# PR details (release notes, changelog, breaking changes)
gh pr view <NUMBER> --json body,title

# Codebase usage of the package
grep -r "<package-name>" {{SRC_DIR}} {{SRC_FILE_PATTERNS}} -l

# package.json for current version and constraints
cat package.json
```

### Step 3: Risk assessment

| Bump type | Default | Check |
|-----------|---------|-------|
| patch | ✅ Safe | Release notes for unexpected breaking changes |
| minor | ✅ Usually safe | New APIs that may conflict with existing usage |
| major | ⚠️ Investigate | Breaking changes vs. actual usage in codebase |

**Major version判定ポイント:**
- Breaking changeが我々のコードで実際に使っているAPIを変更するか？
- 最小バージョン要件（OS, ランタイム, Node等）がプロジェクト設定を満たすか？
- devDependencyなら影響範囲はビルド/型チェックのみで低リスク

**{{PLATFORM_SPECIFIC_CHECKS}}（プロジェクト固有）:**
- プラットフォーム要件の最小バージョン（`{{PLATFORM_CONFIG_FILE}}` の `{{DEPLOYMENT_TARGET_SETTING}}`）
- フレームワーク固有のバージョン互換性確認
- ネイティブコード変更があるパッケージは **マージ後に `{{PREBUILD_CMD}}` が必要**

### Step 4: Present analysis to user

各PRについて以下の表形式で提示し、マージ可否の指示を仰ぐ：

| PR | パッケージ | 変更幅 | 判定 | 理由 |
|----|-----------|--------|------|------|
| #N | package-name old→new | patch/minor/major | ✅/⚠️ | 根拠1文 |

`{{PREBUILD_CMD}}` が必要なPRは備考に明記する。（プロジェクトで使用しない場合はこの列を省略）

### Step 5: Merge approved PRs

```bash
gh pr merge <NUMBER> --merge
```

複数PRは並行実行可。

### Step 6: ロックファイルのコンフリクト解消

複数PRを順にマージすると最後のPRでコンフリクトが発生することがある（{{LOCKFILE}}）。

```bash
# PRブランチをチェックアウト
gh pr checkout <NUMBER>

# mainをマージ
git fetch origin main && git merge origin/main

# {{LOCKFILE}} がコンフリクトした場合
git checkout --theirs {{LOCKFILE}}
{{INSTALL_CMD}}   # ロックファイルを再生成

# コミットしてプッシュ
git add {{LOCKFILE}}
git commit -m "chore: resolve {{LOCKFILE}} conflict after dependabot merges"
git push origin <branch-name>

# マージ
gh pr merge <NUMBER> --merge
```

`{{INSTALL_CMD}}` 後にpre-commitフックが動く場合は全チェックを通過してからコミットする。

## ネイティブ再ビルドが必要なパッケージカテゴリ

次のカテゴリのパッケージはマージ後に `{{PREBUILD_CMD}}` が必要：

{{NATIVE_PREBUILD_PACKAGES}}

## Common Mistakes

- **major bump = 即却下は誤り** — breaking changeが自分のコードに影響するか確認してから判断する
- **ロックファイルを手動編集しない** — `git checkout --theirs` して `{{INSTALL_CMD}}` で再生成する
- **prebuildを忘れる** — ネイティブ変更を含むパッケージをマージ後、次ビルドまでに必ず実行する
