#!/bin/bash
PKG_DESC="OpenAI Codex CLI (GPT agent, ChatGPT-subscription billed) + MCP bridge into Claude Code"
PKG_DEPS=(core)

pkg_install() {
  pkg_brew
  # Bridge is an integration, not a dep: register in Claude iff claude exists.
  if command -v codex &> /dev/null && command -v claude &> /dev/null; then
    if claude mcp get codex &> /dev/null; then
      echo "Codex MCP bridge already registered — skipping."
    else
      echo "Registering Codex as an MCP server in Claude Code..."
      claude mcp add codex -s user -- codex mcp-server \
        || warn "Couldn't register Codex MCP server — run 'claude mcp add codex -s user -- codex mcp-server' by hand."
    fi
  elif ! command -v codex &> /dev/null; then
    echo "Skipped Claude bridge (codex not installed)."
  else
    echo "Skipped Claude bridge (claude CLI not present)."
  fi
  echo "  ⚠ MANUAL: sign in with 'codex login' (ChatGPT subscription); verify: codex login status"
}

pkg_verify() {
  local ok=0
  command -v codex &> /dev/null && echo "  PASS codex CLI" || { echo "  FAIL codex CLI"; ok=1; }
  if command -v claude &> /dev/null; then
    claude mcp get codex &> /dev/null && echo "  PASS claude bridge" || { echo "  FAIL claude bridge"; ok=1; }
  fi
  return $ok
}
