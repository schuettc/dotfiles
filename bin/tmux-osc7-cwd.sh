#!/bin/bash
# Emit OSC 7 (current working directory) to a terminal device.
#
# tmux focus/attach hooks call this with the active pane's cwd and the
# outer client's tty. Writing OSC 7 straight to the OUTER terminal (Ghostty)
# tells it the focused pane's directory — even when that pane runs a process
# that never reports cwd itself (claude, yazi, vim). Without this, Ghostty's
# ⌘T "inherit working directory" falls back to a stale cwd, so a new tab can
# open in the wrong project.
#
# OSC 7 is consumed by the terminal (sets its cwd), never displayed — so this
# is invisible. Safe by construction: only writes to a real /dev tty.
#
# Usage (from a tmux hook):
#   tmux-osc7-cwd.sh "#{client_tty}" "#{pane_current_path}"

set -u

tty="${1:-}"
dir="${2:-}"

# Guard: only ever write to an actual terminal device. If tmux didn't expand
# #{client_tty} (no client in the hook's context) this won't match and we
# no-op, rather than creating a stray file.
case "$tty" in
  /dev/tty*) ;;
  *) exit 0 ;;
esac
[ -n "$dir" ] && [ -d "$dir" ] || exit 0

# OSC 7: ESC ] 7 ; file://HOST/PATH BEL. The hostname must match Ghostty's so
# it treats the path as local (and won't inherit a remote ssh cwd).
printf '\033]7;file://%s%s\007' "$(hostname)" "$dir" > "$tty" 2>/dev/null || true
