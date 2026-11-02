# Espansoによる文字展開

Raycastの自動展開で全文の二重挿入・カーソルの先頭への移動が発生したため、
文字展開をEspansoで試す。Raycastのランチャーと既存Quicklinksは残す。

```sh
brew install --cask espanso
python3 ~/dotfiles/scripts/macos-espanso.py
# 同じ処理は scripts/deploy.sh からも実行する
```

初回はEspanso自身へのmacOSアクセシビリティ許可が必要。
スクリプトはOS権限を自動承認しない。システム設定のプライバシーとセキュリティから
Espansoを許可し、同じコマンドを再実行する。
案内のEnableで一覧に表示されない場合、Device Control and Data Accessの「＋」から
`/Applications/Espanso.app` を追加してオンにする。
macOS 27ではEspanso 2.4.1の `service start` が失敗したため、
スクリプトは登録済みLaunchAgentを `launchctl enable/bootstrap` で起動する。
Raycastの自動展開停止には実行元ターミナルのAccessibilityとSystem EventsのAutomationも必要。
未対応のRaycast UIや権限不足で停止を確認できなければ、Espansoは開始せず終了コード3を返す。

## 管理するもの

- `config/default.yml`: 挿入方式はinject（キー入力）。貼り付け方式は通常のWeb入力で不安定だったため使わない。検索キーとダブルタップの切り替えキーは無効。
  Option+Space（iTerm2）、Control+Space（Aqua Voice）、Command+Space（Raycast）と競合させない。
- `settings.json`: 短縮語の接頭辞。現在は `;`。
- 実行したMacのテキスト置換から `;lgm`・`;gm`・`;elegm` などを生成する。
  元の `lgm` はMac標準辞書に残す。Espansoではスペース不要。
- 生成先は `~/Library/Application Support/espanso/match/dotfiles-macos.yml`（権限600）。
  本文をGitへ入れない。MacBookでもそのMacの辞書から生成する。
- Espansoのdefault.ymlをこのリポジトリへリンクし、ログイン時の起動を登録する。
  既存の設定や生成内容を変更する前に `~/.local/state/dotfiles/espanso/` へバックアップする。
  他のmatchファイルは変更しない。同じ短縮語を別のmatchファイルに登録しない。

辞書の更新・削除は再実行で生成ファイルへ反映する。
異なる内容が重複した元短縮語は除外して件数を通知する。
Espansoの変数構文 `{{…}}` やカーソル構文 `$|$` を含む本文は、意図しない解釈を防ぐためエラーにする。

```sh
# アプリ操作なしで生成内容の件数を確認
python3 ~/dotfiles/scripts/macos-espanso.py --dry-run
# 設定・辞書ファイルだけ準備
python3 ~/dotfiles/scripts/macos-espanso.py --prepare-only
# 停止するとき
espanso service stop
# 自動起動も外す場合
espanso service unregister
```

## 動作確認

初回の導入・生成が成功しても、入力の安定性は別途確認する。
通常の入力欄（ChatGPTなど）とxtermで `;lgm` を複数回手打ちし、
1回だけ展開され、カーソルが末尾に残ることを確認する。入力は送信しない。
日本語IMEとAqua Voiceを使う普段の条件でも確認する。

参考: [インストール](https://espanso.org/docs/install/mac/)、
[設定](https://espanso.org/docs/configuration/options/)、
[挿入方式](https://espanso.org/docs/matches/basics/#injection-mechanism)。
