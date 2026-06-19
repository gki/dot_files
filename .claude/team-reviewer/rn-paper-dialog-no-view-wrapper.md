---
name: rn-paper-dialog-no-view-wrapper
description: react-native-paper Dialog を absoluteFill な View でラップして pointerEvents 切り替えする実装は backdrop と干渉して TextInput キーボードが閉じる
polarity: dont
severity: HIGH
trigger:
  globs:
    - "**/*.tsx"
  keywords:
    - "react-native-paper"
    - "<Dialog"
    - "Portal"
    - "pointerEvents"
    - "absoluteFill"
source: pr-history
origin: pr-history:rn-paper-dialog
---

## 観点

`react-native-paper` の `<Dialog>` を `StyleSheet.absoluteFill` な `<View>` で囲み、`pointerEvents` を動的に切り替える実装は採用しない。Dialog 内 TextInput の focus が突然失われキーボードが閉じる挙動を引き起こす。

## Why

`pointerEvents` の切り替えタイミングで `react-native-paper` 内部の backdrop touch handling が誤作動する。実プロジェクトでレビュー時に「`pointerEvents="none"` の間は背面タップが通り抜ける」というレビュー指摘を受けて wrapper View を入れたが、上記の不具合が出て元に戻した経緯がある。

## チェック方法

- `<Portal>` 内の `<Dialog>` を `<View style={StyleSheet.absoluteFill}>` 等でラップしていないか確認
- 表示制御は `opacity: contentReady ? 1 : 0` を Dialog の `style` に直接適用する
- 同種のレビュー指摘（背面タップ防止のための wrapper 提案）が来た場合は、本観点を根拠に reject する（[[../skills/team-reviewer/SKILL.md]] の suppress 運用）
- 本観点は `react-native-paper` の Dialog に限定する。他 Modal 系コンポーネントの挙動は別途検証要

> 元の実プロジェクト memory の経験則（`react-native-paper` 内部実装に依存・バージョン依存の可能性）。プロジェクト採用時には最新版で挙動再確認する。
