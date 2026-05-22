#!/bin/zsh

function addToPath {
  case ":$PATH:" in
    *":$1:"*) PATH="$1:${PATH/:$1/}" ;; # already there
    *) PATH="$1:$PATH";; # or PATH="$PATH:$1"
  esac
}

function curlh() {
  cat <<EOF
[show header]  --include
[ignore cert]  --insecure
[post]         -X POST -d 'aaa=bbb&ccc=ddd'
[post JSON]    -X POST -H "Content-Type: application/json" -d 'aaa=bbb&ccc=ddd'
EOF
}

# Show all the names (CNs and SANs) listed in the SSL certificate
# for a given domain
function certnames() {
	if [ -z "${1}" ]; then
		echo "ERROR: No domain specified.";
		return 1;
	fi;

	local domain="${1}";
	echo "Testing ${domain}…";
	echo ""; # newline

	local tmp=$(echo -e "GET / HTTP/1.0\nEOT" \
		| openssl s_client -connect "${domain}:443" -servername "${domain}" 2>&1);

	if [[ "${tmp}" = *"-----BEGIN CERTIFICATE-----"* ]]; then
		local certText=$(echo "${tmp}" \
			| openssl x509 -text -certopt "no_aux, no_header, no_issuer, no_pubkey, \
			no_serial, no_sigdump, no_signame, no_validity, no_version");
		echo "Common Name:";
		echo ""; # newline
		echo "${certText}" | grep "Subject:" | sed -e "s/^.*CN=//" | sed -e "s/\/emailAddress=.*//";
		echo ""; # newline
		echo "Subject Alternative Name(s):";
		echo ""; # newline
		echo "${certText}" | grep -A 1 "Subject Alternative Name:" \
			| sed -e "2s/DNS://g" -e "s/ //g" | tr "," "\n" | tail -n +2;
		return 0;
	else
		echo "ERROR: Certificate not found.";
		return 1;
	fi;
}

# execute ls after cd
function chpwd() { ls }

