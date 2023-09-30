#!/bin/bash

set -e

# example Usage: ~/dotfiles/scripts/set_user_image.sh shun.tagami ~/dotfiles/images/earth.jpg
# https://apple.stackexchange.com/questions/117530/setting-account-picture-jpegphoto-with-dscl-in-terminal
# FIXME: does not change the user's picture on the System Preferences.
set_user_image() {
  local user="$1"
  local image="$2"

  dscl . delete /Users/"$user" JPEGPhoto
  dscl . delete /Users/"$user" Picture

  local tmp
  tmp="$(mktemp)"

  local encoded_image
  encoded_image="$(base64 -i "$image")"

  printf "0x0A 0x5C 0x3A 0x2C dsRecTypeStandard:Users 2 dsAttrTypeStandard:RecordName base64:dsAttrTypeStandard:JPEGPhoto\n%s:%s" "$user" "$encoded_image" > "$tmp"
  dsimport "$tmp" /Local/Default M
  rm "$tmp"
}

user="$1"
image="$2"

set_user_image "$user" "$image"
