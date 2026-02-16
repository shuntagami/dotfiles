# misc

各種アプリケーションの設定ファイル。

## gcp-oauth.keys.json

Google Calendar MCP サーバー用の OAuth 認証情報。

- GCP プロジェクト: `automatic-recording-of-minutes`
- GCP Console: https://console.cloud.google.com/apis/credentials?project=automatic-recording-of-minutes
- このファイルが唯一の正。プロジェクト側にはコピーを置かない
- Claude Desktop の `GOOGLE_OAUTH_CREDENTIALS` 環境変数でこのファイルを参照している（`claude_desktop_config.json` を参照）

### クライアントシークレットを更新する場合

1. GCP Console で新しいシークレットを作成
2. このファイルの `client_secret` を更新
3. `npm run auth` で再認証（環境変数を指定）:
   ```bash
   GOOGLE_OAUTH_CREDENTIALS=~/dotfiles/misc/gcp-oauth.keys.json npm run auth
   ```
4. Claude Desktop を再起動
5. GCP Console で古いシークレットを無効化・削除

### `deleted_client` エラーが出た場合

OAuth クライアント自体が GCP から削除されている。GCP Console で新しいクライアントを作成し、このファイルを丸ごと差し替えた上で再認証する。
