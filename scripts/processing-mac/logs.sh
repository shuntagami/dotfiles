# ログと停止通知。3サービスのログと1分ごとの稼働確認を、Vector で Cloud Logging へ送る（設定は logs/）。
# 見方と通知の条件は ele-inc/elevenlabs-transcribe-bot の docs/MAC_SERVICE.md「ログと停止通知」。
#
# 動かすのは処理用Macだけ。2台から稼働確認が届くと、まだサービスの無い新しいMacの down で通知が来るので、
# 切り替えでは旧Macの分を最初に止め、新しいMacの分は確認が通ってから動かす。その間（10分を超えると）
# 「稼働確認が届かない」のメールが来ることがある。

LOGS_LABEL=com.ele-inc.processing-mac.logs
LOGS_HOME="$HOME/.local/state/processing-mac-logs"
LOGS_KEY_SECRET=PROCESSING_MAC_LOGS_GCP_CREDENTIALS
LOGS_PROJECT=automatic-recording-of-minutes
# 起動し直した時刻。logs_verify はこれより後に届いた稼働確認だけを数える。
LOGS_STARTED_AT=

logs_name() { echo "ログと停止通知"; }

logs_installed() { agent_loaded "$LOGS_LABEL"; }

logs_plist() {
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LOGS_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$LIB/logs/run-vector.sh</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>30</integer>
  <key>ProcessType</key>
  <string>Standard</string>
  <key>StandardOutPath</key>
  <string>$HOME/Library/Logs/processing-mac-logs/vector.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/Library/Logs/processing-mac-logs/vector.log</string>
</dict>
</plist>
EOF
}

# 何度実行してもよい。Vector・鍵・LaunchAgent のうち、無いものや変わったものだけを用意する。
logs_install() {
  local plist="$AGENTS_DIR/$LOGS_LABEL.plist" new
  command -v vector >/dev/null || run "brew install vectordotdev/brew/vector"
  # 鍵は Secret Manager から一度だけ取る（登録手順は docs/MAC_SERVICE.md）。
  [ -s "$LOGS_HOME/gcp-credentials.json" ] ||
    run "mkdir -p '$LOGS_HOME' && (umask 077 && gcloud secrets versions access latest --secret=$LOGS_KEY_SECRET --project=$LOGS_PROJECT >'$LOGS_HOME/gcp-credentials.json.tmp') && mv '$LOGS_HOME/gcp-credentials.json.tmp' '$LOGS_HOME/gcp-credentials.json'"
  new="$(logs_plist)"
  if [ "$(cat "$plist" 2>/dev/null)" != "$new" ] || ! logs_installed; then
    note "\$ $LOGS_LABEL を登録して起動する（${plist}）"
    if [ "$DRY_RUN" != 1 ]; then
      LOGS_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      mkdir -p "$AGENTS_DIR" "$HOME/Library/Logs/processing-mac-logs"
      printf '%s\n' "$new" >"$plist"
      launchctl bootout "$GUI/$LOGS_LABEL" 2>/dev/null || true
      launchctl bootstrap "$GUI" "$plist"
    fi
  fi
}

# このMacの稼働確認が Cloud Logging に届いているか。起動し直したなら、その後に届いたものだけを見る。
logs_arrived() {
  local since="${LOGS_STARTED_AT:-$(date -u -v-3M +%Y-%m-%dT%H:%M:%SZ)}"
  gcloud logging read --project="$LOGS_PROJECT" --freshness=1h --limit=1 --format='value(timestamp)' \
    "logName=\"projects/$LOGS_PROJECT/logs/processing-mac-heartbeat\" AND resource.labels.node_id=\"$this_mac\" AND timestamp>=\"$since\"" 2>/dev/null | grep -q .
}

logs_verify() {
  [ "$DRY_RUN" = 1 ] && {
    note "（確認: $(logs_name)）"
    return 0
  }
  wait_for 180 "Cloud Logging への稼働確認" logs_arrived || {
    note "✗ ログと停止通知: 稼働確認が Cloud Logging に届かない（~/Library/Logs/processing-mac-logs/vector.log）"
    return 1
  }
  note "✓ ログと停止通知: このMacから届いている"
}

logs_stop_old() {
  on_old <<EOF
launchctl bootout gui/\$(id -u)/$LOGS_LABEL 2>/dev/null || true
EOF
}

logs_retire_old() {
  on_old <<EOF
f=~/Library/LaunchAgents/$LOGS_LABEL.plist
[ -f "\$f" ] && mkdir -p ~/processing-mac-retired && mv "\$f" ~/processing-mac-retired/ || true
EOF
}
