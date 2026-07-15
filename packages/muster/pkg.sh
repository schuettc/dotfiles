#!/bin/bash
PKG_DESC="muster: cross-terminal agent coordination bus (daemon via LaunchAgent, MCP in Claude/Codex, session hooks)"
PKG_DEPS=(terminal)

pkg_install() {
  pkg_brew

  # muster: the local multi-agent coordination bus (github.com/schuettc/muster —
  # a public Go project). Fully self-installing when Go is present:
  #   clone (if missing) → build → LaunchAgent daemon → MCP registration.
  # The session hooks (auto-register + self-resolving inbox) are wired below in
  # the Claude/Codex settings merges; docs live in the muster repo's README.
  MUSTER_REPO="$HOME/GitHub/schuettc/muster"
  if command -v go &> /dev/null; then
    if [[ ! -d "$MUSTER_REPO" ]]; then
      echo "Cloning muster (public repo)..."
      mkdir -p "$(dirname "$MUSTER_REPO")"
      git clone https://github.com/schuettc/muster.git "$MUSTER_REPO" 2>/dev/null \
        || warn "muster clone failed — clone it by hand and re-run."
    fi
  fi
  if [[ -d "$MUSTER_REPO" ]] && command -v go &> /dev/null; then
    echo "Building muster (coordination bus)..."
    # Build the RELEASED code (origin/main) via a detached temp worktree —
    # NEVER the clone's checked-out branch. A stale local dev checkout once
    # silently DOWNGRADED the live binary below what the installed session
    # hooks require (`muster hook` shipped in v0.3.0), erroring every
    # session's Stop hook. The clone's branch state is never touched.
    git -C "$MUSTER_REPO" fetch origin main --quiet 2>/dev/null || true
    local build_src; build_src="$(mktemp -d)/muster-main"
    if git -C "$MUSTER_REPO" worktree add --detach "$build_src" origin/main 2>/dev/null >/dev/null \
       && CGO_ENABLED=0 go -C "$build_src" build -o "$HOME/.local/bin/muster" ./cmd/muster 2>/dev/null \
       && { git -C "$MUSTER_REPO" worktree remove --force "$build_src" 2>/dev/null || true; }; then
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
      git -C "$MUSTER_REPO" worktree remove --force "$build_src" 2>/dev/null || true
      warn "muster build failed — build it by hand: (git -C $MUSTER_REPO worktree add --detach /tmp/m origin/main && go -C /tmp/m build -o ~/.local/bin/muster ./cmd/muster)"
    fi
  else
    echo "Skipping muster (repo not cloned at $MUSTER_REPO, or Go not installed)."
  fi

  # Claude session hooks: auto-register on the muster bus + self-resolving
  # inbox, via the muster binary itself (v0.3.0 `muster hook`; the old
  # bin/muster-session-hook.sh is retired — its behavior was ported into the
  # binary, reference copy in muster's contrib/). Additive merge — set/ensure
  # our hook entries WITHOUT touching entries owned by other packages
  # (claude). The migrate step strips any legacy script entries first, so
  # existing machines converge to the binary hooks on re-run.
  local settings="$HOME/.claude/settings.json"
  if command -v claude &> /dev/null && command -v jq &> /dev/null; then
    [[ -f "$settings" ]] || echo '{}' > "$settings"
    local tmp; tmp=$(mktemp)
    if jq '
      def ensure_hook(ev; cmd; entry):
        .hooks[ev] = ((.hooks[ev] // [])
          | if ([.[].hooks[]?.command] | index(cmd)) then . else . + [entry] end);
      (.hooks // {}) |= with_entries(.value |= (
        map(.hooks |= map(select(.command // "" | contains("muster-session-hook.sh") | not)))
        | map(select((.hooks | length) > 0))))
      | ensure_hook("Stop"; "~/.local/bin/muster hook Stop claude";
        {"hooks":[{"type":"command","command":"~/.local/bin/muster hook Stop claude"}]})
      | ensure_hook("SessionStart"; "~/.local/bin/muster hook SessionStart claude";
        {"matcher":"startup|resume","hooks":[{"type":"command","command":"~/.local/bin/muster hook SessionStart claude"}]})
      | ensure_hook("SessionEnd"; "~/.local/bin/muster hook SessionEnd claude";
        {"hooks":[{"type":"command","command":"~/.local/bin/muster hook SessionEnd claude"}]})
    ' "$settings" > "$tmp"; then mv "$tmp" "$settings"
    else rm -f "$tmp"; warn "muster: Claude hooks merge failed — settings.json untouched."; fi
  fi

  # Codex session hooks: auto-register on the muster bus + self-resolving
  # inbox, via `muster hook` (v0.3.0 binary-native). Written with an absolute
  # path (Codex hook commands don't reliably expand ~). Idempotent; Codex
  # prompts once to trust the file (trust is by content-hash) on the next
  # 'codex' launch.
  if command -v codex &> /dev/null; then
    mkdir -p "$HOME/.codex"
    cat > "$HOME/.codex/hooks.json" <<EOF
{
  "hooks": {
    "SessionStart": [{"hooks":[{"type":"command","command":"$HOME/.local/bin/muster hook SessionStart codex"}]}],
    "Stop":         [{"hooks":[{"type":"command","command":"$HOME/.local/bin/muster hook Stop codex"}]}]
  }
}
EOF
    echo "Wrote Codex session hooks (~/.codex/hooks.json) — trust them on the next 'codex' launch."
  fi
}

pkg_verify() {
  local ok=0 s="$HOME/.claude/settings.json"
  [[ -x "$HOME/.local/bin/muster" ]] && echo "  PASS muster binary" || { echo "  FAIL muster binary"; ok=1; }
  # Capability, not just existence: the session hooks call `muster hook`
  # (v0.3.0+). A downgraded binary passes an existence check while every
  # session's Stop hook errors — that exact regression happened once.
  "$HOME/.local/bin/muster" 2>&1 | head -1 | grep -q "hook" \
    && echo "  PASS hook subcommand" || { echo "  FAIL hook subcommand (binary too old for installed hooks)"; ok=1; }
  launchctl print "gui/$(id -u)/tools.muster.serve" 2>/dev/null | grep -q "state = running" \
    && echo "  PASS daemon running" || { echo "  FAIL daemon running"; ok=1; }
  [[ -S "$HOME/.local/share/muster/sock" ]] && echo "  PASS socket present" || { echo "  FAIL socket present"; ok=1; }
  if command -v claude &> /dev/null; then
    claude mcp get muster &> /dev/null && echo "  PASS claude MCP registered" || { echo "  FAIL claude MCP registered"; ok=1; }
  fi
  jq -e '[.hooks.Stop[].hooks[]?.command] | index("~/.local/bin/muster hook Stop claude")' "$s" >/dev/null 2>&1 \
    && echo "  PASS Stop hook wired" || { echo "  FAIL Stop hook wired"; ok=1; }
  return $ok
}
