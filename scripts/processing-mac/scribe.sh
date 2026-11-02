# 文字起こし（ele-inc/elevenlabs-transcribe-bot の docs/MAC_SERVICE.md）。
# Slack は Socket Mode、API と Discord は専用の Tunnel `scribe` で受ける。ジョブの記録はクラウドにあり、
# Mac に残す状態がないので、2台を並べて動かしてから旧Macを止めれば、止まる時間なく移せる。

scribe_name() { echo "文字起こし"; }

scribe_installed() { agent_loaded com.ele-inc.scribe-bot.slack; }

scribe_check() {
  local ok=0
  [ -f "$HOME/.cloudflared/cert.pem" ] || {
    note "✗ Cloudflare にログインしていない → cloudflared tunnel login（ele-studio.app を選ぶ）"
    ok=1
  }
  gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | grep -q . || {
    note "✗ Google Cloud にログインしていない → gcloud auth login（Secret Manager を読めるアカウント）"
    ok=1
  }
  return $ok
}

# Nothing to copy: secrets come from Secret Manager and the tunnel credentials from Cloudflare.
scribe_prepare() { :; }

# The installer fetches the existing tunnel's credentials and starts the three agents.
scribe_start() { run '"$HOME/ele-workspace/elevenlabs-transcribe-bot/scripts/mac/install.sh"'; }

scribe_stop_old() {
  # Take the old Mac off the tunnel first, then let running transcriptions finish (up to 15 min).
  on_old <<'EOF'
U=gui/$(id -u)
launchctl bootout $U/com.ele-inc.scribe-bot.tunnel 2>/dev/null || true
for i in $(seq 1 90); do
  curl -s -m 5 http://127.0.0.1:8091/status | grep -q '"active":0' && break
  sleep 10
done
for a in slack update; do launchctl bootout $U/com.ele-inc.scribe-bot.$a 2>/dev/null || true; done
if launchctl print $U/com.ele-inc.scribe-bot.slack >/dev/null 2>&1; then
  echo "旧Macの文字起こしが止まりません" >&2
  exit 1
fi
EOF
}

scribe_verify() {
  local ok=0
  curl -s -m 5 http://127.0.0.1:8091/status | grep -q '"draining":false' || {
    note "✗ 文字起こし: 127.0.0.1:8091/status が応答しない"
    ok=1
  }
  [ "$(curl -s -o /dev/null -w '%{http_code}' https://scribe.ele-studio.app/v1/sources)" = 401 ] || {
    note "✗ 文字起こし: https://scribe.ele-studio.app/v1/sources がアプリまで届かない（401 にならない）"
    ok=1
  }
  [ $ok = 0 ] && note "✓ 文字起こし: このMacで受けている"
  return $ok
}

scribe_retire_old() {
  on_old <<'EOF'
mkdir -p ~/scribe-bot-retired
for a in slack tunnel update; do
  f=~/Library/LaunchAgents/com.ele-inc.scribe-bot.$a.plist
  [ -f "$f" ] && mv "$f" ~/scribe-bot-retired/
done
EOF
}
