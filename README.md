# dotfiles

MacOS / Ubuntu dotfiles.

With this dotfiles, it

- allows you to setup dev environment in **just 1 command** 🚀.
- would work **both on MacOS and Ubuntu**✨.

## Requirement

- Ubuntu(>=20.04)(for Ubuntu user.)
- XCode Command Line Tools(for Mac user. if you don't have, get by runnning following command.)

```bash
$ xcode-select --install
```

## How to use

```bash
# 1. Download dotfiles
$ bash -c "$(curl -fsSL raw.githubusercontent.com/shuntagami/dotfiles/main/scripts/install-dotfiles.sh)"

# 2. Run setup (packages, symlinks, macOS settings, VSCode — all in one)
$ ~/dotfiles/scripts/setup.sh
```

### Run individual steps manually

You can also run each step separately if needed.

```bash
$ ~/dotfiles/scripts/install-packages.sh  # Install Homebrew, anyenv, etc.
$ ~/dotfiles/scripts/deploy.sh            # Symlink dotfiles
$ ~/dotfiles/scripts/macos.sh             # Configure macOS defaults
$ ~/dotfiles/vscode/setup.sh              # Set up VSCode/Cursor
```

### iTerm2

_(Preferences(⌘,)_ → _Preferences_ → check <b>Load preferences from a custom folder or URL</b>, change it to <b>/Users/Username/dotfiles/misc</b>)

![sample](https://user-images.githubusercontent.com/69618840/153607360-dc173d13-c551-4f2c-9ce5-02cbfeb0a120.png)

## Keywords

- [Zsh](https://www.zsh.org/)([sorin-ionescu/prezto](https://github.com/sorin-ionescu/prezto))
- [Vim](https://github.com/vim/vim)([Shugo/dein.vim](https://github.com/Shougo/dein.vim))
- [Homebrew](https://github.com/Homebrew/brew), [Debian/apt](https://github.com/Debian/apt)
- [anyenv](https://github.com/anyenv/anyenv)
- [iTerm2](https://github.com/gnachman/iTerm2)
- [Visual Studio Code](https://github.com/microsoft/vscode)
- [btop](https://github.com/aristocratos/btop)
