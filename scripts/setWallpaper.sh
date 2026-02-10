#!/bin/bash
WALLPAPER="$HOME/dotfiles/static/wallpaper-black.jpg"
osascript -e "tell application \"Finder\" to set desktop picture to POSIX file \"$WALLPAPER\""
echo "Wallpaper set to: $WALLPAPER"
