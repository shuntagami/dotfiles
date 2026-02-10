#!/bin/zsh

# Easier navigation: .., ..., ...., ....., ~ and -
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias .....="cd ../../../.."

alias c="clear"

# Detect which `ls` flavor is in use
if ls --color > /dev/null 2>&1; then # GNU `ls`
	colorflag="--color"
	export LS_COLORS='no=00:fi=00:di=01;31:ln=01;36:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:ex=01;32:*.tar=01;31:*.tgz=01;31:*.arj=01;31:*.taz=01;31:*.lzh=01;31:*.zip=01;31:*.z=01;31:*.Z=01;31:*.gz=01;31:*.bz2=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:*.jpg=01;35:*.jpeg=01;35:*.gif=01;35:*.bmp=01;35:*.pbm=01;35:*.pgm=01;35:*.ppm=01;35:*.tga=01;35:*.xbm=01;35:*.xpm=01;35:*.tif=01;35:*.tiff=01;35:*.png=01;35:*.mov=01;35:*.mpg=01;35:*.mpeg=01;35:*.avi=01;35:*.fli=01;35:*.gl=01;35:*.dl=01;35:*.xcf=01;35:*.xwd=01;35:*.ogg=01;35:*.mp3=01;35:*.wav=01;35:'
else # macOS `ls`
	colorflag="-G"
	export LSCOLORS='BxBxhxDxfxhxhxhxhxcxcx'
fi

# List all files colorized in long format
alias l="ls -lF ${colorflag}"
# List all files colorized in long format, excluding . and ..
alias la="ls -lAF ${colorflag}"
# List only directories
alias lsd="ls -lF ${colorflag} | grep --color=never '^d'"
# Always use color output for `ls`
alias ls="command ls ${colorflag}"

# Always enable colored `grep` output
# Note: `GREP_OPTIONS="--color=auto"` is deprecated, hence the alias usage.
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# Show active network interfaces
alias ifactive="ifconfig | pcregrep -M -o '^[^\t:]+:([^\n]|\n\t)*status: active'"

# Clean up LaunchServices to remove duplicates in the “Open With” menu
alias lscleanup="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user && killall Finder"

# Intuitive map function
# For example, to list all directories that contain a certain file:
# find . -name .gitattributes | map dirname
alias map="xargs -n1"

# Print each PATH entry on a separate line
alias path='echo -e ${PATH//:/\\n}'

alias port-in-use='lsof -i -P -n | grep LISTEN'

# Reload the shell (i.e. invoke as a login shell)
alias relogin="exec ${SHELL} -l"

# URL-encode strings
alias urlencode='python3 -c "import sys, urllib as ul; print ul.quote_plus(sys.argv[1]);"'

# Get week number
alias week='date +%V'

# aws-vault
alias exec-admin='aws-vault exec admin'
alias exec-my='aws-vault exec my'
alias exec-dev='aws-vault exec dev'
alias exec-prod='aws-vault exec prod'

alias k='kubectl'

# git grep
git-grep-count() {
  git grep -c "$1" | awk -F':' '{sum += $2} END {print sum}'
}
alias ggc="git-grep-count"

alias cc="claude"

# --- ffmpeg 区切りカット用 zsh 関数 ---
# 使い方:
#   cut <input> start..end     # 指定区間を抽出（_cut）
#   cut <input> start..        # start 以降を抽出（_after）
#   cut <input> ..end          # 先頭〜end を抽出（_before）
#   cut <input> start~~end     # 指定区間を削除し前後を結合（_removed）
#
# 仕様:
# - mp3/mp4 は -c copy（高速）
# - wav は -c:a pcm_s16le で安全に再エンコード
# - それ以外の拡張子は基本 -c copy を試行（失敗時はエラーメッセージ）
# - 出力ファイル名は元の拡張子を保持し、ベース名に _cut/_after/_before/_removed を付与
# - 一時ファイルは mktemp -d で作成し、処理後に自動削除
# - zsh の glob 展開を抑止（呼び出し時：alias、関数内：NO_GLOB）
#
# 注意:
# - 同名の POSIX `cut` コマンドと名前が衝突します。必要なら `\cut` で元コマンドを呼べます。

