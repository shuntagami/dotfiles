---
name: vfr-sync-rife
description: VFR（可変フレームレート）気味の動画素材を、音声同期を崩さずにRIFEフレーム補間でCFR化してカクつきを軽減する。「カクつき」「音ズレ」「VFR」「フレーム補間」「RIFE」「30fps化」などの依頼時、または表記fpsとavg_frame_rateが乖離した動画（例: 表記30fps・実測15fps）を扱うときに使う。複数ファイルの一括処理に対応。
---

# VFR動画の同期保持RIFE補間

## 原理

スマホ・画面収録などのVFR素材は、表記fps（r_frame_rate）に対して実際のフレーム間隔がバラつく。
PNG連番→RIFE→再結合の「通常の補間パイプライン」はフレームを等間隔とみなすため、
元の時間情報が崩れて音声とズレる（コンテナのdurationは合っていても内部タイミングが歪む）。

このスキルは:
1. 各実フレームのPTSを読み取り、目標fpsグリッド上の本来の位置に配置（量子化誤差 ≤ 1/(2*fps)）
2. 欠けているスロットだけを RIFE v4.6 の任意タイムステップ補間（`-s`）で生成
3. 音声は無劣化コピー。mux後にstart_timeを実測し、AACエンコーダ遅延由来のズレ（数十ms）を`-itsoffset`で自動補正
4. 元動画と出力のduration / 音声start_time / フレーム数を突き合わせて検証

## 使い方

```bash
# 単発
python3 ~/.claude/skills/vfr-sync-rife/scripts/vfr_sync_rife.py "動画.mp4"

# 一括（出力先指定）
python3 ~/.claude/skills/vfr-sync-rife/scripts/vfr_sync_rife.py *.MP4 -o ~/Movies/sync_out
```

- 既定の出力: 各入力と同じ場所の `vfr_sync_out/<元名>_sync.mp4`（元ファイルは変更しない）
- 主なオプション: `--fps N`（既定は表記fpsの四捨五入）, `--crf 18`, `--workers 3`, `--keep-temp`
- 長時間になるので、実行はBashの `run_in_background: true` で行い、完了通知を待つこと

## 実行前チェック

1. `ffprobe`でr_frame_rateとavg_frame_rateを確認。乖離していればVFR → このスキルの出番。
   ほぼ一致していればRIFE補間対象の欠損がなく、実行しても再エンコードにしかならない旨をユーザーに伝える。
2. ffmpeg/ffprobeが必要（`brew install ffmpeg`）。RIFEバイナリは `bin/` に置く（gitには含めていない）。
   `bin/rife-ncnn-vulkan` が無い場合は `scripts/install_rife.sh` を実行して取得する。

## 目安（Apple Silicon, 1080x1920）

- RIFE補間: 約2秒/枚 ÷ workers 3 → 実測15fps素材の1分動画（欠損~450枚）で約5分、3分動画で約15分
- 一時ディスク: PNG展開で1分あたり約5〜10GB（処理後に自動削除）

## 完了時の報告

スクリプトが出す検証行（`✓ 検証OK` / `✗ 音声同期の検証に失敗`）を必ず確認して結果をユーザーに伝える。
判定基準: 音声start_time差 ≤ 5ms、音声フレーム数完全一致。

注意点として必ず添えること:
- 元素材に0.2秒超の欠落があった場合、その区間のRIFE生成コマはモーフィング調に見えることがある
  （欠落の分布はスクリプトのログ「欠損Nスロット」と元のフレーム間隔から判断）
- 実フレームの配置には最大 1/(2*fps) 秒（30fpsなら16.7ms）の量子化が入る
