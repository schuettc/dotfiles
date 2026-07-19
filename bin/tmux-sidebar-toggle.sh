#!/bin/bash
# prefix f: toggle the WHOLE right column of the current window as one unit.
#
#   ON  -> OFF  Park the live agent panes — anything that is neither the main
#               pane nor a @sidebar pane — into a hidden holding window via
#               `break-pane -d` / `join-pane -d`, then kill the @sidebar panes.
#               The agents' processes keep running; the main pane goes full
#               width. Killing agent panes instead would kill the subagents,
#               so they are moved, never destroyed.
#   OFF -> ON   Rebuild scratch/yazi/shell via the canonical builder, then
#               `join-pane` the parked agents back below the shell in their
#               original top-to-bottom order. The holding window self-destructs
#               when its last pane leaves.
#
# The holding window is named `_sbhold` and is filtered out of the status bar
# by window-status-format in .tmux.conf — change both together.
#
# Re-entry lock: the rebuild is a ~1s staggered build (per-app terminal-probe
# focus dance). Without a guard, a rapid second `prefix f` would tear down the
# panes the rebuild is still creating (teardown races rebuild → column left
# collapsed). @sidebar_busy serializes toggles: a press while one is in progress
# is ignored. The trap clears it on exit even if a step fails.
#
# @agent_pin is suppressed for the whole toggle: its after-split-window hook
# re-pins {top-left} to 70% on every split/join we make, which crushes panes
# mid-operation. The trap restores the operator's prior setting (prefix P).
set -u
HOLD=_sbhold

[ "$(tmux show-option -gqv @sidebar_busy 2>/dev/null)" = 1 ] && exit 0
tmux set-option -g @sidebar_busy 1 2>/dev/null
prev_pin=$(tmux show-option -gqv @agent_pin 2>/dev/null)
tmux set-option -g @agent_pin 0 2>/dev/null
trap 'tmux set-option -g @agent_pin "${prev_pin:-1}" 2>/dev/null
      tmux set-option -g @sidebar_busy 0 2>/dev/null' EXIT

name=$(tmux display-message -p '#{session_name}')
dir=$(tmux display-message -p '#{pane_current_path}')

# Main (left) pane = leftmost column, tallest among ties. Robust to pane
# renumbering after kills, unlike `list-panes | head -1`.
main=$(tmux list-panes -F '#{pane_left} #{pane_height} #{pane_id}' \
       | sort -k1,1n -k2,2nr | head -1 | awk '{print $3}')
# Sidebar panes, top to bottom.
tagged=$(tmux list-panes -F '#{pane_top} #{pane_id} #{?@sidebar,1,0}' \
         | awk '$3==1' | sort -k1,1n | awk '{print $2}')
hold_win() {
  tmux list-windows -F '#{window_id} #{window_name}' 2>/dev/null \
    | awk -v n="$HOLD" '$2==n {print $1; exit}'
}

if [ -n "$tagged" ]; then
  # ---------------------------- collapse ----------------------------
  # Park agents top-to-bottom so their order survives the round trip.
  agents=$(tmux list-panes -F '#{pane_top} #{pane_id} #{?@sidebar,1,0}' \
           | awk -v m="$main" '$2!=m && $3==0' | sort -k1,1n | awk '{print $2}')
  for p in $agents; do
    w=$(hold_win)
    if [ -z "$w" ]; then
      tmux break-pane -d -s "$p" -n "$HOLD" 2>/dev/null
    else
      last=$(tmux list-panes -t "$w" -F '#{pane_top} #{pane_id}' \
             | sort -k1,1n | tail -1 | awk '{print $2}')
      tmux join-pane -d -s "$p" -t "$last" -v 2>/dev/null
    fi
  done
  for p in $tagged; do tmux kill-pane -t "$p" 2>/dev/null; done
  tmux select-pane -t "$main" 2>/dev/null
else
  # ---------------------------- restore -----------------------------
  "$HOME/dotfiles/bin/proj-right-column.sh" - "$name" "$dir" fg
  w=$(hold_win)
  if [ -n "$w" ]; then
    # The freshly built column leaves yazi filling everything, so a returning
    # agent has no rows to take and join-pane fails. Reserve room up front:
    # shrink yazi by exactly what the parked panes need, which hands those rows
    # to the shell below it; each join then takes its share back off the shell,
    # landing the shell at its original height.
    per=$(tmux show-option -gqv @sidebar_agent_rows 2>/dev/null); per=${per:-8}
    keep=$(tmux show-option -gqv @sidebar_yazi_min 2>/dev/null); keep=${keep:-6}
    parked=$(tmux list-panes -t "$w" -F '#{pane_top} #{pane_id}' | sort -k1,1n | awk '{print $2}')
    n=$(printf '%s\n' "$parked" | grep -c .)
    # yazi = the tallest sidebar pane (it is the one that fills the remainder).
    mid=$(tmux list-panes -F '#{pane_height} #{pane_id} #{?@sidebar,1,0}' \
          | awk '$3==1' | sort -k1,1nr | head -1 | awk '{print $2}')
    if [ -n "$mid" ] && [ "$n" -gt 0 ]; then
      yh=$(tmux display-message -p -t "$mid" '#{pane_height}')
      need=$((n * per)); avail=$((yh - keep))
      [ "$avail" -lt 0 ] && avail=0
      shrink=$need; [ "$shrink" -gt "$avail" ] && shrink=$avail
      [ "$shrink" -gt 0 ] && tmux resize-pane -t "$mid" -y $((yh - shrink)) 2>/dev/null
    fi
    # Join in REVERSE order, always against the shell: each new pane lands
    # directly below the shell and pushes the previous ones down, so the
    # original top-to-bottom order is what ends up on screen. (Chaining off the
    # previous agent instead would fail — it only has `per` rows to give.)
    shell=$(tmux list-panes -F '#{pane_top} #{pane_id} #{?@sidebar,1,0}' \
            | awk '$3==1' | sort -k1,1n | tail -1 | awk '{print $2}')
    if [ -n "$shell" ]; then
      stuck=0
      for p in $(printf '%s\n' "$parked" | sed '1!G;h;$!d'); do
        tmux join-pane -d -l "$per" -s "$p" -t "$shell" -v 2>/dev/null \
          || tmux join-pane -d -s "$p" -t "$shell" -v 2>/dev/null \
          || stuck=$((stuck + 1))
      done
      # A join fails when the column has no rows left. Those panes stay parked
      # (processes alive) rather than being lost — say so instead of failing mute.
      [ "$stuck" -gt 0 ] && tmux display-message \
        "sidebar: $stuck agent pane(s) still parked in $HOLD — no room in column"
    fi
  fi
  # Re-assert the pin geometry now that the column is whole again.
  if [ "${prev_pin:-1}" = 1 ] && [ "$(tmux display-message -p '#{window_panes}')" -ge 3 ]; then
    tmux resize-pane -t "$main" -x 70% 2>/dev/null
  fi
  tmux select-pane -t "$main" 2>/dev/null
fi
