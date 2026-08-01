#!/bin/bash
PKG_DESC="Cursor Agent CLI (cursor-agent) — peer coding agent on the muster bus"
PKG_DEPS=(core)

pkg_install() {
  pkg_brew
  if command -v cursor-agent &> /dev/null || command -v agent &> /dev/null; then
    echo "Cursor Agent CLI present ($(command -v cursor-agent 2>/dev/null || command -v agent))."
    # Session identity: record which Cursor session owns this tmux session,
    # so sibling panes (scratch, status helpers) can scope themselves to the
    # conversation. Merged additively — muster wires its own hooks into the
    # same file.
    cursor_ensure_hook sessionStart "$HOME/dotfiles/bin/harness-session-stamp.sh" \
      && echo "Wired Cursor session-identity hook (~/.cursor/hooks.json)."
  else
    warn "cursor-cli installed but cursor-agent/agent not on PATH — open a new shell or check brew link."
  fi
  echo "  ⚠ MANUAL: sign in with your Cursor subscription if prompted (agent / cursor-agent)."
}

pkg_verify() {
  local ok=0
  if command -v cursor-agent &> /dev/null || command -v agent &> /dev/null; then
    echo "  PASS cursor-agent CLI"
    if command -v jq &> /dev/null; then
      jq -e --arg c "$HOME/dotfiles/bin/harness-session-stamp.sh" \
        '[.hooks.sessionStart[].command?] | index($c)' "$HOME/.cursor/hooks.json" > /dev/null 2>&1 \
        && echo "  PASS session-identity hook" || { echo "  FAIL session-identity hook"; ok=1; }
    fi
  else
    echo "  FAIL cursor-agent CLI"; ok=1
  fi
  return $ok
}
