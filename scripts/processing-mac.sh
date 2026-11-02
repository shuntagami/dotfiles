#!/bin/bash
# 処理用Mac（社内サービスを常駐させるMac）を引き継ぐ。手順と背景は docs/processing-mac.md。
#
#   processing-mac.sh status            このMacで動いているサービスを表示する
#   processing-mac.sh check   [opts]    引き継ぎに要るもの（ログイン・SSH・空き容量など）を確かめる
#   processing-mac.sh prepare [opts]    旧Macを動かしたまま、データと設定を写す（何度でも実行できる）
#   processing-mac.sh switch  [opts]    旧Macを止めて、このMacで動かし始める
#   processing-mac.sh deploy            deploy.sh から呼ぶ。このMacが処理用Macで、まだサービスが
#                                       無ければ check → prepare → switch を行う。サービスがそろっていれば、
#                                       ログと停止通知（logs.sh）だけを用意し直す。処理用Macでなければ何もしない
#
# opts:
#   --from HOST   旧Macへの SSH 先（既定は misc/processing-mac.conf の PREVIOUS_PROCESSING_MAC）
#   --dry-run     実行するコマンドを表示するだけ。--from . でこのMacを旧Mac役にして通しで試せる
#   --yes         切り替えの確認を省く
set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
CONF="${PROCESSING_MAC_CONF:-$DOTFILES/misc/processing-mac.conf}"
LIB="$DOTFILES/scripts/processing-mac"

# shellcheck source=misc/processing-mac.conf
source "$CONF"
command="${1:-status}"
[ $# -gt 0 ] && shift
while [ $# -gt 0 ]; do
  case "$1" in
    --from) FROM="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --yes) ASSUME_YES=1; shift ;;
    *) echo "不明なオプション: $1" >&2; exit 2 ;;
  esac
done
FROM="${FROM:-${PREVIOUS_PROCESSING_MAC:-}}"

source "$LIB/lib.sh"
source "$LIB/scribe.sh"
source "$LIB/launch-video-gen.sh"
source "$LIB/marunage-studio.sh"
SERVICES=(scribe lvg marunage)
# Logs and alerts are not a service to take over: they start fresh on whichever Mac is the processing Mac.
source "$LIB/logs.sh"

this_mac="$(scutil --get LocalHostName)"

status() {
  local s
  for s in "${SERVICES[@]}"; do
    if "${s}_installed"; then note "● $("${s}_name"): このMacで動いている"; else note "○ $("${s}_name"): このMacには無い"; fi
  done
  if logs_installed; then note "● $(logs_name): このMacから送っている"; else note "○ $(logs_name): このMacからは送っていない"; fi
}

all_installed() {
  local s
  for s in "${SERVICES[@]}"; do "${s}_installed" || return 1; done
}

any_installed() {
  local s
  for s in "${SERVICES[@]}"; do "${s}_installed" && return 0; done
  logs_installed
}

