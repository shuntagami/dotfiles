# AIでMarkdownを改行する

`bin/format-markdown` は、`~/projects/vercel-functions` の処理を呼ぶAI専用コマンド。
ブラウザ・サーバー起動は不要。既定モデルは `gpt-6.1-sol`。
dotfilesの `bin/` はPATHに登録済みなので、そのまま実行できる。

```bash
# 指定ファイルをAIで整形し、成功したら同じファイルへ保存
format-markdown draft.md

# 別ファイルへ保存
format-markdown draft.md --output formatted.md

# stdin → stdout
cat draft.md | format-markdown
```

`--input` / `-i`、`--output` / `-o` も利用できる。
AIが本文を変えた・結果が欠けた・通信に失敗した場合は、ファイルを書き換えずに終了する。
機械的な改行へは自動で切り替えない。40文字以内の本文や見出し・リスト・コードなどは
AIによる改行の対象外。改行以外に、見出しの冗長な太字・区切り線・不要な空白も整理する。

## 準備

Node.js 22.13以上を使い、`~/projects/vercel-functions` で
`pnpm install --frozen-lockfile` を実行しておく。
リポジトリを別の場所に置く場合は `VERCEL_FUNCTIONS_DIR` を設定する。
`OPENAI_API_KEY` は環境変数または `~/.config/openai/api.env` から読む。
処理本体はvercel-functionsの `.env.local` も読むため、そこでもAI設定を上書きできる。
APIキーはdotfilesの追跡ファイルへ記録しない。

API経由で使う場合は `--url https://<host>/api/markdown/format` と
`MARKDOWN_FORMAT_API_KEY` を指定する。
処理の詳細はvercel-functionsの `docs/markdown-format.md` を参照。
