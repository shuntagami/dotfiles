# Raycast / Snippets

Macのテキスト置換にある短縮語をRaycastに移し、ブラウザのターミナルでも使う。
アプリは `misc/Brewfile`、目標の設定値は `settings.json` で管理する。
`settings.json` は手順の正本であり、Raycastが直接読み込む設定ファイルではない。

Raycastの呼び出しはCommand+Spaceにする。
Settings → GeneralのReplace Spotlightを使い、SpotlightのCommand+Spaceを解除して置き換える。
`settings.json` の `replaceSpotlight` はこの目標設定の記録であり、JSONだけでは自動適用されない。
Aqua VoiceはControl+Spaceを使う。
iTerm2のHotkey Windowは元のOption+Spaceを使う。
こちらの保存先は `misc/com.googlecode.iterm2.plist` のDefaultプロファイル。
`deploy.sh` がiTerm2のカスタム設定フォルダを設定する。起動済みのiTerm2への反映は
iTerm2を終了して起動し直した後に確認する。

## よく開くページ（Quicklinks）

`quicklinks.json` にWebリンクを保存する。RaycastのImport QuicklinksからこのJSONを
読み込むと、`mt`（MulmoTerminal）、`slack`、`discord` の短い名前で検索して開ける。
SlackとDiscordのOpen WithはGoogle Chrome。`mt` は既定のブラウザを使う。
インポート後、Settings → Quicklinksで各項目の
Aliasにも名前と同じ文字（`mt`・`slack`・`discord`）を入力する。
エイリアスはJSONインポートでは復元されない。同名のSlack/Discordアプリより
Webリンクを先頭に出すため、各Macで設定する。
`mt` は実行したMacのlocalhost:34567を開く。
MulmoTerminalのサーバーはそのMacで起動しておく。
`quicklinks-settings.json` に合わせ、Settings → QuicklinksのPrefer Existing Tabsをオンにする。
`mt` のOpen Withは明示的なアプリ指定ではなく、Defaultと表示される既定ブラウザの項目を選ぶ。
この経路で既存タブの再利用を有効にする。Mac miniでは既定ブラウザがChromeであることを確認済み。
別のMacでもChromeの既存タブへ移動する場合は、Chromeを既定ブラウザにしておく。
同じURLのタブがあればそこへ移動し、なければ新しく開く。
これらの画面設定はJSONを置くだけでは自動適用されない。
既存リンクのURL変更はインポートでは上書きされないため、Raycastの編集画面でも更新する。

## 導入・復元

```sh
brew install --cask raycast
python3 ~/dotfiles/scripts/macos-raycast.py --deploy
# 同じ処理は scripts/deploy.sh からも実行される
```

`--deploy` は、そのMacの有効なテキスト置換を毎回読み取り、
`~/dotfiles/raycast/snippets.local.json` に変換する。
そのままRaycast公式サイトと同じ起動URLでインポートを要求するため、
JSONの手動選択やMac miniからのデータコピーは不要。MacBookではMacBookの辞書が元になる。
このインポートは追加のみで、既存のRaycastスニペットの更新・削除を同期するものではない。
同じキーワードがすでにある場合は上書きされないため、変更・削除は下の「更新」の手順で行う。
このファイルはGit対象外・権限600。内容に変更があればバックアップして更新する。
Raycast未導入ならスキップする（インストールはBrewfileの担当）。
辞書が空の場合もスキップし、Raycast側の既存スニペットは削除しない。
同じ短縮語に異なる内容が複数ある場合、その短縮語は除外して件数を通知する。
内容が同じ重複は1件にまとめる。波括弧を含む置換はRaycastのプレースホルダーとの
衝突を防ぐためエラーにするので、手動で変換する。
キーワードに空白・改行・引用符・バッククォートがある場合もエラーにする。

1. 初回案内を完了する。General → Replace Spotlightで呼び出しをCommand+Spaceにし、Open at Loginはオン。
2. 開いたインポート画面で確認する。起動URLの実行確認が出る場合もある。
   既存のスニペットがある場合は重複を確認する。URLで開けないときは
   `Import Snippets` を実行し、上のJSONを選ぶ。
3. 自動展開にはmacOSのDevice Control and Data Access（アクセシビリティ）許可が必要。
   OSの許可は各Macでユーザーが承認する。dotfilesから権限DBを書き換えない。
   Request Permissionで進めない場合は、システム設定 → Privacy & Security →
   Device Control and Data Access → ＋ から `/Applications/Raycast.app` を追加する。
   Macの認証後、Raycastのスイッチがオンになったことを確認する。
