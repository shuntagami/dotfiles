#!/bin/bash

set -uo pipefail

# git worktree のディレクトリを Spotlight と Time Machine の対象から外す。
#
# なぜスクリプトなのか: どちらの除外もリテラルなパスしか受け付けず、ワイルドカードが無い。
# そして worktree の置き場所は2系統ある:
#
#   ~/.mulmoterminal/worktrees          MulmoTerminal 管理。全リポジトリ分が1箇所に集まる
#   <repo>/.claude/worktrees            Claude Code 管理。リポジトリの中に作られる
#
# 後者は Claude Code 側に置き場所を変える設定が無い (--worktree はセッション名を取るだけ)
# ため、リポジトリが増えるたびに新しいパスが生まれる。手で足し続ける代わりに、ここで
# 探して当てる。何度実行しても安全。
#
# 中身は git から再生成できるものと、post-checkout フックがコピーした .env だけで、
# .env の原本は本体チェックアウト側 (バックアップ対象のまま) に残る。

SEARCH_ROOTS=("${HOME}/projects" "${HOME}/dotfiles")
PRUNE=( -name node_modules -o -name .git -o -name dist -o -name build -o -name .next )

roots=()
[ -d "${HOME}/.mulmoterminal/worktrees" ] && roots+=("${HOME}/.mulmoterminal/worktrees")
while IFS= read -r dir; do
  [ -n "$dir" ] && roots+=("$dir")
done < <(find "${SEARCH_ROOTS[@]}" \( "${PRUNE[@]}" \) -prune -o -type d -path '*/.claude/worktrees' -print 2>/dev/null)

if [ ${#roots[@]} -eq 0 ]; then
  echo "worktree ディレクトリは見つかりませんでした。"
  exit 0
fi

echo "対象 ${#roots[@]} 件:"
for r in "${roots[@]}"; do echo "  ${r/#$HOME/~}"; done
echo ""

# Spotlight: sudo 不要。ディレクトリ単位の除外を CLI から行う手段はこれだけで、mdutil の
# オプションはすべてボリューム単位、プライバシー一覧の実体
# (/System/Volumes/Data/.Spotlight-V100/VolumeConfiguration.plist) は SIP 配下で書き換え不可。
#
# 効果はこのマシンで実測済み (macOS 26.6.2): マーカーを置いた 2 箇所は mdfind のヒットが 0、
# 除外していない apps は 3。索引自体はボリューム全体で有効なので、除外が効いている。
# GUI (システム設定 → Spotlight → 検索プライバシー) での追加は不要。
for r in "${roots[@]}"; do
  touch "$r/.metadata_never_index" 2>/dev/null \
    && echo "spotlight  ${r/#$HOME/~}" \
    || echo "spotlight  失敗: ${r/#$HOME/~}"
done
echo ""

# Time Machine: sudo が要る。-p はパス指定なので、worktree を作り直しても効き続ける。
for r in "${roots[@]}"; do
  if tmutil isexcluded "$r" 2>/dev/null | grep -q '\[Excluded\]'; then
    echo "timemachine  除外済み: ${r/#$HOME/~}"
  elif sudo tmutil addexclusion -p "$r" 2>/dev/null; then
    echo "timemachine  除外しました: ${r/#$HOME/~}"
  else
    echo "timemachine  失敗: ${r/#$HOME/~}"
  fi
done
