---
name: recovering-malformed-tool-calls
description: >
  Use when tool_use tags generate malformed (e.g. literal `court` / `invoke`
  instead of `<invoke>`) and calls silently fail to execute ("could not be
  parsed"), recurring intermittently in the same session. Provides a retry
  ladder — retry-as-is → trim preceding text → simplify/split the command →
  swap to a simpler tool → /clear (last resort). コンテキスト量とは独立に起きる。
  Triggers: "court invoke", "ツールコール 壊れる", "malformed tool call",
  "tool_use タグ 破損", "could not be parsed".
metadata:
  node_type: skill
---

# Recovering Malformed Tool Calls

tool_use タグ生成が断続的に壊れ（`<invoke>` が `court` / `invoke` 等の不正トークンに化ける）、
ツール呼び出しが「could not be parsed」で実行されないときに、`/clear` に頼る前に試す
**リトライの梯子**。

## いつ使うか

- ツールコールが `court` / `invoke` 等の不正タグになり実行されない（harness が「malformed」を返す）
- 同一セッションで断続的に再発する

使わない: 1 回限りの偶発で次がすぐ通った場合（梯子を持ち出すまでもない）。

## 前提（まず誤診断を避ける）

- **コンテキスト量とは独立に起きる。** 使用率 24% でも頻発した実例がある。
  「コンテキスト肥大が原因」と短絡しない — これは誤診断で時間を溶かす典型。
- 破損したツールコールは **実行されていない**（副作用なし）。同じ呼び出しを出し直してよい。
  ただし直前が merge / push / 削除など重要操作だったら、再試行の前に 1 度だけ状態を確認する。

## ワークフロー（軽い順に梯子を上る・`/clear` は最終段）

1. **そのまま正しい形式で 1 回再試行する。**
   破損はランダムに近く断続的。同じ呼び出しを正しい `<invoke name="...">` 形式で出し直すだけで
   通ることが多い。まずこれを試す（実例では merge / view / CronDelete / pull が再試行で通った）。

2. **ツールコール直前のテキストを削る。**
   長い説明文の直後で壊れやすい傾向がある（確証はないが観察上の相関）。前置きを 1〜2 文に減らすか、
   ツールコールを単独で（テキストほぼ無しで）出す。

3. **コマンド / 引数を単純化・分割する。**
   長い `awk` / `python` ワンライナー・複数行 heredoc・`;` / `&&` の連結は壊れやすい。
   1 コマンド 1 目的に割り、複雑な整形を避ける。
   - 例: `awk '/a/,/b/{print}'` → `sed -n '/a/,/b/p'`
   - 例: `gh api graphql ... | python3 -c "..."` → `gh api graphql ... --jq '...'`

4. **別ツールに置換する。**
   複雑な Bash パイプを、引数が単純な専用ツール（`Read` / `Grep`）に変える。
   長大プロンプトの `Agent` 起動は特に壊れやすいので、プロンプトを短くするか分割を検討。

5. **最終手段: `/clear` で新セッションに切り替える。**
   1〜4 で直らず頻発する場合のみ。先に状態が外部（git / PR / agmsg / TaskList / ファイル）から
   復元可能なことを確認してから実行する。
   - cron / Monitor を仕掛けている場合、`/clear` 後は id を失うので、`/clear` 前に
     CronDelete / TaskStop で畳めるものは畳んでおく。

## 落とし穴

- **「コンテキスト肥大」と誤診断して時間を使う** — 独立現象。実例で誤推測した。
- **同じ複雑コマンドを単純化せず連打する** — 同じ形でまた壊れる。3 で必ず形を変える。
- **破損後に状態確認せず突き進む** — 通常 `court`/`invoke` は未実行で副作用なしだが、
  merge / push / 削除など重要操作の後は「成功したつもり」の取り違えを避けるため 1 度確認する。
- **早々に `/clear` へ飛ぶ** — 会話文脈を失う。1〜4 を尽くしてから。

## 関連

- [[feedback_long_supervisor_session_thinking_stall]] — 別症状（巨大コンテキスト + 拡張思考での
  thinking-only 無応答化）。あちらは**コンテキスト量依存**で、本 skill の破損とは原因が異なる。
  両方とも長丁場セッションで起きるが、対処の入口（再試行の梯子 vs 早めの `/clear`）が違う。
