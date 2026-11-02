# Espansoによる文字展開

Raycastの自動展開で全文の二重挿入・カーソルの先頭への移動が発生したため、
文字展開をEspansoへ移行済み。Raycastはアンインストールし、Command+SpaceはSpotlightに戻す。

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
Raycastが残っているMacではHomebrew経由でアンインストールする。
アプリの保存データはpurgeしない。アンインストールに失敗した場合は終了コード3を返す。

## 管理するもの

- `config/default.yml`: 挿入方式はinject（キー入力）。貼り付け方式は通常のWeb入力で不安定だったため使わない。検索キーとダブルタップの切り替えキーは無効。
  Option+Space（iTerm2）、Control+Space（Aqua Voice）、Command+Space（Spotlight）と競合させない。
- `settings.json`: 短縮語の接頭辞（現在は空文字、追加なし）とMac標準の自動置換停止を管理する。
  `disableSystemTextReplacement: true` でmacOSの `NSAutomaticTextReplacementEnabled` と
  `WebAutomaticTextReplacementEnabled`、Chrome独自の `WebAutomaticTextReplacementEnabled` をオフにする。
  `;lgm` でも語尾の `lgm` が標準辞書と競合する可能性があるため、展開元はEspansoへ一本化する。
  元の設定値（未設定を含む）はstate配下の `native-text-replacement-preferences.json` に保存する。
  macOS 27では設定値をオフに保存してもAppKitのグローバル状態がオンを返すため、
  全アプリでの停止が保証されたとは扱わない。Chromeには独自の停止設定も保存する。
  起動済みアプリで置換が続く場合はアプリを再起動する。個別アプリで明示的にオンにした文字置換は
  そのアプリの編集 → 置換 → テキスト置換でもオフにする。
- 実行したMacのテキスト置換から `lgm`・`gm`・`elegm` など同じ短縮語を生成する。
  接頭辞なしの場合は `left_word: true` を付け、単語の先頭からだけ認識する。
  `lgm` の中の `gm` や文章の途中で誤展開させず、入力が揃った時点で展開する。
  元の `lgm` はMac標準辞書に生成元として残す。Mac標準側では自動展開しない。Espansoではスペース不要。
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

## 標準置換へ戻す場合

セットアップが途中で失敗しても、保存済みの標準置換停止設定は維持する。
自動で元へ戻してEspansoと再び競合させず、原因を解消して再実行する。
Espansoを使わず標準置換へ戻す場合は、先にEspansoを停止し、次の手順で
初回保存時の設定だけを復元する。辞書や無関係な設定は変更しない。
その後 `settings.json` の `disableSystemTextReplacement` をfalseへ変更する。
起動済みアプリには再起動が必要な場合がある。

```sh
espanso service stop
python3 - <<'PY_RESTORE'
import json, os, plistlib, subprocess
from pathlib import Path
state = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state")))
backup = json.loads((state / "dotfiles/espanso/native-text-replacement-preferences.json").read_text())
for domain, saved in backup.items():
    current = plistlib.loads(subprocess.check_output(["defaults", "export", domain, "-"]))
    for key, value in saved.items():
        if value is None:
            current.pop(key, None)
        else:
            current[key] = value
    subprocess.run(["defaults", "import", domain, "-"], input=plistlib.dumps(current), check=True)
    checked = plistlib.loads(subprocess.check_output(["defaults", "export", domain, "-"]))
    assert all(checked.get(key) == value for key, value in saved.items())
print("標準置換の保存前の設定を復元しました。")
PY_RESTORE
```

## 動作確認

初回の導入・生成が成功しても、入力の安定性は別途確認する。
通常の入力欄（ChatGPTなど）とxtermで `lgm` を複数回手打ちし、
1回だけ展開され、カーソルが末尾に残ることを確認する。入力は送信しない。
日本語IMEとAqua Voiceを使う普段の条件でも確認する。

参考: [インストール](https://espanso.org/docs/install/mac/)、
[設定](https://espanso.org/docs/configuration/options/)、
[挿入方式](https://espanso.org/docs/matches/basics/#injection-mechanism)。
