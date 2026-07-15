#!/bin/bash
PKG_DESC="SwiftBar menu-bar attention indicator (🔔 per waiting Claude session, click to focus)"
PKG_DEPS=(claude)

pkg_install() {
  pkg_brew
  if [[ -d "/Applications/SwiftBar.app" ]]; then
    # Point SwiftBar at the tracked plugin folder, launch it at login, start it now.
    defaults write com.ameba.SwiftBar PluginDirectory "$DOTFILES_DIR/config/swiftbar/plugins"
    # Add to Login Items only if not already there (idempotent — a re-run was
    # adding a duplicate SwiftBar entry every time).
    if ! osascript -e 'tell application "System Events" to get name of every login item' 2>/dev/null | grep -q "SwiftBar"; then
      osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/SwiftBar.app", hidden:false}' >/dev/null 2>&1 || true
    fi
    open -a SwiftBar >/dev/null 2>&1 || true
    # The one step that CAN'T be automated: macOS Accessibility (TCC) is SIP-
    # protected, so click-to-focus (un-minimize + raise a window) needs SwiftBar
    # granted Accessibility by hand. Flag it in the Next steps below.
    echo "  ⚠ MANUAL: grant SwiftBar Accessibility (System Settings → Privacy & Security → Accessibility), then restart SwiftBar."
  else
    echo "  SwiftBar not found — the menu-bar indicator is optional (brew bundle installs it)."
  fi
}

pkg_verify() {
  local ok=0
  [[ -d /Applications/SwiftBar.app ]] && echo "  PASS SwiftBar.app installed" || { echo "  FAIL SwiftBar.app"; ok=1; }
  local plugin_dir; plugin_dir=$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null)
  [[ "$plugin_dir" == "$DOTFILES_DIR/config/swiftbar/plugins" ]] \
    && echo "  PASS PluginDirectory configured" || { echo "  FAIL PluginDirectory"; ok=1; }
  return $ok
}
