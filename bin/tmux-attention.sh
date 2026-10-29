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

# The setting is the only opt-in boundary; missing/older proj stays normal.
themed=false
if proj theme --enabled --json 2>/dev/null | jq -e '.enabled == true' >/dev/null 2>&1; then
  themed=true
fi

text='#1e1e2e'; error='#f38ba8'
if $themed; then
  IFS='|' read -r text error < <(tmux display-message -p -t "${1:-}" '#{?@proj_theme_accent_text,#{@proj_theme_accent_text},default}|#{?@proj_theme_error,#{@proj_theme_error},default}' 2>/dev/null)
  text="${text:-default}"; error="${error:-default}"
fi
printf '#[fg=%s,bg=%s,bold] ⚠ %d: %s #[default] ' "$text" "$error" "$count" "$names"
