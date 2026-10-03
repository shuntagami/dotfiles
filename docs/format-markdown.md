# AIでMarkdownを改行する

`bin/format-markdown` はDenoで動くAI専用コマンド。処理とプロンプトを同梱した1ファイルで動く。
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

Deno 2をインストールしておく。Node.js・npmパッケージ・サーバー・vercel-functionsのチェックアウトは不要。
`OPENAI_API_KEY` は環境変数から読み、未設定なら `~/.config/openai/api.env` を読む。
モデルを明示的に変える場合は `MARKDOWN_FORMAT_AI_MODEL` を設定する。
APIキーはdotfilesの追跡ファイルへ記録しない。

## 更新・配布

このファイルはvercel-functionsの共通処理から生成した配布物。直接編集せず、
ソースを変更して次のコマンドで再生成する。

```bash
sh ~/projects/vercel-functions/scripts/bundle-markdown-cli.sh ~/dotfiles/bin/format-markdown
```

生成ファイルを別のマシンへコピーしても、DenoとAPIキーがあれば動く。
OpenAIへ直接接続するため、VercelのAPIキーやURL設定も不要。
処理の詳細はvercel-functionsの `docs/markdown-format.md` を参照。
