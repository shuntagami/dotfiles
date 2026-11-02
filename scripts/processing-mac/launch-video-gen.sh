# launch-video-gen（ele-inc/launch-video-gen の docs/processing-mac.md）。
# ジョブ・素材・書き出しはこのMacのディスク（約 470 GB）にあり、DB や JSON に
# /Users/<ユーザー>/AIEditor-service/... の絶対パスが入っている。そのため、
# 新しいMacも同じユーザー名にし、2台を同時に動かさない（同じジョブを二重に実行する）。
# 公開は Tunnel `launch-video-gen`。marunage-studio も同じ Tunnel を使う。

LVG_ROOT="$HOME/AIEditor-service"
LVG_APP="$LVG_ROOT/app"
LVG_REPO_URL="https://github.com/ele-inc/launch-video-gen.git"
LVG_QWEN_MODEL=".cache/huggingface/hub/models--Qwen--Qwen3-ForcedAligner-0.6B"

lvg_name() { echo "launch-video-gen"; }

lvg_installed() { agent_loaded com.ele-inc.launch-video-gen.web && [ -f "$LVG_ROOT/.deploy/config.json" ]; }

lvg_check() {
  local ok=0 node_version
  node_version="$(node -p 'process.versions.node' 2>/dev/null || echo 0)"
  version_at_least "$node_version" 24.11.0 || {
    note "✗ Node.js 24.11 以上が要る（今は ${node_version}）"
    ok=1
  }
  [ -x /opt/homebrew/opt/ffmpeg-full/bin/ffmpeg ] || {
    note "✗ ffmpeg-full が無い（字幕の焼き込みに要る）→ brew install ffmpeg-full"
    ok=1
  }
  # The copied Python environments point at Homebrew's python@3.13.
  [ -x /opt/homebrew/opt/python@3.13/bin/python3.13 ] || {
    note "✗ python@3.13 が無い → brew install python@3.13"
    ok=1
  }
  [ -x /opt/homebrew/bin/pnpm ] || {
    note "✗ pnpm（corepack）が無い → dotfiles の Brewfile の npm \"corepack\""
    ok=1
  }
  [ -d "/Applications/Google Chrome.app" ] || {
    note "✗ Google Chrome が無い（参考資料の取得に使う）"
    ok=1
  }
  codex login status 2>&1 | grep -qi "logged in" || {
    note "✗ Codex CLI にログインしていない → codex login（レイアウト作成に使う）"
    ok=1
  }
  vercel whoami >/dev/null 2>&1 || {
    note "✗ Vercel CLI にログインしていない → vercel login（共有リンクの公開に使う）"
    ok=1
  }
  return $ok
}

# Everything that can be copied while the old Mac keeps serving. Safe to repeat: rsync only
# sends what changed, so the final copy during the switch is short.
lvg_prepare() {
  [ -d "$LVG_APP/.git" ] || run "mkdir -p '$LVG_ROOT' && git clone $LVG_REPO_URL '$LVG_APP'"
  pull AIEditor-service/app/.env "$LVG_APP/.env"
  # corepack downloads pnpm on first use; do it here rather than inside a launchd job.
  run "cd '$LVG_APP' && pnpm --version && pnpm install --frozen-lockfile"

  # Python environments, the Julius runtime and the Qwen model are large to rebuild; copy them.
  # The phoneme runtime checks its dictionary by modification time, which rsync -a keeps.
  local runtime
  for runtime in phoneme-env qwen-boundary-env $(ask_old 'cd AIEditor-service && ls -d phoneme-runtime-julius-*'); do
    pull "AIEditor-service/$runtime" "$LVG_ROOT/"
  done
  run "mkdir -p '$HOME/.cache/huggingface/hub'"
  pull "$LVG_QWEN_MODEL" "$HOME/.cache/huggingface/hub/"

  # Jobs, sources and outputs. Not --delete yet: the old Mac is still writing.
  say "launch-video-gen のデータを写します（初回は約 470 GB）"
  run "mkdir -p '$LVG_ROOT/home'"
  pull AIEditor-service/home/ "$LVG_ROOT/home/"

  # The tunnel's credentials and routes (app.ele-studio.app and marunage.ele-studio.app).
  # Keep this Mac's cert.pem from `cloudflared tunnel login`; set aside a different config.
  local credentials
  credentials="$(ask_old "sed -n 's/^credentials-file: *//p' .cloudflared/config.yml")"
  [ -n "$credentials" ] || fail "旧Macの ~/.cloudflared/config.yml に credentials-file がありません"
  run "mkdir -p '$HOME/.cloudflared' && chmod 700 '$HOME/.cloudflared'"
  if [ -f "$HOME/.cloudflared/config.yml" ] && ! ask_old 'cat .cloudflared/config.yml' | cmp -s - "$HOME/.cloudflared/config.yml"; then
    run "mv '$HOME/.cloudflared/config.yml' '$HOME/.cloudflared/config.yml.bak-$(date +%Y%m%d%H%M%S)'"
  fi
  pull .cloudflared/config.yml "$HOME/.cloudflared/config.yml"
  pull ".cloudflared/$(basename "$credentials")" "$HOME/.cloudflared/"
}

