# MacBookでコピーした画像をMac Studioへ自動で渡す

Jump Desktop Fluidのクリップボード同期は文字のみ。その補助として、MacBookの画像コピーを監視し、SSH経由でMac Studioの画像クリップボードへ渡す。スクショをクリップボードへ撮った後、Mac Studioの画像を受け付ける入力欄で通常の⌘Vを使う。専用ショートカットは不要。

エージェントの入力欄がCtrl+Vで画像を貼る仕様なら、Ctrl+Vを使う。この仕組みはキーを変更・横取りせず、画像を受信側のクリップボードへ入れるだけなので、貼り付けキーはアプリの仕様に従う。

## 導入

**受信側のMac Studio**のdotfilesで実行する。Studio→MacBookの既存SSH接続、両方のログイン済みmacOS GUIセッション、Studio上のSwiftコンパイラが必要。バイナリは現在両方で使用している同じアーキテクチャ・OS向けにビルドする。

```sh
bin/clipboard-image-sync install --sender shun-tagami-mbp --receiver shun-tagami-mac-studio
bin/clipboard-image-sync status --sender shun-tagami-mbp
```

MacBookのログイン時にLaunchAgentが起動する。Jumpのウィンドウが非アクティブでも画像をコピーできるよう、Jumpのフォーカスには依存しない。**稼働中はMacBookでコピーした画像全般をMac Studioへ送る**。逆方向の画像同期、ファイルの同期、自動貼り付けは行わない。文字の同期はJumpに任せる。

- MacBook: `~/Library/LaunchAgents/com.shuntagami.clipboard-image-bridge.plist`
- 両Mac: `~/Library/Application Support/ClipboardImageBridge/clipboard-image-bridge`
- MacBook: `~/.ssh/id_clipboard_image_bridge`（専用鍵）
- MacBook: `~/Library/Logs/ClipboardImageBridge/service.log`（成功・失敗だけ。画像・文字の内容は出さない）
- Studio: `~/.ssh/authorized_keys` に専用鍵を追加。受信プログラムだけ実行でき、シェル・ポート転送は許可しない。ホスト鍵はStudio自身の公開鍵と照合して登録する。

設定や認証情報をGitへ保存しない。画像はPNGとしてメモリ上で転送し、一時画像ファイルや履歴を作らない。PNG/TIFF形式を扱い、32MiB・6400万画素を上限とする。機密指定・受信済みマーカー付き、および画像データを持たないファイルURLだけのコピーは対象外。

CleanShotの標準設定「File & Image」にも対応する。ファイルURLが一緒に入っていても、クリップボードに含まれる画像データだけを送る。参照先ファイルを開いたり、そのパスを転送したりはしない。CleanShotの撮影後アクションでコピーを有効にするか、Quick Accessのコピーを使う必要がある。

## 挙動と制限

通常はコピーから数百ミリ秒〜数秒後に貼れる。ネットワーク転送が必要なので、転送完了前の⌘Vは古い内容になることがある。新しいコピーが発生したら古い画像の送信を中止し、転送中にStudioで別の内容をコピーした場合も上書きしない。

切断・失敗した画像や、起動前からあった画像は後から再送しない。回線が戻ったら改めてコピーする。画像を貼る際は、Mac Studio側のアプリが画像貼り付けに対応している必要がある。

macOSからクリップボードの読み取り確認が出た場合は、この補助プログラムに許可する。画面収録やアクセシビリティ権限は使用しない。

## 停止・更新

```sh
# 常駐と次回ログイン時の自動起動を停止
bin/clipboard-image-sync stop --sender shun-tagami-mbp
# 更新・再開はinstallを再実行
```

停止後も専用鍵と実行ファイルは残る。完全に削除する場合は、Studioの`authorized_keys`からコメントが`clipboard-image-bridge`の専用鍵行だけを削除し、MacBookの専用鍵2ファイルと両Macの`ClipboardImageBridge`ディレクトリを削除する。他のSSH鍵は変更しない。

## 検証

```sh
python3 scripts/test_clipboard_image_bridge.py
python3 scripts/test_clipboard_image_installer.py
```

テストは専用の名前付きクリップボードで、PNG一致、転送中のコピー競合、不正画像、容量制限、確定前の切断を確認する。ユーザーの通常クリップボードは変更しない。
導入処理のテストでは、SSH鍵ファイルの保存失敗時に既存内容が残ることと、空白・引用符を含む転送先パスを確認する。
