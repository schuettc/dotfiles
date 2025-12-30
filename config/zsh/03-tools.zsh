# Atuin - shell history (replaces zsh history settings)
if command -v atuin &> /dev/null && [[ $- == *i* ]]; then
  eval "$(atuin init zsh)"
fi

# Zoxide - smart cd
if command -v zoxide &> /dev/null && [[ $- == *i* ]]; then
  eval "$(zoxide init zsh)"
fi

# FZF - fuzzy finder
if command -v fzf &> /dev/null && [[ $- == *i* ]]; then
  source <(fzf --zsh)
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
  export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'
fi
