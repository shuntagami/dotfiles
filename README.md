# dotfiles
Simple dotfiles includes<br>
.zshrc with Prezto,<br> 
.vimrc with dein.vim,<br>
setting of iTerm,<br>
installer of applications using brew, cask, and mas

## how to use

Firstly, maku sure that <b>Command line tools for Xcode</b> is installed on your mac. If not, run next command.

```
$ xcode-select --install
```

Clone this repo.
```
$ git clone https://github.com/shuntagami/dotfiles.git
$ cd dotfiles
```

Setup homebrew, and you can install rbenv, nodenv, tfenv by anyenv
```
$ chmod +x homebrew_setup.sh
$ ./homebrew_setup.sh
$ exec $SHELL -l
```

Switch to iTerm2, run next command, restart the iTerm2
```
$ cd dotfiles
$ defaults read com.googlecode.iterm2
```

Setup zsh.

```
$ chmod +x zsh_setup.sh
$ ./zsh_setup.sh
$ zsh
```

Setup anyenv

```
$ chmod +x anyenv_setup.sh
$ ./anyenv_setup.sh
$ zsh
```

## image of iTerm
![sample](https://user-images.githubusercontent.com/69618840/103264511-44306b00-49ee-11eb-8e5e-4398c46d2993.png)

## image of vim
![sample](https://user-images.githubusercontent.com/69618840/103265226-6dea9180-49f0-11eb-8894-83dc523f6803.png)
