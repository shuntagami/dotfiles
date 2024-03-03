#!/usr/bin/env node

import { getWallpaper, setWallpaper } from "wallpaper";
import { homedir } from "os";

await setWallpaper(`${homedir()}/dotfiles/static/wallpaper-black.jpg`);

console.log(await getWallpaper());
