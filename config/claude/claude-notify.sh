#!/bin/bash
# Claude Code hook dispatcher — rings the tmux bell for the exact Claude
# pane so the status-left attention banner (bin/tmux-attention.sh), the
# tmux window indicator, and Ghostty's tab 🔔 / border light up.
#
# Hooks wired (see ~/.claude/settings.json), run SYNCHRONOUSLY:
#   Notification → Claude is waiting for input
#   Stop         → Claude finished a turn
# Both just ring the bell. No macOS notification, no Dock bounce.
#
# Claude Code runs hooks in a STRIPPED environment ($TMUX / $TMUX_PANE are
# unset), so we can't target the pane via env. bin/tmux-hook-pane.sh walks
# this hook's process ancestry (hook → claude → pane shell) until a PID
# matches a tmux pane's #{pane_pid}. Running the hook synchronously (not
# async) keeps the ancestry intact — async reparents the hook and the walk
# fails. No cwd fallback: ringing the wrong/too-many panes (every same-dir
# session) is worse than ringing none.
#
# That walk used to live here and searched only the default socket, which
# silently stopped finding anything once every project got its own tmux
# server ("proj-<project>"): with $TMUX unset, a bare `tmux list-panes -a`
# fails with "error connecting to …/default" and the bell never rang. The
# shared helper searches every socket.

set -u

input=$(cat)
hook_name=$(printf '%s' "$input" | jq -r '.hook_event_name // .hook_name // ""' 2>/dev/null || echo "")

ring_tmux_bell() {
  local pane_line tty
  pane_line=$("$HOME/dotfiles/bin/tmux-hook-pane.sh" "$$" 2>/dev/null) || return 0
  tty=$(printf '%s' "$pane_line" | cut -f4)
  [[ -n "$tty" ]] || return 0
  printf '\a' >> "$tty" 2>/dev/null || true
  return 0
}

case "$hook_name" in
  Notification)
    # Claude is blocked waiting for you → ring the in-terminal bell AND raise the
    # cross-session attention flag: 🔔 in the Ghostty title / Dock menu (via
    # set-titles-string) + the SwiftBar menu-bar item. `raise-pid` walks this
    # hook's process ancestry to find its pane's session, since hooks run with
    # $TMUX unset. Cleared automatically when you switch to that session.
    ring_tmux_bell
    "$HOME/.local/bin/claude-attn" raise-pid "$$" 2>/dev/null || true
    ;;
  Stop)
    # Turn finished → in-terminal bell only. No attention flag: with many
    # parallel sessions, flagging every turn-end would keep half of them lit.
    # (Deliberately NO auto-clear here either: an autonomous turn completing —
    # e.g. a muster drain — would falsely clear a bell the operator never saw.
    # Focus is the one true clear signal; see the client-focus-in hook.)
    ring_tmux_bell
    ;;
esac

exit 0
