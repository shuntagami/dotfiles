# Raycast

現在は利用しない。文字展開は [Espanso](../espanso/README.md) へ移行した。
RaycastはBrewfileから削除し、Espansoのdeploy時にも残っていればアンインストールする。
Command+SpaceはSpotlightへ戻す。以下のリンク設定は移行前の記録として保持する。

## よく開くページ（Quicklinks）

`quicklinks.json` にWebリンクを保存する。RaycastのImport QuicklinksからこのJSONを
読み込むと、`mt`（MulmoTerminal）、`slack`、`discord` の短い名前で検索して開ける。
SlackとDiscordのOpen WithはGoogle Chrome。`mt` は既定のブラウザを使う。
インポート後、Settings → Quicklinksで各項目の
Aliasにも名前と同じ文字（`mt`・`slack`・`discord`）を入力する。
エイリアスはJSONインポートでは復元されない。同名のSlack/Discordアプリより
Webリンクを先頭に出すため、各Macで設定する。
`mt` は実行したMacのlocalhost:34567を開く。
`MULMOTERMINAL_PORT` で別ポートを使うMacでは、Raycastの `mt` を編集し、
URLを `http://localhost:<ポート番号>/terminals` に変更する。
JSONのURLは固定値なので、環境変数の変更だけでは自動追従しない。
MulmoTerminalのサーバーはそのMacで起動しておく。
`quicklinks-settings.json` に合わせ、Settings → QuicklinksのPrefer Existing Tabsをオンにする。
`mt` のOpen Withは明示的なアプリ指定ではなく、Defaultと表示される既定ブラウザの項目を選ぶ。
この経路で既存タブの再利用を有効にする。Mac miniでは既定ブラウザがChromeであることを確認済み。
別のMacでもChromeの既存タブへ移動する場合は、Chromeを既定ブラウザにしておく。
同じURLのタブがあればそこへ移動し、なければ新しく開く。
これらの画面設定はJSONを置くだけでは自動適用されない。
既存リンクのURL変更はインポートでは上書きされないため、Raycastの編集画面でも更新する。


## 過去の移行データ

`scripts/macos-raycast.py` と `snippets.local.json` は過去のインポート用。
現在のdeployからは実行しない。既存Snippetsは削除せず、自動展開だけを停止する。
