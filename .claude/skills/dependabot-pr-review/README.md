# dependabot-pr-review — プレースホルダ一覧

SKILL.md 内の `{{...}}` を、プロジェクトの実際の値に置き換えてください。

| プレースホルダ | 置き換える内容 | 例 |
|--------------|--------------|-----|
| `{{SRC_DIR}}` | ソースコードのルートディレクトリ | `src/`, `app/` |
| `{{SRC_FILE_PATTERNS}}` | grep に渡すファイルフィルタ | `--include="*.ts" --include="*.tsx"` |
| `{{LOCKFILE}}` | パッケージマネージャーのロックファイル名 | `pnpm-lock.yaml`, `yarn.lock`, `package-lock.json` |
| `{{INSTALL_CMD}}` | 依存関係インストールコマンド | `pnpm install`, `npm install`, `yarn install` |
| `{{PLATFORM_SPECIFIC_CHECKS}}` | フレームワーク固有チェックの見出し | `Expo / React Native 固有チェック` |
| `{{PLATFORM_CONFIG_FILE}}` | プラットフォーム設定ファイルのパス | `app.config.ts`, `build.gradle` |
| `{{DEPLOYMENT_TARGET_SETTING}}` | デプロイターゲット設定のキーパス | `buildProperties.ios.deploymentTarget` |
| `{{PREBUILD_CMD}}` | ネイティブコード再生成コマンド（不要なら当該箇所を削除） | `expo prebuild --clean` |
| `{{NATIVE_PREBUILD_PACKAGES}}` | 再ビルドが必要なパッケージカテゴリの箇条書き（不要なら削除） | `- @react-native-community/*`<br>`- react-native-*` |

## ネイティブビルドが不要なプロジェクトの場合

`{{PREBUILD_CMD}}` と `{{NATIVE_PREBUILD_PACKAGES}}` を含む箇所（Step 3の固有チェック節・Step 4備考・「ネイティブ再ビルドが必要なパッケージカテゴリ」セクション・Common Mistakesの3つ目）をまとめて削除してください。
