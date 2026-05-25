---
name: worktree-cleanup
description: >
  Use after merging a PR to clean up the git worktree and local branch.
  Triggers: "worktreeをクリーンアップ", "worktreeを削除", "マージ後のクリーンアップ",
  "ブランチとworktreeを削除", "cleanup worktree", "cleanup merged branch",
  "worktree cleanup", "マージ済みのworktreeを削除", "cleanup after merge".
---

# マージ済み Worktree・ブランチのクリーンアップ

## 概要

PRマージ後、不要になった git worktree とローカルブランチを安全に削除する。

---

## 実行手順

### Step 1: 現在の状態を確認

```bash
# worktree 一覧と現在のブランチを確認
git worktree list
git branch --show-current
```

- 現在のCWDが worktree かどうかを把握する
- 削除対象の worktree パスとブランチ名を特定する

### Step 2: PR がマージ済みか確認

引数として PR番号が渡されている場合:

```bash
gh pr view PR_NUM --json state,mergedAt --jq '{state: .state, mergedAt: .mergedAt}'
```

- `state: "MERGED"` であることを確認してから進む
- MERGED でない場合は **停止** してユーザーに確認する

PR番号が不明な場合は現在のブランチ名で検索:

```bash
gh pr list --head BRANCH_NAME --json number,state,mergedAt
```

### Step 3: メインリポジトリのパスを特定

```bash
# worktree 内で実行している場合、メインリポジトリのルートを取得
git rev-parse --git-common-dir
# 出力例: {{MAIN_REPO_PATH}}/.git
# → メインリポジトリのルート: {{MAIN_REPO_PATH}}
```

`--git-common-dir` の出力から `.git` を除いたパスがメインリポジトリのルート。

### Step 4: Worktree を削除

**重要**: `git worktree remove` は **メインリポジトリから** 実行する。
worktree 内から実行すると失敗する場合がある。

```bash
# MAIN_REPO_PATH: メインリポジトリのルートパス
# WORKTREE_PATH:  削除する worktree のパス
git -C MAIN_REPO_PATH worktree remove WORKTREE_PATH
```

未コミットの変更がある場合は `--force` が必要。ただし、マージ済みであれば通常不要。

成功すれば worktree ディレクトリが削除される。

### Step 5: ローカルブランチを削除

```bash
git -C MAIN_REPO_PATH branch -d BRANCH_NAME
```

- `-d` はマージ済みブランチのみ削除（安全）
- `-D` は強制削除。マージ済み確認済みの場合のみ使用
- **squash merge / rebase merge は `-d` で「マージ済み」と判定されない** → PR の `state: "MERGED"` を Step 2 で確認済みなら `-D` を使う

### Step 6: 完了確認

```bash
git -C MAIN_REPO_PATH worktree list
git -C MAIN_REPO_PATH branch
```

対象の worktree とブランチが一覧から消えていることを確認する。

---

## よくあるエラーと対処

| エラー | 原因 | 対処 |
|--------|------|------|
| `'main' is already used by worktree at ...` | `gh pr merge` がローカルgit操作を試みた | `gh pr merge --repo OWNER/REPO` を使う、または worktree 削除後に merge |
| `fatal: 'BRANCH' is not fully merged` | ローカルに未マージのコミットがある | PR がマージ済みなら `-D` で強制削除 |
| `fatal: cannot remove worktree` | worktree 内から実行している | `git -C MAIN_REPO_PATH worktree remove ...` を使う |

---

## 一括実行の例

```bash
MAIN={{MAIN_REPO_PATH}}
WORKTREE={{MAIN_REPO_PATH}}/.worktrees/{{BRANCH_NAME}}
BRANCH={{BRANCH_NAME}}

git -C "$MAIN" worktree remove "$WORKTREE"
git -C "$MAIN" branch -d "$BRANCH"
git -C "$MAIN" worktree list
git -C "$MAIN" branch
```
