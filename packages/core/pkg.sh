#!/bin/bash
# core — shell foundation. Sourced by packages/lib.sh's run_pkg.

PKG_DESC="Shell foundation: Homebrew CLI tools, zsh config, Starship prompt, Atuin history"
PKG_DEPS=()

pkg_install() {
  pkg_brew
  mkdir -p "$CONFIG_DIR"

  backup_if_exists "$HOME/.zshrc"
  ln -sf "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"
  backup_if_exists "$CONFIG_DIR/zsh"
  ln -sfn "$DOTFILES_DIR/config/zsh" "$CONFIG_DIR/zsh"

  backup_if_exists "$CONFIG_DIR/starship.toml"
  ln -sf "$DOTFILES_DIR/config/starship.toml" "$CONFIG_DIR/starship.toml"

  backup_if_exists "$CONFIG_DIR/atuin"
  ln -sfn "$DOTFILES_DIR/config/atuin" "$CONFIG_DIR/atuin"
  if command -v atuin &> /dev/null; then
    echo "Importing shell history into Atuin..."
    atuin import auto 2>/dev/null || true
  fi

  mkdir -p "$HOME/.local/bin"
}

pkg_verify() {
  local ok=0
  [[ "$(readlink "$HOME/.zshrc")" == "$DOTFILES_DIR/.zshrc" ]] \
    && echo "  PASS ~/.zshrc -> repo" || { echo "  FAIL ~/.zshrc symlink"; ok=1; }
  command -v starship &> /dev/null && echo "  PASS starship" || { echo "  FAIL starship missing"; ok=1; }
  command -v atuin &> /dev/null && echo "  PASS atuin" || { echo "  FAIL atuin missing"; ok=1; }
  return $ok
}
