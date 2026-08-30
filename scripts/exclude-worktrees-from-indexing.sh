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

# Spotlight: sudo 不要。任意ディレクトリでの効果は環境依存なので、確実を期すなら
# システム設定 → Spotlight → 検索プライバシー にも同じパスを登録すること。
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