check() {
  local ok=0 s old_home old_name old_size free
  say "引き継ぎに要るものを確かめます（旧Mac: ${FROM:-未設定}）"
  [ "$this_mac" = "$PROCESSING_MAC" ] || {
    note "✗ このMac（${this_mac}）は処理用Macではない → misc/processing-mac.conf の PROCESSING_MAC をこのMacの名前にする"
    ok=1
  }
  if [ -z "$FROM" ]; then
    note "✗ 旧Macへの SSH 先が無い → misc/processing-mac.conf の PREVIOUS_PROCESSING_MAC に書く（例: Tailscale の名前）"
    return 1
  fi
  if [ "$FROM" = . ]; then
    [ "$DRY_RUN" = 1 ] || fail "--from . は --dry-run と一緒にだけ使えます（このMacのサービスを止めてしまうため）"
    note "（--from . : このMacを旧Mac役にした通しの確認）"
  elif ! ask_old true 2>/dev/null; then
    note "✗ 旧Mac（${FROM}）へパスワードなしで SSH できない → 旧Macで「リモートログイン」を有効にし、このMacの公開鍵を旧Macの ~/.ssh/authorized_keys に足す"
    return 1
  else
    old_name="$(ask_old 'scutil --get LocalHostName')"
    [ "$old_name" != "$this_mac" ] || {
      note "✗ 旧Macと名前（LocalHostName）が同じ → sudo scutil --set LocalHostName 新しい名前"
      ok=1
    }
  fi
  # launch-video-gen's data is full of absolute paths under the home folder.
  old_home="$(ask_old 'printf %s "$HOME"')"
  [ "$old_home" = "$HOME" ] || {
    note "✗ ホームフォルダが旧Macと違う（旧: ${old_home}、新: ${HOME}）→ 同じユーザー名で作り直す"
    ok=1
  }
  version_at_least "$(sw_vers -productVersion)" 27.0 || {
    note "✗ macOS 27 以上が要る（launch-video-gen の音素合わせのランタイムが 27 向けにビルドされている）"
    ok=1
  }
  gh auth status >/dev/null 2>&1 || {
    note "✗ GitHub にログインしていない → gh auth login（HTTPS、Git の認証にも使う）"
    ok=1
  }
  old_size="$(ask_old 'du -sk AIEditor-service/home 2>/dev/null | cut -f1' || echo 0)"
  free="$(df -k "$HOME" | awk 'NR == 2 { print $4 }')"
  [ "$free" -gt $((old_size + old_size / 10 + 50 * 1024 * 1024)) ] || {
    note "✗ 空き容量が足りない（要るのは約 $((old_size / 1024 / 1024 + 50)) GB、空きは $((free / 1024 / 1024)) GB）"
    ok=1
  }
  for s in "${SERVICES[@]}"; do "${s}_check" || ok=1; done
  [ $ok = 0 ] && note "✓ 揃っています"
  return $ok
}

prepare() {
  local s
  say "旧Macを動かしたまま、このMacへ写します"
  # Always on, back after a power cut, reachable over the network (the old Mac's settings;
  # launch-video-gen asks for disksleep 0 as well).
  run "sudo pmset -a sleep 0 disksleep 0 autorestart 1 womp 1"
  # Company repositories. The Studio clone must be a full clone, so make it before the
  # workspace script, which would otherwise create a partial one.
  [ -d "$HOME/ele-workspace/.git" ] || run "git clone https://github.com/ele-inc/ele-workspace.git '$HOME/ele-workspace'"
  [ -d "$HOME/ele-workspace/launch-consulting-studio/.git" ] ||
    run "git clone https://github.com/ele-inc/launch-consulting.git '$HOME/ele-workspace/launch-consulting-studio'"
  run "cd '$HOME/ele-workspace' && node scripts/setup-repositories.mjs"
  for s in "${SERVICES[@]}"; do
    say "$("${s}_name") を用意します"
    "${s}_prepare"
  done
}

