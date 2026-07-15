#!/usr/bin/env bash
# muster session hook — wires an agent session to the muster bus.
#
#   SessionStart : auto-register this tmux session as a muster agent.
#   Stop         : self-resolving inbox — if this session has unread muster mail,
#                  tell the agent to drain it (autonomous continuation), keyed off
#                  the @muster_inbox tmux option the muster daemon sets.
#
# Usage (from a Claude settings.json / Codex hooks.json command):
#   muster-session-hook.sh <SessionStart|Stop> <claude|codex>
#
# Safe as a global hook: for any session that isn't a registered agent (no
# @muster_inbox), the Stop branch is a no-op. Never blocks session start.

event="$1"
model="${2:-claude}"
muster="$HOME/.local/bin/muster"
[ -x "$muster" ] || exit 0

case "$event" in
  SessionStart)
    # Register (alias auto-derives from the tmux session name; project/pane from
    # $TMUX). Best-effort — never block session start.
    "$muster" register --model "$model" >/dev/null 2>&1 || true
    exit 0
    ;;

  Stop)
    input="$(cat 2>/dev/null)"
    # Loop guard: if we already triggered a continuation this cycle, let it stop.
    if command -v jq >/dev/null 2>&1; then
      [ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0
    else
      case "$input" in
        *'"stop_hook_active":true'* | *'"stop_hook_active": true'*) exit 0 ;;
      esac
    fi

    [ -n "$TMUX" ] || exit 0
    count="$(tmux show-options -qv @muster_inbox 2>/dev/null)"
    case "$count" in
      '' | *[!0-9]*) exit 0 ;;   # unset or non-numeric → nothing to drain
    esac
    [ "$count" -gt 0 ] || exit 0

    # Tell the agent to drain its inbox and act autonomously. decision:block makes
    # both Claude and Codex continue with `reason` as the next prompt. When the
    # agent calls get_inbox, the daemon clears @muster_inbox → next Stop is quiet.
    reason="You have ${count} unread muster message(s). Call your muster get_inbox tool now, read each new thread with get_thread, handle the request, and reply with the muster reply tool. Act autonomously — do not ask the user."
    if command -v jq >/dev/null 2>&1; then
      jq -nc --arg r "$reason" '{decision:"block",reason:$r}'
    else
      printf '{"decision":"block","reason":"%s"}\n' "$reason"
    fi
    exit 0
    ;;
esac
exit 0
