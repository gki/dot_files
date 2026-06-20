---
name: memory-triage
description: >
  Use when MEMORY.md has grown large, memories feel stale, or the user asks to
  clean up / reorganize / triage memory entries. Triggers: "memory を整理",
  "memory をクリーンアップ", "memory の棚卸し", "memory が多い",
  "不要なmemoryを削除", "memory を最新化".
---

# Memory Triage

メモリエントリを読み、より適切な場所（グローバルルール・CLAUDE.md・スキル）に移行しクリーンアップする。

## 判断フロー

```dot
digraph triage {
    "全メモリファイルを読む" [shape=box];
    "CLAUDE.md（project/global）と重複?" [shape=diamond];
    "構造的に強制済み?\n(scripts, config, etc.)" [shape=diamond];
    "アクティブなスキルがカバー済み?" [shape=diamond];
    "短い常時ルール?\n(判断不要・毎回適用)" [shape=diamond];
    "プロジェクト固有?" [shape=diamond];
    "削除" [shape=box, style=filled, fillcolor=lightcoral];
    "削除（スキルが正典）" [shape=box, style=filled, fillcolor=lightcoral];
    "削除（構造的解決済み）" [shape=box, style=filled, fillcolor=lightcoral];
    "~/.claude/rules/ に移行\n→ メモリ削除" [shape=box, style=filled, fillcolor=lightblue];
    "プロジェクト CLAUDE.md に移行\n→ メモリ削除" [shape=box, style=filled, fillcolor=lightblue];
    "メモリに残す" [shape=box, style=filled, fillcolor=lightgreen];

    "全メモリファイルを読む" -> "CLAUDE.md（project/global）と重複?";
    "CLAUDE.md（project/global）と重複?" -> "削除" [label="yes"];
    "CLAUDE.md（project/global）と重複?" -> "構造的に強制済み?\n(scripts, config, etc.)" [label="no"];
    "構造的に強制済み?\n(scripts, config, etc.)" -> "削除（構造的解決済み）" [label="yes"];
    "構造的に強制済み?\n(scripts, config, etc.)" -> "アクティブなスキルがカバー済み?" [label="no"];
    "アクティブなスキルがカバー済み?" -> "削除（スキルが正典）" [label="yes"];
    "アクティブなスキルがカバー済み?" -> "短い常時ルール?\n(判断不要・毎回適用)" [label="no"];
    "短い常時ルール?\n(判断不要・毎回適用)" -> "プロジェクト固有?" [label="yes"];
    "短い常時ルール?\n(判断不要・毎回適用)" -> "メモリに残す" [label="no (判断が必要)"];
    "プロジェクト固有?" -> "プロジェクト CLAUDE.md に移行\n→ メモリ削除" [label="yes"];
    "プロジェクト固有?" -> "~/.claude/rules/ に移行\n→ メモリ削除" [label="no (全プロジェクト共通)"];
}
```

## メモリに残すべきもの

以下はすべての上位チェックを抜けた場合のみ残す:

- **文脈依存の判断ルール** — 「循環変更かどうか」のような状況判断が必要なもの
- **プロジェクト固有の不具合知識** — 特定コンポーネント・ライブラリの挙動
- **歴史的事件記録** — なぜそうなったかの背景（コードからは読めない）
- **worktree 固有のコマンド・手順** — 特殊な実行環境でのみ必要な詳細

## 移行先の優先度

| 移行先 | 適切なケース |
|---|---|
| `~/.claude/rules/development-workflow.md` | ワークフロー上のルール（push 前テスト、supervisor 禁止事項等）|
| `~/.claude/rules/` の他のファイル | code-review.md・git-workflow.md・agents.md 等に対応するルール |
| プロジェクト `CLAUDE.md` | 当該プロジェクトのみ適用されるルール |
| 既存スキルへの追記 | スキルが既にある文脈に属するルール（`pr-check-review-threads` の評価観点等）|

**優先度**: プロジェクト CLAUDE.md > `~/.claude/rules/` > デフォルト動作

## 作業手順

1. 全メモリファイルを `cat` で一括読み込み
2. 各エントリを上記フローで分類（削除 / 移行 / 残す）
3. 重複チェック: 移行前に移行先に既に同内容がないか確認
4. 削除対象: ファイルを削除 → MEMORY.md インデックスから該当行を削除
5. 移行対象: 移行先ファイルに追記 → ファイルを削除 → MEMORY.md から削除
6. MEMORY.md のエントリ説明文が実態と乖離していれば合わせて更新

## よくある削除パターン

- `pnpm を使う` → プロジェクト CLAUDE.md に既記載 → **削除**
- `eas build --no-wait` → package.json スクリプトに既反映 → **削除**
- `PR作成後 ScheduleWakeup` → プロジェクト CLAUDE.md に既記載 → **削除**
- `pr-check-review-threads を使う` → CLAUDE.md + スキル両方で強制済み → **削除**
- `循環変更は拒否` → `pr-check-review-threads` スキルに移行 → **削除**
- `supervisor pane でコード編集禁止` → `development-workflow.md` に移行 → **削除**
