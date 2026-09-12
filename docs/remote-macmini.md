# Mac mini を MacBook から操作する

MacBook から自宅の Mac mini を操作するための構成と初期設定をまとめる。

## 構成

| 用途 | 経路 |
|---|---|
| GUI の通常利用 | Jump Desktop の Fluid 接続 |
| SSH、Syncthing、疎通確認 | Tailscale |
| GUI の予備経路 | Tailscale 上の Apple 画面共有 |

Jump Desktop は画質、仮想ディスプレイ、キーボードショートカット、
クリップボード、MacBook のマイク転送をまとめて担当する。Tailscale は
Jump Desktop の代替ではなく、SSH とファイル同期、および障害時の予備経路として残す。

## MacBook 側

```sh
brew install --cask jump-desktop
```

Jump Desktop を起動し、Jump Desktop Connect と同じアカウントでサインインする。
Mac mini が一覧に現れたら、`Fluid` と表示された接続を使う。

接続後、次の設定にする。

- `Displays > Virtual Displays > 1`
- `Displays > Match Display Resolution` を有効化
- `Displays > Use Retina Resolution` を有効化
- `Remote > macOS Shortcuts` を有効化
- `Remote > Audio > Send Audio` から MacBook のマイクを選択
- クリップボード共有を有効化
- 必要に応じて Privacy Mode を有効化

上記は Jump Desktop 9.1.9 のメニュー名。仮想ディスプレイの切り替えで
接続ウィンドウが作り直された場合は、対象モニター上で再度全画面表示にする。

### 27インチモニターでローカルと同じ表示サイズにする

表示設定は `misc/jump-desktop/display.json` で管理する。接続元のMacで
Jump Desktopにサインインし、Mac miniの接続を登録した後、次を実行する。

```sh
jump-display-check         # 保存設定との差分を確認（差分ありは終了コード1）
jump-display-apply --quit  # Jump Desktopを終了→設定適用→アプリ再起動
```

`--quit` は接続中のセッションを切断する。既にアプリを終了していれば
`jump-display-apply` だけでよい。alias未読み込みの場合は
`node ~/dotfiles/scripts/jump-desktop-display.mjs --quit` を使う。
再起動後はMac miniに接続する。`scripts/deploy.sh` でも適用するが、
アプリ起動中・接続未登録ならスキップする。

スクリプトは `~/Documents/JumpDesktop/Viewer/Servers/*.jump` のうち、
設定ファイルの `displayName` に一致する1件だけに表示設定をマージする。
接続名を変更した場合は `displayName` も合わせる。認証情報や接続先IDは
既存ファイルに残し、gitには含めない。変更前の接続ファイルは
`~/Library/Application Support/dotfiles/backups/jump-desktop/` に保存する。
復元時はJump Desktopを終了し、バックアップを元の接続ファイルへコピーする。
保存形式はJump Desktop 9.1.9で確認。保存設定の確認と、接続中の実際の
表示の確認は別なので、再接続後は以下の解像度も確認する。

MacBook 側で `res.27` を実行して見かけの解像度を `3008×1692` にし、
Jump Desktop をそのモニターで全画面表示する。上記の仮想ディスプレイ・
解像度追従・Retina の3設定が有効なら、接続先は見かけの解像度
`3008×1692`、描画ピクセル数 `6016×3384` となる。
Jump Desktop の `Displays` メニューでは `Display 1 (6016x3384) Virtual`
と表示される。ウィンドウ表示では、そのウィンドウサイズに追従する。

Mac mini 側で `res.27` が `cannot be set to 3008x1692` を返す場合、
その時点の対象ディスプレイに該当モードがない。`display_manager` は既存の
解像度を選ぶだけなので、先に Jump Desktop 側で上記の設定を行う。
接続中の解像度は Jump Desktop の追従機能で揃えられるため、通常は
Mac mini 側で `res.27` を実行する必要はない。

### 音声入力

音声入力を使うとき、Mac mini 側の入力デバイスが
`Jump Desktop Microphone` になっていることを確認する。MacBook 側で音声入力が
起動してしまう場合は、`macOS Shortcuts` を有効にするか、Mac mini の
`編集 > 音声入力を開始` を画面上から実行する。

## Mac mini 側

既存の予備経路から接続する。

```sh
vnc-macmini
```

Mac mini のターミナルで次を実行する。

```sh
brew install --cask jump-desktop-connect
```

Jump Desktop Connect を開き、以下を行う。

1. MacBook と同じJump Desktopアカウントでサインインする。
2. Fluid Remote Desktopを有効にする。
3. 画面収録、アクセシビリティ、マイクなど、表示されたmacOS権限を許可する。
4. `Ready for Remote Access` になったことを確認する。
5. Mac miniを再起動しても一覧へ復帰することを確認する。

アカウントには二要素認証を設定する。

## Apple 画面共有の予備設定

MacBook の画面共有アプリで `shun-tagami-mac-mini` の接続情報を開き、
両方のMacがApple SiliconかつmacOS 14以降なら次の設定にする。

- 画面共有タイプ: `高パフォーマンス`
- ディスプレイタイプ: `1つの仮想ディスプレイ`
- `表示 > ダイナミック解像度`: オン
- `編集 > 共有クリップボードを使用`: オン

高パフォーマンス接続にはUDP 5900、5901、5902の疎通が必要。

## 確認

Tailscale が直接接続になっていることを確認する。

```sh
tailscale ping shun-tagami-mac-mini
tailscale status
```

Jump Desktop 接続後は次を順に確認する。

1. MacBook の画面サイズに合わせて仮想ディスプレイが作られる。
2. Retina 表示で文字がにじまない。
3. 両方向のコピー＆ペーストができる。
4. Mac mini 側のアプリへ主要なショートカットを送れる。
5. MacBook のマイクで Mac mini 側の音声入力ができる。

Touch ID、AirDrop、近距離通信を使うContinuity機能などはリモート転送されない。

### 左右Commandによる英数・かな切り替え

Jump DesktopはKarabiner-Elementsが生成する `japanese_eisuu` / `japanese_kana`
をFluid接続先へ安定して転送しない。このdotfilesではJump Desktopが前面のときだけ、
左Command単押しをF18、右Command単押しをF19として送る。接続先Macの
HammerspoonがF18をABC、F19を日本語入力へ変換する。

この機能には両方のMacへの最新dotfilesの反映と、Hammerspoonの起動が必要。
通常アプリでは従来どおりKarabiner-Elementsが直接英数・かなキーを送信する。

## SSH の改善

現在の `macmini` 接続はパスワード認証を明示している。Jump Desktopの動作確認後、
MacBookのEd25519公開鍵をMac miniの `~/.ssh/authorized_keys` に登録してから、
`misc/ssh/config` を公開鍵認証へ切り替える。鍵を登録する前に設定を切り替えると
予備経路を失うため、別作業として行う。
