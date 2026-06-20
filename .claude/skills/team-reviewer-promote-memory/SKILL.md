---
name: team-reviewer-promote-memory
description: >
  Use when promoting accumulated review-related memory entries into the
  project's team:reviewer knowledge store (.claude/team-reviewer/*.md).
  Triggers: "memory をレビュー観点に昇格", "team-reviewer 知識ストアに昇格",
  "promote memory to reviewer".
---

# team-reviewer-promote-memory

蓄積した「レビュー系」memory を `.claude/team-reviewer/*.md`（team:reviewer 知識ストア）へ昇格する供給スキル。

## いつ使うか
- 定着したレビュー学習（視覚検証基準・コードレビュー観点）を、配布スキルを編集せず共有可能な形へ昇格させたいとき
- 初回 bulk 昇格、または個別 memory が「これはレビュー観点だ」と判明したとき

## 昇格してよい / だめ
- **昇格する**: 共有すべきレビュー基準（視覚検証の方法・移行/並行性/データ移行のアンチパターン等）
- **昇格しない**: 個人環境依存・運用 Tips（tmux/sendkeys、supervisor 運用、scheme 名、シミュレータ作成、CI ジョブ skip 条件、pod install ブロッカー等）

## ワークフロー
1. 対象プロジェクトの Claude Code memory ディレクトリからレビュー系を抽出する。
   memory ディレクトリは `~/.claude/projects/<プロジェクト cwd の絶対パスの `/` を `-` に変換した名前>/memory/`
   （例: cwd が `/Users/me/dev/myapp` なら `~/.claude/projects/-Users-me-dev-myapp/memory/`）
2. 昇格可否を判定する（上記基準。迷ったら人間確認）
3. frontmatter を変換する:
   - memory `name`/`description` → 知識 `.md` の `name`/`description`
   - 観点が「守るべき基準」なら `polarity: do`、「避けるべきアンチパターン」なら `polarity: dont`
   - `severity` を 4 段階で付与（データ損失/セキュリティ=CRITICAL、バグ/CI落ち=HIGH、保守性=MEDIUM、補助手順=LOW）
   - `trigger.globs`（該当ファイルパターン）と `trigger.keywords`（diff/文脈マッチ語）を付与
   - `source: memory`、`origin: <昇格元 memory ファイル名（拡張子なし）>`
4. 本文を 3 節へ再構成する: memory の趣旨→`## 観点`、Why→`## Why`、How to apply→`## チェック方法`
5. `.claude/team-reviewer/<name>.md` を作成し、`INDEX.md` に 1 行追記する（形式 `- [name](file.md) — フック [polarity/severity]`、セクションは視覚検証 / コードを維持）
6. **二重管理回避**: 昇格元 memory の先頭にバナーを追記する（破壊的削除はしない）:
   ```
   > **→ team:reviewer 昇格済み**（正準は `.claude/team-reviewer/<name>.md`）。以下は昇格元の記録。
   ```
   これにより実体は知識ストアに一本化しつつ、memory recall でも知見が失われない（可逆）。

## 注意
- 知識ストア（`.claude/team-reviewer/`）は version 管理対象（repo 内）。memory ディレクトリは repo 外なので、バナー追記は PR に含まれない副作用になる
- 1 観点 = 1 ファイル。INDEX のセクション分け（視覚検証 / コード）を維持する
- 同義観点が既にある場合は新規作成せず、既存 `.md` に追記・更新する（INDEX 肥大を防ぐ）
