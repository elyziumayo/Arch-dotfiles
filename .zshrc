# Set the directory to store zinit and plugins
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
fastfetch
# if no zinit,downlaod
if [ ! -d "$ZINIT_HOME" ]; then
   mkdir -p "$(dirname $ZINIT_HOME)"
   git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

# Source/Load zinit
source "${ZINIT_HOME}/zinit.zsh"

#starship
eval "$(starship init zsh)"

# zsh plugins  
zinit ice light zsh-users/zsh-completions
zinit ice light zdharma/fast-syntax-highlighting
zinit light zsh-users/zsh-autosuggestions 
zinit light Aloxaf/fzf-tab

# Add in snippets
zinit ice wait"1" snippet OMZL::git.zsh
zinit ice wait"1" snippet OMZP::git
zinit ice wait"1" snippet OMZP::sudo
zinit ice wait"1" snippet OMZP::archlinux
zinit ice wait"1" snippet OMZP::command-not-found

# Load completions
autoload -Uz compinit && compinit
zinit cdreplay -q

# Keybindings
bindkey -e
bindkey '^p' history-search-backward
bindkey '^n' history-search-forward
bindkey '^[w' kill-region

# History
HISTSIZE=5000
HISTFILE=~/.zsh_history
SAVEHIST=$HISTSIZE
HISTDUP=erase
setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_ignore_dups
setopt hist_find_no_dups

# Completion styling
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza --color $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'eza --color $realpath'

# Aliases
alias ls='eza -l --icons=always -h'
alias vim='nvim'
alias c='clear'
alias repoup='sudo reflector --verbose --sort rate -l 20 --age 6 --save /etc/pacman.d/mirrorlist'

# Shell integrations
eval "$(fzf --zsh)"
eval "$(zoxide init --cmd cd zsh)"
