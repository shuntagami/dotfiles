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


## プロジェクトの色と背景を別のMacへ引き継ぐ

個人用のプロジェクト設定の正本は非公開の `ele-workspace` リポジトリの
`config/mulmoterminal-projects.json`。背景画像はこのリポジトリの
`backgrounds/dog.JPG`、濃さ・表示方法は `background.json`。設定・画像の両方をGitで管理する。
このdotfilesは公開なので、非公開プロジェクト名をここへ保存しない。
各アプリの共有リポジトリに個人用の画像を追加する必要はない。

```sh
python3 ~/dotfiles/scripts/sync-mulmoterminal-projects.py --dry-run
python3 ~/dotfiles/scripts/sync-mulmoterminal-projects.py
```

`deploy.sh` からも既存の `apply-mulmoterminal-background.py` 経由で実行する。
ホームからの相対パスで対象を指定し、存在しないプロジェクトはスキップする。
各プロジェクトの既存設定を優先して不足キーだけ補い、設定・画像の配布先を
そのチェックアウトの `.git/info/exclude` に追加する。既にGit管理されている
設定ファイルは書き換えない。共有設定とローカル設定が両方Git管理され、
追加が必要な場合は停止してプロジェクト側のPRで対応する。

別の背景画像や明示的な背景無効化も保持する。画像の内容が正本と異なる場合は
上書きせず停止する。登録一覧・配置順・アカウントは変更しない。
変更を他のMacへ配る場合は 非公開リポジトリの `config/mulmoterminal-projects.json` を更新してcommit・pushし、
取り込み先で上記コマンドを実行する。既存キーの変更は各Macで自動上書きしないため、
意図した差分を確認して適用する。反映後はMulmoTerminalの画面を再読み込みする。
