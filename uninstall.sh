#!/bin/bash
# Undo what install.sh did. Safe by default and re-runnable:
#   - removes ONLY symlinks that point into this dotfiles dir, then restores any
#     *.bak backup install.sh made (never deletes a real file we didn't create)
#   - removes the claude-attn CLI symlink
#   - removes the SwiftBar Login Item + plugin-dir preference (leaves the app)
#   - strips the hooks/statusline install.sh merged into ~/.claude/settings.json
#     (backed up to settings.json.bak first)
#
# Leaves Homebrew packages and the SwiftBar app installed unless you pass --purge.
#
# Usage:
#   ./uninstall.sh           # remove links + config, restore backups
#   ./uninstall.sh --purge   # also: uninstall SwiftBar, delete TPM
#
# Does NOT kill your tmux server (you'd lose live sessions). Restart tmux or run
# `tmux source ~/.tmux.conf` afterwards to apply the reverted config.

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.config"
PURGE=0
[[ "${1:-}" == "--purge" ]] && PURGE=1

echo "Uninstalling dotfiles..."

# Remove a symlink only if it points into THIS dotfiles dir, then restore a .bak
# backup if one exists. Anything that isn't our symlink is left untouched.
unlink_restore() {
  local target="$1"
  if [[ -L "$target" ]]; then
    local dest; dest="$(readlink "$target")"
    case "$dest" in
      "$DOTFILES_DIR"/*) rm -f "$target"; echo "  removed symlink  $target" ;;
      *) echo "  kept (foreign symlink → $dest)  $target"; return ;;
    esac
  elif [[ -e "$target" ]]; then
    echo "  kept (real file, not ours)  $target"; return
  fi
  if [[ -e "$target.bak" ]]; then
    mv "$target.bak" "$target"
    echo "  restored backup  $target.bak → $target"
  fi
}

# Config symlinks install.sh creates
unlink_restore "$HOME/.zshrc"
unlink_restore "$CONFIG_DIR/zsh"
unlink_restore "$CONFIG_DIR/starship.toml"
unlink_restore "$CONFIG_DIR/atuin"
unlink_restore "$CONFIG_DIR/ghostty/config"
unlink_restore "$HOME/.tmux.conf"
unlink_restore "$CONFIG_DIR/yazi"
unlink_restore "$CONFIG_DIR/claude"

# claude-attn CLI symlink (the menu-bar / hook trigger)
if [[ -L "$HOME/.local/bin/claude-attn" ]]; then
  rm -f "$HOME/.local/bin/claude-attn" && echo "  removed symlink  ~/.local/bin/claude-attn"
fi

# SwiftBar: drop the Login Item + the plugin-dir preference (keep the app)
if osascript -e 'tell application "System Events" to delete (every login item whose name is "SwiftBar")' >/dev/null 2>&1; then
  echo "  removed SwiftBar Login Item"
fi
defaults delete com.ameba.SwiftBar PluginDirectory >/dev/null 2>&1 && echo "  cleared SwiftBar PluginDirectory pref"

# Claude settings: strip what install.sh merged in (our hooks/statusline/perm),
# preserving everything else. Backed up first so it's reversible.
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
if [[ -f "$CLAUDE_SETTINGS" ]] && command -v jq &>/dev/null; then
  cp "$CLAUDE_SETTINGS" "$CLAUDE_SETTINGS.bak"
  TMP=$(mktemp)
  if jq '
    (if ((.hooks.Notification // []) | tostring | test("claude-notify.sh")) then del(.hooks.Notification) else . end)
    | (if ((.hooks.Stop // []) | tostring | test("claude-notify.sh")) then del(.hooks.Stop) else . end)
    | (if ((.statusLine | tostring) | test("statusline.sh")) then del(.statusLine) else . end)
    | (if .permissions.allow then .permissions.allow |= map(select(. != "Bash(*/.claude/sessions/*)")) else . end)
  ' "$CLAUDE_SETTINGS" > "$TMP"; then
    mv "$TMP" "$CLAUDE_SETTINGS"
    echo "  stripped our hooks/statusline from ~/.claude/settings.json (backup: settings.json.bak)"
  else
    rm -f "$TMP"; echo "  ⚠ couldn't edit settings.json — left it (and the .bak) as-is"
  fi
fi

if (( PURGE )); then
  echo "Purging apps..."
  if [[ -d "/Applications/SwiftBar.app" ]]; then
    osascript -e 'tell application "SwiftBar" to quit' >/dev/null 2>&1
    brew uninstall --cask swiftbar >/dev/null 2>&1 && echo "  uninstalled SwiftBar"
    rm -f "$HOME/Library/Preferences/com.ameba.SwiftBar.plist" 2>/dev/null
  fi
  rm -rf "$HOME/.tmux/plugins/tpm" 2>/dev/null && echo "  removed TPM"
  echo "  (Brewfile formulae/casks left installed — remove individually if you want.)"
fi

echo ""
echo "Uninstall complete."
echo "  • Restart tmux (or 'tmux source ~/.tmux.conf') to apply the reverted config."
echo "  • Open a new shell — your previous ~/.zshrc.bak (if any) has been restored."
(( PURGE )) || echo "  • Homebrew packages + SwiftBar were kept. Re-run with --purge to remove them."
