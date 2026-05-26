# external-blocker-detection — プレースホルダ一覧

このスキルにはプロジェクト固有のプレースホルダはありません。

SKILL.md 内の `$RUN_ID` / `$REPO` などは実行時に埋める**ランタイム値**で、事前の置き換えは不要です。

## 使うシーン

- CI / build / tool failures が「コードを 1 文字も変えていないのに連続赤」「数秒で fail」「同一 SHA の rerun も同じ症状」など、コード由来とは思えない症状を示しているとき
- ログに `billing` / `outage` / `quota` / `cert expir` / `rate limit` などのキーワードが出ているとき
- 別 worker / 別 repo でも同時に同種の失敗が出ているとき

## 前提

- `gh run view` / `gh run list` / `gh api` が叩ける（GitHub Actions 利用プロジェクト向け。GitLab CI / CircleCI の場合は判定軸を読み替える）
- `AskUserQuestion` で 3 択を提示できる環境（人間エスカレーションの定型）
- repo オーナーの billing 操作・cert 更新等の手動アクションは人間に依頼する前提

## 関連スキル

- `supervising-worker-panes` — supervisor が worker の「課金問題」申告を独立検証する場面
- `supervisor-independent-verification` — マージ前の独立確認
