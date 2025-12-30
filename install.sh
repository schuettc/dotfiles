#!/bin/bash
set -e

DOTFILES_DIR="$HOME/dotfiles"
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
ln -sf "$DOTFILES_DIR/config/zsh" "$CONFIG_DIR/zsh"

# Starship
backup_if_exists "$CONFIG_DIR/starship.toml"
ln -sf "$DOTFILES_DIR/config/starship.toml" "$CONFIG_DIR/starship.toml"

# Atuin
backup_if_exists "$CONFIG_DIR/atuin"
ln -sf "$DOTFILES_DIR/config/atuin" "$CONFIG_DIR/atuin"

# Import existing shell history into Atuin
if command -v atuin &> /dev/null; then
  echo "Importing shell history into Atuin..."
  atuin import auto 2>/dev/null || true
fi

# Configure iTerm2 if installed
if [[ -d "/Applications/iTerm.app" ]]; then
  echo "Configuring iTerm2..."
  "$DOTFILES_DIR/iterm2/setup-iterm.sh" import 2>/dev/null || \
  "$DOTFILES_DIR/iterm2/setup-iterm.sh" configure 2>/dev/null || true
fi

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Restart your terminal or run: source ~/.zshrc"
echo "  2. Set up Atuin sync: atuin register (new) or atuin login (existing)"
echo "  3. Configure iTerm2 fonts: ~/dotfiles/iterm2/setup-iterm.sh set-fonts"
echo "  4. Test shell speed: time zsh -i -c exit"
echo ""
