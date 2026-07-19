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

# Main (left) pane = leftmost column, and among ties the tallest — robust to
# whatever agent panes exist to its right. (list-panes|head -1 would break once
# pane indices renumber after kills.)
left=$(tm list-panes -t "$name" -F '#{pane_left} #{pane_height} #{pane_id}' 2>/dev/null \
       | sort -k1,1n -k2,2nr | head -1 | awk '{print $3}')
[ -n "$left" ] || exit 0

build() {
  local right mid bottom anchor
  # anchor = topmost non-main, non-sidebar pane already in the window, i.e. the
  # top of the agent column left behind when the sidebar was toggled off while
  # Claude's --tmux subagents were running.
  anchor=$(tm list-panes -F '#{pane_id} #{pane_top} #{pane_left} #{?@sidebar,1,0}' 2>/dev/null \
           | awk -v m="$left" '$1!=m && $4==0' | sort -k2,2n -k3,3n | head -1 | awk '{print $1}')
  if [ -n "$anchor" ]; then
    # Agents occupy the right column. Insert the scratch → yazi → shell stack
    # ABOVE them, in-column (-b), so the column stays one 30%-wide unit
    # (scratch → yazi → shell → agents) instead of wedging a 1-col sliver
    # beside the main pane. Width is inherited from the agent column, so no
    # -l here; the agent-pin re-assert at the end restores main to 70%.
    right=$(tm split-window -v -b -t "$anchor" -c "$dir" -P -F '#{pane_id}' scratch 2>/dev/null) || return 0
    tm set-option -p -t "$right" @sidebar 1 2>/dev/null
    sleep 0.5                                 # scratch reads its probe while focused
    mid=$(tm split-window -v -t "$right" -c "$dir" -P -F '#{pane_id}' yazi 2>/dev/null) || return 0
    tm set-option -p -t "$mid" @sidebar 1 2>/dev/null
    sleep 0.5                                 # yazi reads its probe while focused
    bottom=$(tm split-window -v -t "$mid" -c "$dir" -P -F '#{pane_id}' 2>/dev/null) || return 0
    tm set-option -p -t "$bottom" @sidebar 1 2>/dev/null
    tm resize-pane -t "$bottom" -y 10 2>/dev/null
    tm resize-pane -t "$right" -y 12 2>/dev/null
  else
    # No foreign panes: main is the only pane. Split the 30% column off the right.
    right=$(tm split-window -h -l 30% -t "$left" -c "$dir" -P -F '#{pane_id}' scratch 2>/dev/null) || return 0
    tm set-option -p -t "$right" @sidebar 1 2>/dev/null
    sleep 0.5                                 # scratch reads its probe while focused
    mid=$(tm split-window -v -t "$right" -c "$dir" -P -F '#{pane_id}' yazi 2>/dev/null) || return 0
    tm set-option -p -t "$mid" @sidebar 1 2>/dev/null
    sleep 0.5                                 # yazi reads its probe while focused
    bottom=$(tm split-window -v -l 10 -t "$mid" -c "$dir" -P -F '#{pane_id}' 2>/dev/null) || return 0
    tm set-option -p -t "$bottom" @sidebar 1 2>/dev/null
    tm resize-pane -t "$right" -y 12 2>/dev/null
  fi
}

# Suppress the agent-pin hook for the duration of the build: its
# `after-split-window → resize {top-left} -x 70%` fires on every split we make
# and, with agents in the right column, crushes the fresh sidebar panes to 1
# column. We restore the operator's prior pin state and re-assert main's 70%
# once, after the build, so the final geometry is deterministic.
run() {
  local prev_pin
  prev_pin=$(tm show-option -gqv @agent_pin 2>/dev/null)
  tm set-option -g @agent_pin 0 2>/dev/null
  build
  tm set-option -g @agent_pin "${prev_pin:-1}" 2>/dev/null
  if [ "${prev_pin:-1}" = 1 ] && [ "$(tm display-message -p '#{window_panes}' 2>/dev/null)" -ge 3 ]; then
    tm resize-pane -t "$left" -x 70% 2>/dev/null
  fi
  tm select-pane -t "$left" 2>/dev/null
}

if [ "$mode" = fg ]; then run; else run & fi
