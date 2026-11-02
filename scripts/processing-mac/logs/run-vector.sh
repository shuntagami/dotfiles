#!/bin/bash
# LaunchAgent com.ele-inc.processing-mac.logs が起動する（登録は scripts/processing-mac/logs.sh）。
# vector.yaml が使う環境変数を決めて、Vector を起動する。このファイルと設定は ~/.local/state/processing-mac-logs/app
# に写したもの（dotfiles のブランチを切り替えても、動いている Vector が変わらないように）。
set -euo pipefail

PROCESSING_MAC_LOGS_DIR="$(cd "$(dirname "$0")" && pwd)"
PROCESSING_MAC_LOGS_HOME="${PROCESSING_MAC_LOGS_HOME:-$HOME/.local/state/processing-mac-logs}"
PROCESSING_MAC_NAME="$(scutil --get LocalHostName)"
export PROCESSING_MAC_LOGS_DIR PROCESSING_MAC_LOGS_HOME PROCESSING_MAC_NAME

# 初めて動かすMac（読んだ位置の記録が無い）では、ログを先頭から送る。切り替えた直後の起動の様子も残すため。
# 記録があるMacでは末尾から読む。記録の無いファイル（送る行がまだ無かったもの）の古い行を送り直さないため。
if [ -e "$PROCESSING_MAC_LOGS_HOME/data/service_logs/checkpoints.json" ]; then
  PROCESSING_MAC_LOGS_READ_FROM=end
else
  PROCESSING_MAC_LOGS_READ_FROM=beginning
fi
export PROCESSING_MAC_LOGS_READ_FROM

mkdir -p "$PROCESSING_MAC_LOGS_HOME/data"
# 動いている版の印。logs.sh の logs_version と同じ作り方で、deploy がこれと写しを比べて起動し直すかを決める。
(cd "$PROCESSING_MAC_LOGS_DIR" && find . -type f -print0 | sort -z | xargs -0 shasum -a 256 | shasum -a 256 | cut -d' ' -f1) \
  >"$PROCESSING_MAC_LOGS_HOME/running-version"
# 設定の ${…} を展開するには、今の Vector（0.61）では明示の許可が要る。展開するのは上の4つと HOME だけ
# （秘密の値は環境変数に入れない。鍵はファイルで渡す）。
# LaunchAgent の PATH（/opt/homebrew/bin・/usr/local/bin）から探す。
exec vector --dangerously-allow-env-var-interpolation \
  --config "$PROCESSING_MAC_LOGS_DIR/vector.yaml"
