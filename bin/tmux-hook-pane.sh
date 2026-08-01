#!/bin/bash
# Resolve which tmux pane a coding-agent hook belongs to.
#
# Agent harnesses (Claude Code, Codex, Cursor) run hooks in a STRIPPED
# environment: $TMUX and $TMUX_PANE are unset even when the session was
# launched from a pane. The pane is still an ancestor of the hook process
# though — hook → agent → pane shell — so we walk the parent chain until a
# PID matches some pane's #{pane_pid}.
#
# Usage:  tmux-hook-pane.sh [start-pid]      (default: this script's own PID)
# Output: one tab-separated line on success —
#           <socket>\t<session_name>\t<pane_id>\t<pane_tty>
#         nothing, exit 1, when no pane owns this process.
#
# EVERY socket is searched, not just the default one. Each project gets its
# own tmux server ("proj-<project>", see 04-aliases.zsh), and with $TMUX
# unset a bare `tmux list-panes -a` talks to a "default" socket that on this
# setup does not exist — it fails with "error connecting to …/default" and
# finds nothing at all. A single-socket lookup is therefore not a partial
# answer here, it is always an empty one.
#
# Callers must run SYNCHRONOUSLY. Backgrounding a hook reparents it away
# from the agent and the ancestry is lost.
#
# Fails closed on purpose: no match means no output and a non-zero exit,
# never a guess. Consumers act on the exact pane or not at all — targeting
# the wrong pane (or every pane in the same directory) is worse than
# doing nothing.

set -u

start_pid="${1:-$$}"

command -v tmux >/dev/null 2>&1 || exit 1

sock_dir="${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)"
[ -d "$sock_dir" ] || exit 1

# Snapshot every pane on every live server once, tagged with its socket.
# Dead sockets (server already exited) just fail the query and are skipped.
panes=""
for sock_path in "$sock_dir"/*; do
  [ -S "$sock_path" ] || continue
  sock="${sock_path##*/}"
  out=$(tmux -L "$sock" list-panes -aF \
    "${sock}"$'\t''#{pane_pid}'$'\t''#{session_name}'$'\t''#{pane_id}'$'\t''#{pane_tty}' 2>/dev/null) || continue
  [ -n "$out" ] && panes="${panes}${out}"$'\n'
done
[ -n "$panes" ] || exit 1

# Walk outward from start_pid; first match wins. The guard bounds the climb
# in case ps ever returns something cyclic.
pid="$start_pid"
guard=0
while [ -n "$pid" ] && [ "$pid" != "0" ] && [ "$pid" != "1" ] && [ "$guard" -lt 30 ]; do
  # #{pane_pid} is field 2 — it exists only to match against and is dropped
  # from the output, which is the 4 fields this script documents.
  line=$(printf '%s\n' "$panes" | awk -F'\t' -v p="$pid" \
    '$2==p { print $1 "\t" $3 "\t" $4 "\t" $5; exit }')
  if [ -n "$line" ]; then
    printf '%s\n' "$line"
    exit 0
  fi
  pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
  guard=$((guard + 1))
done

exit 1
