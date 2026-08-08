#!/bin/bash
# prefix T handler: rename this SESSION — one gesture for every surface
# (session-identity plan 2026-08-08; spec in docs/superpowers/specs/).
#
# The tmux session name IS the identity: #S = the work = (with muster) the
# bus alias. The tmux half lives here: validate, refuse collisions, rename.
# With muster present, `muster become <name>` additionally claims the alias
# on the bus (mail follows via lineage) and types /rename into the
# registered Claude pane — muster owns injection; this script never
# send-keys. A muster whose CLI predates `become` fails the probe and the
# rename stays tmux-only (Claude's internal name catches up on the
# operator's next /rename).
#
# tmux run-shell children inherit $TMUX but NOT $TMUX_PANE — $1 is
# #{pane_id}, expanded by the binding at press time; $2 is the new name.
# Output goes through display-message: run-shell opens a full-screen view
# for ANY stdout, which reads as an error screen instead of feedback.
export TMUX_PANE="$1"
new="$2"

cur=$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}')

if [[ -z "$new" || "$new" == "$cur" ]]; then
  tmux display-message "rename cancelled (still: $cur)"
  exit 0
fi

if [[ ! "$new" =~ ^[A-Za-z0-9_/-]+$ ]]; then
  tmux display-message "invalid name: $new (allowed: letters digits - _ /)"
  exit 0
fi

# Refuse names a LIVE session already holds — on any server, because the
# name doubles as the bus-global muster alias. Silent identity theft is the
# failure mode this exists to prevent.
sockdir="${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)"
for s in "$sockdir"/*; do
  [[ -S "$s" ]] || continue
  if tmux -S "$s" has-session -t "=$new" 2>/dev/null; then
    tmux display-message "name taken by a live session: $new"
    exit 0
  fi
done

tmux rename-session -t "$TMUX_PANE" "$new"

if command -v muster >/dev/null 2>&1 && muster become --help >/dev/null 2>&1; then
  if out=$(muster become "$new" 2>&1); then
    tmux display-message "renamed → $new · muster: ${out//$'\n'/ · }"
  else
    tmux display-message "renamed → $new · muster become FAILED: ${out//$'\n'/ · }"
  fi
else
  tmux display-message "renamed → $new (tmux only)"
fi
tmux refresh-client -S
