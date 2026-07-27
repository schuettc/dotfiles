#!/bin/bash
PKG_DESC="Cursor Agent CLI (cursor-agent) — peer coding agent on the muster bus"
PKG_DEPS=(core)

pkg_install() {
  pkg_brew
  if command -v cursor-agent &> /dev/null || command -v agent &> /dev/null; then
    echo "Cursor Agent CLI present ($(command -v cursor-agent 2>/dev/null || command -v agent))."
  else
    warn "cursor-cli installed but cursor-agent/agent not on PATH — open a new shell or check brew link."
  fi
  echo "  ⚠ MANUAL: sign in with your Cursor subscription if prompted (agent / cursor-agent)."
}

pkg_verify() {
  local ok=0
  if command -v cursor-agent &> /dev/null || command -v agent &> /dev/null; then
    echo "  PASS cursor-agent CLI"
  else
    echo "  FAIL cursor-agent CLI"; ok=1
  fi
  return $ok
}
