# 個人用の背景画像

`background.json` で画像・不透明度・表示方法を管理する。現在は `backgrounds/dog.JPG` を不透明度15％、`cover`（セル全体に広げ、はみ出す部分は切り取り）で使う。

```sh
python3 ~/dotfiles/scripts/apply-mulmoterminal-background.py
```

deployでも実行する。各MacのMulmoTerminalに保存されたディレクトリと、現在のtmuxセルの作業ディレクトリへ適用する。存在しないディレクトリはスキップし、別の背景が設定済みなら維持する。

画像を各ディレクトリの `.mulmoterminal-background/dog.JPG` にコピーし、`.mulmoterminal.local.json` の背景項目だけを更新する。個人用ファイルはGitのローカルexcludeへ登録する。ただし、既に追跡済みの設定ファイルは変更差分として残る。画像を差し替えた場合もこのスクリプトを再実行する。

稼働中サーバーがあれば、設定が受理されたことと配信画像の一致を確認する。既存ブラウザに表示されない場合は再読み込みする。今後作るディレクトリやworktreeは、作成後に再実行する必要がある。アプリの全セル共通設定を追加するものではない。

# 設定（config.json）を複数の Mac でそろえる

`~/.mulmoterminal/config.json` はアプリ自身が「一時ファイルに書いて置き換える」形で保存するため、シンボリックリンクにできない（保存した瞬間にリンクが普通のファイルに戻る）。そのため `scripts/sync-mulmoterminal-config.py` で、丸ごとのコピーではなくキーごとにそろえる。

```sh
~/dotfiles/scripts/save-mulmoterminal-config.sh      # この Mac の設定 -> dotfiles（コミット前に git diff で確認）
~/dotfiles/scripts/install-mulmoterminal-config.sh   # dotfiles -> この Mac の設定（deploy.sh でも実行）
```

どちらも `--dry-run` を付けると、変わるキーを表示するだけで何も書かない。

- `install` は、設定が無ければ丸ごと作る。あれば、dotfiles と違う共有キーだけを設定する。MulmoTerminal が動いていれば `/api/config` 経由で入れるので、ブラウザのタブを再読み込みすれば反映される（`prRepos` などはサーバーの再起動が要る。スクリプトが表示する）。
- 片方の Mac で設定を変えたら、その Mac で `save` → コミット → push し、もう片方で pull → `install`（または `deploy.sh`）。
- `install` は共有キーを dotfiles の値で上書きする。この Mac で変えてまだ `save` していない設定は、先に `save` しておく。

## そろえないキー

スクリプトの `LOCAL_KEYS` に並べたキーは、`install` で上書きせず、`save` でも dotfiles 側の値を残す。

| キー | 理由 |
|---|---|
| `cwdPresets` | 最近開いたディレクトリ。Mac ごとに違う |
| `worklogEnabled` | 作業ログの定期要約。トークンを使うので一台（Mac mini）だけで動かす |
| `accounts`, `repoDirs` | この Mac のディスク上のパスを指す |
| `prRepos`, `gitlabHosts` | 仕事のリポジトリ名・ホスト名。このリポジトリは公開なのでコミットしない。Mac 間では `/api/config` に直接 POST してそろえる |
