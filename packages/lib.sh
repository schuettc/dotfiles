#!/bin/bash
# Shared helpers for package install scripts. Sourced (not executed) by
# install.sh and packages/run.sh. bash-3.2-safe; no set -e by design.

PACKAGES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$PACKAGES_DIR")"
CONFIG_DIR="$HOME/.config"

WARNINGS=()
warn() { printf '  ⚠ %s\n' "$1" >&2; WARNINGS+=("$1"); }
die()  { printf '\n✗ FATAL: %s\n' "$1" >&2; exit 1; }

backup_if_exists() {
  if [[ -e "$1" && ! -L "$1" ]]; then
    echo "Backing up $1 to $1.bak"
    mv "$1" "$1.bak"
  fi
}

# Install the current package's Brewfile, if it has one. Install-only.
pkg_brew() {
  [[ -f "$PKG_DIR/Brewfile" ]] || return 0
  brew bundle --no-upgrade --file="$PKG_DIR/Brewfile" \
    || warn "$(basename "$PKG_DIR"): some brew packages failed — re-run 'brew bundle --no-upgrade --file=$PKG_DIR/Brewfile'"
}

# Source and run one package in the current shell (keeps WARNINGS shared).
run_pkg() {
  local name="$1" dir="$PACKAGES_DIR/$1"
  [[ -f "$dir/pkg.sh" ]] || { warn "unknown package: $name"; return 1; }
  PKG_DIR="$dir"
  unset -f pkg_install pkg_verify 2>/dev/null
  PKG_DESC="" ; PKG_DEPS=()
  source "$dir/pkg.sh"
  echo ""
  echo "── $name: $PKG_DESC"
  pkg_install
  pkg_verify || warn "$name: verification reported failures"
}
