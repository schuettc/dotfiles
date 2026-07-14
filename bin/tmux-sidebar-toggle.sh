#!/bin/bash
# prefix f: toggle the right column (panes tagged @sidebar) in the current
# window. If any tagged panes exist, kill them; otherwise rebuild the column
# via the canonical builder. Run from inside tmux (run-shell), so plain `tmux`
# targets the current server; the builder is called with server "-" (current).
#
# Re-entry lock: the rebuild is a ~1s staggered build (per-app terminal-probe
# focus dance). Without a guard, a rapid second `prefix f` would tear down the
# panes the rebuild is still creating (teardown races rebuild → column left
# collapsed). @sidebar_busy serializes toggles: a press while one is in progress
# is ignored. The trap clears it on exit even if a step fails. The rebuild is
# run in "fg" (synchronous) mode so this script holds the lock for its full
# duration; the `bind` uses `run-shell -b` so the server never blocks meanwhile.
set -u
[ "$(tmux show-option -gqv @sidebar_busy 2>/dev/null)" = 1 ] && exit 0
tmux set-option -g @sidebar_busy 1 2>/dev/null
trap 'tmux set-option -g @sidebar_busy 0 2>/dev/null' EXIT

name=$(tmux display-message -p '#{session_name}')
dir=$(tmux display-message -p '#{pane_current_path}')
tagged=$(tmux list-panes -F '#{pane_id} #{@sidebar}' | awk '$2==1 {print $1}')
if [ -n "$tagged" ]; then
  for p in $tagged; do tmux kill-pane -t "$p" 2>/dev/null; done
else
  "$HOME/dotfiles/bin/proj-right-column.sh" - "$name" "$dir" fg
fi
