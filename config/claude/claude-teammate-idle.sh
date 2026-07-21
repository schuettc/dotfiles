#!/bin/bash
# Stop hook — a teammate records its OWN idleness, authoritatively.
#
# Background: Claude Code teammates are spawned into a tmux pane and are
# deliberately persistent (a finished teammate stays resumable), so nothing ever
# terminates them and each holds a pty forever. `SubagentStop` fires in the
# PARENT and carries no pane id, so it cannot identify a teammate's pane.
#
# But a teammate is itself a full Claude session, so its own `Stop` hook fires
# when it finishes a turn — and that hook's environment carries:
#   TMUX_PANE                        its own pane id
#   TMUX                             its own socket
#   agent_type in the payload        non-empty for teammates only (see below)
#
# So the teammate can stamp "I went idle at T" itself. That replaces guessing
# idleness from spinner glyphs or screen-content hashing with a fact. If the
# teammate is later resumed and works again, Stop fires again and the stamp
# refreshes, so a resumed agent can never look stale.
#
# Discriminating a teammate from a main session: the Stop payload carries a
# non-empty "agent_type" (e.g. "general-purpose") ONLY for teammates; a main
# session's Stop omits it. Do NOT use CLAUDE_CODE_CHILD_SESSION for this — it
# is set in EVERY hook subprocess, main sessions included, so it marks "you are
# a hook", not "you are a teammate". Using it stamped two main panes before
# this was caught.
#
# Writes only; never kills. Reaping is a separate, explicit step
# (bin/claude-reap-teammate-panes.sh), so this hook can never surprise anyone.
set -u

[ -n "${TMUX_PANE:-}" ] || exit 0

payload=$(cat 2>/dev/null || true)

# Teammate marker. Empty/absent -> main session -> never stamp.
atype=$(printf '%s' "$payload" | sed -n 's/.*"agent_type":"\([^"]*\)".*/\1/p' | head -1)
[ -n "$atype" ] || exit 0

dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-teammate-idle"
mkdir -p "$dir" 2>/dev/null || exit 0

# Key by socket + pane. Pane ids are only unique per tmux server, and this
# machine runs a per-project socket for every workspace — keying on the pane
# alone would collide across them (the exact bug in the statusline state file,
# whose key strips '%' and so mixes up every socket's %NN).
sock=$(printf '%s' "${TMUX:-}" | cut -d, -f1)
sock=${sock##*/}
[ -n "$sock" ] || sock=unknown
key="${sock}_${TMUX_PANE#%}"

sid=$(printf '%s' "$payload" | sed -n 's/.*"session_id":"\([^"]*\)".*/\1/p' | head -1)

{
  echo "idle_since=$(date +%s)"
  echo "pane=${TMUX_PANE}"
  echo "socket=${sock}"
  echo "session_id=${sid}"
  echo "agent_type=${atype}"
} >"$dir/$key" 2>/dev/null

exit 0