4. Raycastをメニューから終了して起動し直し、Settings → Snippetsの
   Enable Snippet Expansionをオンにする。
5. `settings.json` に合わせ、Expansion ModeをImmediately、Expand within Wordsをオフ、
   Override System Snippetsをオフにする。Raycastが処理する短縮語には即時展開を使う。
   このMac miniでは、実験的なOverride System Snippetsをオンにすると手打ち・Aqua Voiceが
   二重になり、オフで正常になることを利用者が確認（2026-11-02）。オンに戻さない。
   オフではMac標準と同じ短縮語をRaycast側で上書きしない。
   通常の入力欄で `lgm`＋Spaceが動いても、xtermで動くとは限らない。
   この端末では通常欄での展開を確認したが、xtermでは元の短縮語は展開されていない。
   xterm用にMac標準と衝突しない `;lgm` を1件追加し、動作を検証中。
   選択肢の文字クリックで切り替わらない場合は、メニューの検索欄で絞り込み、
   ↓ → Enterで選び、表示値が変わったことを確認する。
6. xtermの未送信入力欄で展開を確認し、手打ち・Aqua Voiceが二重にならないことも確認する。
   通常の入力欄だけで展開できても、xterm対応の確認済みとはしない。
   ターミナルで取りこぼす場合はResponse Timeを遅くし、動作を確認する。
7. インポート・既存スニペットの手動更新／削除・展開設定・動作を確認できたら、次を実行する。

   ```sh
   python3 ~/dotfiles/scripts/macos-raycast.py --confirm-setup
   ```

   これはユーザーによる完了確認の記録であり、アプリの状態を自動検証するコマンドではない。
   `~/.local/state/dotfiles/raycast/confirmed.json` に内容と設定値のハッシュだけを保存する
   （`XDG_STATE_HOME` があればその配下）。次のdeployでは辞書・設定値に変更がなければ
   インポート画面を繰り返し開かない。辞書や `settings.json` が変わると再確認が必要になる。

初回・変更時は終了コード3で未完了を知らせる。`deploy.sh` は警告を出して残りを続行する。
アプリの起動に成功しただけで、インポートや設定を完了扱いにはしない。

## 更新

`--deploy` はそのMacの辞書からインポート用JSONを作り直すが、Raycast側の既存データは同期しない。
ローカルJSONへの独自変更はバックアップして更新される。

- **新規追加**：Mac標準の辞書に登録しdeployを実行して、Raycastでインポートを確認する。
- **内容・キーワードの変更**：Mac標準の辞書を変更したうえで、RaycastのSearch Snippetsから
  対象を選び、編集画面で内容・キーワードも更新する。再インポートだけでは既存データは上書きされない。
- **削除**：Mac標準の辞書とRaycastのSearch Snippetsの両方から対象を削除する。
  Mac側の削除や空の辞書のdeployだけでは、Raycast側の古いデータは残る。

更新後にdeployでJSONを作り直し、Raycast内に古い内容や不要な項目が残っていないことを
確認してから `--confirm-setup` を実行する。フィンガープリントの記録は同期処理ではない。
JSONだけを編集してもRaycastへ自動反映されない。

```sh
python3 ~/dotfiles/scripts/macos-raycast.py --check
# Mac標準の登録から作り直す場合（既存JSONはバックアップされる）
python3 ~/dotfiles/scripts/macos-raycast.py --refresh-from-macos
# 生成だけ行い、既存JSONは保持する（従来の動作）
python3 ~/dotfiles/scripts/macos-raycast.py
```

## 管理範囲

Raycast v2の設定はアプリ内のDBに保存されるため、DBを直接書き換えたりリンクしない。
画面で設定を適用し、復元時も `settings.json` に合わせる。
公式の起動URLはSnippetsのインポートに使えるが、展開設定を直接適用する公式CLIは確認できていない。
アカウント情報、履歴、メールアドレスなどを含む実データはGitに入れない。
全設定のバックアップが必要なら公式のExport Settings & Dataを使う。
暗号化された `.rayconfig` はGit対象外。パスフレーズは別途安全に保管する。

公式仕様：[Snippets](https://manual.raycast.com/snippets)、
[Import & Export](https://manual.raycast.com/import-export)。
起動URLは [Raycast公式Snippet Explorerの実装](https://github.com/raycast/ray-so/blob/main/app/%28navigation%29/snippets/%5B%5B...slug%5D%5D/snippets.tsx) に合わせる。
