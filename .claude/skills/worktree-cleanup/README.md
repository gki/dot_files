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
