#!/bin/bash
# 処理用Macの稼働確認。Vector（vector.yaml）が1分ごとに実行し、サービスごとに JSON を1行出す。
#   {"service":"scribe-bot","status":"ok"}
#   {"service":"marunage-studio","status":"down","problems":"…"}
# down が続くか、この出力が届かなくなると、メールで通知が来る
# （ele-inc/elevenlabs-transcribe-bot の infra/processing-mac-logs.tf）。
# 標準出力は JSON だけにする（Vector が1行ずつ JSON として読む）。macOS の bash 3.2 で動かす。
set -o pipefail

GUI="gui/$(id -u)"
problems=()

agent_pid() {
  launchctl print "$GUI/com.ele-inc.$1" 2>/dev/null | awk '/^\tstate = / { state = $3 } /^\tpid = / { pid = $3 } END { if (state == "running") print pid }'
}

# running <LaunchAgent の名前（com.ele-inc. の後ろ）>
running() {
  [ -n "$(agent_pid "$1")" ] || problems+=("$1 が動いていない")
}

# returns <期待する HTTP ステータス> <URL>
returns() {
  local code
  code="$(curl -s -m 5 -o /dev/null -w '%{http_code}' "$2")"
  [ "$code" = "$1" ] || problems+=("$2 が $1 でなく $code を返す")
}

# answers <応答に含まれるはずの文字列> <URL>
answers() {
  curl -s -m 5 "$2" | grep -qF "$1" || problems+=("$2 の応答に $1 が無い")
}

# tunnel_ready <cloudflared の LaunchAgent の名前>: Cloudflare とつながっているか。
# cloudflared は 127.0.0.1:20241〜 のどれかで /ready を返すので、プロセスからポートをたどる。
tunnel_ready() {
  local pid port
  pid="$(agent_pid "$1")"
  [ -n "$pid" ] || {
    problems+=("$1 が動いていない")
    return
  }
  port="$(lsof -nP -a -p "$pid" -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR > 1 { sub(/.*:/, "", $9); print $9; exit }')"
  curl -s -m 5 "http://127.0.0.1:${port:-0}/ready" | grep -q '"status":200' ||
    problems+=("$1 が Cloudflare とつながっていない")
}

# report <サービス名>: ここまでの確認結果を1行の JSON にして、次のサービスのために空にする。
report() {
  local detail
  if [ ${#problems[@]} -eq 0 ]; then
    printf '{"service":"%s","status":"ok"}\n' "$1"
  else
    detail="$(printf '%s; ' "${problems[@]}")"
    detail="${detail%; }"
    detail="${detail//\\/\\\\}"
    printf '{"service":"%s","status":"down","problems":"%s"}\n' "$1" "${detail//\"/\\\"}"
  fi
  problems=()
}

running scribe-bot.slack
returns 200 http://127.0.0.1:8091/status
tunnel_ready scribe-bot.tunnel
# 外から Cloudflare を通って、このMacの Tunnel まで届くか。`/` は Tunnel 自身が 404 を返し、アプリには届かない
# （アプリまで届く URL にすると、毎分のリクエストが文字起こしのログに残る）。Tunnel が切れていれば 530 になる。
returns 404 https://scribe.ele-studio.app/
report scribe-bot

running launch-video-gen.web
returns 200 http://127.0.0.1:8440/
tunnel_ready launch-video-gen.tunnel
report launch-video-gen

running marunage-studio.web
returns 200 http://127.0.0.1:3100/login
running marunage-studio.runtime
answers '"ok":true' http://127.0.0.1:8080/health
report marunage-studio
