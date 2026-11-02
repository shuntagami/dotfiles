# Raycast / Snippets

Macのテキスト置換にある短縮語をRaycastに移し、ブラウザのターミナルでも使う。
アプリは `misc/Brewfile`、目標の設定値は `settings.json` で管理する。
`settings.json` をセットアップスクリプトが読み、Raycastの画面へ適用する。
Raycast本体が直接読み込む設定ファイルではない。
ただし `snippets.keywordPrefix` は移行スクリプトが読み、生成する短縮語の先頭に付ける。
現在は `;`。Mac標準の `lgm`・`gm`・`elegm` は、Raycastでは `;lgm`・`;gm`・`;elegm` になる。
Mac標準の登録を残して、実験的な上書き機能を使わずにxtermで展開するための設定。

Raycastの呼び出しはCommand+Spaceにする。
Settings → GeneralのReplace Spotlightを使い、SpotlightのCommand+Spaceを解除して置き換える。
`settings.json` の `replaceSpotlight` を有効にすると、スクリプトがReplace Spotlightを操作する。
Aqua VoiceはControl+Spaceを使う。
iTerm2のHotkey Windowは元のOption+Spaceを使う。
こちらの保存先は `misc/com.googlecode.iterm2.plist` のDefaultプロファイル。
`deploy.sh` がiTerm2のカスタム設定フォルダを設定する。起動済みのiTerm2への反映は
iTerm2を終了して起動し直した後に確認する。

## 自動セットアップ

開発途中。Mac miniでは基本設定とスニペット設定まで確認済みだが、
Quicklinks編集時のキーボードフォーカスで停止する。MacBookでの一通りの動作確認は未完了。
現時点では `deploy.sh` だけでセットアップが完了することを保証しない。

```sh
zsh ~/dotfiles/scripts/deploy.sh
# Raycastだけ設定するとき
python3 ~/dotfiles/scripts/macos-raycast-setup.py
```

実行したMac自身の辞書からスニペットを生成し、インポートの確定、呼び出しキー、
自動展開の各スイッチ、QuicklinksのURL・起動先・エイリアス・既存タブ優先を自動設定する。
RaycastのDBは直接書き換えない。実行中はRaycastの設定画面を操作するので、
Raycastへの別の入力は完了まで待つ。

初回にmacOSが求める権限承認だけはユーザーが行う。
実行元ターミナルのAccessibility／System EventsのAutomationと、Raycast自身のAccessibilityが対象。
スクリプトは許可ボタンを自動承認せず、未完了を終了コード3で知らせる。
Raycastの権限待ちでも、進められるインポートやリンク設定は先に済ませる。
許可後に同じコマンドを再実行すると、Raycastを起動し直して続行する。
利用規約への同意・ログインが必要な初回画面も、自動で同意・入力しない。

Raycast v2の英語UIとmacOS標準のosascript／swiftcを使う。追加の外部ライブラリは不要。
設定項目が見つからない、保存成功を確認できないなどの場合は完了扱いにしない。
途中で自動展開設定に失敗した場合は、自動展開をオフに戻して入力への干渉を避ける。
macOSのSpotlightキーを一時的に有効化してから公式のReplace Spotlightを操作し、
失敗時は以前のSpotlight設定へ戻す。

確認できたインポートのハッシュと適用済み設定を
`~/.local/state/dotfiles/raycast/automated-setup.json` に保存する（実データは入れない）。
辞書・設定・スクリプト・Raycastのバージョンが同じ次回以降は画面操作を省略する。
アプリ画面で手動変更した後に設定を戻す場合は、次を使う。

```sh
python3 ~/dotfiles/scripts/macos-raycast-setup.py --force
```

スニペットのインポートは追加のみ。確認記録にある短縮語の内容が変わった場合や、
未確認の既存キーワードが衝突してスキップされた場合は、成功とせず確認を求める。
既存の該当スニペットを更新・確認後、下記の手動確認用 `--confirm-setup` を実行してから再適用する。
辞書からの削除をRaycast側に自動反映することはしない。

## よく開くページ（Quicklinks）

