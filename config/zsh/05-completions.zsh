# Docker completions
[[ -d "$HOME/.docker/completions" ]] && fpath=($HOME/.docker/completions $fpath)

# Homebrew completions
if type brew &>/dev/null; then
  fpath=($(brew --prefix)/share/zsh/site-functions $fpath)
fi

# Load completion list module (required for menu selection)
zmodload zsh/complist

# Completion styling (must be before compinit)
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*:descriptions' format '%B%d%b'
zstyle ':completion:*:messages' format '%d'
zstyle ':completion:*:warnings' format 'No matches for: %d'

# Initialize completion system
autoload -Uz compinit
compinit -C  # -C for faster startup (uses cache)

# AWS completions (bash-style - doesn't support menu select)
if [[ -f /usr/local/bin/aws_completer ]]; then
  autoload -Uz bashcompinit && bashcompinit
  complete -C '/usr/local/bin/aws_completer' aws
fi
