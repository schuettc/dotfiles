#!/bin/bash
# Resilient by design: we deliberately do NOT `set -e`. One failing step (a flaky
# brew cask, no network for TPM, …) shouldn't abort the whole install and leave a
# half-configured machine. Each risky step warns and continues; a summary of
# warnings prints at the end. Truly fatal problems (no Homebrew) call die().
# (No `set -u` either — macOS bash 3.2 errors on empty-array expansion under it.)

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.config"

WARNINGS=()
warn() { printf '  ⚠ %s\n' "$1" >&2; WARNINGS+=("$1"); }
die()  { printf '\n✗ FATAL: %s\n' "$1" >&2; exit 1; }

echo "Installing dotfiles..."

# Homebrew — fatal if we can't get it, since everything else depends on it.
if ! command -v brew &> /dev/null; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    || die "Homebrew install failed (network?). Fix and re-run."
  [[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
fi
command -v brew &> /dev/null || die "brew not on PATH after install — open a new shell and re-run."

# Install packages from Brewfile. brew bundle keeps going past a single failed
# formula/cask and exits non-zero at the end; warn rather than abort so the rest
# of the setup (symlinks, hooks, …) still happens.
echo "Installing Homebrew packages..."
brew bundle --file="$DOTFILES_DIR/Brewfile" \
  || warn "Some Homebrew packages failed — re-run 'brew bundle --file=$DOTFILES_DIR/Brewfile' or install them by hand."

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
ln -sfn "$DOTFILES_DIR/config/zsh" "$CONFIG_DIR/zsh"

# Starship
backup_if_exists "$CONFIG_DIR/starship.toml"
ln -sf "$DOTFILES_DIR/config/starship.toml" "$CONFIG_DIR/starship.toml"

# Atuin
backup_if_exists "$CONFIG_DIR/atuin"
ln -sfn "$DOTFILES_DIR/config/atuin" "$CONFIG_DIR/atuin"

# Import existing shell history into Atuin
if command -v atuin &> /dev/null; then
  echo "Importing shell history into Atuin..."
  atuin import auto 2>/dev/null || true
fi

# Ghostty config
echo "Linking Ghostty config..."
mkdir -p "$CONFIG_DIR/ghostty"
backup_if_exists "$CONFIG_DIR/ghostty/config"
ln -sf "$DOTFILES_DIR/config/ghostty/config" "$CONFIG_DIR/ghostty/config"

# tmux config
echo "Linking tmux config..."
backup_if_exists "$HOME/.tmux.conf"
ln -sf "$DOTFILES_DIR/.tmux.conf" "$HOME/.tmux.conf"

# yazi config (file explorer)
echo "Linking yazi config..."
backup_if_exists "$CONFIG_DIR/yazi"
ln -sfn "$DOTFILES_DIR/config/yazi" "$CONFIG_DIR/yazi"

# Install TPM (tmux plugin manager) and bootstrap declared plugins.
# `~/.tmux/plugins/tpm` is where TPM lives; the .tmux.conf above declares
# tmux-sensible, tmux-resurrect, and tmux-continuum.
if [[ ! -d "$HOME/.tmux/plugins/tpm" ]]; then
  echo "Cloning TPM..."
  git clone --depth 1 https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm" \
    || warn "TPM clone failed (network?) — tmux plugins won't install; re-run later."
fi
if command -v tmux &> /dev/null; then
  echo "Installing tmux plugins..."
  # install_plugins reads TMUX_PLUGIN_MANAGER_PATH from a running tmux
  # server's global env. Kill any stale server (likely with old config),
  # spin up a fresh one to load the current .tmux.conf, then install.
  tmux kill-server 2>/dev/null || true
  tmux new-session -d -s _bootstrap_install 2>/dev/null || true
  "$HOME/.tmux/plugins/tpm/bin/install_plugins" 2>/dev/null || true
  tmux kill-server 2>/dev/null || true
fi

# Claude Code setup
echo "Setting up Claude Code..."
mkdir -p "$HOME/.claude/sessions"

# Link Claude status line script
backup_if_exists "$CONFIG_DIR/claude"
ln -sfn "$DOTFILES_DIR/config/claude" "$CONFIG_DIR/claude"

# Merge Claude settings (preserves existing settings, adds/updates our config).
# Hooks: Notification + Stop both fire claude-notify.sh (macOS notif + tmux bell).
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
CLAUDE_HOOK_BLOCK='{"hooks":[{"type":"command","command":"~/.config/claude/claude-notify.sh"}]}'

if [[ -f "$CLAUDE_SETTINGS" ]]; then
  echo "Updating Claude Code settings (statusline + hooks)..."
  if command -v jq &> /dev/null; then
    TEMP_FILE=$(mktemp)
    if jq --argjson hook "$CLAUDE_HOOK_BLOCK" '
      .statusLine = {
        "type": "command",
        "command": "~/.config/claude/statusline.sh"
      } |
      .permissions = (.permissions // {}) + {
        "allow": ((.permissions.allow // []) + ["Bash(*/.claude/sessions/*)"] | unique)
      } |
      .hooks = (.hooks // {}) + {
        "Notification": [$hook],
        "Stop":         [$hook]
      }
    ' "$CLAUDE_SETTINGS" > "$TEMP_FILE"; then
      mv "$TEMP_FILE" "$CLAUDE_SETTINGS"
    else
      rm -f "$TEMP_FILE"
      warn "Couldn't merge Claude settings (jq error) — left ~/.claude/settings.json untouched."
    fi
  else
    echo "  Note: Install jq for automatic settings merge, or add manually."
  fi
else
  cat > "$CLAUDE_SETTINGS" << 'EOF'
{
  "statusLine": {
    "type": "command",
    "command": "~/.config/claude/statusline.sh"
  },
  "permissions": {
    "allow": [
      "Bash(*/.claude/sessions/*)"
    ]
  },
  "hooks": {
    "Notification": [
      {"hooks": [{"type": "command", "command": "~/.config/claude/claude-notify.sh"}]}
    ],
    "Stop": [
      {"hooks": [{"type": "command", "command": "~/.config/claude/claude-notify.sh"}]}
    ]
  }
}
EOF
fi

# Claude attention indicator: the `claude-attn` CLI (raise/clear/list/focus the
# per-session @claude_attn flag) + the SwiftBar menu-bar plugin. The Notification
# hook and any script/skill call `claude-attn raise`; it surfaces as 🔔 in the
# Ghostty tab/Dock title (set-titles-string, ~/.tmux.conf) and a SwiftBar badge.
echo "Setting up Claude attention indicator..."
mkdir -p "$HOME/.local/bin"
ln -sf "$DOTFILES_DIR/bin/claude-attn" "$HOME/.local/bin/claude-attn"
SWIFTBAR_A11Y_NOTE=""
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
  SWIFTBAR_A11Y_NOTE="grant SwiftBar Accessibility for click-to-focus"
else
  echo "  SwiftBar not found — the menu-bar indicator is optional (brew bundle installs it)."
fi

echo ""
if (( ${#WARNINGS[@]} )); then
  echo "Installation finished with ${#WARNINGS[@]} warning(s):"
  for w in "${WARNINGS[@]}"; do echo "  ⚠ $w"; done
  echo "(Everything else installed — address the above and re-run; install.sh is safe to repeat.)"
else
  echo "Installation complete — no warnings."
fi
echo ""
echo "Next steps:"
echo "  1. Open Ghostty (cmd+space → \"Ghostty\") and run: source ~/.zshrc"
echo "  2. Run \`proj\` and pick a project to spin up your first workspace."
echo "  3. Inside a project, cmd+T spawns more terminals (auto-joins tmux)."
echo "  4. Set up Atuin sync (optional): atuin register / atuin login"
if [[ -n "$SWIFTBAR_A11Y_NOTE" ]]; then
  echo "  5. ⚠ MANUAL: $SWIFTBAR_A11Y_NOTE —"
  echo "     System Settings → Privacy & Security → Accessibility → enable SwiftBar,"
  echo "     then quit + reopen SwiftBar. (Can't be automated — macOS TCC is SIP-protected.)"
  echo "  6. Read docs/terminal-usage.md for the day-to-day cheat sheet."
else
  echo "  5. Read docs/terminal-usage.md for the day-to-day cheat sheet."
fi
echo ""
