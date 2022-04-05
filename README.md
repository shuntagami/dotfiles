# dotfiles

MacOS / Ubuntu dotfiles.

With this dotfiles, it

- allows you to setup dev environment in **just 3 commands** 🚀.
- would work **both on MacOS and Ubuntu**✨.

## Warning

If you want to give these dotfiles a try, you should first fork this repository, review the code, and remove things you don’t want or need. Don’t blindly use my settings unless you know what that entails. Use at your own risk!

## Requirement

- Ubuntu(>=20.04)(for Ubuntu user.)
- XCode Command Line Tools(for Mac user. if you don't have, get by runnning following command.)

```bash
$ xcode-select --install
```

## How to use

Run the following commnad.

```bash
$ bash -c "$(curl -fsSL raw.githubusercontent.com/shuntagami/dotfiles/main/scripts/install_dotfiles.sh)"
$ ~/dotfiles/scripts/install_packages.sh
$ ~/dotfiles/scripts/deploy.sh
```

### For Mac user

- Setup macOS.

```bash
$ ~/dotfiles/scripts/macos.sh
```

- Setup Iterm.

_(Preferences(⌘,)_ → _Preferences_ → check <b>Load preferences from a custom folder or URL</b>, change it to <b>/Users/Username/dotfiles/misc</b>)

![sample](https://user-images.githubusercontent.com/69618840/153607360-dc173d13-c551-4f2c-9ce5-02cbfeb0a120.png)

### For Visual Studio Code user

- Setup Visual Studio Code

```bash
$ ~/dotfiles/scripts/vscode.sh
```

## Keywords

- [Zsh](https://www.zsh.org/)([sorin-ionescu/prezto](https://github.com/sorin-ionescu/prezto))
- [vim](https://github.com/vim/vim)([Shugo/dein.vim](https://github.com/Shougo/dein.vim))
- [Homebrew](https://github.com/Homebrew/brew), [Debian/apt](https://github.com/Debian/apt)
- [anyenv](https://github.com/anyenv/anyenv)
- [iTerm2](https://github.com/gnachman/iTerm2)
- [Visual Studio Code](https://github.com/microsoft/vscode)
- [btop](https://github.com/aristocratos/btop)