cut() {
  emulate -L zsh
  setopt LOCAL_OPTIONS NO_GLOB

  # ---- ヘルパ（エラー出力） ----
  _err() { print -u2 -- "$@"; }

  # ---- 依存確認 ----
  if ! command -v ffmpeg >/dev/null 2>&1; then
    _err "エラー: ffmpeg が見つかりません。インストール後に再実行してください。"
    return 127
  fi

  # ---- 引数チェック ----
  if (( $# != 2 )); then
    _err "使い方: cut <input> <range>"
    _err "  例) cut movie.mp4 00:30..01:45"
    _err "      cut audio.wav 01:00.."
    _err "      cut talk.mp3 ..05:00"
    _err "      cut clip.mp4 00:30:00~~01:30:00"
    return 2
  fi

  local input="$1"
  local raw_range="$2"

  if [[ ! -f "$input" ]]; then
    _err "エラー: 入力ファイルが見つかりません: $input"
    return 2
  fi

  # パス要素（zsh 独自の修飾子を使用）
  local dir="${input:h}"
  local stem="${input:t:r}"
  local ext="${input:e:l}"

  if [[ -z "$ext" ]]; then
    _err "エラー: 入力ファイルに拡張子がありません。"
    return 2
  fi

  # ---- range パース（空白除去してから判定）----
  local range="${raw_range//[[:space:]]/}"
  local start="" end="" tag=""
  if [[ "$range" == *"~~"* ]]; then
    # 削除＆結合
    start="${range%%~~*}"
    end="${range##*~~}"
    tag="_removed"
    if [[ -z "$start" || -z "$end" ]]; then
      _err "エラー: 'start~~end' 形式は start と end の両方が必要です。例: 00:30:00~~01:30:00"
      return 2
    fi
  elif [[ "$range" == *".."* ]]; then
    start="${range%%..*}"
    end="${range##*..}"
    if [[ -n "$start" && -n "$end" ]]; then
      tag="_cut"
    elif [[ -n "$start" && -z "$end" ]]; then
      tag="_after"
    elif [[ -z "$start" && -n "$end" ]]; then
      tag="_before"
    else
      _err "エラー: '..' の前後が空です。例: 00:10.., ..05:00, 00:10..00:20"
      return 2
    fi
  else
    _err "エラー: 範囲指定は '..' または '~~' を含む必要があります。"
    return 2
  fi

  # ---- 出力パス ----
  local out="${dir}/${stem}${tag}.${ext}"

  # ---- 一時ディレクトリ & クリーンアップ ----
  local tmpdir
  if ! tmpdir="$(mktemp -d)"; then
    _err "エラー: 一時ディレクトリの作成に失敗しました。"
    return 1
  fi
  # RETURN で関数終了時にもクリーンアップ
  trap 'rm -rf -- "$tmpdir"' INT TERM EXIT RETURN

  # ---- ストリーム情報（動画有無 判定は任意）----
  local has_video=0
  if command -v ffprobe >/dev/null 2>&1; then
    local vkind
    vkind="$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_type -of csv=p=0 -- "$input" 2>/dev/null)"
    [[ "$vkind" == "video" ]] && has_video=1
  fi

  # ---- コーデック方針 ----
  #   wav       : 常に再エンコード（pcm_s16le）
  #   mp3 / mp4 : -c copy（高速）
  #   その他    : まず -c copy を試行（同一ファイル由来なら基本OK）
  local -a seg_codecs concat_codecs
  case "$ext" in
    wav)
      seg_codecs=(-c:a pcm_s16le)
      concat_codecs=(-c:a pcm_s16le)
      ;;
    mp3)
      seg_codecs=(-c copy)
      concat_codecs=(-c copy)
      ;;
    mp4)
      seg_codecs=(-c copy)
      concat_codecs=(-c copy -movflags +faststart)
      ;;
    *)
      seg_codecs=(-c copy)
      concat_codecs=(-c copy)
      ;;
  esac

  # ---- 実処理 ----
  # ffmpeg は -loglevel error で静かに、失敗時にわかりやすく返す
  local ff() { ffmpeg -hide_banner -y -loglevel error "$@"; }

  case "$tag" in
    _cut)
      # start..end 抽出
      # 精度重視のため -i の後に -ss/-to を付与
      if ! ff -i "$input" -ss "$start" -to "$end" "${seg_codecs[@]}" "$out"; then
        _err "エラー: 抽出に失敗しました（$start..$end）。入力と範囲を確認してください。"
        return 1
      fi
      ;;

    _before)
      # ..end 抽出
      if ! ff -i "$input" -to "$end" "${seg_codecs[@]}" "$out"; then
        _err "エラー: 抽出に失敗しました（..$end）。"
        return 1
      fi
      ;;

    _after)
      # start.. 抽出
      if ! ff -i "$input" -ss "$start" "${seg_codecs[@]}" "$out"; then
        _err "エラー: 抽出に失敗しました（$start..）。"
        return 1
      fi
      ;;

    _removed)
      # start~~end を削除し、前後を結合
      local seg1="${tmpdir}/part1.${ext}"
      local seg2="${tmpdir}/part2.${ext}"

      # 先頭〜start
      if ! ff -i "$input" -to "$start" "${seg_codecs[@]}" "$seg1"; then
        _err "エラー: 前半セグメントの作成に失敗しました（..$start）。"
        return 1
      fi
      # end〜末尾
      if ! ff -i "$input" -ss "$end" "${seg_codecs[@]}" "$seg2"; then
        _err "エラー: 後半セグメントの作成に失敗しました（$end..）。"
        return 1
      fi

      if [[ "$ext" == "wav" ]]; then
        # WAV は demuxer concat の互換性問題を避け、フィルタで連結（再エンコード）
        if ! ff -i "$seg1" -i "$seg2" -filter_complex "[0:a][1:a]concat=n=2:v=0:a=1" "${concat_codecs[@]}" "$out"; then
          _err "エラー: WAV の結合に失敗しました。"
          return 1
        fi
      else
        # demuxer concat（同一ファイル由来なのでパラメータ一致）
        local list="${tmpdir}/list.txt"
        printf "file '%s'\nfile '%s'\n" "$seg1" "$seg2" >| "$list"
        if ! ff -f concat -safe 0 -i "$list" "${concat_codecs[@]}" "$out"; then
          _err "エラー: 結合に失敗しました（concat demuxer）。"
          _err "ヒント: コンテナ互換性の問題の可能性があります。別の拡張子や再エンコードでの出力を検討してください。"
          return 1
        fi
      fi
      ;;
  esac

  print -P "%F{green}完了:%f ${out}"
}

# 呼び出し時点での glob 展開を抑止するため、エイリアスで noglob を付与
# （関数内でも NO_GLOB を設定して二重で安全対策）
alias cut='noglob cut'

unzipall() {
  if [ "$#" -eq 0 ]; then
    echo "Usage: unzipall <zip-file> [more.zip...]"
    return 1
  fi

  for zipfile in "$@"; do
    if [ ! -f "$zipfile" ]; then
      echo "File not found: $zipfile"
      continue
    fi

    echo "Extracting: $zipfile"

    # 1. 最初のzip解凍（文字化け対策）
    LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 unzip -oq "$zipfile" 2>/dev/null || \
    ditto -x -k "$zipfile" .

    rm -f "$zipfile"

    # 2. 再帰解凍（zipがなくなるまで1個ずつ処理）
    while true; do
      nextzip=$(find . -type f -name "*.zip" | head -n 1)
      [ -z "$nextzip" ] && break

      echo "Extracting nested: $nextzip"

      LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 unzip -oq "$nextzip" 2>/dev/null || \
      ditto -x -k "$nextzip" .

      rm -f "$nextzip"
    done
  done
}
