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

# Node: the LTS line, not Homebrew's newest `node`. pi runs on whichever node is
# first on PATH (#!/usr/bin/env node), and each new Node major breaks native
# addons and experimental flags before they catch up. node@24 is keg-only, so
# it is put first here; move this (and kempt.toml's node@24) to the next LTS.
[[ -d /opt/homebrew/opt/node@24/bin ]] && export PATH="/opt/homebrew/opt/node@24/bin:$PATH"

# Local binaries
export PATH="$HOME/.local/bin:$PATH"

# Go binaries (`go install` target)
[[ ":$PATH:" != *":$HOME/go/bin:"* ]] && export PATH="$HOME/go/bin:$PATH"

# VS Code
[[ -d "/Applications/Visual Studio Code.app/Contents/Resources/app/bin" ]] && \
  export PATH="$PATH:/Applications/Visual Studio Code.app/Contents/Resources/app/bin"

# Default editor (used by yazi, git commit, crontab, etc.).
# nvim runs in the terminal and blocks until you quit, so tools that wait
# on the editor (git commit) need no --wait flag.
export EDITOR='nvim'
export VISUAL='nvim'