# What has been stopped on the old Mac so far, to say how to undo it if a step fails.
stopped=()
on_switch_error() {
  [ ${#stopped[@]} -gt 0 ] || return 0
  local name
  printf '\n[processing-mac] 途中で止まりました。旧Macで止めたもの: %s\n' "${stopped[*]}" >&2
  printf '    旧Macに戻すには、旧Macのターミナルで次を実行する:\n' >&2
  for name in "${stopped[@]}"; do
    printf '      for f in ~/Library/LaunchAgents/com.ele-inc.%s.*.plist; do launchctl bootstrap gui/$(id -u) "$f"; done\n' "$name" >&2
  done
}

switch() {
  local unpushed s ok=0
  say "旧Macが空いているかを確かめます"
  unpushed="$(marunage_unpushed_old)"
  if [ -n "$unpushed" ]; then
    local message="marunage-studio の worktree に、旧Macにしか無い作業があります。push してから実行してください:
$unpushed"
    [ "$DRY_RUN" = 1 ] && note "（本番ならここで止まる）$message" || fail "$message"
  fi
  wait_for 600 "launch-video-gen の処理" lvg_idle_old || fail "launch-video-gen が処理中です。終わってから実行してください"
  wait_for 600 "marunage-studio のチャット" marunage_idle_old || fail "marunage-studio のチャットが動いています。終わってから実行してください"

  confirm "旧Mac（${FROM}）のサービスを止めて、このMacへ切り替えます。app.ele-studio.app と marunage.ele-studio.app は、最後の同期と起動が終わるまで止まります。続けますか？" ||
    fail "切り替えをやめました。旧Macはそのまま動いています"

  trap on_switch_error EXIT
  # The old Mac would report its services down as they stop; this Mac starts sending after the checks.
  say "旧Macのログと停止通知を止めます"
  stopped+=(processing-mac)
  logs_stop_old

  # Transcription can overlap: start here first, then retire the old Mac's copy.
  say "文字起こしをこのMacで起動し、旧Macを止めます"
  scribe_start
  stopped+=(scribe-bot)
  scribe_stop_old

  say "旧Macの launch-video-gen と marunage-studio を止めます"
  stopped+=(launch-video-gen)
  lvg_stop_old
  stopped+=(marunage-studio)
  marunage_stop_old

  say "最後の同期をします"
  lvg_sync_final
  marunage_sync_final

  say "このMacで起動します"
  lvg_start
  marunage_start
  say "公開URL（app・marunage）をこのMacへ向けます"
  lvg_switch_tunnel
  trap - EXIT

  say "確かめます"
  [ "$DRY_RUN" = 1 ] || sleep 20 # let the tunnel connect
  for s in "${SERVICES[@]}"; do
    [ "$DRY_RUN" = 1 ] && { note "（確認: $("${s}_name")）"; continue; }
    "${s}_verify" || ok=1
  done
  if [ $ok != 0 ]; then
    fail "確認に通らないものがあります。旧Macの登録はそのまま残しているので、上の表示を見て直すか、docs/processing-mac.md の「戻す」で旧Macに戻してください"
  fi
  say "ログと停止通知をこのMacから送り始めます"
  logs_install
  logs_verify || note "サービスは切り替わっています。ログと停止通知は、直してから processing-mac.sh deploy を実行し直してください。"
  # Only now keep the old Mac from starting them again at its next login.
  for s in "${SERVICES[@]}"; do "${s}_retire_old"; done
  logs_retire_old
  say "切り替えが終わりました"
  note "misc/processing-mac.conf の PREVIOUS_PROCESSING_MAC を空に戻して commit してください。"
  note "旧Macの後片付け（秘密の値や鍵を消す）は docs/processing-mac.md の手順で、数日たってから行います。"
  note "リモート接続の名前（Jump Desktop・agent-browser）を新しいMacへ向け直す一覧も docs/processing-mac.md にあります。"
}

# A dry run shows the whole plan even when something is missing.
checked() { check || [ "$DRY_RUN" = 1 ] || exit 1; }

case "$command" in
  status) status ;;
  check) check ;;
  prepare) checked && prepare ;;
  switch) checked && switch ;;
  deploy)
    if [ "$this_mac" != "$PROCESSING_MAC" ]; then
      if any_installed; then
        say "このMac（${this_mac}）は処理用Macではありませんが、常駐が残っています"
        status
        note "引き継ぎ済みなら、docs/processing-mac.md の「旧Macの後片付け」で消してください。"
      fi
      exit 0
    fi
    if all_installed; then
      say "処理用Mac: このMacで動いています"
      logs_install
      status
      logs_verify
      exit 0
    fi
    say "このMac（${this_mac}）は処理用Macです。まだ動いていないサービスを引き受けます"
    status
    check || fail "足りないものを揃えてから、もう一度 deploy.sh（または processing-mac.sh deploy）を実行してください"
    prepare
    switch
    ;;
  *) echo "使い方: processing-mac.sh status|check|prepare|switch|deploy [--from HOST] [--dry-run] [--yes]" >&2; exit 2 ;;
esac