# Create a data URL from a file
function dataurl() {
	local mimeType=$(file -b --mime-type "$1");
	if [[ $mimeType == text/* ]]; then
		mimeType="${mimeType};charset=utf-8";
	fi
	echo "data:${mimeType};base64,$(openssl base64 -in "$1" | tr -d '\n')";
}

# show docker FAQ command
function dockerh() {
  cat <<EOF
[build]     $ docker build -t name/image:1.1 .
[run]       $ docker run -d -p 3000:80 name/image:2.0
[nsenter]   $ docker run --rm -v /usr/local/bin:/target jpetazzo/nsenter
[enter]     $ docker-enter PID
EOF
}

# show find FAQ command
function findh() {
  cat <<EOF
[name] $ find ./ -name *.md
[each] $ find ./ -name *.md | xargs -L 1 echo
EOF
}

# Use Git’s colored diff when available
hash git &>/dev/null;
if [ $? -eq 0 ]; then
	function diff() {
		git diff --no-index --color-words "$@";
	}
fi;

# combination of --fixup and --squash options to help later invocation of interactive rebase
function fixup() {
  git log --oneline -n 20;
  echo "Type the commit number to fixup: " && read number;
  git commit --fixup ${number} && git stash -u;
  git rebase -i --autosquash `git log --pretty=%P -n 1 ${number}`;
}
# Determine size of a file or total size of a directory
function fs() {
	if du -b /dev/null > /dev/null 2>&1; then
		local arg=-sbh;
	else
		local arg=-sh;
	fi
	if [[ -n "$@" ]]; then
		du $arg -- "$@";
	else
		du $arg .[^.]* ./*;
	fi;
}

# Compare original and gzipped file size
function gz() {
	local origsize=$(wc -c < "$1");
	local gzipsize=$(gzip -c "$1" | wc -c);
	local ratio=$(echo "$gzipsize * 100 / $origsize" | bc -l);
	printf "orig: %d bytes\n" "$origsize";
	printf "gzip: %d bytes (%2.2f%%)\n" "$gzipsize" "$ratio";
}

has () {
  type "$1" > /dev/null 2>&1
}

set-git-user-from-gh() {
  if ! has gh; then
    echo "gh command not found. Install GitHub CLI first."
    return 1
  fi

  if ! gh auth status >/dev/null 2>&1; then
    echo "Not logged in to GitHub CLI. Run: gh auth login"
    return 1
  fi

  local name email
  name="$(gh api user --jq '.name // .login')" || return 1
  email="$(gh api user --jq '.email // empty')" || return 1

  if [[ -z "$email" ]]; then
    email="$(gh api user --jq '"\(.id)+\(.login)@users.noreply.github.com"')" || return 1
  fi

  git config --global user.name "$name"
  git config --global user.email "$email"

  echo "Configured global Git identity:"
  echo "  user.name  = $(git config --global --get user.name)"
  echo "  user.email = $(git config --global --get user.email)"
}

alias git-user-sync='set-git-user-from-gh'

init-repo() {
  # ── Git 初期化・コミット
  git init || return 1
  git commit --allow-empty -m "Initial empty commit"
  git add -A
  git status
  git commit -v -m "first"

  # ── 入力
  print -n "Repository name: ";     read name
  print -n "Description: ";         read description

  # ── GitHub ユーザー名 & 所属 org 取得
  github_user=$(gh api user --jq .login)
  orgs=(${(f)"$(gh api user/memberships/orgs --jq '.[].organization.login')"})
  orgs+=("$github_user")

  # ── メニュー表示
  echo "Select account to host repository:"
  for (( i=1; i<=${#orgs}; i++ )); do
    echo "  $i) ${orgs[$i]}"
  done

  # ── 選択プロンプト（空入力→デフォルト）
  while true; do
    print -n "Enter number [1-${#orgs}] (default: ${github_user}): "; read choice
    if [[ -z $choice ]]; then
      selected=$github_user
      break
    elif (( choice >= 1 && choice <= ${#orgs} )); then
      selected=${orgs[choice]}
      break
    else
      echo "Invalid selection, try again."
    fi
  done

  # ── リポジトリ作成＆push
  gh repo create "${selected}/${name}" \
    --description "${description}" \
    --private \
    --confirm

  git remote add origin "https://github.com/${selected}/${name}.git"
  git push -u origin HEAD:main
}

# mpr: ブランチ名を指定して、あなた名義でPRを作成（元PRのタイトル/本文をコピー）
# 使い方:
#   mpr <ブランチ名> [baseブランチ] [新しいブランチ名]
# 例:
#   mpr feat/add-univapay-webhook
#   mpr feat/add-univapay-webhook main shun/univapay-mirror
mpr() (
  set -euo pipefail

  # ── 入力
  local src_branch="${1:-}"
  local base_branch="${2:-}"
  local new_branch="${3:-}"

  if [ -z "${src_branch}" ]; then
    echo "Usage: mpr <BRANCH_NAME> [base] [new_branch]" >&2
    return 1
  fi

  # ── 現在のリポジトリ・デフォルトブランチ
  local repo default_branch
  repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
  default_branch="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"

  # ── 元ブランチに紐づくPRのタイトル/本文/baseブランチ/URLを取得
  local pr_title pr_body pr_base pr_url
  pr_title="$(gh pr list --head "${src_branch}" --json title --jq '.[0].title // empty')"
  pr_body="$(gh pr list --head "${src_branch}" --json body --jq '.[0].body // empty')"
  pr_base="$(gh pr list --head "${src_branch}" --json baseRefName --jq '.[0].baseRefName // empty')"
  pr_url="$(gh pr list --head "${src_branch}" --json url --jq '.[0].url // empty')"

  # ── baseブランチ決定: 引数 > 元PRのbase > リポジトリのデフォルト
  if [ -z "${base_branch}" ]; then
    if [ -n "${pr_base}" ]; then
      base_branch="${pr_base}"
    else
      base_branch="${default_branch}"
    fi
  fi

  # ── 新規ブランチ名（未指定なら末尾に日時を付与して競合回避）
  if [ -z "${new_branch}" ]; then
    new_branch="shun/${src_branch##*/}-$(date +%Y%m%d-%H%M%S)"
  fi

  # ── 取得・ブランチ作成・push
  git fetch origin "${src_branch}" --depth=1
  git checkout -B "${new_branch}" "origin/${src_branch}"
  git push -u origin "${new_branch}"

  # ── PR作成（元PRのタイトル/本文をコピー、なければ --fill）
  if [ -n "${pr_title}" ]; then
    local new_body="${pr_body}

---
Original PR: ${pr_url}"
    gh pr create --base "${base_branch}" --head "${new_branch}" --title "${pr_title}" --body "${new_body}"
  else
    echo "Warning: No PR found for branch ${src_branch}, using --fill" >&2
    gh pr create --base "${base_branch}" --head "${new_branch}" --fill
  fi

  # ── 完了表示
  echo "Created PR from ${src_branch} as ${new_branch} (base=${base_branch}) on ${repo}"
)

# Create a new directory and enter it
function mkd() {
	mkdir -p "$@" && cd "$_";
}

# git w wrapper: run git-w, then enter the worktree it reports.
git() {
  if [[ "$1" != "w" ]]; then
    command git "$@"
    return $?
  fi

  local output rc workdir
  output=$(command git "$@" 2>&1)
  rc=$?

  echo "$output"
  if [[ $rc -ne 0 ]]; then
    return $rc
  fi

  workdir=$(echo "$output" | sed -n 's/^  cd //p')
  if [[ -n "$workdir" && -d "$workdir" ]]; then
    cd "$workdir"
  fi
}

# git worktree wrapper: create worktree + cd into it
# Usage: gw <branch-or-pr-number>
gw() {
  if [[ -z "$1" ]]; then
    echo 'usage: gw <branch-or-pr-number>'
    return 1
  fi

  local output rc
  output=$(git w "$@" 2>&1)
  rc=$?

  echo "$output"
  if [[ $rc -ne 0 ]]; then
    return $rc
  fi

  local workdir
  workdir=$(echo "$output" | sed -n 's/^  cd //p')

  if [[ -n "$workdir" && -d "$workdir" ]]; then
    cd "$workdir"
  fi
}

# Promote uncommitted work in the main worktree to a fresh worktree.
# Useful when you started Claude/coding directly in the main checkout and
# realized you want isolation. Stashes (incl. untracked), creates the
# worktree, pops the stash there, and copies the latest Claude session
# jsonl so `claude --resume` in the new worktree shows the conversation.
# Usage: gwp <branch-or-pr-number>
gwp() {
  if [[ -z "$1" ]]; then
    echo 'usage: gwp <branch-or-pr-number>'
    return 1
  fi

  local toplevel main_worktree
  toplevel=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo '[gwp] not inside a git repository'
    return 1
  }
  main_worktree=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')

  if [[ "$toplevel" != "$main_worktree" ]]; then
    echo "[gwp] must be run from the main worktree ($main_worktree)" >&2
    echo "[gwp] you are in: $toplevel" >&2
    return 1
  fi

  if [[ -z "$(git status --porcelain)" ]]; then
    echo "[gwp] no uncommitted changes to promote; use 'gw' instead" >&2
    return 1
  fi

  local source_dir="$toplevel"
  local stash_msg="gwp: promote to worktree '$1'"

  echo "[gwp] stashing uncommitted changes (including untracked)..."
  if ! git stash push -u -m "$stash_msg" >/dev/null; then
    echo '[gwp] stash failed' >&2
    return 1
  fi

  local output rc workdir
  output=$(git w "$@" 2>&1)
  rc=$?
  echo "$output"
  if [[ $rc -ne 0 ]]; then
    echo '[gwp] worktree creation failed; restoring stash' >&2
    git stash pop >/dev/null 2>&1
    return $rc
  fi
  workdir=$(echo "$output" | sed -n 's/^  cd //p')
  if [[ -z "$workdir" || ! -d "$workdir" ]]; then
    echo '[gwp] could not determine new worktree path; restoring stash' >&2
    git stash pop >/dev/null 2>&1
    return 1
  fi

  cd "$workdir" || return 1

  echo "[gwp] applying stash in $workdir..."
  if ! git stash pop; then
    echo '[gwp] stash pop had conflicts — resolve manually (stash entry preserved)' >&2
  fi

  # Copy the most recent Claude Code session jsonl to the new project dir so
  # `claude --resume` here can pick up the conversation. Encoding: `/` and `.`
  # in the cwd both become `-` in the project dir name.
  local encoded_source encoded_target src_proj dst_proj latest
  encoded_source=$(printf '%s' "$source_dir" | tr '/.' '--')
  encoded_target=$(printf '%s' "$workdir"   | tr '/.' '--')
  src_proj="$HOME/.claude/projects/$encoded_source"
  dst_proj="$HOME/.claude/projects/$encoded_target"

  if [[ -d "$src_proj" ]]; then
    latest=$(ls -t "$src_proj"/*.jsonl 2>/dev/null | head -1)
    if [[ -n "$latest" ]]; then
      mkdir -p "$dst_proj"
      cp "$latest" "$dst_proj/"
      echo "[gwp] copied Claude session: $(basename "$latest")"
      echo "[gwp] resume here with:  claude --resume"
    else
      echo "[gwp] no Claude session jsonl found in $src_proj"
    fi
  fi
}

# Companion to gw: delete a worktree + its branch. If invoked from inside a
# linked worktree, cd back to the main worktree first so `git wd`'s relative
# resolution is correct and `git worktree remove` cannot evict the caller.
# Usage: gwd <branch-or-pr-number>
gwd() {
  if [[ -z "$1" ]]; then
    echo 'usage: gwd <branch-or-pr-number>'
    return 1
  fi

  local toplevel main_worktree
  toplevel=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo '[gwd] not inside a git repository'
    return 1
  }
  main_worktree=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')

  if [[ -n "$main_worktree" && "$main_worktree" != "$toplevel" ]]; then
    echo "[gwd] cd to main worktree: $main_worktree"
    cd "$main_worktree" || return 1
  fi

  git wd "$@"
}

alias ggrep="git grep -A 5 -B 5"

function gngrep() {
  git grep -A "$1" -B "$1" "$2"
}

# Normalize `open` across Linux, macOS, and Windows.
# This is needed to make the `o` function (see below) cross-platform.
if [ ! $(uname -s) = 'Darwin' ]; then
	if grep -q Microsoft /proc/version; then
		# Ubuntu on Windows using the Linux subsystem
		alias open='explorer.exe';
	else
		alias open='xdg-open';
	fi
fi

# Create a .tar.gz archive, using `zopfli`, `pigz` or `gzip` for compression
function targz() {
	local tmpFile="${@%/}.tar";
	tar -cvf "${tmpFile}" --exclude=".DS_Store" "${@}" || return 1;

	size=$(
		stat -f"%z" "${tmpFile}" 2> /dev/null; # macOS `stat`
		stat -c"%s" "${tmpFile}" 2> /dev/null;  # GNU `stat`
	);

	local cmd="";
	if (( size < 52428800 )) && hash zopfli 2> /dev/null; then
		# the .tar file is smaller than 50 MB and Zopfli is available; use it
		cmd="zopfli";
	else
		if hash pigz 2> /dev/null; then
			cmd="pigz";
		else
			cmd="gzip";
		fi;
	fi;

	echo "Compressing .tar ($((size / 1000)) kB) using \`${cmd}\`…";
	"${cmd}" -v "${tmpFile}" || return 1;
	[ -f "${tmpFile}" ] && rm "${tmpFile}";

	zippedSize=$(
		stat -f"%z" "${tmpFile}.gz" 2> /dev/null; # macOS `stat`
		stat -c"%s" "${tmpFile}.gz" 2> /dev/null; # GNU `stat`
	);

	echo "${tmpFile}.gz ($((zippedSize / 1000)) kB) created successfully.";
}

# https://gist.github.com/1321338
function extract {
  echo Extracting $1 ...
  if [ -f $1 ] ; then
    case $1 in
      *.tar.bz2)   tar xjf $1  ;;
      *.tar.gz)    tar xzf $1  ;;
      *.bz2)       bunzip2 $1  ;;
      *.rar)       rar x $1    ;;
      *.gz)        gunzip $1   ;;
      *.tar)       tar xf $1   ;;
      *.tbz2)      tar xjf $1  ;;
      *.tgz)       tar xzf $1  ;;
      *.zip)       unzip $1   ;;
      *.Z)         uncompress $1  ;;
      *.7z)        7z x $1  ;;
      *)        echo "'$1' cannot be extracted via extract()" ;;
    esac
  else
      echo "'$1' is not a valid file"
  fi
}

function generate-gif() {
    local input_file=$1
    local output_file="${input_file%.*}.gif"
    ffmpeg -i "$input_file" -r 10 "$output_file"
    echo "GIF generated: $output_file"
}

video-to-mp3() {
  if [[ $# -eq 0 ]]; then
    echo "使用方法: video-to-mp3 <動画ファイル>"
    return 1
  fi

  local input_file="$1"
  local output_file="${input_file%.*}.mp3"

  if [[ ! -f "$input_file" ]]; then
    echo "エラー: ファイル '$input_file' が見つかりません。"
    return 1
  fi

  echo "変換中: $input_file → $output_file"
  ffmpeg -i "$input_file" -vn -ab 128k "$output_file"

  if [[ $? -eq 0 ]]; then
    echo "変換完了: $output_file"
  else
    echo "変換失敗"
  fi
}

mov-to-mp4() {
  if [[ $# -eq 0 ]]; then
    echo "使用方法: mov-to-mp4 <動画ファイル> [出力MP4]"
    return 1
  fi

  local input_file="$1"
  local output_file

  if [[ -n "$2" ]]; then
    output_file="$2"
  elif [[ "${input_file:e:l}" == "mp4" ]]; then
    output_file="${input_file%.*}_compressed.mp4"
  else
    output_file="${input_file%.*}.mp4"
  fi

  if [[ ! -f "$input_file" ]]; then
    echo "エラー: ファイル '$input_file' が見つかりません。"
    return 1
  fi

  if [[ "$input_file" == "$output_file" ]]; then
    echo "エラー: 入力と出力に同じファイルは指定できません。別の出力名を指定してください。"
    return 1
  fi

  echo "変換中: $input_file → $output_file"
  ffmpeg -i "$input_file" \
    -c:v libx264 -crf 28 -preset slow -pix_fmt yuv420p \
    -c:a aac -b:a 128k -ac 2 -movflags +faststart \
    "$output_file"

  if [[ $? -eq 0 ]]; then
    echo "変換完了: $output_file"
  else
    echo "変換失敗"
  fi
}

mp4-compress() {
  if [[ $# -eq 0 ]]; then
    echo "使用方法: mp4-compress <MP4ファイル> [出力MP4]"
    return 1
  fi

  local input_file="$1"
  local output_file="${2:-${input_file%.*}_compressed.mp4}"

  mov-to-mp4 "$input_file" "$output_file"
}

_llm_video_compress_usage() {
  cat <<'EOF'
使用方法: llm-video-compress [options] <動画ファイル> [出力MP4]

LLM投入向けに、動画のサイズと情報量を落とした MP4 を作成します。

例:
  llm-video-compress input.mp4
  llm-video-compress --cheap input.mp4
  llm-video-compress --fps 0.5 --height 480 input.mp4
  llm-video-compress --no-audio input.mp4
  llm-video-compress --start 00:10:00 --end 00:20:00 input.mp4

Options:
  --profile <name>       balanced | cheap | detail (default: balanced)
  --cheap                --profile cheap と同じ
  --detail               --profile detail と同じ
  --fps <number>         出力動画の FPS。balanced=1, cheap=0.5, detail=2
  --height <px>          最大高さ。balanced=720, cheap=480, detail=1080
  --crf <number>         x264 CRF。balanced=30, cheap=32, detail=28
  --preset <name>        x264 preset (default: medium)
  --audio-bitrate <rate> AAC 音声ビットレート。balanced=64k, cheap=48k, detail=96k
  --no-audio             音声を削除する
  --start <time>         開始位置。例: 75, 01:15, 00:01:15
  --end <time>           終了位置。--duration とは併用不可
  --duration <time>      切り出す長さ。--end とは併用不可
  --dry-run              実行する ffmpeg コマンドだけ表示
  -h, --help             ヘルプを表示

注意:
  Gemini でトークン消費を本当に削るには、API 側でも videoMetadata.fps と
  media_resolution=LOW/MEDIUM を指定してください。このコマンドはアップロード
  する実ファイルを軽くします。
EOF
}

_llm_video_time_to_seconds() {
  awk -v t="$1" '
    BEGIN {
      if (t !~ /^[0-9]+([.][0-9]+)?(:[0-9]+([.][0-9]+)?){0,2}$/) {
        exit 1
      }
      n = split(t, a, ":")
      if (n == 1) {
        s = a[1]
      } else if (n == 2) {
        s = a[1] * 60 + a[2]
      } else if (n == 3) {
        s = a[1] * 3600 + a[2] * 60 + a[3]
      } else {
        exit 1
      }
      if (s < 0) {
        exit 1
      }
      printf "%.3f", s
    }
  '
}

_llm_video_human_bytes() {
  awk -v bytes="$1" '
    BEGIN {
      split("B KiB MiB GiB TiB", unit, " ")
      size = bytes + 0
      idx = 1
      while (size >= 1024 && idx < 5) {
        size /= 1024
        idx++
      }
      if (idx == 1) {
        printf "%d %s", size, unit[idx]
      } else {
        printf "%.1f %s", size, unit[idx]
      }
    }
  '
}

_llm_video_file_bytes() {
  stat -f%z "$1" 2>/dev/null || stat -c%s "$1" 2>/dev/null
}

llm-video-compress() {
  emulate -L zsh
  setopt LOCAL_OPTIONS NO_GLOB

  local profile="balanced"
  local fps="" height="" crf="" preset="medium" audio_bitrate=""
  local keep_audio=1 dry_run=0
  local start="" end="" duration=""
  local -a positional

  while (( $# > 0 )); do
    case "$1" in
      -h|--help)
        _llm_video_compress_usage
        return 0
        ;;
      --profile)
        shift
        if [[ -z "$1" ]]; then
          echo "エラー: --profile の値が必要です。" >&2
          return 2
        fi
        profile="$1"
        ;;
      --profile=*)
        profile="${1#*=}"
        ;;
      --cheap)
        profile="cheap"
        ;;
      --detail)
        profile="detail"
        ;;
      --fps)
        shift
        fps="$1"
        ;;
      --fps=*)
        fps="${1#*=}"
        ;;
      --height)
        shift
        height="$1"
        ;;
      --height=*)
        height="${1#*=}"
        ;;
      --crf)
        shift
        crf="$1"
        ;;
      --crf=*)
        crf="${1#*=}"
        ;;
      --preset)
        shift
        preset="$1"
        ;;
      --preset=*)
        preset="${1#*=}"
        ;;
      --audio-bitrate)
        shift
        audio_bitrate="$1"
        ;;
      --audio-bitrate=*)
        audio_bitrate="${1#*=}"
        ;;
      --no-audio)
        keep_audio=0
        ;;
      --start)
        shift
        start="$1"
        ;;
      --start=*)
        start="${1#*=}"
        ;;
      --end)
        shift
        end="$1"
        ;;
      --end=*)
        end="${1#*=}"
        ;;
      --duration)
        shift
        duration="$1"
        ;;
      --duration=*)
        duration="${1#*=}"
        ;;
      --dry-run)
        dry_run=1
        ;;
      --)
        shift
        positional+=("$@")
        break
        ;;
      -*)
        echo "エラー: 不明なオプションです: $1" >&2
        _llm_video_compress_usage >&2
        return 2
        ;;
      *)
        positional+=("$1")
        ;;
    esac
    shift
  done

  if (( ${#positional[@]} < 1 || ${#positional[@]} > 2 )); then
    _llm_video_compress_usage >&2
    return 2
  fi

  case "$profile" in
    balanced)
      [[ -z "$fps" ]] && fps="1"
      [[ -z "$height" ]] && height="720"
      [[ -z "$crf" ]] && crf="30"
      [[ -z "$audio_bitrate" ]] && audio_bitrate="64k"
      ;;
    cheap)
      [[ -z "$fps" ]] && fps="0.5"
      [[ -z "$height" ]] && height="480"
      [[ -z "$crf" ]] && crf="32"
      [[ -z "$audio_bitrate" ]] && audio_bitrate="48k"
      ;;
    detail)
      [[ -z "$fps" ]] && fps="2"
      [[ -z "$height" ]] && height="1080"
      [[ -z "$crf" ]] && crf="28"
      [[ -z "$audio_bitrate" ]] && audio_bitrate="96k"
      ;;
    *)
      echo "エラー: --profile は balanced, cheap, detail のいずれかを指定してください。" >&2
      return 2
      ;;
  esac

  if [[ -n "$end" && -n "$duration" ]]; then
    echo "エラー: --end と --duration は併用できません。" >&2
    return 2
  fi

  if ! awk -v v="$fps" 'BEGIN { exit !((v ~ /^([0-9]+([.][0-9]+)?|[.][0-9]+)$/) && v + 0 > 0) }'; then
    echo "エラー: --fps には 0 より大きい数値を指定してください。" >&2
    return 2
  fi

  if ! awk -v v="$height" 'BEGIN { exit !(v ~ /^[0-9]+$/ && v + 0 > 0) }'; then
    echo "エラー: --height には 0 より大きい整数を指定してください。" >&2
    return 2
  fi

  if ! awk -v v="$crf" 'BEGIN { exit !(v ~ /^[0-9]+$/ && v >= 0 && v <= 51) }'; then
    echo "エラー: --crf は 0 から 51 の整数を指定してください。" >&2
    return 2
  fi

  local input_file="${positional[1]}"
  local output_file="${positional[2]:-${input_file%.*}_llm.mp4}"

  if [[ ! -f "$input_file" ]]; then
    echo "エラー: ファイル '$input_file' が見つかりません。" >&2
    return 1
  fi

  if [[ "$input_file" == "$output_file" ]]; then
    echo "エラー: 入力ファイルと出力ファイルが同じです。" >&2
    return 2
  fi

  if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "エラー: ffmpeg が見つかりません。" >&2
    return 127
  fi

  if ! command -v ffprobe >/dev/null 2>&1; then
    echo "エラー: ffprobe が見つかりません。" >&2
    return 127
  fi

  local start_sec="0" end_sec="" duration_sec=""
  if [[ -n "$start" ]]; then
    if ! start_sec="$(_llm_video_time_to_seconds "$start")"; then
      echo "エラー: --start の形式が不正です: $start" >&2
      return 2
    fi
  fi
  if [[ -n "$end" ]]; then
    if ! end_sec="$(_llm_video_time_to_seconds "$end")"; then
      echo "エラー: --end の形式が不正です: $end" >&2
      return 2
    fi
  fi
  if [[ -n "$duration" ]]; then
    if ! duration_sec="$(_llm_video_time_to_seconds "$duration")"; then
      echo "エラー: --duration の形式が不正です: $duration" >&2
      return 2
    fi
  fi

  if [[ -n "$end_sec" ]]; then
    if ! awk -v s="$start_sec" -v e="$end_sec" 'BEGIN { exit !(e > s) }'; then
      echo "エラー: --end は --start より後の時刻を指定してください。" >&2
      return 2
    fi
  fi

  local source_height
  source_height="$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 -- "$input_file" 2>/dev/null | head -n 1)"

  local -a vf_parts trim_args cmd
  vf_parts=("fps=${fps}")
  if [[ -z "$source_height" || "$source_height" != <-> || "$source_height" -gt "$height" ]]; then
    vf_parts+=("scale=-2:${height}")
  fi
  vf_parts+=("setsar=1")
  local vf="${(j:,:)vf_parts}"

  trim_args=()
  [[ -n "$start" ]] && trim_args+=(-ss "$start")
  [[ -n "$end" ]] && trim_args+=(-to "$end")
  [[ -n "$duration" ]] && trim_args+=(-t "$duration")

  cmd=(ffmpeg -hide_banner -y -i "$input_file")
  cmd+=("${trim_args[@]}")
  cmd+=(-map 0:v:0)
  if (( keep_audio )); then
    cmd+=(-map "0:a?")
  else
    cmd+=(-an)
  fi
  cmd+=(-vf "$vf" -c:v libx264 -crf "$crf" -preset "$preset" -pix_fmt yuv420p)
  if (( keep_audio )); then
    cmd+=(-c:a aac -b:a "$audio_bitrate" -ac 1)
  fi
  cmd+=(-sn -dn -movflags +faststart "$output_file")

  if (( dry_run )); then
    printf '%q ' "${cmd[@]}"
    printf '\n'
    return 0
  fi

  local audio_desc="音声あり ${audio_bitrate}/mono"
  (( keep_audio )) || audio_desc="音声なし"

  echo "変換中: $input_file → $output_file"
  echo "設定: profile=${profile}, fps=${fps}, max-height=${height}, crf=${crf}, ${audio_desc}"
  if [[ -n "$start" || -n "$end" || -n "$duration" ]]; then
    echo "範囲: start=${start:-0}, end=${end:-未指定}, duration=${duration:-未指定}"
  fi

  if "${cmd[@]}"; then
    echo "変換完了: $output_file"

    local input_bytes output_bytes
    input_bytes="$(_llm_video_file_bytes "$input_file")"
    output_bytes="$(_llm_video_file_bytes "$output_file")"
    if [[ -n "$input_bytes" && -n "$output_bytes" ]]; then
      echo "サイズ: $(_llm_video_human_bytes "$input_bytes") → $(_llm_video_human_bytes "$output_bytes")"
    fi

    local original_duration clip_duration
    original_duration="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 -- "$input_file" 2>/dev/null)"
    if [[ -n "$duration_sec" ]]; then
      clip_duration="$duration_sec"
    elif [[ -n "$end_sec" ]]; then
      clip_duration="$(awk -v s="$start_sec" -v e="$end_sec" 'BEGIN { printf "%.3f", e - s }')"
    elif [[ -n "$original_duration" ]]; then
      clip_duration="$(awk -v o="$original_duration" -v s="$start_sec" 'BEGIN { d = o - s; if (d < 0) d = 0; printf "%.3f", d }')"
    fi

    if [[ -n "$clip_duration" ]]; then
      local low_tokens high_tokens
      low_tokens="$(awk -v d="$clip_duration" -v f="$fps" -v a="$keep_audio" 'BEGIN { printf "%d", d * f * 70 + (a ? d * 32 : 0) }')"
      high_tokens="$(awk -v d="$clip_duration" -v f="$fps" -v a="$keep_audio" 'BEGIN { printf "%d", d * f * 280 + (a ? d * 32 : 0) }')"
      echo "Gemini概算: videoMetadata.fps=${fps} 指定時、LOW/MEDIUM 約 ${low_tokens} tokens, HIGH 約 ${high_tokens} tokens"
      echo "注意: Gemini側で fps/media_resolution を指定しないと、出力FPSだけではトークン削減に反映されない場合があります。"
    fi
  else
    echo "変換失敗" >&2
    return 1
  fi
}

pdf2img() {
  local input="$1"
  if [[ -z "$input" ]]; then
    echo "Usage: pdf2img <file.pdf>"
    return 1
  fi

  local base="${input:t:r}" # ファイル名から拡張子を除いた部分
  mkdir -p "$base"
  pdftoppm -png "$input" "$base/$base"
}

# JSONの文字列抽出（引数があればファイル、なければクリップボード）
function jread() {
  if [ -p /dev/stdin ]; then
    # パイプ入力がある場合 (echo "{}" | jread)
    cat - | jq -r '.. | select(type == "string")'
  elif [ -z "$1" ]; then
    # 引数がない場合 (クリップボード)
    pbpaste | jq -r '.. | select(type == "string")'
  else
    # 引数がある場合 (ファイル読み込み)
    cat "$1" | jq -r '.. | select(type == "string")'
  fi
}
