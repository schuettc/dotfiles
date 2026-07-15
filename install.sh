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

# macOS only — this setup leans on Homebrew casks, launchd (muster LaunchAgent),
# SwiftBar/osascript, and pbcopy throughout. Fail loudly up front rather than
# leaving a Linux/WSL machine half-configured.
[[ "$(uname)" == "Darwin" ]] || die "This install is macOS-only (found $(uname)). No Linux/Windows support yet."

echo "Installing dotfiles..."

# Homebrew — fatal if we can't get it, since everything else depends on it.
if ! command -v brew &> /dev/null; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    || die "Homebrew install failed (network?). Fix and re-run."
  [[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
fi
command -v brew &> /dev/null || die "brew not on PATH after install — open a new shell and re-run."

# Install packages from Brewfile. --no-upgrade makes this install-only: it adds
# what's missing but never force-upgrades already-installed packages. That keeps
# the bootstrap non-interactive — self-updating casks (e.g. docker-desktop, which
# updates itself ahead of brew) would otherwise trigger a sudo-requiring upgrade
# that has no TTY here and fails. Run `brew upgrade` deliberately when you want
# upgrades. brew bundle keeps going past a single failed formula/cask and exits
# non-zero at the end; warn rather than abort so the rest of the setup still happens.
echo "Installing Homebrew packages..."
brew bundle --file="$DOTFILES_DIR/Brewfile" --no-upgrade \
  || warn "Some Homebrew packages failed — re-run 'brew bundle --file=$DOTFILES_DIR/Brewfile --no-upgrade' or install them by hand."

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

# neovim config (LazyVim)
echo "Linking neovim config..."
backup_if_exists "$CONFIG_DIR/nvim"
ln -sfn "$DOTFILES_DIR/config/nvim" "$CONFIG_DIR/nvim"

# MarkEdit custom styles (editor + preview fonts).
# MarkEdit is a sandboxed app; its settings live in the app container, not
# ~/.config. We only link when the container exists (i.e. MarkEdit is installed),
# and only when editor.css isn't already our symlink. Restart MarkEdit to apply.
MARKEDIT_DIR="$HOME/Library/Containers/app.cyan.markedit/Data/Documents"
if [[ -d "$MARKEDIT_DIR" ]]; then
  echo "Linking MarkEdit styles..."
  backup_if_exists "$MARKEDIT_DIR/editor.css"
  ln -sf "$DOTFILES_DIR/config/markedit/editor.css" "$MARKEDIT_DIR/editor.css"
else
  echo "Skipping MarkEdit (not installed)."
fi

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
  # server's global env, so we need a live server that has loaded the
  # current .tmux.conf. Run the whole bootstrap on a DEDICATED throwaway
  # socket (-L) with $TMUX scrubbed: if this script runs from a shell
  # inside tmux, bare `tmux` inherits $TMUX and targets the CURRENT
  # server — a kill-server there nukes the project you're sitting in
  # (this bit us: it killed the live proj-muster server mid-upgrade and
  # left its replacement's hook queue deadlocked behind a hung tpm).
  # run-shell (not a direct script call) so install_plugins' bare `tmux`
  # calls inherit $TMUX for the bootstrap server, not the default socket.
  env -u TMUX tmux -L _bootstrap_tpm kill-server 2>/dev/null || true
  env -u TMUX tmux -L _bootstrap_tpm new-session -d -s _bootstrap_install 2>/dev/null || true
  env -u TMUX tmux -L _bootstrap_tpm run-shell "$HOME/.tmux/plugins/tpm/bin/install_plugins" 2>/dev/null || true
  env -u TMUX tmux -L _bootstrap_tpm kill-server 2>/dev/null || true
fi

# Claude Code setup
echo "Setting up Claude Code..."
mkdir -p "$HOME/.claude/sessions"

# Link Claude status line script
backup_if_exists "$CONFIG_DIR/claude"
ln -sfn "$DOTFILES_DIR/config/claude" "$CONFIG_DIR/claude"

# Merge Claude settings (preserves existing settings, adds/updates our config).
# Hooks: Notification + Stop fire claude-notify.sh (macOS notif + tmux bell);
# muster adds SessionStart (auto-register on the bus) and a second Stop hook
# (self-resolving inbox) via bin/muster-session-hook.sh.
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
CLAUDE_HOOKS_BLOCK='{
  "Notification": [{"hooks":[{"type":"command","command":"~/.config/claude/claude-notify.sh"}]}],
  "Stop":         [{"hooks":[{"type":"command","command":"~/.config/claude/claude-notify.sh"},{"type":"command","command":"~/dotfiles/bin/muster-session-hook.sh Stop claude"}]}],
  "SessionStart": [{"matcher":"startup|resume","hooks":[{"type":"command","command":"~/dotfiles/bin/muster-session-hook.sh SessionStart claude"}]}]
}'

if [[ -f "$CLAUDE_SETTINGS" ]]; then
  echo "Updating Claude Code settings (statusline + hooks)..."
  if command -v jq &> /dev/null; then
    TEMP_FILE=$(mktemp)
    if jq --argjson hooks "$CLAUDE_HOOKS_BLOCK" '
      .statusLine = {
        "type": "command",
        "command": "~/.config/claude/statusline.sh"
      } |
      .permissions = (.permissions // {}) + {
        "allow": ((.permissions.allow // []) + ["Bash(*/.claude/sessions/*)"] | unique)
      } |
      .hooks = (.hooks // {}) + $hooks
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
      {"hooks": [{"type": "command", "command": "~/.config/claude/claude-notify.sh"}, {"type": "command", "command": "~/dotfiles/bin/muster-session-hook.sh Stop claude"}]}
    ],
    "SessionStart": [
      {"matcher": "startup|resume", "hooks": [{"type": "command", "command": "~/dotfiles/bin/muster-session-hook.sh SessionStart claude"}]}
    ]
  }
}
EOF
fi

# Codex session hooks: auto-register on the muster bus + self-resolving inbox, via
# bin/muster-session-hook.sh. Written with an absolute path (Codex hook commands
# don't reliably expand ~). Idempotent; Codex prompts once to trust the file
# (trust is by content-hash) on the next 'codex' launch.
if command -v codex &> /dev/null; then
  mkdir -p "$HOME/.codex"
  cat > "$HOME/.codex/hooks.json" <<EOF
{
  "hooks": {
    "SessionStart": [{"hooks":[{"type":"command","command":"$DOTFILES_DIR/bin/muster-session-hook.sh SessionStart codex"}]}],
    "Stop":         [{"hooks":[{"type":"command","command":"$DOTFILES_DIR/bin/muster-session-hook.sh Stop codex"}]}]
  }
}
EOF
  echo "Wrote Codex session hooks (~/.codex/hooks.json) — trust them on the next 'codex' launch."
fi

# Codex MCP bridge: register the OpenAI Codex CLI as an MCP server inside Claude
# Code (user scope), so Claude can delegate discrete coding tasks / second opinions
# to GPT via `codex mcp-server`. Runs on the ChatGPT subscription (`codex login`),
# not an API key. Idempotent — skip if codex is missing or already registered.
if command -v codex &> /dev/null && command -v claude &> /dev/null; then
  if claude mcp get codex &> /dev/null; then
    echo "Codex MCP bridge already registered — skipping."
  else
    echo "Registering Codex as an MCP server in Claude Code..."
    claude mcp add codex -s user -- codex mcp-server \
      || warn "Couldn't register Codex MCP server — run 'claude mcp add codex -s user -- codex mcp-server' by hand."
  fi
else
  echo "Skipping Codex MCP bridge (codex or claude not on PATH)."
fi

# Ensure the local bin dir exists before anything builds into it (muster,
# scratch, etc.) — on a fresh machine it may not exist yet.
mkdir -p "$HOME/.local/bin"

# muster: the local multi-agent coordination bus (github.com/schuettc/muster —
# a private Go project). Fully self-installing when Go is present:
#   clone (if missing) → build → LaunchAgent daemon → MCP registration.
# The session hooks (auto-register + self-resolving inbox) are wired above in
# the Claude/Codex settings merges; docs live in the muster repo's README.
MUSTER_REPO="$HOME/GitHub/schuettc/muster"
if command -v go &> /dev/null; then
  if [[ ! -d "$MUSTER_REPO" ]]; then
    echo "Cloning muster (private repo — needs GitHub SSH auth)..."
    mkdir -p "$(dirname "$MUSTER_REPO")"
    git clone git@github.com:schuettc/muster.git "$MUSTER_REPO" 2>/dev/null \
      || warn "muster clone failed (no SSH auth to github.com:schuettc/muster?) — clone it by hand and re-run."
  fi
fi
if [[ -d "$MUSTER_REPO" ]] && command -v go &> /dev/null; then
  echo "Building muster (coordination bus)..."
  # Build whatever branch the clone has checked out (dev during development).
  if CGO_ENABLED=0 go -C "$MUSTER_REPO" build -o "$HOME/.local/bin/muster" ./cmd/muster 2>/dev/null; then
    # ── Daemon via LaunchAgent ─────────────────────────────────────────
    # `muster serve` owns ~/.local/share/muster/{sock,bus.db}; everything
    # (MCP tools, CLI, session hooks) is dead without it, so it must be
    # supervised — KeepAlive restarts it on crash, RunAtLoad on login.
    # PATH matters: the daemon shells out to `tmux` for the 📬 wake, and
    # launchd's default PATH has no /opt/homebrew/bin — without it the bus
    # works but notifications silently never appear.
    MUSTER_PLIST="$HOME/Library/LaunchAgents/tools.muster.serve.plist"
    mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.local/share/muster"
    cat > "$MUSTER_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>tools.muster.serve</string>
  <key>ProgramArguments</key>
  <array>
    <string>$HOME/.local/bin/muster</string>
    <string>serve</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>/opt/homebrew/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>StandardOutPath</key><string>$HOME/.local/share/muster/serve.log</string>
  <key>StandardErrorPath</key><string>$HOME/.local/share/muster/serve.log</string>
</dict>
</plist>
EOF
    echo "Starting muster daemon (LaunchAgent)..."
    launchctl bootout "gui/$(id -u)/tools.muster.serve" 2>/dev/null || true
    pkill -f "$HOME/.local/bin/muster serve" 2>/dev/null || true   # reap any hand-started daemon holding the socket
    launchctl bootstrap "gui/$(id -u)" "$MUSTER_PLIST" 2>/dev/null \
      || warn "Couldn't bootstrap muster LaunchAgent — run: launchctl bootstrap gui/\$(id -u) $MUSTER_PLIST"
    # ── MCP registration (idempotent) ──────────────────────────────────
    command -v claude &> /dev/null && ! claude mcp get muster &> /dev/null \
      && { echo "Registering muster in Claude Code..."; claude mcp add muster -s user -- muster mcp || warn "Register muster in Claude by hand: claude mcp add muster -s user -- muster mcp"; }
    command -v codex &> /dev/null && ! codex mcp get muster &> /dev/null \
      && { echo "Registering muster in Codex..."; codex mcp add muster -- muster mcp || warn "Register muster in Codex by hand: codex mcp add muster -- muster mcp"; }
  else
    warn "muster build failed — build it by hand: (cd $MUSTER_REPO && go build -o ~/.local/bin/muster ./cmd/muster)"
  fi
else
  echo "Skipping muster (repo not cloned at $MUSTER_REPO, or Go not installed)."
fi

# scratch: the per-worktree markdown scratchpad TUI (github.com/schuettc/scratch,
# public). It is the top pane of every tmux workspace's right column (see
# config/zsh/04-aliases.zsh -> __proj_right_column). Install the published module
# into ~/.local/bin; if `go install` can't reach the network, fall back to
# building a local clone if one is present. Idempotent; skips if Go is absent.
if command -v go &> /dev/null; then
  echo "Installing scratch (notes pane)..."
  if ! GOBIN="$HOME/.local/bin" go install github.com/schuettc/scratch@latest 2>/dev/null; then
    SCRATCH_REPO="$HOME/GitHub/schuettc/scratch"
    if [[ -d "$SCRATCH_REPO" ]] && go -C "$SCRATCH_REPO" build -o "$HOME/.local/bin/scratch" . 2>/dev/null; then
      : # offline: built from the local clone
    else
      warn "scratch install failed — try: GOBIN=~/.local/bin go install github.com/schuettc/scratch@latest"
    fi
  fi
else
  echo "Skipping scratch (Go not installed)."
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
echo "  4b. Sign in to Codex (needs a ChatGPT subscription): codex login"
echo "      Verify with 'codex login status'; Claude Code reaches it via the codex MCP tool."
if [[ -n "$SWIFTBAR_A11Y_NOTE" ]]; then
  echo "  5. ⚠ MANUAL: $SWIFTBAR_A11Y_NOTE —"
  echo "     System Settings → Privacy & Security → Accessibility → enable SwiftBar,"
  echo "     then quit + reopen SwiftBar. (Can't be automated — macOS TCC is SIP-protected.)"
  echo "  6. Read docs/terminal-usage.md for the day-to-day cheat sheet."
else
  echo "  5. Read docs/terminal-usage.md for the day-to-day cheat sheet."
fi
echo ""
