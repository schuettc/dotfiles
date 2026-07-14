#!/bin/bash
# Build the standard right column for a session whose only pane is the main
# (left) pane:  scratch (top, ~12 rows) -> yazi (middle) -> shell (bottom,
# ~10 rows).  Each pane is tagged `@sidebar 1` so tmux-sidebar-toggle.sh
# (prefix f) can toggle the column by tag regardless of what runs in it.
#
# scratch AND yazi both probe the terminal at startup (bg-color / cursor pos);
# tmux delivers the responses to the FOCUSED pane, so each must be focused while
# it probes or the responses leak as escape-code garbage.  The column is built
# in a detached, staggered job: create each probing app focused, give it ~0.5s
# to read its responses, then move on; finally return focus to the main pane.
# Detached so it never blocks the caller's `exec tmux attach`.
#
# Usage: proj-right-column.sh <server|-> <session> <dir>
#   server "-" means "the current server" (used from inside tmux, e.g. prefix f).
set -u
srv="${1:?server}"; name="${2:?session}"; dir="${3:?dir}"
tm() { if [ "$srv" = "-" ]; then tmux "$@"; else tmux -L "$srv" "$@"; fi; }

left=$(tm list-panes -t "$name" -F '#{pane_id}' 2>/dev/null | head -1)
[ -n "$left" ] || exit 0

(
  right=$(tm split-window -h -l 30% -t "$left" -c "$dir" -P -F '#{pane_id}' scratch 2>/dev/null) || exit 0
  tm set-option -p -t "$right" @sidebar 1 2>/dev/null
  sleep 0.5                                   # scratch reads its probe while focused
  mid=$(tm split-window -v -t "$right" -c "$dir" -P -F '#{pane_id}' yazi 2>/dev/null) || exit 0
  tm set-option -p -t "$mid" @sidebar 1 2>/dev/null
  sleep 0.5                                   # yazi reads its probe while focused
  bottom=$(tm split-window -v -l 10 -t "$mid" -c "$dir" -P -F '#{pane_id}' 2>/dev/null) || exit 0
  tm set-option -p -t "$bottom" @sidebar 1 2>/dev/null
  tm resize-pane -t "$right" -y 12 2>/dev/null
  tm select-pane -t "$left" 2>/dev/null
) &
