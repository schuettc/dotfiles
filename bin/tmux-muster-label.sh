#!/bin/bash
# prefix T handler: run `muster label` with the tmux context run-shell drops.
#
# tmux run-shell children inherit $TMUX but NOT $TMUX_PANE, and muster's
# ambient tmux calls resolve the current session through the pane — without
# this shim the label half-writes against whatever session tmux guesses.
# $1 is #{pane_id}, expanded by the binding at press time; $2 is the label
# (empty = clear). Output goes to a status-line display-message: run-shell
# opens a full-screen view for ANY stdout, which reads as an error screen
# instead of feedback.
export TMUX_PANE="$1"
shift
if out=$("$HOME/.local/bin/muster" label "$@" 2>&1); then
  tmux display-message "muster: ${out//$'\n'/ · }"
else
  tmux display-message "muster label FAILED: ${out//$'\n'/ · }"
fi
