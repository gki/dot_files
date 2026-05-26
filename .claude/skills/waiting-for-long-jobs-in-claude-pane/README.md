# waiting-for-long-jobs-in-claude-pane — プレースホルダ一覧

SKILL.md 内の `{{...}}` を、プロジェクトの実際の値に置き換えてください。

| プレースホルダ | 置き換える内容 | 例 |
|--------------|--------------|-----|
| `{{LONG_BUILD_COMMAND}}` | 長時間ジョブの実コマンド | iOS: `xcodebuild test -workspace App.xcworkspace -scheme AppTests -destination 'platform=iOS Simulator,id=<UDID>'`<br>Node: `pnpm test --runInBand`<br>Rust: `cargo test --release` |
| `{{PROGRESS_PATTERN}}` | Monitor の grep に渡す進捗行パターン | iOS: `Test Case` / Node: `PASS\|FAIL` / Rust: `test result` |
| `{{PR_NUM}}` | `gh pr checks` に渡す PR 番号 | `96` |

> **注**: 表セル内の `PASS\|FAIL` の `\` は Markdown 表のパイプエスケープです。コピーして `grep -E` に渡す際は `\` を外し `grep -E "PASS|FAIL"` のように使ってください。

## 適用例: iOS / Xcode プロジェクトでの使い方

### Pattern A（10 分以内に終わる単体ビルド）

```bash
timeout 600 xcodebuild test \
  -workspace App.xcworkspace \
  -scheme AppUnitTests \
  -destination 'platform=iOS Simulator,id=<UDID>' \
  2>&1 | tail -200
```

### Pattern B（フル UI regression、30 分超）

```
Monitor(
  command="xcodebuild test -workspace App.xcworkspace -scheme AppUITests -destination 'platform=iOS Simulator,id=<UDID>' 2>&1 | grep --line-buffered -E 'Test Case|PASS|FAIL|error:'",
  description="full UI regression progress",
  persistent: true
)
```

### Pattern C（PR の CI 待ち）

```bash
# jq の stdout ("true"/"false") で判定する。gh pr checks は pending 中も exit 0 を返すため
# `>/dev/null` 形式だと初回ループで即終了してしまう。
until [ "$(gh pr checks 96 --json bucket --jq 'all(.[]; .bucket!="pending")')" = "true" ]; do
  sleep 30
done
```

## 補足

- 並列 worker 時はシミュレータ UDID を専有指定（衝突回避）
- `timeout` 値はジョブの最長想定 + 10% を目安に。短すぎると本物の hung と区別がつかない
- 自分が worker か supervisor か迷ったら worker discipline に倒す（strictly safer）

## 関連スキル

- `sending-keys-to-claude-tui` — TUI 死亡時の `claude --resume` 復旧
- `supervising-worker-panes` — supervisor 側からの hung 検出
