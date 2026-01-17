#!/bin/bash
set -e

# Get the directory where this script is located
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.config"

echo "Installing dotfiles..."

# Check for Homebrew
if ! command -v brew &> /dev/null; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Install packages from Brewfile
echo "Installing Homebrew packages..."
brew bundle --file="$DOTFILES_DIR/Brewfile"

# Create config directory if it doesn't exist
mkdir -p "$CONFIG_DIR"

# Create symlinks
echo "Creating symlinks..."

# Backup existing configs
backup_if_exists() {
  if [[ -e "$1" && ! -L "$1" ]]; then
    echo "Backing up $1 to $1.bak"
    mv "$1" "$1.bak"
  fi
}

# ZSH config
backup_if_exists "$HOME/.zshrc"
ln -sf "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"

backup_if_exists "$CONFIG_DIR/zsh"
ln -sfn "$DOTFILES_DIR/config/zsh" "$CONFIG_DIR/zsh"

# Starship
backup_if_exists "$CONFIG_DIR/starship.toml"
ln -sf "$DOTFILES_DIR/config/starship.toml" "$CONFIG_DIR/starship.toml"

# Atuin
backup_if_exists "$CONFIG_DIR/atuin"
ln -sfn "$DOTFILES_DIR/config/atuin" "$CONFIG_DIR/atuin"

# Import existing shell history into Atuin
if command -v atuin &> /dev/null; then
  echo "Importing shell history into Atuin..."
  atuin import auto 2>/dev/null || true
fi

# Configure iTerm2 if installed (use 'configure' to avoid quitting iTerm2)
if [[ -d "/Applications/iTerm.app" ]]; then
  echo "Configuring iTerm2 to sync from dotfiles..."
  "$DOTFILES_DIR/iterm2/setup-iterm.sh" configure 2>/dev/null || true
fi

# Claude Code setup
echo "Setting up Claude Code..."
mkdir -p "$HOME/.claude/sessions"

# Link Claude status line script
backup_if_exists "$CONFIG_DIR/claude"
ln -sfn "$DOTFILES_DIR/config/claude" "$CONFIG_DIR/claude"

# Merge Claude settings (preserves existing settings, adds/updates our config)
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
if [[ -f "$CLAUDE_SETTINGS" ]]; then
  echo "Updating Claude Code status line config..."
  # Use jq to merge settings if available
  if command -v jq &> /dev/null; then
    TEMP_FILE=$(mktemp)
    jq '.statusLine = {
      "type": "command",
      "command": "~/.config/claude/statusline.sh"
    } | .permissions = (.permissions // {}) + {
      "allow": ((.permissions.allow // []) + ["Bash(*/.claude/sessions/*)"] | unique)
    }' "$CLAUDE_SETTINGS" > "$TEMP_FILE" && mv "$TEMP_FILE" "$CLAUDE_SETTINGS"
  else
    echo "  Note: Install jq for automatic settings merge, or add manually."
  fi
else
  # Create new settings file
  cat > "$CLAUDE_SETTINGS" << 'EOF'
{
  "statusLine": {
    "type": "command",
    "command": "~/.config/claude/statusline.sh"
  },
  "permissions": {
    "allow": [
      "Bash(*/.claude/sessions/*)"
    ]
  }
}
EOF
fi

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Restart your terminal or run: source ~/.zshrc"
echo "  2. Set up Atuin sync: atuin register (new) or atuin login (existing)"
echo "  3. Configure iTerm2 fonts: $DOTFILES_DIR/iterm2/setup-iterm.sh set-fonts"
echo "  4. Test shell speed: time zsh -i -c exit"
echo ""
