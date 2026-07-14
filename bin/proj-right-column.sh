#!/bin/bash
# Build the standard right column for a session whose only pane is the main
# (left) pane:  scratch (top, ~12 rows) -> yazi (middle) -> shell (bottom,
# ~10 rows).  Each pane is tagged `@sidebar 1` so tmux-sidebar-toggle.sh
# (prefix f) can toggle the column by tag regardless of what runs in it.
#
# scratch AND yazi both probe the terminal at startup (bg-color / cursor pos);
# tmux delivers the responses to the FOCUSED pane, so each must be focused while
# it probes or the responses leak as escape-code garbage.  The column is built
# as a staggered job: create each probing app focused, give it ~0.5s to read its
# responses, then move on; finally return focus to the main pane.
#
# Usage: proj-right-column.sh <server|-> <session> <dir> [bg|fg]
#   server "-" means "the current server" (used from inside tmux, e.g. prefix f).
#   mode "bg" (default) forks the build so it survives the caller's
#        `exec tmux attach` — the proj / pt / auto-join launch path.
#   mode "fg" runs the build synchronously so the caller can hold a re-entry
#        lock across the whole rebuild — the prefix f toggle. This is what stops
#        a rapid second toggle from racing (tearing down) an in-flight rebuild.
set -u
srv="${1:?server}"; name="${2:?session}"; dir="${3:?dir}"; mode="${4:-bg}"
tm() { if [ "$srv" = "-" ]; then tmux "$@"; else tmux -L "$srv" "$@"; fi; }

left=$(tm list-panes -t "$name" -F '#{pane_id}' 2>/dev/null | head -1)
[ -n "$left" ] || exit 0

build() {
  local right mid bottom
  right=$(tm split-window -h -l 30% -t "$left" -c "$dir" -P -F '#{pane_id}' scratch 2>/dev/null) || return 0
  tm set-option -p -t "$right" @sidebar 1 2>/dev/null
  sleep 0.5                                   # scratch reads its probe while focused
  mid=$(tm split-window -v -t "$right" -c "$dir" -P -F '#{pane_id}' yazi 2>/dev/null) || return 0
  tm set-option -p -t "$mid" @sidebar 1 2>/dev/null
  sleep 0.5                                   # yazi reads its probe while focused
  bottom=$(tm split-window -v -l 10 -t "$mid" -c "$dir" -P -F '#{pane_id}' 2>/dev/null) || return 0
  tm set-option -p -t "$bottom" @sidebar 1 2>/dev/null
  tm resize-pane -t "$right" -y 12 2>/dev/null
  tm select-pane -t "$left" 2>/dev/null
}

if [ "$mode" = fg ]; then build; else build & fi
