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

# lint as filetype
function lint() {
  if [[ $# == 0 ]]; then
    cat <<EOF
$ lint foo.js  # eslint
$ lint bar.md  # textlint
$ lint bar.txt # textlint
EOF
    return
  fi

  FILEPATH=$1
  EXTNAME=${FILEPATH##*.}

  if [[ $EXTNAME == "js" ]]; then
    eslint -c $DOTFILES/misc/.eslintrc $1
    return
  fi

  if [[ $EXTNAME == "rb" ]]; then
    rubocop -c $DOTFILES/misc/.rubocop.yml $1
    return
  fi

  if [[ $EXTNAME == "md" || $EXTNAME == "txt" ]]; then
    textlint -c $DOTFILES/misc/.textlintrc $1
    return
  fi
}

# Create a new directory and enter it
function mkd() {
	mkdir -p "$@" && cd "$_";
}

# `o` with no arguments opens the current directory, otherwise opens the given
# location
function o() {
	if [ $# -eq 0 ]; then
		open .;
	else
		open "$@";
	fi;
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

# Start a PHP server from a directory, optionally specifying the port
# (Requires PHP 5.4.0+.)
function phpserver() {
	local port="${1:-4000}";
	local ip=$(ipconfig getifaddr en1);
	sleep 1 && open "http://${ip}:${port}/" &
	php -S "${ip}:${port}";
}

# Change current branch by PR number
pr-checkout () {
  gh pr list;
  echo "Type the number of PR to checkout: " && read number;
  gh pr checkout ${number};
}

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

pdfcompress() {
  local input="$1"
  local output="$2"

  if [[ -z "$input" ]]; then
    echo "Usage: pdfcompress input.pdf [output.pdf]"
    return 1
  fi

  if [[ -z "$output" ]]; then
    local basename="${input%.*}"
    local ext="${input##*.}"
    output="${basename}_compressed.${ext}"
  fi

  gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 \
     -dPDFSETTINGS=/ebook -dNOPAUSE -dQUIET -dBATCH \
     -sOutputFile="$output" "$input"
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
