#!/bin/bash
# Bright "needs attention" banner for tmux status-left.
#
# Lists every session that has a window with a pending bell flag — i.e.
# a Claude pane rang the bell (turn finished / waiting for input) and you
# haven't visited it yet. tmux clears window_bell_flag automatically when
# you switch to that window, so the banner disappears once you've looked.
#
# Sessions never attached (session_last_attached empty) are skipped: diazo
# starts a pi session per plan that is worked on its page, not in tmux, and
# proj lists those under "not opened" instead.
#
# Output: "⚠ 2: now-playing, mlb-dk " on a peach background, or nothing
# when no session needs attention.

set -u

# session names with at least one bell-flagged window, attached at least once, deduped
sessions=$(
  tmux list-windows -a -F '#{session_name} #{window_bell_flag} #{session_last_attached}' 2>/dev/null \
    | awk '$2 == 1 && $3 != "" { print $1 }' \
    | sort -u
)
[[ -z "$sessions" ]] && exit 0

count=$(printf '%s\n' "$sessions" | grep -c .)
names=$(printf '%s' "$sessions" | paste -sd ',' - | sed 's/,/, /g')

printf '#[fg=#1e1e2e,bg=#f38ba8,bold] ⚠ %d: %s #[default] ' "$count" "$names"
