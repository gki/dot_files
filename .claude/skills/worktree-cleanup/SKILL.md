---
name: worktree-cleanup
description: >
  Use after merging a PR to clean up the git worktree and local branch.
  iOS/Xcode プロジェクトでは紐づく DerivedData も削除する。
  Triggers: "worktreeをクリーンアップ", "worktreeを削除", "マージ後のクリーンアップ",
  "ブランチとworktreeを削除", "cleanup worktree", "cleanup merged branch",
  "worktree cleanup", "マージ済みのworktreeを削除", "cleanup after merge",
  "DerivedData を削除", "iOS worktree 掃除", "xcworkspace cleanup".
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
# 出力例: /path/to/myproject/.git
# → メインリポジトリのルート: /path/to/myproject
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

### Step 7: iOS / Xcode 固有 — DerivedData の紐づきクリーンアップ

worktree を削除しただけでは `~/Library/Developer/Xcode/DerivedData/` に **その worktree でビルドされた成果物**（通常 0.5–2GB）が残り続けるため、別途削除する。**プロジェクトの DerivedData を全削除する必要はなく、対象 worktree に紐づくものだけ消せる**。

#### 仕組み

各 DerivedData フォルダ直下の `info.plist` に `WorkspacePath` キーが入っており、そのフォルダがどの `.xcworkspace` から生成されたかを記録している。これで逆引きできる。

#### 確認: 現在の DerivedData → workspace マッピング

```bash
for dir in ~/Library/Developer/Xcode/DerivedData/*/; do
  plist="$dir/info.plist"
  [ -f "$plist" ] || continue
  name="${dir%/}"; name="${name##*/}"
  ws=$(/usr/libexec/PlistBuddy -c 'Print :WorkspacePath' "$plist" 2>/dev/null)
  size=$(/usr/bin/du -sh "$dir" 2>/dev/null | /usr/bin/awk '{print $1}')
  printf '%-8s  %s\n            ← %s\n' "$size" "$name" "$ws"
done
```

#### 削除: 特定 worktree に紐づく DerivedData だけクリア

```bash
# WORKTREE_PATH と XCWORKSPACE_NAME は事前に確定させる
TARGET_WS="WORKTREE_PATH/XCWORKSPACE_NAME.xcworkspace"
for dir in ~/Library/Developer/Xcode/DerivedData/*/; do
  ws=$(/usr/libexec/PlistBuddy -c 'Print :WorkspacePath' "$dir/info.plist" 2>/dev/null)
  if [ "$ws" = "$TARGET_WS" ]; then
    echo "Removing $dir (was $ws)"
    rm -rf "$dir"
  fi
done
```

#### 注意

- **Step 4 で worktree dir を削除する前に Step 7 用の `WorkspacePath` を控えておく** — 削除後は info.plist は残るが path 比較が機能するので問題ないが、worktree 削除後に DerivedData を `find` で探すなら `WorkspacePath` がメイン手がかり
- DerivedData は **次回ビルドで自動再生成** されるため、誤って消しても致命傷にならない。判断に迷ったら消してよい
- 並列で複数 worktree を回した直後は **simulator のキャッシュ**も肥大している可能性 → `xcrun simctl delete unavailable` も併用（OS 不一致の古い simulator を一掃）

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
WORKTREE={{MAIN_REPO_PATH}}/.worktrees/feature-foo
BRANCH={{BRANCH_NAME}}

git -C "$MAIN" worktree remove "$WORKTREE"
git -C "$MAIN" branch -d "$BRANCH"
git -C "$MAIN" worktree list
git -C "$MAIN" branch
```

## iOS / Xcode 一括実行の例

```bash
MAIN={{MAIN_REPO_PATH}}
WORKTREE=/path/to/wt-{{ISSUE_NUM}}
BRANCH={{BRANCH_NAME}}
XCWS_NAME=Timer   # → $WORKTREE/Timer.xcworkspace

# 1. uncommitted 変更 / untracked file の確認（supervisor が置いた .worker-prompt.md 等がある場合は --force が必要）
git -C "$WORKTREE" status --short

# 2. worktree 削除（必要なら --force）
git -C "$MAIN" worktree remove "$WORKTREE" || git -C "$MAIN" worktree remove --force "$WORKTREE"

# 3. ブランチ削除（squash merge は -D）
git -C "$MAIN" branch -D "$BRANCH"

# 4. 紐づく DerivedData だけ削除
TARGET_WS="$WORKTREE/$XCWS_NAME.xcworkspace"
for dir in ~/Library/Developer/Xcode/DerivedData/*/; do
  ws=$(/usr/libexec/PlistBuddy -c 'Print :WorkspacePath' "$dir/info.plist" 2>/dev/null)
  if [ "$ws" = "$TARGET_WS" ]; then
    echo "Removing $dir"
    rm -rf "$dir"
  fi
done

# 5. 完了確認
git -C "$MAIN" worktree list
git -C "$MAIN" branch
```
