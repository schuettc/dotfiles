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

# GitHub CLI: do NOT export GITHUB_TOKEN here.
# `gh` manages its own credential in the keyring; git uses SSH. Exporting
# GITHUB_TOKEN=$(gh auth token) shadows that keyring credential — `gh auth
# login` then refuses to run, a stale token lingers under org SSO (gh/API
# return SAML 403s), and tmux captures it into its global env and hands it to
# every pane. Tools that genuinely need GITHUB_TOKEN should set it in their own
# scope; gh's git credential helper covers HTTPS if you ever switch protocols.
