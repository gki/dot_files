# pr-check-review-threads — プレースホルダ一覧

SKILL.md 内の `{{...}}` を、プロジェクトの実際の値に置き換えてください。

| プレースホルダ | 置き換える内容 | 例 |
|--------------|--------------|-----|
| `{{TYPE_CHECK_CMD}}` | 型チェックコマンド | `npm run type-check`, `pnpm type-check`, `tsc --noEmit` |
| `{{LINT_CMD}}` | Lintコマンド | `npm run lint`, `pnpm lint`, `biome check .` |
| `{{TEST_CMD}}` | 特定ファイルの単体テストコマンド | `npm test -- --testPathPattern=PATH`, `pnpm test PATH` |
| `{{TEST_CMD_ALL}}` | 全体の単体テストコマンド | `npm test`, `pnpm test` |
| `{{E2E_TEST_CMD}}` | E2Eテストコマンド（不要なら行ごと削除） | `npx detox test --testPathPattern=PATTERN`, `npx playwright test` |
| `{{CODING_RULES_DOC}}` | コーディング規約ドキュメントのパス | `docs/naming-rule.md`, `CONTRIBUTING.md` |
| `{{CODING_RULES}}` | プロジェクト固有のコーディングルール一覧 | `Default Export禁止、バレルエクスポート禁止などのルール` |

## E2Eテストが不要なプロジェクトの場合

D-3 の `{{E2E_TEST_CMD}}` の行を削除してください。
