# モニターの明るさ

`zsh scripts/deploy.sh` で、ほかのdotfilesと一緒に設定・更新する。`scripts/setup.sh` もdeploy経由で適用する。単独で更新する場合は `bash scripts/macos-monitorcontrol.sh` を実行する。`scripts/macos.sh` からも呼ばれる。MonitorControlとXcode Command Line Toolsが必要で、MonitorControl未導入のMacではスキップする。

別のMacでは、この変更を含むブランチを取得したうえで `zsh scripts/deploy.sh` を実行する。同じ切り替えルールを各Macに導入する仕組みで、アプリ画面で変更した設定や現在の明るさをMac間でリアルタイム同期するものではない。表示機器のID、消灯前の明るさ、バックアップ、ログは各Macで保持する。

| 接続状態 | 明るさの操作 |
| --- | --- |
| MacBookを外部モニターにミラーリング | 内蔵パネルのバックライトを0に維持。F1/F2の明るさキーとMonitorControlのメニューで外部モニターだけ調整 |
| 拡張デスクトップ | 内蔵画面も操作対象に戻し、明るさキーとMonitorControlの共通スライダーで両方を調整。内蔵画面からの明るさ連動も有効 |
| 外部モニターを取り外す | 消灯前に保存した内蔵画面の明るさを復元。明るさキーはmacOSの通常動作に戻る |

ミラーリング解除時は、外部モニターの保存済み明るさに内蔵画面を合わせる。モニター側の情報がなければ消灯前の値に戻す。数値を揃えても、パネルの性能・HDR・環境光によって見た目の明るさは異なる。

macOS標準のコントロールセンターは内蔵画面の明るさを操作するため、ミラーリング中の外部モニター調整には使わない。MonitorControlにアクセシビリティ権限が必要。外部モニターのハードウェア調光はモニターと接続経路のDDC/CI対応が必要。

`scripts/monitorcontrol-mode.swift` が接続状態を毎秒確認し、約2秒安定したところで設定を切り替える。切り替え時はMonitorControlを再起動する。ミラーリング中は共有映像を暗くしないようソフトウェアの追加調光を無効にし、内蔵画面はDisplayServicesで物理バックライトだけを消す。DisplayServices/CoreDisplayとMonitorControl 4.xの設定形式に依存する。

起動設定は `~/Library/LaunchAgents/local.dotfiles.monitorcontrol-mode.plist`、実行ファイルは `~/Library/Application Support/dotfiles/monitorcontrol-mode` に生成する。ログは `~/Library/Logs/dotfiles/monitorcontrol-mode*.log`。ビルド済みファイルはgitに含めない。

現在の状態:

```sh
"$HOME/Library/Application Support/dotfiles/monitorcontrol-mode" --status
```

自動切り替えを停止する場合:

```sh
launchctl bootout "gui/$(id -u)/local.dotfiles.monitorcontrol-mode"
rm "$HOME/Library/LaunchAgents/local.dotfiles.monitorcontrol-mode.plist"
```

停止しただけでは消灯を解除しない。MonitorControlの内蔵画面スライダー、またはmacOSのディスプレイ設定から明るさを戻す。導入前のMonitorControl設定は `~/Library/Application Support/dotfiles/monitorcontrol-before.plist` に保存される。
