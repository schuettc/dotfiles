#!/bin/bash
# prefix f: toggle the right column (panes tagged @sidebar) in the current
# window. If any tagged panes exist, kill them; otherwise rebuild the column
# via the canonical builder. Run from inside tmux (run-shell), so plain `tmux`
# targets the current server; the builder is called with server "-" (current).
set -u
name=$(tmux display-message -p '#{session_name}')
dir=$(tmux display-message -p '#{pane_current_path}')
tagged=$(tmux list-panes -F '#{pane_id} #{@sidebar}' | awk '$2==1 {print $1}')
if [ -n "$tagged" ]; then
  for p in $tagged; do tmux kill-pane -t "$p" 2>/dev/null; done
else
  "$HOME/dotfiles/bin/proj-right-column.sh" - "$name" "$dir"
fi
