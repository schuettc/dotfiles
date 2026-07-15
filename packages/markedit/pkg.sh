#!/bin/bash
# markedit — MarkEdit markdown-editor styles (skips if app not installed). Sourced by packages/lib.sh's run_pkg.

PKG_DESC="MarkEdit markdown-editor styles (skips if app not installed)"
PKG_DEPS=(core)

pkg_install() {
  pkg_brew

  local MARKEDIT_DIR="$HOME/Library/Containers/app.cyan.markedit/Data/Documents"
  if [[ -d "$MARKEDIT_DIR" ]]; then
    echo "Linking MarkEdit styles..."
    backup_if_exists "$MARKEDIT_DIR/editor.css"
    ln -sf "$DOTFILES_DIR/config/markedit/editor.css" "$MARKEDIT_DIR/editor.css"
  else
    echo "Skipping MarkEdit (not installed)."
  fi
}

pkg_verify() {
  local MARKEDIT_DIR="$HOME/Library/Containers/app.cyan.markedit/Data/Documents"
  if [[ ! -d "$MARKEDIT_DIR" ]]; then
    echo "  PASS markedit (not installed — skipped)"
    return 0
  fi

  local ok=0
  [[ "$(readlink "$MARKEDIT_DIR/editor.css")" == "$DOTFILES_DIR/config/markedit/editor.css" ]] \
    && echo "  PASS editor.css symlink" || { echo "  FAIL editor.css symlink"; ok=1; }
  return $ok
}
