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

    # MarkEdit-preview extension provides the Shift-Cmd-V markdown preview.
    # It self-notifies about updates, so only fetch when absent.
    if [[ ! -s "$MARKEDIT_DIR/scripts/markedit-preview.js" ]]; then
      echo "Installing MarkEdit-preview extension..."
      local tmp url
      tmp="$(mktemp -d)"
      url="$(curl -fsSL https://api.github.com/repos/MarkEdit-app/MarkEdit-preview/releases/latest \
        | jq -r '.assets[0].browser_download_url')"
      if [[ -n "$url" && "$url" != "null" ]] \
        && curl -fsSL -o "$tmp/preview.zip" "$url" \
        && unzip -q -o "$tmp/preview.zip" -d "$tmp"; then
        mkdir -p "$MARKEDIT_DIR/scripts"
        cp "$tmp"/MarkEdit-preview-*/dist/markedit-preview.js "$MARKEDIT_DIR/scripts/markedit-preview.js"
      else
        warn "markedit: could not download MarkEdit-preview extension (Shift-Cmd-V preview unavailable)"
      fi
      rm -rf "$tmp"
    fi
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
  [[ -s "$MARKEDIT_DIR/scripts/markedit-preview.js" ]] \
    && echo "  PASS markedit-preview extension" || { echo "  FAIL markedit-preview extension"; ok=1; }
  return $ok
}
