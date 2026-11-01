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
3. 自動展開にはmacOSのDevice Control and Data Access（アクセシビリティ）許可が必要。
   OSの許可は各Macでユーザーが承認する。dotfilesから権限DBを書き換えない。
   Request Permissionで進めない場合は、システム設定 → Privacy & Security →
   Device Control and Data Access → ＋ から `/Applications/Raycast.app` を追加する。
   Macの認証後、Raycastのスイッチがオンになったことを確認する。
4. Raycastをメニューから終了して起動し直し、Settings → Snippetsの
   Enable Snippet Expansionをオンにする。
5. `settings.json` に合わせ、Expansion ModeをImmediately、Expand within Wordsをオフ、
   Override System Snippetsをオンにする。短縮語を入力し終わると、スペースを待たずに展開する。
   Mac miniのxtermではAfter Delimiter (discarding)で展開できず、Immediatelyへの変更後に
   ユーザーの手入力でメールアドレスに展開することを確認済み（2026-11-01）。
   選択肢の文字クリックで切り替わらない場合は、メニューの検索欄で絞り込み、
   ↓ → Enterで選び、表示値が変わったことを確認する。
6. 未送信の入力欄で英数入力にして `lgm`、`gm`、`elegm` を手打ちする（スペース不要）。
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
