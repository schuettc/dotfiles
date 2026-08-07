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

# Install AND upgrade the current package's Brewfile, if it has one.
# --no-upgrade was the old policy (install-if-missing, drift forever);
# dotup is the convergence mechanism now, so listed formulae/casks track
# brew's latest on every run.
pkg_brew() {
  [[ -f "$PKG_DIR/Brewfile" ]] || return 0
  brew bundle --file="$PKG_DIR/Brewfile" \
    || warn "$(basename "$PKG_DIR"): some brew packages failed — re-run 'brew bundle --file=$PKG_DIR/Brewfile'"
}

# ─── release-based tool installs ────────────────────────────────────────────
# The version policy for self-built tools (muster, scratch, …): releases and
# tags are the source of truth. No gh, no GitHub API — one unauthenticated
# HEAD request resolves the latest tag (the /releases/latest redirect ends in
# /tag/vX.Y.Z), and assets come from the stable releases/latest/download URL.
# See docs/superpowers/specs/2026-08-07-release-based-tool-installs-design.md.

# latest_release_tag <owner/repo> — print the latest release tag (vX.Y.Z).
# Prints nothing and returns 1 on any failure (offline, no releases yet);
# callers treat that as "can't know" and keep what they have.
latest_release_tag() {
  local url
  url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' --max-time 10 \
    "https://github.com/$1/releases/latest" 2>/dev/null) || return 1
  case "$url" in
    */releases/tag/*) printf '%s\n' "${url##*/}" ;;
    *) return 1 ;;
  esac
}

# install_release_binary <owner/repo> <asset.tar.gz> <bin-name>
# Download the latest release's asset plus checksums.txt, verify the sha256,
# and install the tarball's <bin-name> into ~/.local/bin. Every failure path
# warns and returns 1 with the previously installed binary untouched.
install_release_binary() {
  local repo="$1" asset="$2" bin="$3"
  local base="https://github.com/$repo/releases/latest/download"
  local tmp; tmp=$(mktemp -d) || return 1
  local rc=0
  curl -fsSL --max-time 300 -o "$tmp/$asset" "$base/$asset" 2>/dev/null || rc=$?
  if [[ $rc -eq 0 ]]; then
    curl -fsSL --max-time 30 -o "$tmp/checksums.txt" "$base/checksums.txt" 2>/dev/null || rc=$?
  fi
  if [[ $rc -ne 0 ]]; then
    rm -rf "$tmp"
    # curl -f turns an HTTP error response (eg. 404) into rc 22 — that's a
    # missing asset (release assets can lag the tag by a few seconds on a
    # fresh publish), distinct from a network-level failure.
    if [[ $rc -eq 22 ]]; then
      warn "$bin: asset not found (release assets may still be uploading) — kept the existing binary."
    else
      warn "$bin: download failed (offline?) — kept the existing binary."
    fi
    return 1
  fi
  local want got
  want=$(awk -v a="$asset" '$2 == a {print $1}' "$tmp/checksums.txt")
  if command -v shasum &> /dev/null; then
    got=$(shasum -a 256 "$tmp/$asset" | awk '{print $1}')
  else
    got=$(sha256sum "$tmp/$asset" | awk '{print $1}')
  fi
  if [[ -z "$want" || "$want" != "$got" ]]; then
    rm -rf "$tmp"
    warn "$bin: sha256 mismatch on $asset — kept the existing binary."
    return 1
  fi
  if ! tar -xzf "$tmp/$asset" -C "$tmp" "$bin" 2>/dev/null; then
    rm -rf "$tmp"
    warn "$bin: $asset does not contain '$bin' — kept the existing binary."
    return 1
  fi
  mkdir -p "$HOME/.local/bin" || {
    rm -rf "$tmp"
    warn "$bin: couldn't create ~/.local/bin — kept the existing binary."
    return 1
  }
  chmod +x "$tmp/$bin" || {
    rm -rf "$tmp"
    warn "$bin: couldn't make $bin executable — kept the existing binary."
    return 1
  }
  # Stage inside ~/.local/bin (not straight from $tmp, which may be a
  # different filesystem/tmpfs) so the final mv is a same-filesystem
  # rename — genuinely atomic; a running daemon keeps its old inode.
  local staging="$HOME/.local/bin/.$bin.new.$$"
  mv -f "$tmp/$bin" "$staging" || {
    rm -f "$staging"
    rm -rf "$tmp"
    warn "$bin: couldn't stage into ~/.local/bin — kept the existing binary."
    return 1
  }
  mv -f "$staging" "$HOME/.local/bin/$bin" || {
    rm -f "$staging"
    rm -rf "$tmp"
    warn "$bin: couldn't install to ~/.local/bin — kept the existing binary."
    return 1
  }
  rm -rf "$tmp"
  return 0
}

# verify_release_current <owner/repo> <installed-version> <label>
# pkg_verify's drift check: FAIL (rc 1) when the installed version doesn't
# match the latest release tag; silent success when the tag can't be
# resolved (offline verify still stands on the capability checks).
verify_release_current() {
  [[ -n "${PKG_VERIFY_SKIP_DRIFT:-}" ]] && return 0
  local repo="$1" installed="$2" label="$3" latest
  latest=$(latest_release_tag "$repo") || return 0
  if [[ "${latest#v}" == "${installed#v}" && -n "$installed" ]]; then
    echo "  PASS $label at latest release ($latest)"
  else
    echo "  FAIL $label version ${installed:-unknown} != latest release $latest (run dotup)"
    return 1
  fi
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
