# team:reviewer 観点ストア INDEX

`team-reviewer` skill が PR レビュー時に読み込むプロジェクト固有観点の置き場。各観点 `.md` の `trigger.globs` / `trigger.keywords` が変更 diff に該当するときだけ本文を deep-read して、汎用レビュー観点（コード品質 / テスト / docs / セキュリティ）に上乗せする。

形式は `team-reviewer-promote-memory` と `team-reviewer-mine-prs` スキルが規定する frontmatter + 3 節（## 観点 / ## Why / ## チェック方法）。

## 視覚検証

- [screenshot-diff-uses-tooling](screenshot-diff-uses-tooling.md) — スクショの一致判定は目視禁止 / ツールで数値測定 [do/MEDIUM]
- [icon-bbox-must-measure](icon-bbox-must-measure.md) — アイコン W×H は罫線 Y / Center Y では検出できない / bbox を別途実測 [do/MEDIUM]
- [ui-migration-cumulative-drift](ui-migration-cumulative-drift.md) — UI 移行は全画面の全幅罫線で本数+Y を比較 / 部分計測は累積ズレを隠す [do/HIGH]
- [xml-color-not-source-of-truth](xml-color-not-source-of-truth.md) — Storyboard/XIB 色属性は appearance proxy で上書きされ得る [dont/MEDIUM]
- [migration-fidelity-design-doc](migration-fidelity-design-doc.md) — 移行は統一値が基準 / 不統一な旧画面に pixel-match 追従しない [do/MEDIUM]
- [pixel-repro-needs-custom-layout](pixel-repro-needs-custom-layout.md) — 旧 grouped TableView の px 再現は Form/List ではなく ScrollView+VStack 自前 [dont/MEDIUM]
- [ui-merge-needs-before-after](ui-merge-needs-before-after.md) — UI 変更のマージ判断時は before/after スクショ実物を提示する [do/MEDIUM]

## コード

- [swift-concurrency-sync-setup-not-isolated](swift-concurrency-sync-setup-not-isolated.md) — @MainActor XCTestCase の同期 setUp が isolated プロパティに触れると strict concurrency CI で失敗 [dont/HIGH]
- [host-init-precedes-data-migration](host-init-precedes-data-migration.md) — Storyboard root の UIHostingController.init は DB マイグレーションより早い [dont/HIGH]
- [db-migration-no-managed-cross-thread](db-migration-no-managed-cross-thread.md) — 移行 Migrator は旧 ORM の managed object を別スレッド write に持ち込まない [dont/CRITICAL]
- [db-migration-upsert-not-deleteall](db-migration-upsert-not-deleteall.md) — 起動時 DB 移行は deleteAll でなく upsert / ユーザー新規データを保持 [do/CRITICAL]
- [rn-paper-dialog-no-view-wrapper](rn-paper-dialog-no-view-wrapper.md) — react-native-paper Dialog の absoluteFill View ラッパー禁止 / TextInput キーボード閉じる [dont/HIGH]
- [shell-cmd-output-size-check](shell-cmd-output-size-check.md) — 抽出系コマンドの exit 0 は中身保証ではない / wc -c で裏取り [do/MEDIUM]
- [template-no-hardcoded-personal-paths](template-no-hardcoded-personal-paths.md) — テンプレ doc に個人実パス / 個人 ID を含めない [dont/HIGH]
- [template-shell-quote-and-define-vars](template-shell-quote-and-define-vars.md) — テンプレ doc のシェル例は変数クォート / 命名統一 / 定義or注釈 [do/MEDIUM]
- [gh-cli-jq-camelcase](gh-cli-jq-camelcase.md) — gh --json フィールドは camelCase / --jq は単一フィルタ文字列 [do/MEDIUM]
- [graphql-pagination-direction](graphql-pagination-direction.md) — 網羅判定の GraphQL は last:N でなく first:N で取る [do/HIGH]
- [doc-no-specific-issue-numbers](doc-no-specific-issue-numbers.md) — 汎用テンプレに特定 issue/PR # を埋め込まない / placeholder 命名統一 [dont/MEDIUM]
- [doc-cross-platform-tool-assumption](doc-cross-platform-tool-assumption.md) — テンプレ doc で OS 依存ツールを前提にしない / 注記・代替を併記 [do/LOW]
- [pr-description-impl-scope-match](pr-description-impl-scope-match.md) — PR description の宣言スコープと実装 diff の範囲を一致させる [do/HIGH]
- [skill-doc-stays-on-purpose](skill-doc-stays-on-purpose.md) — skill 文書に主責務外の節を入れない / 別 skill へのリンクで繋ぐ [dont/MEDIUM]
