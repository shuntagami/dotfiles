# macOS設定の同期・反映・メンテナンス

普段は `zsh ~/dotfiles/scripts/deploy.sh` を実行する。macOSでは `deploy-macos.sh` が、共通設定と同じ入口からシステム設定・アプリ設定を適用する。

- **同期**：管理する保存値を現在値と比較し、違う項目だけ書き、読み戻して確認する。
- **反映**：作業を中断するFinder／Dockやアプリの再起動は、反映待ちとして記録し、別コマンドで実行する。
- **メンテナンス**：Spotlight再構築やDB削除は、設定の同期とは別の、明示したときだけ実行する操作にする。

旧 `scripts/macos.sh` は互換入口として残す。内容は `deploy-macos.sh` への委譲で、旧スクリプトの一括終了・削除処理は実行しない。`setup.sh` もdeploy経由で同じ設定を使う。

## 設定の管理元

| ファイル | 管理するもの |
|---|---|
| `misc/macos-settings.json` | Finder・Dock・入力・スクリーンショット形式・ブラウザなどのpreferences、ログイン項目、`/Volumes` の表示 |
| `misc/macos-machines.json` | laptop／desktop別のMac名・Dock位置・電源・起動音のNVRAM設定 |
| `misc/default-apps.json` | 標準アプリ、CleanShotのショートカット、競合するmacOS撮影ショートカット |
| その他の `misc/*`・`espanso/*` | 既存の各アプリ専用スクリプトが管理する値 |

preferenceの `values` は管理するキーだけを指定する。辞書の指定は管理する子キーだけをマージし、配列は全体を管理する。`currentHost: true` は実行したMac固有のスコープ、`admin: true` は管理者権限を必要とする保存先。`activation` は `Finder`・`Dock`・`Activity Monitor`・`login` など、反映に必要な操作を指定する。

書き込みは `defaults` を通し、plist全体の置換は行わない。JSONのboolean・number・string・array・objectを、型付きplist値として保存する。無関係な設定は維持する。変更前の管理対象値は `~/.local/state/dotfiles/macos/backups/` に保存する（`XDG_STATE_HOME` 指定時はその配下）。存在しなかった値も区別して記録する。

Safariなどの保護されたpreferencesには `container` を指定する。フォルダにアクセスできないときは、`defaults export` が空の辞書を返しても「設定なし」と扱わない。該当アプリだけを権限待ちとして報告して終了コード3を返し、deployは他の設定を続行する。権限を付与した端末・エージェントの実行環境から再実行すると、その設定も同期する。一般の読み取り・書き込みエラーは従来どおり失敗として停止する。

関連付けは通常deployでは監査だけ行い、OSの確認画面を開かない。明示的な `macos-default-apps.sh --set-default pdf` などで1拡張子だけ修復を要求する。撮影ショートカットは静かに同期する。通知プロファイルも、通常は承認待ちを表示し、`macos-notifications.sh --install-profile` を明示したときだけ開く。

管理者権限が必要な差分がある場合だけsudo認証を行う。電源設定は実機の `pmset` に出てくる電源・機能を対象とし、利用できない項目は名前を表示してスキップする。`standbydelay`・`lidwake` などは機種によって対象外になる。

保存値の検証と、OSやアプリがその設定を実際に使うことは別。旧スクリプトから継承したpreferencesには古いOS向けのキーもある。読み戻しの成功を、現行OSでの機能の有効化や再起動完了とは扱わない。

## 端末ごとの違い

バッテリーの有無でlaptop／desktopを判定する。Mac名は旧スクリプトの規約を維持し、MacBookは `Shun-Tagami-MBP`、デスクトップは機種名から `Shun-Tagami-Mac-Studio` などを作る。Dock位置はMacBookで右、デスクトップで左にする。旧スクリプト末尾の「常に左」による上書きは除去した。

このMacだけ違う設定にする場合は `~/.config/dotfiles/macos-machine.json` に書く。端末別ファイルはGitへ入れない。指定したトップレベル項目が共通の端末設定を置き換える。

```json
{
  "name": "My-Mac",
  "dock": "bottom",
  "power": {"all": {"displaysleep": 20}, "ac": {"sleep": 0}},
  "nvram": null
}
```

`name`・`dock`・`power`・`nvram` に `null` を指定すると、その項目をこのMacでは管理しない。未知のキー・不正な値は書き込み前に停止する。`full`／`minimal` はdeployと同じ選択を使い、minimalではHammerspoon・Karabinerのログイン項目を追加しない。

## 差分の確認

```sh
node ~/dotfiles/scripts/macos-system-settings.mjs --dry-run
node ~/dotfiles/scripts/macos-system-settings.mjs --check
```

この2コマンドはシステム・端末設定とログイン項目の確認用。アプリ固有設定の検査は各スクリプトの `--check` を使う。`--dry-run` は差分を表示、`--check` は不一致があれば終了コード1。どちらも設定・バックアップ・反映待ちを書かず、sudoも実行しない。ログイン項目の読み取りにはSystem EventsへのOS権限が必要な場合がある。

