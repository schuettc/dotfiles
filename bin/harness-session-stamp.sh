#!/bin/bash
# SessionStart hook: record which coding-agent session owns a tmux session.
#
# Reads the harness's hook payload on stdin, takes its session_id, resolves
# the pane this hook belongs to, and stamps the pane's tmux SESSION with:
#
#     @harness_session   <session id>
#
# Wired for Claude Code, Codex and Cursor — all three send a JSON payload
# carrying session_id, and all three fire SessionStart on both a fresh start
# and a resume.
#
# Why this exists: a pane running `scratch` (or anything else that wants to
# scope itself to the conversation) is a SIBLING of the agent's pane. It
# does not inherit the agent's environment, so it cannot read
# $CLAUDE_CODE_SESSION_ID. The tmux session option is the hand-off — any
# pane in the session can read it.
#
# Firing on resume is the point. A resumed conversation keeps its session
# id (verified: resuming appends to the same transcript under the same id
# rather than minting a new one), so re-stamping on resume moves the id
# onto whatever pane the operator resumed into — a different tab, or a
# different worktree — and session-scoped state follows them there. A fresh
# session gets a new id and therefore a clean slate.
#
# Writes nothing and exits 0 when the pane can't be resolved (a paneless or
# daemon-hosted session), when there's no session id, or when tmux is
# absent. A hook must never fail a session start.

set -u

payload=$(cat 2>/dev/null || true)

command -v jq >/dev/null 2>&1 || exit 0
session_id=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null || true)
[ -n "$session_id" ] || exit 0

# Refuse anything that isn't a plain session identifier. The value is about
# to be handed to tmux and then used by consumers to build file paths.
case "$session_id" in
  *[!A-Za-z0-9._-]* | "" ) exit 0 ;;
esac

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pane_line=$("$here/tmux-hook-pane.sh" "$$" 2>/dev/null) || exit 0
[ -n "$pane_line" ] || exit 0

sock=$(printf '%s' "$pane_line" | cut -f1)
session=$(printf '%s' "$pane_line" | cut -f2)
[ -n "$sock" ] && [ -n "$session" ] || exit 0

# Bare session name, NOT "=$name": tmux 3.7b rejects the exact-match prefix
# for set-option's target ("no such session: =foo"), even though has-session
# and switch-client accept it. The name comes straight from list-panes, and
# tmux resolves an exact match before any prefix match, so this is precise.
tmux -L "$sock" set-option -t "$session" @harness_session "$session_id" 2>/dev/null || true

exit 0
