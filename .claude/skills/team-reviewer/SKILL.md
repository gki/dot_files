---
name: team-reviewer
description: >
  Use when reviewing a diff/PR for this project — applies generic code-review
  criteria plus project-specific review knowledge loaded from
  .claude/team-reviewer/*.md. Triggers: "team:reviewer でレビュー",
  "diff をレビュー", "プロジェクト固有観点でレビュー",
  "review with project knowledge".
---

# team:reviewer

diff（または PR）を、汎用レビュー観点 + プロジェクト固有のレビュー知見でレビューし、構造化指摘を出す。

## プロジェクト固有のレビュー知見を読み込む（必須・最初に実行）

`.claude/team-reviewer/` が存在するなら、その配下を対象に:

1. まず `INDEX.md`（1 行要約）を **Read** する
2. レビュー対象 diff に対し、各項目の `trigger` を判定する — `globs` が変更ファイルパスに該当、または `keywords` が diff 内容・変更文脈に該当するか
3. 該当する項目のみ本文を **deep-read** し、汎用レビュー観点に「プロジェクト固有の追加基準」として上乗せする

> この読み込みは **Read のみ**で行う（Skill ツールに依存しない）。そのため tmux pane worker / Agent subagent のどちらから起動されても同じ結果になる（**基盤直交**）。知識の中身はこのスキル md には一切書かない（= 配布スキル本体非編集の原則）。

## 入力

- **レビュー対象 diff**: 既定は `git diff <base>...HEAD`。dispatch prompt / args で範囲・対象ファイルを上書き可
- **プロジェクト知見**: 上記 `.claude/team-reviewer/`

## レビュー観点

1. **汎用**（このスキルに固定記述）:
   - コード品質: 命名の妥当性 / 関数 <50 行 / ネスト <4 / 明示的なエラー処理
   - テスト: 新規機能・バグ修正にテストがあるか
   - ドキュメント整合: 変更が docs/コメントと矛盾しないか
   - セキュリティ: 秘密情報のハードコード / 入力検証 / インジェクション
   - severity は 4 段階で付与する: CRITICAL=BLOCK（セキュリティ/データ損失）/ HIGH=WARN（バグ・重大な品質問題）/ MEDIUM=INFO（保守性）/ LOW=NOTE（軽微・スタイル）
2. **固有**（`.claude/team-reviewer/` からロード）:
   - `polarity: do` の観点 = 「この基準を満たすか」を確認し、満たさなければ指摘する
   - `polarity: dont` の観点 = 「このアンチパターンを踏んでいないか」を確認し、踏んでいれば指摘する（満たしていれば偽陽性として抑制）
   - `polarity: suppress` の観点 = **この種の指摘は出さない**（人間が reject した実績の記録）。diff への指摘根拠にせず、汎用・固有観点から該当する指摘候補が出かけたらその候補を抑制する。findings には決して出さない

## 出力（機械可読 JSON を正 + 人間向け 1 行要約）

受け取り手は **後続の自動処理（機械パース。Phase 2 の PR コメント投稿等）** を想定する。よって出力の正は **1 個の JSON オブジェクト**とし、その直後に人間向けの 1 行要約を添える。

### JSON スキーマ

```json
{
  "target": "<レビュー対象 diff の説明>",
  "summary": { "total": 0, "bySeverity": { "CRITICAL": 0, "HIGH": 0, "MEDIUM": 0, "LOW": 0 } },
  "checkedCriteria": ["汎用:code", "汎用:test", "汎用:docs", "汎用:security", "<固有観点の .md name>"],
  "findings": [
    {
      "file": "<path>",
      "line": 0,
      "severity": "CRITICAL|HIGH|MEDIUM|LOW",
      "criterion": "<固有は .md name / 汎用は 汎用:カテゴリ>",
      "rationale": "<なぜ問題か。固有観点なら .md の Why を引用>",
      "suggestion": "<具体的な修正案>"
    }
  ]
}
```

### 規定

- **findings は severity 降順**（CRITICAL → HIGH → MEDIUM → LOW）で並べる
- **指摘ゼロでも `findings: []`** とし、`checkedCriteria` に確認した全観点（汎用 4 カテゴリ + ロードした固有 `.md` 名。`polarity: suppress` のエントリも「確認した観点」として含める）を**必ず列挙**する（「沈黙＝未確認に見せない」原則を JSON で担保。suppress 該当で指摘を出さなかった場合も checkedCriteria に名前が残るため「意図的抑制」と判別できる）
- `polarity: suppress` のエントリは findings の `criterion` に使わない（指摘根拠にしない）。suppress により抑制した指摘候補は findings に含めない
- `summary.total` は `findings` の件数、`summary.bySeverity` は severity 別内訳と一致させる
- `criterion` は固有観点なら `.md` の `name`、汎用なら `汎用:code` / `汎用:test` / `汎用:docs` / `汎用:security`
- `line` は diff/サンプル位置の**近似でよく、不明なら `null`**
- **JSON ブロックの直後に人間向けの 1 行要約**を付す（例: `→ 7 件 CRIT2/HIGH3/MED2、最重要 Migrator.swift:14 (data-migration-safety)`）
- **PR コメント自動投稿は Phase 1 では行わない**（YAGNI・範囲外）。出力は上記 JSON + 1 行要約に留める

## レビュー手順（まとめ）

1. レビュー対象 diff を取得する
2. 上記「知見を読み込む」を実行（INDEX → trigger 該当 → deep-read）
3. 汎用観点で diff を走査
4. ロードした固有観点（do/dont）で diff を走査し、`suppress` 観点に該当する指摘候補（汎用・固有とも）は findings から除外する
5. 指摘を**上記 JSON フォーマット**でまとめる（findings は severity 降順 / 各 finding の `criterion` に固有観点は `.md` name・汎用は `汎用:カテゴリ` を入れる / `checkedCriteria` に確認した全観点を列挙）。JSON ブロックの直後に人間向け 1 行要約を付す

## 連携: セルフレビュー記録

PR のセルフレビューとして実行した場合、レビュー完了・対応確定後は `/pr-record-self-review` スキルで構造化記録を PR に投稿する。