`quicklinks.json` にWebリンクを保存する。RaycastのImport QuicklinksからこのJSONを
読み込むと、`mt`（MulmoTerminal）、`slack`、`discord` の短い名前で検索して開ける。
SlackとDiscordのOpen WithはGoogle Chrome。`mt` は既定のブラウザを使う。
自動セットアップは、各項目のAliasにも名前と同じ文字
（`mt`・`slack`・`discord`）を設定する。
エイリアスは単体のJSONインポートには含まれないが、自動セットアップが名前と同じ値を設定する。
同名のSlack/DiscordアプリよりWebリンクを先頭に出すための設定。
`mt` は実行したMacのlocalhost:34567を開く。
`MULMOTERMINAL_PORT` で別ポートを使うMacでは、`quicklinks.json` の `mt` の
URLを `http://localhost:<ポート番号>/terminals` に変更して再適用する。
JSONのURLは固定値なので、環境変数の変更だけでは自動追従しない。
MulmoTerminalのサーバーはそのMacで起動しておく。
`quicklinks-settings.json` に合わせ、Prefer Existing Tabsをオンにする。
`mt` のOpen Withには、Defaultと表示される既定ブラウザの項目を設定する。
この経路で既存タブの再利用を有効にする。Mac miniでは既定ブラウザがChromeであることを確認済み。
別のMacでもChromeの既存タブへ移動する場合は、Chromeを既定ブラウザにしておく。
同じURLのタブがあればそこへ移動し、なければ新しく開く。
これらの画面設定も自動セットアップが適用する。
既存リンクのURLはインポートでは上書きされないため、編集画面を操作して更新する。

## 手動で確認するとき

```sh
brew install --cask raycast
python3 ~/dotfiles/scripts/macos-raycast.py --deploy
# 自動セットアップが未対応のUIなどで、データだけ準備する場合
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
   通常欄の `lgm`＋Spaceと、Raycastのxterm用の `;lgm` は区別する。
   Mac標準と衝突しない `;lgm` の保存を画面で確認し、利用者の手入力で
   xterm上でメールアドレスに展開することを確認済み（2026-11-02）。
   選択肢の文字クリックで切り替わらない場合は、メニューの検索欄で絞り込み、
   ↓ → Enterで選び、表示値が変わったことを確認する。
6. xtermの未送信入力欄で半角の `;lgm`・`;gm`・`;elegm` を手打ちする（スペース不要）。
   手打ち・Aqua Voiceが二重にならないことも確認する。
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
生成済みの短縮語がMac標準の辞書にも存在するときは、衝突としてエラーにする。
`keywordPrefix` を変更して再生成する。以前のRaycast項目は自動削除しない。

```sh
python3 ~/dotfiles/scripts/macos-raycast.py --check
# Mac標準の登録から作り直す場合（既存JSONはバックアップされる）
python3 ~/dotfiles/scripts/macos-raycast.py --refresh-from-macos
# 生成だけ行い、既存JSONは保持する（従来の動作）
python3 ~/dotfiles/scripts/macos-raycast.py
```

## 管理範囲

Raycast v2の設定はアプリ内のDBに保存されるため、DBを直接書き換えたりリンクしない。
自動セットアップが画面を操作して `settings.json` の値を適用する。
公式の起動URLはSnippetsのインポートに使えるが、展開設定を直接適用する公式CLIは確認できていないため、
画面操作は同梱のAppleScriptと小さなネイティブ入力ヘルパーで行う。
アカウント情報、履歴、メールアドレスなどを含む実データはGitに入れない。
全設定のバックアップが必要なら公式のExport Settings & Dataを使う。
暗号化された `.rayconfig` はGit対象外。パスフレーズは別途安全に保管する。

公式仕様：[Snippets](https://manual.raycast.com/snippets)、
[Import & Export](https://manual.raycast.com/import-export)。
起動URLは [Raycast公式Snippet Explorerの実装](https://github.com/raycast/ray-so/blob/main/app/%28navigation%29/snippets/%5B%5B...slug%5D%5D/snippets.tsx) に合わせる。
