# worktree-cleanup — プレースホルダ一覧

SKILL.md 内の `{{...}}` を、プロジェクトの実際の値に置き換えてください。

| プレースホルダ | 置き換える内容 | 例 |
|--------------|--------------|-----|
| `{{MAIN_REPO_PATH}}` | メインリポジトリのルートパス | `/Users/yourname/Development/myproject` |
| `{{BRANCH_NAME}}` | 「一括実行の例」セクションのサンプルブランチ名 | `feature/my-feature` |

## 補足

- Step 3 の「出力例」コメントと「一括実行の例」セクションのみ置き換えが必要です。
- Step 4〜5 の `MAIN_REPO_PATH` / `WORKTREE_PATH` / `BRANCH_NAME` は実行時変数なので、そのままで構いません。
- worktree のパス規則（例: `.worktrees/` 配下など）はプロジェクトに合わせて調整してください。
- **squash merge / rebase merge** は `git branch -d` で「マージ済み」と判定されない点に注意。PR の `state: "MERGED"` を Step 2 で確認済みなら `-D` を使う。

## 適用例: iOS / Xcode プロジェクトでの DerivedData 連動削除

worktree を削除しても `~/Library/Developer/Xcode/DerivedData/` に紐づくキャッシュ（通常 0.5–2 GB）が残り続けるため、別途削除する。プロジェクト全体の DerivedData を消す必要はなく、対象 worktree に紐づくものだけを `WorkspacePath` で逆引きできる。

### 現在の DerivedData → workspace マッピング確認

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

### 特定 worktree に紐づく DerivedData だけクリア

```bash
# 前提: 削除対象の worktree path と xcworkspace 名を事前に確定 (SKILL.md の WORKTREE_PATH 命名と一致)
WORKTREE_PATH=/path/to/myproject/.worktrees/feature-NN
XCWS_NAME=App
TARGET_WS="$WORKTREE_PATH/$XCWS_NAME.xcworkspace"
for dir in ~/Library/Developer/Xcode/DerivedData/*/; do
  ws=$(/usr/libexec/PlistBuddy -c 'Print :WorkspacePath' "$dir/info.plist" 2>/dev/null)
  if [ "$ws" = "$TARGET_WS" ]; then
    echo "Removing $dir (was $ws)"
    rm -rf "$dir"
  fi
done
```

### iOS 一括実行サンプル

```bash
MAIN_REPO_PATH=/path/to/myproject
WORKTREE_PATH=/path/to/myproject/.worktrees/feature-55
BRANCH_NAME=feature/my-feature-55
XCWS_NAME=App   # → $WORKTREE_PATH/App.xcworkspace

# 1. uncommitted 変更 / untracked file の確認（supervisor が置いた .worker-prompt.md 等で --force が要る場合あり）
git -C "$WORKTREE_PATH" status --short

# 2. worktree 削除（必要なら --force）
git -C "$MAIN_REPO_PATH" worktree remove "$WORKTREE_PATH" || git -C "$MAIN_REPO_PATH" worktree remove --force "$WORKTREE_PATH"

# 3. ブランチ削除（squash merge は -D）
git -C "$MAIN_REPO_PATH" branch -D "$BRANCH_NAME"

# 4. 紐づく DerivedData だけ削除
TARGET_WS="$WORKTREE_PATH/$XCWS_NAME.xcworkspace"
for dir in ~/Library/Developer/Xcode/DerivedData/*/; do
  ws=$(/usr/libexec/PlistBuddy -c 'Print :WorkspacePath' "$dir/info.plist" 2>/dev/null)
  if [ "$ws" = "$TARGET_WS" ]; then
    echo "Removing $dir"
    rm -rf "$dir"
  fi
done

# 5. 完了確認
git -C "$MAIN_REPO_PATH" worktree list
git -C "$MAIN_REPO_PATH" branch
```

### 補足

- DerivedData は **次回ビルドで自動再生成** されるため、誤って消しても致命傷にならない。判断に迷ったら消してよい。
- 並列で複数 worktree を回した直後は **simulator のキャッシュ**も肥大している可能性。`xcrun simctl delete unavailable` も併用（OS 不一致の古い simulator を一掃）。
