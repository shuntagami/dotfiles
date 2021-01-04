# dotfiles
Simple dotfiles includes<br>
.zsh with Prezto,<br> 
.vimrc with dein.vim,<br>
setting of iTerm,<br>
installer of applications using brew, cask, and mas

## how to use

Firstly, maku sure that <b>Command line tools for Xcode</b> is installed on your mac. If not, run next command.

```
$ xcode-select --install
```

```
$ git clone https://github.com/shuntagami/dotfiles.git
$ cd dotfiles
$ chmod +x homebrew_install.sh
$ ./homebrew_install.sh
```

After installing brew, you'll be able to swich to iTerm<br>
```
$ cd dotfiles
$ defaults read com.googlecode.iterm2
```

then, restart the iTerm(beautiful screen will appear)

```
$ chmod +x install.sh
$ ./install.sh
$ zsh
```

## image of iTerm
![sample](https://user-images.githubusercontent.com/69618840/103264511-44306b00-49ee-11eb-8e5e-4398c46d2993.png)

## image of vim
![sample](https://user-images.githubusercontent.com/69618840/103265226-6dea9180-49f0-11eb-8894-83dc523f6803.png)
