#!/bin/bash
# prefix T handler: one naming gesture for tmux, the bus, and the agent
# harness (naming-contract plan 2026-08-05; spec in the muster repo).
#
# With muster on PATH, delegate to `muster label`: tmux option pair + bus
# sync + typing /rename into the live Claude pane — KEEP AS-IS, the
# injection is operator-confirmed working well. Without muster, fall back to
# the plain tmux half of the contract: label + manual flag (both unset on
# clear). No send-keys in the fallback — typing into panes is muster's job.
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

if command -v muster >/dev/null 2>&1; then
  if out=$(muster label "$@" 2>&1); then
    tmux display-message "muster: ${out//$'\n'/ · }"
  else
    tmux display-message "muster label FAILED: ${out//$'\n'/ · }"
  fi
  exit 0
fi

# muster-less fallback: the tmux half of the naming contract only.
if [[ -n "${1:-}" ]]; then
  tmux set-option -t "$TMUX_PANE" @claude_task "$1"
  tmux set-option -t "$TMUX_PANE" @claude_task_manual 1
  tmux refresh-client -S
  tmux display-message "label: $1 (tmux only — muster not installed)"
else
  tmux set-option -u -t "$TMUX_PANE" @claude_task
  tmux set-option -u -t "$TMUX_PANE" @claude_task_manual
  tmux refresh-client -S
  tmux display-message "label cleared (tmux only — muster not installed)"
fi
