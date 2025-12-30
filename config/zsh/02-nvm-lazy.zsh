# Lazy load NVM for fast shell startup (~300ms savings)
export NVM_DIR="$HOME/.nvm"

# Only set up lazy loading if NVM exists
if [[ -d "$NVM_DIR" ]]; then
  nvm() {
    unset -f nvm node npm npx pnpm
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    nvm "$@"
  }

  node() {
    unset -f nvm node npm npx pnpm
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    node "$@"
  }

  npm() {
    unset -f nvm node npm npx pnpm
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    npm "$@"
  }

  npx() {
    unset -f nvm node npm npx pnpm
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    npx "$@"
  }

  pnpm() {
    unset -f nvm node npm npx pnpm
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    pnpm "$@"
  }
fi
