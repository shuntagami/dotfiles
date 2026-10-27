# 作業場所とPR

PRはブランチの変更を共有する仕組みで、追加のworktreeは必須ではない。

- アプリが人ごとのworkspaceを割り当てている場合は、その場所で編集・ブランチ切り替え・commit・pushを行う。別の作業コピーを作っても、アプリが見るフォルダは自動では切り替わらない。
- dotfilesのmainは実際の設定の参照元でもある。新しい作業は編集前に別worktreeへ分ける。
- 編集後に移す場合は、自分の変更だけを移し、内容を確認して元の変更を整理する。別フォルダへコピーしただけでは、元に残った変更がマージ後のpullを妨げる。

## dotfilesだけに適用する設定

`.gitconfig` の条件付きincludeは、`~/dotfiles/.git` とそのlinked worktreeに `config/git/dotfiles.gitconfig` を読み込む。

- `pull.ff=only`：pullで意図しないmerge commitを作らない。未保存変更との衝突を解消する設定ではない。
- `workflow.checkDuplicateEdits=true`：linked worktreeからpushする際、mainに未保存の同じ内容が残っていないか確認する。

`git-hooks/pre-push` は、pushするブランチで変えたファイルのうち、primary worktreeのmainに同じ内容が未ステージ・ステージ済み・未追跡で残る場合だけ停止する。内容の異なる変更や無関係な変更は重複と判定しない。確認は読み取り専用で、stash・削除・branch切り替え・fetchはしない。

このチェックは明示的に有効化したリポジトリだけに適用する。Studioの個人worktreeなど、他のリポジトリのpull方針やGit操作を変更しない。同じworktree内でブランチを切り替えてPRを作る運用も妨げない。

停止したら表示された元ファイルとcommitの内容を照合し、自分の変更だけを退避・整理する。元の作業に追加編集が混じる場合は、まとめてrestoreやstashをしない。チェックはあらゆる競合を防ぐものではなく、後から加わる編集や別端末の変更は別途確認が必要。

GitHubでのマージ後も、ローカルにはfetchと取り込みが必要。自動同期に任せられるが、編集中の内容と衝突した場合は停止するのが正常。`autostash` の復元も競合し得るため、コピーの残置を直す代わりにはしない。

検証：`python3 -m unittest discover -s scripts -p test_worktree_duplicate_guard.py`

参考：[pull設定](https://git-scm.com/docs/git-config#Documentation/git-config.txt-pullff)、[pre-pushフック](https://git-scm.com/docs/githooks#_pre_push)。
