#!/bin/bash
# Emit a colored context-% indicator for tmux's status-right when the
# focused pane is running Claude Code. Reads the per-pane state file
# written by ~/.config/claude/statusline.sh.
#
# Usage:
#   tmux-claude-context.sh <pane_id>          # e.g. '%47' (from tmux's #{pane_id})
#
# Output (with embedded tmux color directives):
#   "⌬ 24%"   green  (< 50%)
#   "⌬ 64%"   yellow (50–79%)
#   "⌬ 88%"   red    (≥ 80%)
#   ""        (nothing) — no Claude in this pane, or state is stale

set -u

pane_id="${1:-}"
[[ -z "$pane_id" ]] && exit 0

state_dir="${TMPDIR:-/tmp}/claude-status"
state_key="${pane_id//[^a-zA-Z0-9]/_}"
state_file="$state_dir/$state_key"

[[ -f "$state_file" ]] || exit 0

# Stale check: 10 minutes since last update → Claude probably exited.
updated=$(awk -F= '$1=="updated"{print $2}' "$state_file" 2>/dev/null)
now=$(date +%s)
if [[ -n "$updated" ]] && (( now - updated > 600 )); then
  exit 0
fi

pct=$(awk -F= '$1=="context_pct"{print $2}' "$state_file" 2>/dev/null)
[[ -z "$pct" || ! "$pct" =~ ^[0-9]+$ ]] && exit 0

# Skip if we don't actually have a useful value yet.
(( pct == 0 )) && exit 0

if   (( pct >= 80 )); then
  printf '#[fg=#f38ba8,bold]⌬ %d%%#[default]' "$pct"
elif (( pct >= 50 )); then
  printf '#[fg=#f9e2af]⌬ %d%%#[default]' "$pct"
else
  printf '#[fg=#a6e3a1]⌬ %d%%#[default]' "$pct"
fi
