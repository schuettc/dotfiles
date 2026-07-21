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

# Liveness gate: only show the indicator if this pane is actually running
# Claude. A Claude pane's current command is the version string (e.g.
# "2.1.156") or "claude". This beats guessing from file age — statusline.sh
# only rewrites the state file at each turn boundary, so during a long turn
# the file looks "stale" while Claude is very much alive. If the command
# isn't Claude, the pane moved on → no icon.
#
# The same query also yields '#{socket_path}' — the server that owns this pane
# — so one tmux call covers both the liveness gate and the state key below.
info=$(tmux display-message -p -t "$pane_id" '#{pane_current_command}
#{socket_path}' 2>/dev/null)
cmd=${info%%$'\n'*}
sock_path=${info#*$'\n'}
[[ "$cmd" == claude || "$cmd" =~ ^[0-9]+\.[0-9]+ ]] || exit 0

# Stable path: $HOME/.cache is identical for the Claude process (even when
# its sandbox sets a different $TMPDIR) and for tmux — so both sides agree.
state_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-status"

# Key = socket name + pane number, identical to the derivation in
# ~/.config/claude/statusline.sh. Pane ids repeat across the ~14 per-project
# tmux servers on this machine, so a pane-only key mixed up their state files.
# The writer takes the socket from its inherited $TMUX; here it comes from
# '#{socket_path}' of the server that owns the pane. Both are basenames, so
# the /tmp vs /private/tmp symlink difference can't split them.
sock=${sock_path##*/}
[[ -n "$sock" ]] || { sock="${TMUX:-}"; sock="${sock%%,*}"; sock="${sock##*/}"; }
[[ -n "$sock" ]] || sock=unknown
state_key="${sock}_${pane_id#%}"
state_key="${state_key//[^a-zA-Z0-9_.-]/_}"
state_file="$state_dir/$state_key"

[[ -f "$state_file" ]] || exit 0

# Orphan backstop (paranoia only — liveness already proved Claude is running
# in this pane). Just suppresses a genuinely ancient file (>7 days), e.g. left
# by a long-dead session whose pane id got reused. A multi-hour idle gap is
# normal (work overnight, resume) and must NOT hide the indicator.
updated=$(awk -F= '$1=="updated"{print $2}' "$state_file" 2>/dev/null)
now=$(date +%s)
if [[ -n "$updated" ]] && (( now - updated > 604800 )); then
  exit 0
fi

model=$(awk -F= '$1=="model"{print $2}' "$state_file" 2>/dev/null)
pct=$(awk -F= '$1=="context_pct"{print $2}' "$state_file" 2>/dev/null)

# Model label (dim) — moved here from the in-Claude statusline. Shown as soon
# as we know it, even before context% is meaningful.
prefix=""
[[ -n "$model" ]] && prefix="#[fg=#a6adc8]${model}#[default] "

# Context indicator, colored by usage. Omitted until there's a real value.
ctx=""
if [[ "$pct" =~ ^[0-9]+$ ]] && (( pct > 0 )); then
  if   (( pct >= 80 )); then ctx="#[fg=#f38ba8,bold]⌬ ${pct}%#[default]"
  elif (( pct >= 50 )); then ctx="#[fg=#f9e2af]⌬ ${pct}%#[default]"
  else                       ctx="#[fg=#a6e3a1]⌬ ${pct}%#[default]"
  fi
fi

# Nothing useful to show → stay silent.
[[ -z "$prefix$ctx" ]] && exit 0
printf '%s%s' "$prefix" "$ctx"
