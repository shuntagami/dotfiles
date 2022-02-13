#!/usr/bin/env bash

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
  git log --oneline -n 10;
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

# Put together dull routine when hosting repo on github
init_repo () {
  git init && git commit --allow-empty -m "empty commit" && git add -A && git status && git commit -v
  echo "Type repository name: " && read name;
  echo "Type repository description: " && read description;
  gh repo create ${name} --description ${description} --public;
  git remote add origin git@github.com:shuntagami/${name}.git
  git push origin +HEAD;
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
pr_checkout () {
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

