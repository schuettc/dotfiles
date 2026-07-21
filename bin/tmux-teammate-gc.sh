#!/bin/bash
# prefix g: ask this window's Claude lead to stop its finished teammates.
#
# Why a nudge and not a script action: TaskStop is an in-session Claude tool,
# not a shell command, so nothing outside the session can call it. Only the lead
# can, and only it knows which teammates are done. So we type the request into
# its pane, exactly as `muster nudge` does for the inbox drain (prefix m).
#
# TaskStop is the ONLY complete removal — it ends the teammate's process, frees
# its tmux pane, AND deregisters it from the team roster. Killing the pane
# instead (bin/claude-reap-teammate-panes.sh) reclaims the pty but strands a
# ghost entry in ~/.claude/teams/<session>/config.json, which keeps showing in
# the session's teammate list. The reaper stays as the fallback for orphans
# whose lead session is gone; this is the primary path.
#
# Scope is the CURRENT WINDOW only — deliberately. Sweeping every session would
# type into panes you are not looking at, and each lead gives a considered
# answer (it keeps teammates that are still working), which is worth reading.
#
# stdout must stay silent: run-shell pops an output view pane for ANY output,
# so every message goes to the status line via display-message instead.
set -u

PROMPT="TaskStop your finished teammates."

# The lead is the leftmost, tallest pane. Teammate panes run `claude` too, so
# position — not command — is what distinguishes them. Tallest breaks ties when
# the right column is split into a stack.
lead=$(tmux list-panes -F '#{pane_left} #{pane_height} #{pane_id}' 2>/dev/null \
       | sort -k1,1n -k2,2nr | head -1 | awk '{print $3}')
if [ -z "$lead" ]; then
  tmux display-message "teammate-gc: no panes found"
  exit 0
fi

# Only type into a pane actually running Claude. A Claude pane's current command
# is "claude" or the bare version string (e.g. "2.1.216") — the same liveness
# gate bin/tmux-claude-context.sh uses. Without this, a stray prefix g would
# paste a sentence into a shell prompt.
cmd=$(tmux display-message -p -t "$lead" '#{pane_current_command}' 2>/dev/null)
case "$cmd" in
  claude|[0-9]*.[0-9]*) ;;
  *) tmux display-message "teammate-gc: pane ${lead} is not Claude (${cmd}) — nothing sent"; exit 0 ;;
esac

# -l sends the text literally, so nothing in it is read as a key name. Enter is
# a separate send so the prompt submits as one line.
if tmux send-keys -t "$lead" -l "$PROMPT" 2>/dev/null \
   && tmux send-keys -t "$lead" Enter 2>/dev/null; then
  tmux display-message "teammate-gc: asked ${lead} to stop finished teammates"
else
  tmux display-message "teammate-gc: send to ${lead} failed"
fi
