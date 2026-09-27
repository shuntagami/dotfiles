# 個人用の背景画像

`background.json` で画像・不透明度・表示方法を管理する。現在は `backgrounds/dog.JPG` を不透明度15％、`contain`（全体表示）で使う。

```sh
python3 ~/dotfiles/scripts/apply-mulmoterminal-background.py
```

deployでも実行する。各MacのMulmoTerminalに保存されたディレクトリと、現在のtmuxセルの作業ディレクトリへ適用する。存在しないディレクトリはスキップし、別の背景が設定済みなら維持する。

画像を各ディレクトリの `.mulmoterminal-background/dog.JPG` にコピーし、`.mulmoterminal.local.json` の背景項目だけを更新する。個人用ファイルはGitのローカルexcludeへ登録する。ただし、既に追跡済みの設定ファイルは変更差分として残る。画像を差し替えた場合もこのスクリプトを再実行する。

稼働中サーバーがあれば、設定が受理されたことと配信画像の一致を確認する。既存ブラウザに表示されない場合は再読み込みする。今後作るディレクトリやworktreeは、作成後に再実行する必要がある。アプリの全セル共通設定を追加するものではない。
