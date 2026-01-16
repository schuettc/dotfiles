# Lazy load NVM for fast shell startup (~300ms savings)
export NVM_DIR="$HOME/.nvm"

# Only set up if NVM exists
if [[ -d "$NVM_DIR" ]]; then
  # Add default node to PATH for Starship detection (without loading NVM)
  NODE_VERSIONS_PATH="$NVM_DIR/versions/node"
  if [[ -d "$NODE_VERSIONS_PATH" ]]; then
    # Get the default version alias
    if [[ -f "$NVM_DIR/alias/default" ]]; then
      DEFAULT_ALIAS=$(cat "$NVM_DIR/alias/default")
      # Find matching version (handles "20" -> "v20.14.0")
      DEFAULT_VERSION=$(ls -1 "$NODE_VERSIONS_PATH" 2>/dev/null | grep "^v${DEFAULT_ALIAS}" | sort -t. -k1.2n -k2n -k3n | tail -1)
    fi

    # Fallback to latest if no default or no match
    if [[ -z "$DEFAULT_VERSION" ]]; then
      DEFAULT_VERSION=$(ls -1 "$NODE_VERSIONS_PATH" 2>/dev/null | sort -t. -k1.2n -k2n -k3n | tail -1)
    fi

    if [[ -n "$DEFAULT_VERSION" && -d "$NODE_VERSIONS_PATH/$DEFAULT_VERSION/bin" ]]; then
      export PATH="$NODE_VERSIONS_PATH/$DEFAULT_VERSION/bin:$PATH"
    fi
  fi

  # Lazy load NVM itself (for switching versions, etc.)
  nvm() {
    unset -f nvm
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    nvm "$@"
  }
fi