## 再起動が必要な変更

```sh
node ~/dotfiles/scripts/macos-activation.mjs --status
node ~/dotfiles/scripts/macos-activation.mjs --apply
```

反映待ちは `~/.local/state/dotfiles/macos/pending-activation.json` に残す。次のdeployで保存値が一致していても、この案内は消さない。Aqua Voice・Clipy・CleanShotとKarabinerの変更も同じ一覧に入る。

`--apply` を明示すると、一覧にあるアプリだけを再起動する。動いていないアプリは次回起動で保存値を読むものとして扱う。Finder／Dockは終了後にmacOSがプロセスを自動起動し、Activity Monitorは次回起動で反映する。通常のアプリは終了完了を確認してから起動する。Karabinerは登録済みのユーザーサービスを再起動する。失敗した項目は残り、成功した項目だけ一覧から消す。

設定の保存と明示的な反映処理が同時に走った場合、同じロックを使って反映待ちの取りこぼしを防ぐ。別プロセスが処理中ならエラーで停止する。異常終了で `macos/activation.lock` が残ったときは、処理中のプロセスがないことを確認してからその空ディレクトリを削除し、再実行する。

`login` はログアウト／ログインやMac再起動が必要な可能性がある設定。自動でログアウト・再起動はしない。実施した後に次のコマンドで確認済みとする。

```sh
node ~/dotfiles/scripts/macos-activation.mjs --acknowledge-login
```

既存のBetterDisplayによる表示構成の自動切り替え、管理する常駐ヘルパーの更新、停止中のEspansoサービスの起動、撮影ショートカットの即時再読み込みは専用スクリプトの役割として維持する。BetterDisplayは表示構成や必要な設定が変わる場合にアプリを再起動する。この変更でそれらの自動化まで停止するわけではない。

## メンテナンス

次はdeploy／setupから呼ばれない。

```sh
node ~/dotfiles/scripts/macos-maintenance.mjs spotlight --dry-run
node ~/dotfiles/scripts/macos-maintenance.mjs spotlight
node ~/dotfiles/scripts/macos-maintenance.mjs launchservices
node ~/dotfiles/scripts/macos-maintenance.mjs launchpad --dry-run
```

- `spotlight`：全体の索引再構築を要求する。sudoが必要。
- `launchservices`：「このアプリケーションで開く」の登録を再構築する。
- `launchpad`：旧スクリプトと同じ名前に一致するLaunchpad DBを削除する。`--dry-run` で対象ファイルを確認できる。必要なDock再起動は別途行う。

## 旧macos.shからの整理

| 旧処理 | 新しい扱い |
|---|---|
| `defaults write` の構文が正しいキー | `macos-settings.json` に移管。管理対象の保存値を照合・検証 |
| Dark Mode | 共通preferenceとして保存し、セッションの反映待ちへ |
| Dock位置の二重指定 | `macos-machines.json` の1か所に統一 |
| 全撮影ショートカットの無条件無効化 | 削除。CleanShotの導入状況を確認する `macos-default-apps` に一本化 |
| 引用符が全角の `“include-date”` | 誤った別キーなので移管しない。正しい `include-date` のみ管理 |
| 電源・Mac名・起動音 | 端末ポリシーとして差分だけ反映 |
| ログイン項目の毎回追加 | 既存パスを確認して不足分だけ追加 |
| Finder／Dock／Activity Monitorの一括終了 | 反映待ちを記録して明示コマンドで実行 |
| Spotlight再構築・LaunchServices再構築・Launchpad DB削除 | 明示的なメンテナンスコマンドへ |
| sudo Touch ID | `setup.sh` の既存処理が担当 |
| Aqua Voice・Clipy設定の重複呼び出し | `deploy-macos.sh` の既存処理へ統一 |
| `/Volumes` の非表示解除 | 属性が異なる場合だけ反映 |
| sleepimageの削除・作り直し・immutable化 | システムファイルへの旧式の介入として廃止 |
| Dropboxアプリ内アイコンの改名 | インストール済みアプリの改変なので廃止 |
| `tmutil disablelocal` | 旧式のスナップショット無効化処理として廃止 |
| `systemsetup -setrestartfreeze` | 現行環境での有効性・機種対応を確認できていないため自動移管しない |
| System Preferencesの強制終了、独自sudo keepalive | 廃止。設定同期のたびにUIを閉じず、sudoは差分が必要な時に実行 |

## 検証

```sh
node --test scripts/test-macos-system-settings.mjs scripts/test-macos-app-settings.mjs
PYTHONPATH=scripts python3 -m unittest test_deploy test_user_config_paths test_mcp_sync
```

設定・アプリ・sudoの操作は一時ホームと偽コマンドで検証する。ネイティブdefaultsの型付きXML書き込みも一時plistだけで確認する。実機の全設定をテストのために適用しない。
