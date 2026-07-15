#!/bin/bash
# nvim — Neovim editor with LazyVim config. Sourced by packages/lib.sh's run_pkg.

PKG_DESC="Neovim (\$EDITOR) with LazyVim config"
PKG_DEPS=(core)

pkg_install() {
  pkg_brew

  echo "Linking neovim config..."
  backup_if_exists "$CONFIG_DIR/nvim"
  ln -sfn "$DOTFILES_DIR/config/nvim" "$CONFIG_DIR/nvim"
}

pkg_verify() {
  local ok=0
  command -v nvim &> /dev/null && echo "  PASS nvim" || { echo "  FAIL nvim missing"; ok=1; }
  [[ "$(readlink "$CONFIG_DIR/nvim")" == "$DOTFILES_DIR/config/nvim" ]] \
    && echo "  PASS config/nvim symlink" || { echo "  FAIL config/nvim symlink"; ok=1; }
  return $ok
}
