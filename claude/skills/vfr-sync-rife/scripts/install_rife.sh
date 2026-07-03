#!/bin/bash
# rife-ncnn-vulkan のバイナリと rife-v4.6 モデルを bin/ に取得する（gitには含めない）
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$SKILL_DIR/bin"
URL="https://github.com/nihui/rife-ncnn-vulkan/releases/download/20221029/rife-ncnn-vulkan-20221029-macos.zip"

if [[ -x "$BIN_DIR/rife-ncnn-vulkan" && -d "$BIN_DIR/rife-v4.6" ]]; then
  echo "既にインストール済み: $BIN_DIR"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "ダウンロード中 (約440MB)..."
curl -sL -o "$TMP/rife.zip" "$URL"
unzip -q "$TMP/rife.zip" -d "$TMP"
mkdir -p "$BIN_DIR"
cp "$TMP"/rife-ncnn-vulkan-*/rife-ncnn-vulkan "$BIN_DIR/"
cp -R "$TMP"/rife-ncnn-vulkan-*/rife-v4.6 "$BIN_DIR/"
xattr -d com.apple.quarantine "$BIN_DIR/rife-ncnn-vulkan" 2>/dev/null || true
echo "完了: $BIN_DIR (バイナリ25MB + モデル10MB)"
