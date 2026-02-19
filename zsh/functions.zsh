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
    echo "使用方法: mov-to-mp4 <MOVファイル> [出力MP4]"
    return 1
  fi

  local input_file="$1"
  local output_file

  if [[ -n "$2" ]]; then
    output_file="$2"
  else
    output_file="${input_file%.*}.mp4"
  fi

  if [[ ! -f "$input_file" ]]; then
    echo "エラー: ファイル '$input_file' が見つかりません。"
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
