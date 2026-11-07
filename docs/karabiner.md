# Karabinerの初回設定

Commandキーを単独で押して離すと、左は英数、右はかなに切り替わります。
設定は `karabiner.json` の `Default profile` にあります。

`full` プロファイルの `scripts/deploy.sh` が設定を反映します。
Karabinerが先に `~/.config/karabiner` を作っていた場合は、同じ場所の
`karabiner.bak.<時刻>` に退避してからdotfilesへのリンクを作ります。
繰り返し実行しても、正しいリンクは作り直しません。

設定だけを入れ直す場合は、次を実行します。

```bash
python3 ~/dotfiles/scripts/install-user-configs.py karabiner
open -a Karabiner-Elements
```

Karabinerのメニューか設定画面からRestartを選びます。
Complex Modificationsに左右Commandのルールが表示されることを確認してください。

初回起動時は、Karabiner画面の案内に従ってバックグラウンドサービス、
アクセシビリティ、ドライバー拡張を許可します。
設定を配置するだけでは、これらの許可は付きません。
[公式の許可手順](https://karabiner-elements.pqrs.org/docs/manual/misc/required-macos-settings/)を参照してください。
