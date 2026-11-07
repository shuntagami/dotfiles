# 処理用Mac

社内サービスを常駐させるMacです。どのMacかは [`misc/processing-mac.conf`](../misc/processing-mac.conf) に書きます。新しいMacへ移すときは、新しいMacで `deploy.sh` を実行すると、旧Macからデータを写し、確認のうえで切り替えます（[`scripts/processing-mac.sh`](../scripts/processing-mac.sh)）。

| サービス | 受け口 | 常駐（LaunchAgent） | Mac に置くデータ | 詳しい資料 |
|---|---|---|---|---|
| 文字起こし | Slack（Socket Mode）、`https://scribe.ele-studio.app`（Tunnel `scribe`） | `com.ele-inc.scribe-bot.{slack,tunnel,update}` | なし（記録はクラウド） | ele-inc/elevenlabs-transcribe-bot の `docs/MAC_SERVICE.md` |
| launch-video-gen | `https://app.ele-studio.app`（Tunnel `launch-video-gen`） | `com.ele-inc.launch-video-gen.{web,update,tunnel}` | `~/AIEditor-service`（約 470 GB） | ele-inc/launch-video-gen の `docs/processing-mac.md` |
| marunage-studio | `https://marunage.ele-studio.app`（launch-video-gen の Tunnel） | `com.ele-inc.marunage-studio.{web,runtime,update}` | env の3ファイル、チャットの記録 | ele-inc/marunage-studio の `docs/design-2026-10-26-local-files-on-mac.md` |

app と marunage は Cloudflare Access のログインを通ります。Tunnel・DNS・Access の設定は、Mac を替えても変わりません。

## ログと停止通知

3サービスのログ（`~/Library/Logs/{scribe-bot,launch-video-gen,marunage-studio}/*.log`）は、Vector が Cloud Logging（GCP プロジェクト `automatic-recording-of-minutes`）へ送ります。Vector は1分ごとに各サービスが動いているかも確かめて送り、止まっていればメールが届きます。

