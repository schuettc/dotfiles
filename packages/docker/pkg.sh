#!/bin/bash
# docker — Docker Desktop (opt-in: not run by install.sh; use packages/run.sh docker
# or the install wizard). Sourced by packages/lib.sh's run_pkg.

PKG_DESC="Docker Desktop (opt-in — not part of the full install)"
PKG_DEPS=(core)

pkg_install() {
  pkg_brew
}

pkg_verify() {
  local ok=0
  [[ -d "/Applications/Docker.app" ]] \
    && echo "  PASS Docker Desktop" || { echo "  FAIL Docker Desktop missing"; ok=1; }
  return $ok
}