lvg_idle_old() {
  ask_old 'curl -s -m 5 -H "Authorization: Bearer $(cat AIEditor-service/.deploy/token)" http://127.0.0.1:8441/health' |
    grep -q '"busy":false'
}

# Stop taking work, wait for the queue to drain, then stop the app. The tunnel stays on the old
# Mac until this one is ready; in between, visitors get Cloudflare's error page.
lvg_stop_old() {
  on_old <<'EOF'
U=gui/$(id -u); T=$(cat ~/AIEditor-service/.deploy/token)
launchctl bootout $U/com.ele-inc.launch-video-gen.update 2>/dev/null || true
drained=
for i in $(seq 1 60); do
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H "Authorization: Bearer $T" http://127.0.0.1:8441/drain)
  case "$code" in 2??) drained=1; break ;; esac
  sleep 10
done
if [ -z "$drained" ]; then
  launchctl bootstrap $U ~/Library/LaunchAgents/com.ele-inc.launch-video-gen.update.plist 2>/dev/null || true
  echo "launch-video-gen の処理が10分たっても終わらないので、止めずに戻しました" >&2
  exit 1
fi
launchctl bootout $U/com.ele-inc.launch-video-gen.web 2>/dev/null || true
# Two copies running would run the same jobs twice. Stop here unless the old one is really down.
for i in $(seq 1 30); do curl -s -m 2 -o /dev/null http://127.0.0.1:8440/ || break; sleep 2; done
if launchctl print $U/com.ele-inc.launch-video-gen.web >/dev/null 2>&1 || curl -s -m 2 -o /dev/null http://127.0.0.1:8440/; then
  echo "旧Macの launch-video-gen が止まりません" >&2
  exit 1
fi
EOF
}

# With the app stopped, make the copy exact (--delete also drops stale SQLite -wal/-shm files).
lvg_sync_final() {
  pull AIEditor-service/home/ "$LVG_ROOT/home/" --delete
  pull AIEditor-service/app/.env "$LVG_APP/.env"
  if [ "$DRY_RUN" != 1 ]; then
    local left
    left="$(rsync -an --delete -i -e "ssh ${SSH_OPTS[*]}" "$FROM:AIEditor-service/home/" "$LVG_ROOT/home/" | wc -l | tr -d ' ')"
    [ "$left" = 0 ] || fail "launch-video-gen のデータが旧Macと一致しません（差分 $left 件）。もう一度 switch を実行してください"
  fi
}

# Order matters: the auto-update setup reads and replaces the web agent, so it must exist first.
lvg_start() {
  run "cd '$LVG_APP' && git pull --ff-only && pnpm install --frozen-lockfile && pnpm run processing-mac:install launch-video-gen"
  run "launchctl bootstrap $GUI '$AGENTS_DIR/com.ele-inc.launch-video-gen.web.plist'"
  wait_for 900 "launch-video-gen の起動" curl -sf -o /dev/null http://127.0.0.1:8440/ ||
    fail "launch-video-gen が 15 分たっても起動しません（~/Library/Logs/launch-video-gen/）"
  run "cd '$LVG_APP' && pnpm run processing-mac:autoupdate '$LVG_ROOT' 8440"
}

# Move the public hostnames (launch-video-gen and marunage-studio) to this Mac.
lvg_switch_tunnel() {
  on_old <<'EOF'
launchctl bootout gui/$(id -u)/com.ele-inc.launch-video-gen.tunnel 2>/dev/null || true
for i in $(seq 1 15); do pgrep -f "cloudflared tunnel run launch-video-gen" >/dev/null || break; sleep 2; done
if pgrep -f "cloudflared tunnel run launch-video-gen" >/dev/null; then
  echo "旧Macの Tunnel（launch-video-gen）が止まりません" >&2
  exit 1
fi
EOF
  run "launchctl bootstrap $GUI '$AGENTS_DIR/com.ele-inc.launch-video-gen.tunnel.plist'"
}

lvg_verify() {
  local ok=0 token
  token="$(cat "$LVG_ROOT/.deploy/token" 2>/dev/null || true)"
  curl -s -m 5 -H "Authorization: Bearer $token" http://127.0.0.1:8441/health | grep -q '"busy"' || {
    note "✗ launch-video-gen: 管理用の 127.0.0.1:8441/health が応答しない"
    ok=1
  }
  [ "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8440/)" = 200 ] || {
    note "✗ launch-video-gen: 127.0.0.1:8440 が 200 を返さない"
    ok=1
  }
  # Cloudflare Access sends visitors to its login page.
  [ "$(curl -s -o /dev/null -w '%{http_code}' https://app.ele-studio.app/)" = 302 ] || {
    note "✗ launch-video-gen: https://app.ele-studio.app が Access のログインへ転送しない"
    ok=1
  }
  [ $ok = 0 ] && note "✓ launch-video-gen: このMacで動いている（画面での確認は docs/processing-mac.md）"
  return $ok
}

lvg_retire_old() {
  on_old <<'EOF'
mkdir -p ~/launch-video-gen-retired
for a in web update tunnel; do
  f=~/Library/LaunchAgents/com.ele-inc.launch-video-gen.$a.plist
  [ -f "$f" ] && mv "$f" ~/launch-video-gen-retired/
done
EOF
}
