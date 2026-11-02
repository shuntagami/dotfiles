#!/bin/bash
# LaunchAgent com.ele-inc.processing-mac.logs が起動する（登録は scripts/processing-mac/logs.sh）。
# vector.yaml が使う環境変数を決めて、Vector を起動する。設定ファイルを書き換えると、Vector が読み直す。
set -euo pipefail

PROCESSING_MAC_LOGS_DIR="$(cd "$(dirname "$0")" && pwd)"
PROCESSING_MAC_LOGS_HOME="${PROCESSING_MAC_LOGS_HOME:-$HOME/.local/state/processing-mac-logs}"
PROCESSING_MAC_NAME="$(scutil --get LocalHostName)"
export PROCESSING_MAC_LOGS_DIR PROCESSING_MAC_LOGS_HOME PROCESSING_MAC_NAME

mkdir -p "$PROCESSING_MAC_LOGS_HOME/data"
# 設定の ${…} を展開するには、今の Vector（0.61）では明示の許可が要る。展開するのは上の3つと HOME だけ
# （秘密の値は環境変数に入れない。鍵はファイルで渡す）。
exec /opt/homebrew/bin/vector --dangerously-allow-env-var-interpolation --watch-config \
  --config "$PROCESSING_MAC_LOGS_DIR/vector.yaml"
