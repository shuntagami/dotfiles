# ログと停止通知。3サービスのログと1分ごとの稼働確認を、Vector で Cloud Logging へ送る（設定は logs/）。
# 見方と通知の条件は ele-inc/elevenlabs-transcribe-bot の docs/MAC_SERVICE.md「ログと停止通知」。
#
# 動かすのは処理用Macだけ。2台から稼働確認が届くと、まだサービスの無い新しいMacの down で通知が来るので、
# 切り替えでは旧Macの分を最初に止め、新しいMacの分は確認が通ってから動かす。その間（10分を超えると）
# 「稼働確認が届かない」のメールが来ることがある。

LOGS_LABEL=com.ele-inc.processing-mac.logs
LOGS_HOME="$HOME/.local/state/processing-mac-logs"
# logs/ の写し。LaunchAgent はここから動かす（dotfiles のブランチを切り替えても、動いている Vector が変わらない）。
LOGS_APP="$LOGS_HOME/app"
LOGS_KEY_SECRET=PROCESSING_MAC_LOGS_GCP_CREDENTIALS
LOGS_PROJECT=automatic-recording-of-minutes
# 起動し直した時刻。logs_verify はこれより後に届いた稼働確認だけを数える。
LOGS_STARTED_AT=

logs_name() { echo "ログと停止通知"; }

logs_installed() { agent_loaded "$LOGS_LABEL"; }

logs_running() { launchctl print "$GUI/$LOGS_LABEL" 2>/dev/null | grep -q '^[[:space:]]state = running$'; }

# フォルダの中身から作る版の印。run-vector.sh も起動時に同じ作り方で running-version に書く。
logs_version() { (cd "$1" && find . -type f -print0 | sort -z | xargs -0 shasum -a 256 | shasum -a 256 | cut -d' ' -f1); }

logs_status() {
  if logs_running; then
    note "● $(logs_name): このMacから送っている"
  elif logs_installed; then
    note "▲ $(logs_name): 登録されているが動いていない（~/Library/Logs/processing-mac-logs/vector.log）"
  else
    note "○ $(logs_name): このMacからは送っていない"
  fi
}

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
    <string>$LOGS_APP/run-vector.sh</string>
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

logs_check() {
  gcloud secrets versions describe latest --secret="$LOGS_KEY_SECRET" --project="$LOGS_PROJECT" >/dev/null 2>&1 || {
    note "✗ ログ用の鍵（Secret Manager の ${LOGS_KEY_SECRET}）を読めない → gcloud auth login。鍵が無ければ ele-inc/elevenlabs-transcribe-bot の docs/MAC_SERVICE.md「ログと停止通知」で登録する"
    return 1
  }
}

# Vector と鍵。旧Macから写すものは無い。
# 呼び出し元が || で受けると set -e が効かないので、失敗はすべて return 1 で返す（logs_install も同じ）。
logs_prepare() {
  command -v vector >/dev/null || run "brew install vectordotdev/brew/vector" || return 1
  # 鍵は Secret Manager から一度だけ取る（登録手順は docs/MAC_SERVICE.md）。
  [ -s "$LOGS_HOME/gcp-credentials.json" ] ||
    run "mkdir -p '$LOGS_HOME' && (umask 077 && gcloud secrets versions access latest --secret=$LOGS_KEY_SECRET --project=$LOGS_PROJECT >'$LOGS_HOME/gcp-credentials.json.tmp') && mv '$LOGS_HOME/gcp-credentials.json.tmp' '$LOGS_HOME/gcp-credentials.json'" ||
    return 1
}

# 何度実行してもよい。Vector・鍵・logs/ の写し・LaunchAgent のうち、無いものや変わったものだけを用意し、
# 動いている版が写しと違えば Vector を起動し直す（途中で失敗しても、次の実行で揃う）。
logs_install() {
  local plist="$AGENTS_DIR/$LOGS_LABEL.plist" new
  logs_prepare || return 1
  if ! diff -rq "$LIB/logs" "$LOGS_APP" >/dev/null 2>&1; then
    run "mkdir -p '$LOGS_APP' && rsync -a --delete '$LIB/logs/' '$LOGS_APP/'" || return 1
  fi
  new="$(logs_plist)"
  if [ "$(cat "$plist" 2>/dev/null)" != "$new" ] || ! logs_installed; then
    note "\$ $LOGS_LABEL を登録して起動する（${plist}）"
    [ "$DRY_RUN" = 1 ] && return 0
    LOGS_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    mkdir -p "$AGENTS_DIR" "$HOME/Library/Logs/processing-mac-logs" || return 1
    printf '%s\n' "$new" >"$plist" || return 1
    launchctl bootout "$GUI/$LOGS_LABEL" 2>/dev/null || true
    launchctl bootstrap "$GUI" "$plist" || return 1
  elif [ "$(cat "$LOGS_HOME/running-version" 2>/dev/null)" != "$(logs_version "$LOGS_APP" 2>/dev/null)" ]; then
    note "\$ launchctl kickstart -k ${GUI}/${LOGS_LABEL}（動いている版が写しと違うので起動し直す）"
    [ "$DRY_RUN" = 1 ] && return 0
    LOGS_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    launchctl kickstart -k "$GUI/$LOGS_LABEL" || return 1
  fi
}

# このMacの稼働確認が Cloud Logging に届いているか。起動し直したなら、その後に届いたものだけを見る。
# 起動し直していなければ、直近75秒の分を見る（稼働確認は1分ごとなので、Vector が動いていれば必ずある）。
logs_arrived() {
  local since="${LOGS_STARTED_AT:-$LOGS_VERIFY_SINCE}"
  gcloud logging read --project="$LOGS_PROJECT" --freshness=1h --limit=1 --format='value(timestamp)' \
    "logName=\"projects/$LOGS_PROJECT/logs/processing-mac-heartbeat\" AND resource.labels.node_id=\"$this_mac\" AND timestamp>=\"$since\"" 2>/dev/null | grep -q .
}

logs_verify() {
  [ "$DRY_RUN" = 1 ] && {
    note "（確認: $(logs_name)）"
    return 0
  }
  LOGS_VERIFY_SINCE="$(date -u -v-75S +%Y-%m-%dT%H:%M:%SZ)"
  wait_for 180 "Cloud Logging への稼働確認" logs_arrived || {
    note "✗ ログと停止通知: 稼働確認が Cloud Logging に届かない（~/Library/Logs/processing-mac-logs/vector.log）"
    return 1
  }
  note "✓ ログと停止通知: このMacから届いている"
}

logs_stop_old() {
  on_old <<EOF
U=gui/\$(id -u)
launchctl bootout \$U/$LOGS_LABEL 2>/dev/null || true
# 止めた直後はまだ登録が見えることがあるので、少し待ってから決める。
for i in 1 2 3 4 5 6 7 8 9 10; do
  launchctl print \$U/$LOGS_LABEL >/dev/null 2>&1 || exit 0
  sleep 1
done
echo "旧Macのログ送信が止まりません" >&2
exit 1
EOF
}

logs_retire_old() {
  on_old <<EOF
f=~/Library/LaunchAgents/$LOGS_LABEL.plist
[ -f "\$f" ] && mkdir -p ~/processing-mac-retired && mv "\$f" ~/processing-mac-retired/ || true
EOF
}
