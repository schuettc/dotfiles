# Homebrew
eval "$(/opt/homebrew/bin/brew shellenv)"

# pnpm
export PNPM_HOME="$HOME/Library/pnpm"
[[ ":$PATH:" != *":$PNPM_HOME:"* ]] && export PATH="$PNPM_HOME:$PATH"

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
if command -v pyenv &> /dev/null; then
  eval "$(pyenv init -)"
fi

# MySQL client
export PATH="/opt/homebrew/opt/mysql-client/bin:$PATH"

# Local binaries
export PATH="$HOME/.local/bin:$PATH"

# VS Code
[[ -d "/Applications/Visual Studio Code.app/Contents/Resources/app/bin" ]] && \
  export PATH="$PATH:/Applications/Visual Studio Code.app/Contents/Resources/app/bin"

# Default editor (used by yazi, git commit, crontab, etc.).
# nvim runs in the terminal and blocks until you quit, so tools that wait
# on the editor (git commit) need no --wait flag.
export EDITOR='nvim'
export VISUAL='nvim'
