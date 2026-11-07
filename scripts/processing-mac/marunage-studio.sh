# marunage-studio（ele-inc/marunage-studio の docs/design-2026-10-26-local-files-on-mac.md と
# scripts/mac-studio-install.mjs）。Studio（3100）・Agent Runtime（8080）・自動更新の3つ。
# 公開は launch-video-gen の Tunnel にある marunage.ele-studio.app の行で、Tunnel と一緒に移る。
# 旧Macから必ず要るのは env の3ファイル。人ごとの worktree は push 済みなら取り直せる。

MARUNAGE_REPO="$HOME/ele-workspace/marunage-studio"
MARUNAGE_SERVICE="$HOME/ele-workspace/marunage-studio-service"
MARUNAGE_ENV_FILES=(.env.local .env.mac.local .env.production.local)

marunage_name() { echo "marunage-studio"; }

marunage_installed() { agent_loaded com.ele-inc.marunage-studio.web && [ -f "$MARUNAGE_SERVICE/.deploy/config.json" ]; }

marunage_check() {
  local ok=0 tool
  # The agent runtime starts this exact path for every chat turn.
  [ -x "$HOME/.local/bin/claude" ] || {
    note "✗ Claude Code のコマンド版が無い → dotfiles の install-packages.sh（~/.local/bin/claude）"
    ok=1
  }
  for tool in node git pnpm gh; do
    [ -x "/opt/homebrew/bin/$tool" ] || {
      note "✗ /opt/homebrew/bin/$tool が無い（marunage-studio の install が使う）"
      ok=1
    }
  done
  return $ok
}

marunage_prepare() {
  local f
  run "mkdir -p '$MARUNAGE_REPO/apps/studio'"
  for f in "${MARUNAGE_ENV_FILES[@]}"; do
    pull "ele-workspace/marunage-studio-service/env/$f" "$MARUNAGE_REPO/apps/studio/$f"
  done
  run "chmod 600 '$MARUNAGE_REPO/apps/studio/'.env.*"
  # corepack fetches pnpm on first use; do it here rather than inside a launchd job.
  run "cd '$MARUNAGE_REPO' && pnpm --version"
  # Writes the agents and builds the first release, but does not start anything (no --load).
  run "cd '$MARUNAGE_REPO' && node scripts/mac-studio-install.mjs --env-from '$MARUNAGE_REPO/apps/studio'"
  # The per-person worktrees get origin/main through this timer.
  agent_loaded com.user.git-sync || run '"$HOME/dotfiles/bin/git-sync-all" install'
}

# Unpushed work in the per-person worktrees lives only on the old Mac. Never carry it over
# silently: list it and stop, so its owner can push first.
marunage_unpushed_old() {
  ask_old 'for w in ele-workspace/launch-consulting-studio-worktrees/*/; do
    [ -d "$w" ] || continue
    dirty=$(git -C "$w" status --porcelain | wc -l | tr -d " ")
    ahead=$(git -C "$w" rev-list --count origin/main..HEAD 2>/dev/null || echo 0)
    [ "$dirty" = 0 ] && [ "$ahead" = 0 ] || echo "${w}（未 commit $dirty 件・未 push $ahead 件）"
  done'
}

marunage_idle_old() {
  ask_old 'curl -s -m 5 http://127.0.0.1:8080/health' | grep -q '"activeTurns":0,.*"pendingQuestions":0' &&
    ask_old 'test ! -e ele-workspace/marunage-studio-service/.deploy/update.lock'
}

marunage_stop_old() {
  on_old <<'EOF'
U=gui/$(id -u)
for a in update runtime web; do launchctl bootout $U/com.ele-inc.marunage-studio.$a 2>/dev/null || true; done
for i in $(seq 1 60); do
  # The ports may close before launchd removes the jobs (or vice versa).
  if ! launchctl print $U/com.ele-inc.marunage-studio.web >/dev/null 2>&1 &&
    ! launchctl print $U/com.ele-inc.marunage-studio.runtime >/dev/null 2>&1 &&
    ! launchctl print $U/com.ele-inc.marunage-studio.update >/dev/null 2>&1 &&
    ! curl -s -m 2 -o /dev/null http://127.0.0.1:3100/ &&
    ! curl -s -m 2 -o /dev/null http://127.0.0.1:8080/health; then
    exit 0
  fi
  sleep 1
done
echo "旧Macの marunage-studio が止まりません" >&2
exit 1
EOF
}

marunage_sync_final() {
  local f
  # Releases link these files from the service's env/ folder.
  for f in "${MARUNAGE_ENV_FILES[@]}"; do
    pull "ele-workspace/marunage-studio-service/env/$f" "$MARUNAGE_SERVICE/env/$f"
  done
  # Chat output and the chat's Claude settings: without them old chats show only what the DB has.
  run "mkdir -p '$HOME/ele-workspace/launch-consulting-studio-chat' '$HOME/.marunage-studio-claude'"
  pull ele-workspace/launch-consulting-studio-chat/ "$HOME/ele-workspace/launch-consulting-studio-chat/"
  pull .marunage-studio-claude/ "$HOME/.marunage-studio-claude/"
  run "python3 '$HOME/dotfiles/scripts/install-user-configs.py' agent-instructions --claude-config-dir '$HOME/.marunage-studio-claude'"
}

marunage_start() {
  local a
  for a in web runtime update; do
    run "launchctl bootstrap $GUI '$AGENTS_DIR/com.ele-inc.marunage-studio.$a.plist'"
  done
  wait_for 300 "marunage-studio の起動" curl -sf -o /dev/null http://127.0.0.1:3100/login ||
    fail "marunage-studio が 5 分たっても起動しません（~/Library/Logs/marunage-studio/）"
}

marunage_verify() {
  local ok=0
  [ "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3100/login)" = 200 ] || {
    note "✗ marunage-studio: 127.0.0.1:3100/login が 200 を返さない"
    ok=1
  }
  curl -s -m 5 http://127.0.0.1:8080/health | grep -q '"ok":true' || {
    note "✗ marunage-studio: Agent Runtime（127.0.0.1:8080/health）が応答しない"
    ok=1
  }
  [ "$(curl -s -o /dev/null -w '%{http_code}' https://marunage.ele-studio.app/login)" = 302 ] || {
    note "✗ marunage-studio: https://marunage.ele-studio.app が Access のログインへ転送しない"
    ok=1
  }
  [ $ok = 0 ] && note "✓ marunage-studio: このMacで動いている"
  return $ok
}

marunage_retire_old() {
  on_old <<'EOF'
mkdir -p ~/marunage-studio-retired
for a in web runtime update; do
  f=~/Library/LaunchAgents/com.ele-inc.marunage-studio.$a.plist
  [ -f "$f" ] && mv "$f" ~/marunage-studio-retired/
done
EOF
}