- **見る：** [Logs Explorer](https://console.cloud.google.com/logs/query;query=resource.labels.namespace%3D%22processing-mac%22?project=automatic-recording-of-minutes)。ログ名はサービスごと（`processing-mac-scribe-bot` など）、稼働確認は `processing-mac-heartbeat`。30日残ります。
- **通知が来るとき：** 稼働確認が10分届かない（Mac・回線・Vector が止まった）、またはあるサービスが10分のうち8回以上応答しない。戻ればもう一度メールが届きます。宛先と条件は ele-inc/elevenlabs-transcribe-bot の `infra/processing-mac-logs.tf`、詳しくは同じリポジトリの `docs/MAC_SERVICE.md`「ログと停止通知」。
- **このMacの中：** LaunchAgent `com.ele-inc.processing-mac.logs`（[`scripts/processing-mac/logs.sh`](../scripts/processing-mac/logs.sh) が登録）が `run-vector.sh` を起動します。設定は [`logs/vector.yaml`](../scripts/processing-mac/logs/vector.yaml)、稼働確認は [`logs/heartbeat.sh`](../scripts/processing-mac/logs/heartbeat.sh)。
  - 動くのは `~/.local/state/processing-mac-logs/app` に写したものです。dotfiles のブランチを切り替えても、動いている Vector は変わりません。
  - Vector 自身のログは `~/Library/Logs/processing-mac-logs/vector.log`、鍵は `~/.local/state/processing-mac-logs/gcp-credentials.json`（Secret Manager の `PROCESSING_MAC_LOGS_GCP_CREDENTIALS`）。
- **入れる・直す：** 処理用Macで `deploy.sh`（または `scripts/processing-mac.sh deploy`）を実行します。Vector・鍵・写し・LaunchAgent のうち、無いものや変わったものを用意し（写しが変われば Vector を起動し直す）、Cloud Logging に届くことを確かめます。`logs/` を書き換えたときも、これで反映します。

サービスを足したときは、`logs/vector.yaml` の `include` と `logs/heartbeat.sh` の確認を足して、`deploy` で反映します。

## 新しいMacへ移す

### 1. 新しいMacの下準備（手で行う）

- **ユーザー名を旧Macと同じにする**（`shun.tagami`）。launch-video-gen のデータには `/Users/shun.tagami/AIEditor-service/...` の絶対パスが DB と JSON に数千件入っていて、書き換える仕組みがありません。
- macOS 27 以上にする。launch-video-gen の音素合わせのランタイムが 27 向けにビルドされています。
- Mac の名前を `Shun-Tagami-Mac-Studio` にする。**Tailscale にログインする前に**行います（Tailscale の名前 `shun-tagami-mac-studio` はここから付きます）。`scripts/macos.sh` はデスクトップの Mac を機種名で名付けるので、それを実行しても同じ名前になります。手で付けるなら次のとおりです。

  ```bash
  sudo scutil --set ComputerName Shun-Tagami-Mac-Studio
  sudo scutil --set LocalHostName Shun-Tagami-Mac-Studio
  ```

  旧Mac（`Shun-Tagami-Mac-mini`）と同じ名前だと、`check` が止めます。
- [README](../README.md) の手順で dotfiles を入れる。文字起こし・launch-video-gen・marunage-studio に要る道具は Brewfile と `install-packages.sh` で入ります（Claude Code のコマンド版を含む）。
- 次のログインを済ませる。

  ```bash
  gh auth login             # HTTPS、Git の認証にも使う
  gh auth setup-git         # Git の認証に gh を使う設定を明示的に反映
  gcloud auth login         # automatic-recording-of-minutes の Secret Manager を読めるアカウント
  cloudflared tunnel login  # ブラウザで ele-studio.app を選ぶ
  codex login               # launch-video-gen のレイアウト作成
  vercel login              # launch-video-gen の共有リンク
  ```

- Tailscale アプリにログインする。
- 旧Macへパスワードなしで SSH できるようにする。旧Macで「システム設定 → 一般 → 共有 → リモートログイン」を有効にし、新しいMacで次を実行します（パスワードを聞かれるのはここだけ）。

  ```bash
  ssh-copy-id shun-tagami-mac-mini   # Tailscale の名前
  ssh shun-tagami-mac-mini true      # 何も聞かれずに終わればよい
  ```

  2台を Thunderbolt ケーブルでつなぐと、データのコピーがずっと速くなります。その場合は、旧Macの Thunderbolt Bridge の IP を SSH 先に使います。

### 2. どのMacからどのMacへ移すかを書く

新しいMacの `misc/processing-mac.conf` を次のようにします。

```bash
PROCESSING_MAC=Shun-Tagami-Mac-Studio
PREVIOUS_PROCESSING_MAC=shun-tagami-mac-mini   # 旧Macへの SSH 先（Tailscale の名前）
```

### 3. 事前に確かめる・写しておく

```bash
~/dotfiles/scripts/processing-mac.sh check     # ✗ が出たものを直す
~/dotfiles/scripts/processing-mac.sh prepare   # 任意。前日などに、旧Macを動かしたまま大きなデータを写しておく
```

`prepare` は何度実行してもよく、2回目以降は変わった分だけを写します。最初は launch-video-gen のデータ（約 470 GB）を写すので時間がかかります。

切り替えの前に、次を済ませます。

- marunage-studio の人ごとの worktree（`~/ele-workspace/launch-consulting-studio-worktrees/`）の作業を、すべて commit・push する。旧Macにしか無い作業があると、切り替えは止まります。
- app と marunage が少しの間止まることを、使っている人に伝える。

### 切り替えの間の旧Mac

旧Macは、電源とネットワークがつながっていればよく、モニターは要りません。サービスはログイン中のユーザーで動いていて、新しいMacが SSH で止めたり写したりします。気をつけるのは次の3つです。

- **再起動しない・電源を抜かない。** FileVault が有効なので、再起動すると起動時のロック解除の画面で止まり、誰かがログインするまでサービスも SSH も動きません。モニターとキーボードをつながないとログインできません。
- **ログインしたままにする**（今の状態のまま）。ログアウトすると常駐が止まります。
- 戻すときのコマンドは、旧Macの画面（Jump Desktop か画面共有。モニターが無くても使える）からターミナルで実行します。

Thunderbolt ケーブルでつなぐ場合は、2台を近くに置きます。

### 4. 切り替える

新しいMacで `deploy.sh`（または `~/dotfiles/scripts/processing-mac.sh deploy`）を実行します。このMacが処理用Macで、まだサービスが無いので、次の順に進みます。

1. **check**：ログイン・SSH・ユーザー名・空き容量などを確かめる。
2. **prepare**：旧Macを動かしたまま写す。
   - 社内リポジトリ（marunage-studio が編集に使う launch-consulting の clone は full clone）
   - launch-video-gen の `.env`・Python 環境・ローカルモデルのキャッシュ（Qwen・wav2vec2 など。Hugging Face の共有 `hub/blobs` も含む）・データ・Tunnel の認証ファイルと設定
   - marunage-studio の env（最初の版のビルドまで行う）
3. **旧Macが空いているか**を確かめる。marunage の worktree に未 push の作業があれば止まります。launch-video-gen の処理と marunage のチャットは、終わるまで最大10分待ちます。
4. **確認**：「旧Macのサービスを止めて切り替えます。続けますか？」に `y` と答える。
5. **switch**：
   1. 旧Macのログ送信（Vector）を止める。止めていくサービスを、旧Macが「応答しない」と報告しないようにするためです。
   2. 文字起こしをこのMacで起動してから、旧Macの文字起こしを止める（止まる時間なし）。
   3. 旧Macの launch-video-gen（新しい処理の受付を止めてから）と marunage-studio を止める。
   4. 最後の同期をする（launch-video-gen のデータを完全に一致させる）。
   5. このMacで launch-video-gen と marunage-studio を起動する。
   6. 公開URL（app・marunage）を、旧Macの Tunnel からこのMacの Tunnel へ付け替える。
   7. 外と中から動作を確かめる。
   8. 通れば、このMacからログを送り始め、Cloud Logging に届くことを確かめる。
   9. 旧Macの登録ファイル（plist）を `~/<サービス名>-retired/` へ退避する。次に旧Macへログインしても動き出さないようにするためです。

**止まる時間**：app と marunage は 5-3 から 5-6 の間止まります。文字起こしは止まりません。5-1 から 5-8 までが10分を超えると、「稼働確認が届かない」のメールが来ます（その間はログを送る Mac がいないため）。

実行するコマンドだけを先に見るには、次を使います。

```bash
~/dotfiles/scripts/processing-mac.sh switch --dry-run
~/dotfiles/scripts/processing-mac.sh switch --from . --dry-run   # 旧Macが無くても、このMacを旧Mac役にして通しで見る
```

### 5. 終わったら

- `misc/processing-mac.conf` の `PREVIOUS_PROCESSING_MAC` を空に戻し、commit・push する。
- 画面で確かめる。
  - **app**：ログインして案件一覧が出る。既存の動画のプレビューが再生できる。書き出しの画面で BGM・効果音を選べる。小さな素材でカットを1回試す。
  - **marunage**：ログインし、チャットを1ターン動かす。「main に push」が通る。
  - **Slack**：文字起こしくんに短い動画の URL を送る。

## 切り替えた後に、名前を Mac Studio へ向け直す

サービス以外で Mac mini の名前を使っているところです。Mac Studio を普段使いし始めたら直します。

- **SSH・画面共有：** `ssh studio` と `vnc-studio` は足してあります。旧Macを手放したら、`misc/ssh/config` の `macmini` と `zsh/mac.zsh` の `vnc-macmini` を消します。
- **Jump Desktop の画面設定：** MacBook の Jump Desktop に Studio の接続（表示名 `Shun-Tagami-Mac-Studio`）を作ってから、`misc/jump-desktop/display.json` の `displayName` を `Shun-Tagami-Mac-Studio` にします。接続が無いうちは、deploy.sh はこの設定を飛ばすだけです。
- **agent-browser：** `codex/AGENTS.md` と `docs/agent-browser.md` の `AGENT_BROWSER_HOST=shun-tagami-mac-mini` を `shun-tagami-mac-studio` にします。
- **Studio 側の遠隔操作の準備**（Jump Desktop Connect、Tailscale、画面共有）は [remote-macmini.md](remote-macmini.md) の Mac mini 側の手順と同じです。

## 戻す

- **切り替えの途中で止まったとき**：止めた旧Macのサービスと、旧Macで戻すコマンドが表示されます。旧Macのターミナルで実行してください。
- **切り替えた後に問題が見つかったとき**：
  1. 新しいMacで、10の常駐を止める。

     ```bash
     for l in scribe-bot.{slack,tunnel,update} launch-video-gen.{web,update,tunnel} marunage-studio.{web,runtime,update} processing-mac.logs; do
       launchctl bootout gui/$(id -u)/com.ele-inc.$l
     done
     ```

  2. 旧Macで、`~/scribe-bot-retired/`・`~/launch-video-gen-retired/`・`~/marunage-studio-retired/`・`~/processing-mac-retired/` の plist を `~/Library/LaunchAgents/` へ戻す。それぞれ `launchctl enable gui/$(id -u)/<Label>` で無効化を解除してから、`launchctl bootstrap gui/$(id -u) <plist>` で起動する。

  切り替えた後に新しいMacで作ったジョブや素材は、新しいMacに残ります。

## 旧Macの後片付け（数日たって問題がなければ）

旧Macは、初期化してから手放してください。ここにある秘密の値（各サービスの API キー、GCP のサービスアカウントの鍵（ログ用を含む）、Tunnel の認証ファイル）は、新しいMacでも同じものを使っているためです。初期化せずに手元に残すなら、次を消します。

```bash
rm -rf ~/scribe-bot-service ~/AIEditor-service ~/ele-workspace/marunage-studio-service \
  ~/scribe-bot-retired ~/launch-video-gen-retired ~/marunage-studio-retired \
  ~/.local/state/processing-mac-logs ~/processing-mac-retired
rm -f ~/.cloudflared/*.json ~/.cloudflared/config.yml
```

## 決めておくこと：自動ログイン

常駐（LaunchAgent）は、ユーザーがログインしている間だけ動きます。今の処理用Macは FileVault が有効で、自動ログインはありません。そのため停電のあと Mac は自動で起動しますが、誰かがログインするまでサービスは止まったままです。

- **このままにする**：停電のあとは手でログインする。
- **自動ログインにする**：FileVault を切る必要があり、Mac の中の秘密の値が守られにくくなる。

## 処理用Mac以外で deploy.sh を実行したとき

何もしません。処理用Macでないのに常駐が残っていれば、そのことだけを表示します。
