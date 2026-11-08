# モニターの明るさ・音量（BetterDisplay）

外部モニターの明るさ・音量（DDC）は BetterDisplay で操作する。以前は MonitorControl を使っていたが、仮想ディスプレイ（画面共有・収録用の16:9画面）も同じアプリで扱えるため、BetterDisplay に一本化した。

音量はMac標準の音量アップ／ダウン・ミュートキーで操作する。BetterDisplayの `audioKeyboardControl=displayWithAudioDeviceNameMatch` により、既定の出力デバイス名がモニター名と一致するときだけ音量キーでモニターを操作し、それ以外ではmacOSへ返す。モニター名と出力デバイス名が異なる場合は、BetterDisplayのディスプレイ設定（Device Control > Audio Device Configuration…）でオーディオデバイス名を上書きする。

明るさキーは `videoKeyboardControl=all`（明るさを操作できる全画面）にする。

## 音声の出力先

出力・入力デバイスはmacOSのサウンド設定で選ぶ。Jump Desktop接続中のMac miniは、通常音・通知音とも `Jump Desktop Audio` を使う。AudioPriorityBarはこの切り替えをモニター出力へ戻して音声転送を妨げたため、導入対象から外した。

| 操作 | 担当 |
| --- | --- |
| 出力先・マイクの選択 | macOS（リモート接続中の出力先はJump Desktop） |
| 外部モニター（DDC）の音量 | BetterDisplay（音量キー） |
| スピーカー・ヘッドホンの音量 | macOS（音量キー） |

## 設定・更新

`zsh scripts/deploy.sh` で、ほかのdotfilesと一緒に設定・更新する。`scripts/setup.sh` もdeploy経由で適用する。単独で更新する場合は `bash scripts/macos-betterdisplay.sh` を実行する。`scripts/macos.sh` からは重複実行しない。BetterDisplayとXcode Command Line Toolsが必要で、BetterDisplay未導入のMacではスキップする。

初回だけ、次の手作業が必要。

