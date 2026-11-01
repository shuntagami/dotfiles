# Raycast / Snippets

Macのテキスト置換にある短縮語をRaycastに移し、ブラウザのターミナルでも使う。
アプリは `misc/Brewfile`、目標の設定値は `settings.json` で管理する。
`settings.json` は手順の正本であり、Raycastが直接読み込む設定ファイルではない。

## 導入・復元

```sh
brew install --cask raycast
python3 ~/dotfiles/scripts/macos-raycast.py
open -a Raycast
```

スクリプトは、そのMacの有効なテキスト置換を
`~/dotfiles/raycast/snippets.local.json` に変換する。
このファイルはGit対象外・権限600。既存ファイルは上書きしない。
別のMacへ移す場合はこのJSONを安全な方法でコピーするか、そのMacで再生成する。
同じ短縮語に異なる内容が複数ある場合、その短縮語は除外して件数を通知する。
内容が同じ重複は1件にまとめる。波括弧を含む置換はRaycastのプレースホルダーとの
衝突を防ぐためエラーにするので、手動で変換する。

1. 初回案内を完了する。呼び出しはOption+Space、Open at Loginはオン。
2. `Import Snippets` を実行し、上のJSONを選ぶ。既存のスニペットがある場合は
   重複を確認し、繰り返し一括インポートしない。
3. Settings → Snippetsで `settings.json` の値を設定する。
   Expansion ModeはAfter Delimiter (discarding)：短縮語の後にスペースを打つと展開し、
   スペース自体は残さない。Expand within Wordsはオフ。
4. 同じ短縮語がMac標準にもあるのでOverride System Snippetsをオンにする。
   この項目が無効ならRaycastの展開がスキップされる場合がある。
5. 自動展開にはmacOSのDevice Control and Data Access（アクセシビリティ）許可が必要。
   OSの許可は各Macでユーザーが承認する。dotfilesから権限DBを書き換えない。
6. 未送信の入力欄で `lgm`、`gm`、`elegm`＋スペースを試す。
   ターミナルで取りこぼす場合はResponse Timeを遅くし、動作を確認する。

## 更新

ローカルJSONを編集してから、必要なスニペットをRaycast側でも更新する。
JSONの編集はRaycastへ自動反映されない。

```sh
python3 ~/dotfiles/scripts/macos-raycast.py --check
# Mac標準の登録から作り直す場合（既存JSONはバックアップされる）
python3 ~/dotfiles/scripts/macos-raycast.py --refresh-from-macos
```

## 管理範囲

Raycast v2の設定はアプリ内のDBに保存されるため、DBを直接書き換えたりリンクしない。
画面で設定を適用し、復元時も `settings.json` に合わせる。
アカウント情報、履歴、メールアドレスなどを含む実データはGitに入れない。
全設定のバックアップが必要なら公式のExport Settings & Dataを使う。
暗号化された `.rayconfig` はGit対象外。パスフレーズは別途安全に保管する。

公式仕様：[Snippets](https://manual.raycast.com/snippets)、
[Import & Export](https://manual.raycast.com/import-export)。
