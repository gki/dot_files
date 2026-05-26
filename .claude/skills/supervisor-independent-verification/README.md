# supervisor-independent-verification — プレースホルダ一覧

SKILL.md 内の `{{...}}` を、プロジェクトの実際の値に置き換えてください。

| プレースホルダ | 置き換える内容 | 例 |
|--------------|--------------|-----|
| `{{UI_COMPONENT}}` | UI ホスト/ラッパーコンポーネント名 | iOS: `UIHostingController` / Android: `ComposeView` / Web: ルートコンポーネント |
| `{{SCREENSHOT_DIR}}` | スクショ成果物の格納先 (PR diff に含めるパス、**末尾スラッシュ無し**) | `docs/screenshots`, `tests/visual/snapshots` |

`$PR`, `$REPO`, `$REPO_DIR`, `$BRANCH` などはランタイム値です（実行時に PR 番号等から決まる）。

## 適用例: iOS / SwiftUI プロジェクトでの使い方

7 軸表の⑤⑥は典型的に:

- **⑤ 親遷移正常**: `MenuHostingController` 等の `present(NewHostingController(rootView: ...), animated:)` パターンが diff に残っているか
- **⑥ 不要レガシー削除**: `Main.storyboard` の旧 scene、旧 `UIViewController` ファイルが `git rm` されているか（grep で dangling segue 参照確認）

スクショ取得例（git push 済バージョンから）:

```bash
git -C "$REPO_DIR" show "origin/$BRANCH:docs/screenshots/2026-05-26-settings-before.png" \
  > "/tmp/sv-verify-$PR/before.png"
git -C "$REPO_DIR" show "origin/$BRANCH:docs/screenshots/2026-05-26-settings-after.png" \
  > "/tmp/sv-verify-$PR/after.png"
```

screenshot-fidelity-check の 2/2b/2c/2d/2e（getbbox 残差・罫線ズレ・テキスト帯ズレ・要素 bbox ズレ・色 hex 不一致）を**全部**回す。worker が報告した軸だけ追試するのではない。

## 前提

- `screenshot-fidelity-check` skill が利用可能（**本 repo には未同梱**。user scope `~/.claude/skills/` 等で別途導入しておく）
- `gh` と `git` でブランチを fetch 可能
- `SendUserFile` + `AskUserQuestion` で前後画像とマージ判断を同ターンで提示できる環境

## 関連スキル

- `screenshot-fidelity-check` — 視覚検証の本体（本 repo 未同梱、別途用意）
- `supervising-worker-panes` — worker の「完了」申告をトリガに本 skill を起動
- `sending-keys-to-claude-tui` — 完了未達なら worker に追加コミット依頼を返す