- BetterDisplayにアクセシビリティ権限を与える（システム設定 > プライバシーとセキュリティ > アクセシビリティ）。権限がないと明るさ・音量キーが効かない。
- 仕事で使うMacでは Pro ライセンスを購入する。BetterDisplayは個人の非商用利用なら無料機能を使えるが、業務利用は無料機能でもライセンスが必要（買い切り、[betterdisplay.pro](https://betterdisplay.pro/)）。

### MonitorControlからの移行

セットアップは、MonitorControl用の自動切り替え（`local.dotfiles.monitorcontrol-mode`）を停止して削除し、起動中のMonitorControlを終了する。ミラーリング中に消灯した内蔵画面の状態は新しいヘルパーへ引き継ぐ。アプリ本体はBrewfileから外しただけで自動では削除しないので、移行後に `brew uninstall --cask monitorcontrol` で削除する。

BetterDisplayは起動時にモニターの現在値を読み込まず、明るさ・音量を100%とみなす。そのまま操作すると最初のキー入力で急に明るく・大きくなるため、自動切り替えのヘルパーがDDCで現在の明るさ・音量を読み、BetterDisplayに保存値がないモニターに一度だけ書き込む。DDCの読み取りに対応しないモニターでは、BetterDisplayの値のままになる。

## 接続状態ごとの動作

別のMacでは、この変更を含むブランチを取得したうえで `zsh scripts/deploy.sh` を実行する。同じ切り替えルールを各Macに導入する仕組みで、アプリ画面で変更した設定や現在の明るさをMac間でリアルタイム同期するものではない。表示機器のID、消灯前の明るさ、バックアップ、ログは各Macで保持する。

| 接続状態 | 明るさの操作 |
| --- | --- |
| MacBookを外部モニターにミラーリング | 内蔵パネルのバックライトを0に維持。内蔵画面を明るさキーの対象から外し、F1/F2の明るさキーとBetterDisplayのメニューで外部モニターだけ調整 |
| 拡張デスクトップ | 内蔵画面も操作対象に戻し、明るさキーで両方を調整 |
| 外部モニターを取り外す | 消灯前に保存した内蔵画面の明るさを復元。明るさキーはmacOSの通常動作に戻る |
| 仮想ディスプレイだけをミラーリング | ミラーリング扱いにしない。内蔵画面は消灯しない |

ミラーリング解除時は、外部モニターの保存済み明るさに内蔵画面を合わせる。モニター側の情報がなければ消灯前の値に戻す。数値を揃えても、パネルの性能・HDR・環境光によって見た目の明るさは異なる。

MonitorControlにあった「内蔵画面の自動調光に外部モニターを連動させる」設定は移行していない。BetterDisplayではディスプレイグループの同期で設定できるが、動作を確認していないため自動では有効にしない。

macOS標準のコントロールセンターは内蔵画面の明るさを操作するため、ミラーリング中の外部モニター調整には使わない。外部モニターのハードウェア調光はモニターと接続経路のDDC/CI対応が必要。

## 自動切り替えの仕組み

`scripts/betterdisplay-mode.swift` が接続状態を毎秒確認し、約2秒安定したところで設定を切り替える。BetterDisplayのディスプレイ別設定は起動時にしか読まれないため、管理する設定値が実際に変わるとき（MacBookでミラーリングを始める・やめるとき）だけBetterDisplayを再起動する。それ以外では再起動しないので、仮想ディスプレイやそのミラーリングは切れない。

管理する設定は次のとおり。`<番号>` はBetterDisplayがディスプレイごとに振る番号（`betterdisplaycli get -identifiers` の `tagID`）。

| 設定 | ミラーリング中 | それ以外 |
| --- | --- | --- |
| `videoKeyboardControl` | `all` | `all` |
| `audioKeyboardControl` | `displayWithAudioDeviceNameMatch` | 同左 |
| `allowKeyboardControl@Display:<内蔵画面>` | `false` | `true` |
| `allowCombinedBrightness@Display:<外部モニター>` | `false`（共有映像を暗くしないようDDCだけで調光） | `true` |

内蔵画面はDisplayServicesで物理バックライトだけを消す。仮想ディスプレイ（`kCGDisplayIsVirtualDevice`）は接続状態の判定と管理対象から外す。DisplayServices/CoreDisplayの非公開APIとBetterDisplay 5.xの設定形式に依存する。

起動設定は `~/Library/LaunchAgents/local.dotfiles.betterdisplay-mode.plist`、実行ファイルは `~/Library/Application Support/dotfiles/betterdisplay-mode` に生成する。ログは `~/Library/Logs/dotfiles/betterdisplay-mode*.log`。ビルド済みファイルはgitに含めない。

セットアップ時に表示構成・設定値・明るさ復元・プロセス起動の自己テストを実行する。セットアップ途中の失敗からBetterDisplayを復旧できるかは、`python3 scripts/test_betterdisplay_setup.py -v` で検証できる（macOS・BetterDisplay導入済みの環境が必要。テスト中のコマンドと保存先は隔離する）。

現在の状態:

```sh
"$HOME/Library/Application Support/dotfiles/betterdisplay-mode" --status
```

自動切り替えを停止する場合:

```sh
launchctl bootout "gui/$(id -u)/local.dotfiles.betterdisplay-mode"
rm "$HOME/Library/LaunchAgents/local.dotfiles.betterdisplay-mode.plist"
```

停止しただけでは消灯を解除しない。BetterDisplayの内蔵画面スライダー、またはmacOSのディスプレイ設定から明るさを戻す。導入前のBetterDisplay設定は `~/Library/Application Support/dotfiles/betterdisplay-before.plist` に保存される。

## 解像度と画面共有（`res` コマンド）

`bin/res` はBetterDisplayを使って、主画面の表示を切り替える。

```sh
res                # 主画面の解像度・HiDPI・リフレッシュレートと、共有中かどうか
res hidpi          # 同じ大きさのままHiDPI（高精細）で描画する。res hidpi off で戻す
res share          # 画面共有・収録用の16:9画面に切り替える
res share off      # 共有を終えて元の表示に戻す
```

`res hidpi` は表示の大きさ（UIの広さ）を変えずに、内部で倍の解像度で描画して縮小する。文字がくっきりする。切り替えでリフレッシュレートが可変（48-120Hzなど）に変わらないよう、今の値を引き継ぐ。

`res share` の仕組みは次のとおり。40インチなどの横長モニターをそのまま共有すると、相手の画面では文字がかなり小さくなる。そこで、16:9の仮想ディスプレイ「Screen Share 16x9」（1920×1080相当、HiDPI）を主画面にし、モニターをそのミラーにする。こうすると、MacBookで共有するのと同じ見え方になる。モニターには中央の16:9部分だけが表示される。共有・収録では、この画面全体（メニューバーを含む）を「画面」として選ぶ。仮想ディスプレイがなければ初回に作る。

仮想ディスプレイをつないだり切ったりすると、macOSがモニターの表示モードを別のもの（5120×2160など）に変えてしまう。そのため `res share` は共有前のモードを `~/Library/Application Support/dotfiles/res-share-target` に保存し、`res share off` で戻す。
