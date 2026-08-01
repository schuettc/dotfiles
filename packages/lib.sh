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

# ─── agent-harness hook files ───────────────────────────────────────────────
# Codex (~/.codex/hooks.json) and Cursor (~/.cursor/hooks.json) are shared
# between packages: the muster package wires bus hooks there, and the codex
# and cursor packages wire session-identity hooks. Every writer must merge
# ADDITIVELY — these files were previously rewritten wholesale, so whichever
# package installed last silently erased the others' hooks (install order
# puts muster last, so it always won).
#
# Both helpers are idempotent: re-running never duplicates an entry. Codex
# hook commands don't reliably expand ~, so pass absolute paths.

# codex_ensure_hook <event> <absolute-command>
codex_ensure_hook() {
  _harness_ensure_hook "$HOME/.codex/hooks.json" "$1" "$2" claude_shape
}

# cursor_ensure_hook <event> <absolute-command> [extra-json-object]
# Cursor's schema differs: camelCase events, flat {command} entries, and
# per-entry extras such as {"loop_limit":3} on stop.
cursor_ensure_hook() {
  _harness_ensure_hook "$HOME/.cursor/hooks.json" "$1" "$2" cursor_shape "${3-}"
}

_harness_ensure_hook() {
  local file="$1" ev="$2" cmd="$3" shape="$4" extra="${5-}" tmp
  # Spelled out rather than defaulted inline: "${5:-{\}}" expands to the
  # literal {\}, which --argjson rejects as invalid JSON.
  [[ -n "$extra" ]] || extra='{}'
  command -v jq &> /dev/null || {
    warn "jq missing — add \"$cmd\" to $file by hand."
    return 1
  }
  mkdir -p "$(dirname "$file")"
  [[ -s "$file" ]] || printf '{}\n' > "$file"
  # A hand-edited or truncated file must not take the install down with it.
  jq -e . "$file" > /dev/null 2>&1 || {
    warn "$file is not valid JSON — leaving it alone; add \"$cmd\" by hand."
    return 1
  }
  tmp=$(mktemp) || return 1
  local prog
  if [[ "$shape" == cursor_shape ]]; then
    prog='.version = (.version // 1)
      | .hooks[$ev] = ((.hooks[$ev] // [])
        | if ([.[].command?] | index($cmd)) then .
          else . + [({"command":$cmd} + $extra)] end)'
  else
    prog='.hooks[$ev] = ((.hooks[$ev] // [])
      | if ([.[].hooks[]?.command] | index($cmd)) then .
        else . + [{"hooks":[{"type":"command","command":$cmd}]}] end)'
  fi
  if jq --arg ev "$ev" --arg cmd "$cmd" --argjson extra "$extra" "$prog" "$file" > "$tmp"; then
    mv "$tmp" "$file"
  else
    rm -f "$tmp"
    warn "Couldn't merge $cmd into $file (jq error) — file untouched."
    return 1
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
