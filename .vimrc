" ==============================================================================
" プラグイン管理 (dein.vim)
" ==============================================================================
if &compatible
  set nocompatible
endif

filetype off

let s:dein_dir = expand('~/.cache/dein')
let s:dein_repo_dir = s:dein_dir . '/repos/github.com/Shougo/dein.vim'

if !isdirectory(s:dein_repo_dir)
  execute '!git clone https://github.com/Shougo/dein.vim' s:dein_repo_dir
endif
execute 'set runtimepath^=' . s:dein_repo_dir

if dein#load_state(s:dein_dir)
  call dein#begin(s:dein_dir)
  call dein#load_toml('~/.dein.toml', {'lazy': 0})
  call dein#end()
  call dein#save_state()
endif
if dein#check_install()
  call dein#install()
endif

filetype plugin indent on

" ==============================================================================
" 基本設定
" ==============================================================================
set mouse=a
set noswapfile
set noundofile
set ruler
set cmdheight=2
set laststatus=2
set statusline=%<%f\ %m%r%h%w%{'['.(&fenc!=''?&fenc:&enc).']['.&ff.']'}%=%l,%c%V%8P
set title
set wildmenu
set showcmd
set hidden
set visualbell
set formatoptions=q
set synmaxcol=200

" インデント
set expandtab
set tabstop=2
set shiftwidth=2
set smarttab
set autoindent
set smartindent

" 表示
set list
set listchars=tab:>\ ,extends:<
set number
set cursorline
set cursorcolumn
set showmatch
set background=dark

" ==============================================================================
" クリップボード
" ==============================================================================
if has("unix")
  let s:uname = system("uname -s")
  if s:uname == "Linux\n"
    set clipboard=unnamedplus
  elseif s:uname == "Darwin\n"
    set clipboard=unnamed
  endif
else
  set clipboard=unnamed
endif

" 削除時にクリップボードを上書きしない（ブラックホールレジスタを使用）
nnoremap d "_d
nnoremap dd "_dd
nnoremap D "_D
nnoremap x "_x
nnoremap X "_X
xnoremap d "_d
nnoremap c "_c
nnoremap cc "_cc
nnoremap C "_C
xnoremap c "_c

" ==============================================================================
" 外観 (syntax, colorscheme)
" ==============================================================================
syntax on
colorscheme hybrid

highlight Normal ctermbg=NONE guibg=NONE
highlight NonText ctermbg=NONE guibg=NONE
highlight SpecialKey ctermbg=NONE guibg=NONE
highlight EndOfBuffer ctermbg=NONE guibg=NONE

" ==============================================================================
" ファイルブラウザ (netrw, molder)
" ==============================================================================
let g:netrw_liststyle=1
let g:netrw_banner=0
let g:netrw_sizestyle="H"
let g:netrw_timefmt="%Y/%m/%d(%a) %H:%M:%S"
let g:netrw_preview=1
let g:molder_show_hidden=1

" ==============================================================================
" 検索
" ==============================================================================
set ignorecase
set smartcase
set incsearch
set wrapscan
set hlsearch
nnoremap <Esc><Esc> :nohlsearch<CR><Esc>

" ==============================================================================
" プラグイン設定
" ==============================================================================
let g:auto_save = 1

" ==============================================================================
" キーマッピング
" ==============================================================================
" 自動的に閉じ括弧を入力
inoremap { {}<LEFT>
inoremap [ []<LEFT>
inoremap ( ()<LEFT>

" ==============================================================================
" 全角スペースの表示
" ==============================================================================
function! ZenkakuSpace()
    highlight ZenkakuSpace cterm=underline ctermfg=lightblue guibg=darkgray
endfunction
if has('syntax')
    augroup ZenkakuSpace
        autocmd!
        autocmd ColorScheme * call ZenkakuSpace()
        autocmd VimEnter,WinEnter,BufRead * let w:m1=matchadd('ZenkakuSpace', '　')
    augroup END
    call ZenkakuSpace()
endif

" ==============================================================================
" 挿入モード時、ステータスラインの色を変更
" ==============================================================================
let g:hi_insert = 'highlight StatusLine guifg=darkblue guibg=darkyellow gui=none ctermfg=blue ctermbg=yellow cterm=none'
if has('syntax')
  augroup InsertHook
    autocmd!
    autocmd InsertEnter * call s:StatusLine('Enter')
    autocmd InsertLeave * call s:StatusLine('Leave')
  augroup END
endif
let s:slhlcmd = ''
function! s:StatusLine(mode)
  if a:mode == 'Enter'
    silent! let s:slhlcmd = 'highlight ' . s:GetHighlight('StatusLine')
    silent exec g:hi_insert
  else
    highlight clear StatusLine
    silent exec s:slhlcmd
  endif
endfunction
function! s:GetHighlight(hi)
  redir => hl
  exec 'highlight '.a:hi
  redir END
  let hl = substitute(hl, '[\r\n]', '', 'g')
  let hl = substitute(hl, 'xxx', '', '')
  return hl
endfunction

" ==============================================================================
" autocmd
" ==============================================================================
" memo保存時に自動git-sync
function! AsyncGitSync()
    if has('nvim')
        call jobstart(['memo', 'git-sync'])
    else
        call job_start(['memo', 'git-sync'])
    endif
endfunction

augroup memo_auto_git
    autocmd!
    autocmd BufWritePost */memo/_posts/*.md call AsyncGitSync()
augroup END

" 最後のカーソル位置を復元する
if has("autocmd")
    autocmd BufReadPost *
    \ if line("'\"") > 0 && line ("'\"") <= line("$") |
    \   exe "normal! g'\"" |
    \ endif
endif

filetype on
