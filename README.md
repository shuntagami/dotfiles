# dotfiles
Simple dotfiles includes<br>
.zshrc with <a href="https://github.com/sorin-ionescu/prezto">Prezto</a>,<br> 
.vimrc with <a href="https://github.com/Shougo/dein.vim">dein.vim</a>,<br>
setting of macOS, iTerm, Homebrew.<br>
It's possible to set up environment for creating Rails app 


## Warning
 If you want to give these dotfiles a try, you should first fork this repository, review the code, and remove things you don’t want or need. Don’t blindly use my settings unless you know what that entails. Use at your own risk!

## How to use
Firstly, maku sure that <b>Command line tools for Xcode</b> is installed on your mac. If not, run next command.

```
$ xcode-select --install
```

Clone this repo.
```
$ git clone https://github.com/shuntagami/dotfiles.git && cd dotfiles
```

Setup homebrew, and install rbenv, nodenv, tfenv by anyenv.
```
$ chmod +x homebrew_setup.sh
$ ./homebrew_setup.sh
$ exec $SHELL -l
```

Switch to iTerm2, change the setting. (Preferences(⌘,) → Preferences → check <b>Load preferences from a custom folder or URL</b>, change it to <b>/Users/Username/dotfiles</b>)

Setup macOS.
```
$ chmod +x macos.sh
$ ./macos.sh
```

Setup zsh.
```
$ chmod +x zsh_setup.sh
$ ./zsh_setup.sh
```

Setup anyenv.(install latest version of ruby, Node.js, and other plugins)
```
$ chmod +x anyenv_setup.sh
$ ./anyenv_setup.sh
```

## Image of iTerm
![sample](https://user-images.githubusercontent.com/69618840/103264511-44306b00-49ee-11eb-8e5e-4398c46d2993.png)

## Image of vim
![sample](https://user-images.githubusercontent.com/69618840/103265226-6dea9180-49f0-11eb-8894-83dc523f6803.png)
