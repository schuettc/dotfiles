#!/bin/bash
PKG_DESC="Claude Code integration: tmux-aware statusline, attention-bell hooks, claude-attn CLI"
PKG_DEPS=(core)   # terminal recommended (bells/status need tmux) but not required

pkg_install() {
  pkg_brew
  echo "Setting up Claude Code..."
  mkdir -p "$HOME/.claude/sessions"
  backup_if_exists "$CONFIG_DIR/claude"
  ln -sfn "$DOTFILES_DIR/config/claude" "$CONFIG_DIR/claude"
  mkdir -p "$HOME/.local/bin"
  ln -sf "$DOTFILES_DIR/bin/claude-attn" "$HOME/.local/bin/claude-attn"

  local settings="$HOME/.claude/settings.json"
  [[ -f "$settings" ]] || echo '{}' > "$settings"
  if command -v jq &> /dev/null; then
    local tmp; tmp=$(mktemp)
    # Additive merge: set statusline/permissions; ensure our hook entries
    # exist WITHOUT touching entries owned by other packages (muster).
    if jq '
      def ensure_hook(ev; cmd):
        .hooks[ev] = ((.hooks[ev] // [])
          | if ([.[].hooks[]?.command] | index(cmd)) then .
            else . + [{"hooks":[{"type":"command","command":cmd}]}] end);
      .statusLine = {"type":"command","command":"~/.config/claude/statusline.sh"}
      | .permissions = ((.permissions // {}) + {"allow": (((.permissions.allow // []) + ["Bash(*/.claude/sessions/*)"]) | unique)})
      | ensure_hook("Notification"; "~/.config/claude/claude-notify.sh")
      | ensure_hook("Stop"; "~/.config/claude/claude-notify.sh")
      | ensure_hook("Stop"; "~/.config/claude/claude-teammate-idle.sh")
    ' "$settings" > "$tmp"; then
      mv "$tmp" "$settings"
    else
      rm -f "$tmp"; warn "Couldn't merge Claude settings (jq error) — ~/.claude/settings.json untouched."
    fi
  else
    warn "jq missing — merge Claude statusline/hooks into ~/.claude/settings.json by hand."
  fi
}

pkg_verify() {
  local ok=0 s="$HOME/.claude/settings.json"
  [[ "$(readlink "$CONFIG_DIR/claude")" == "$DOTFILES_DIR/config/claude" ]] \
    && echo "  PASS ~/.config/claude -> repo" || { echo "  FAIL config link"; ok=1; }
  [[ -x "$HOME/.local/bin/claude-attn" ]] && echo "  PASS claude-attn" || { echo "  FAIL claude-attn"; ok=1; }
  jq -e '.statusLine.command == "~/.config/claude/statusline.sh"' "$s" >/dev/null 2>&1 \
    && echo "  PASS statusline wired" || { echo "  FAIL statusline"; ok=1; }
  jq -e '[.hooks.Stop[].hooks[]?.command] | index("~/.config/claude/claude-notify.sh")' "$s" >/dev/null 2>&1 \
    && echo "  PASS notify hooks" || { echo "  FAIL notify hooks"; ok=1; }
  jq -e '[.hooks.Stop[].hooks[]?.command] | index("~/.config/claude/claude-teammate-idle.sh")' "$s" >/dev/null 2>&1 \
    && echo "  PASS teammate-idle hook" || { echo "  FAIL teammate-idle hook"; ok=1; }
  return $ok
}
