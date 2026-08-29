#!/usr/bin/env zsh
# Tests for bin/tmux-hook-pane.sh and bin/harness-session-stamp.sh.
#
# Run directly:  zsh tests/harness-session-stamp.test.zsh
#
# These drive a REAL tmux server on a throwaway socket rather than stubbing
# tmux. The bug these scripts exist to fix — a walk that searched only the
# "default" socket and therefore found nothing once every project got its
# own server — is invisible to a stub, because a stub answers whatever
# socket it is asked about.

set -u

REPO="${0:A:h:h}"
WALK="$REPO/bin/tmux-hook-pane.sh"
STAMP="$REPO/bin/harness-session-stamp.sh"

typeset -g PASS=0 FAIL=0
ok() {
  if [[ "$2" == "$3" ]]; then
    (( PASS++ )); printf '  ok   %s\n' "$1"
  else
    (( FAIL++ )); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
  fi
}

command -v tmux >/dev/null || { echo "tmux required"; exit 1; }

# A private socket dir so the throwaway server can't be confused with the
# operator's real ones, and so the scripts' own socket enumeration is
# exercised against a directory we control.
TMPROOT=$(mktemp -d)
export TMUX_TMPDIR="$TMPROOT"
SOCK="test-harness-$$"
trap 'tmux -L "$SOCK" kill-server 2>/dev/null; rm -rf "$TMPROOT"' EXIT

tmux -L "$SOCK" new-session -d -s workproj -x 80 -y 24
# A second server: the walk must search ACROSS sockets, not just one.
SOCK2="test-harness2-$$"
tmux -L "$SOCK2" new-session -d -s otherproj -x 80 -y 24
trap 'tmux -L "$SOCK" kill-server 2>/dev/null; tmux -L "$SOCK2" kill-server 2>/dev/null; rm -rf "$TMPROOT"' EXIT

echo "── pane resolution ──"

# Run the walk INSIDE a pane: its ancestry ends at that pane's shell, which
# is exactly the shape a hook has.
# send-keys takes a PANE target: "=name" is session-target syntax and is
# rejected here ("can't find pane"). Resolve the pane id and aim at that.
run_in_pane() {  # run_in_pane <socket> <session> <command…>
  local sock="$1" sess="$2"; shift 2
  local pane out i
  pane=$(tmux -L "$sock" list-panes -t "$sess" -F '#{pane_id}' 2>/dev/null | head -1)
  [[ -n "$pane" ]] || { echo "NO-PANE"; return 1; }
  # mktemp, not $RANDOM: run_in_pane is often called inside $(…), and a
  # subshell inherits the RNG state, so $RANDOM yields the SAME value every
  # time. The reused file was already non-empty from an earlier call, so the
  # wait below returned instantly and the assertions raced the pane.
  out=$(mktemp "$TMPROOT/out.XXXXXX")
  rm -f "$out"
  # Scrub the outer-agent marker first: when this test itself runs inside an
  # agent session, the throwaway tmux server inherits AGENT_SESSION_ID and
  # every pane would trip the stamp script's child-of-an-agent guard. A case
  # that wants the marker sets it explicitly in its own command.
  tmux -L "$sock" send-keys -t "$pane" "{ unset AGENT_SESSION_ID; $* ; } > '$out' 2>&1" Enter
  for i in {1..60}; do
    [[ -s "$out" ]] && break
    sleep 0.1
  done
  command cat "$out" 2>/dev/null
}

line=$(run_in_pane "$SOCK" workproj "TMUX_TMPDIR='$TMPROOT' '$WALK'")
ok "resolves its own socket"  "$SOCK"   "$(printf '%s' "$line" | cut -f1)"
ok "resolves its own session" "workproj" "$(printf '%s' "$line" | cut -f2)"
ok "reports a pane id"        "1"        "$([[ "$(printf '%s' "$line" | cut -f3)" == %* ]] && echo 1 || echo 0)"
ok "reports a tty"            "1"        "$([[ "$(printf '%s' "$line" | cut -f4)" == /dev/* ]] && echo 1 || echo 0)"

# The regression guard: a pane on the SECOND server must resolve too. A
# default-socket-only walk returns nothing here.
line2=$(run_in_pane "$SOCK2" otherproj "TMUX_TMPDIR='$TMPROOT' '$WALK'")
ok "finds a pane on another socket" "$SOCK2|otherproj" \
   "$(printf '%s' "$line2" | cut -f1)|$(printf '%s' "$line2" | cut -f2)"

# Outside any pane the walk must fail closed — no output, non-zero exit.
out=$(TMUX_TMPDIR="$TMPROOT" "$WALK" 2>/dev/null); rc=$?
ok "fails closed off-pane (rc)"     "1" "$rc"
ok "fails closed off-pane (silent)" ""  "$out"

echo "── stamping ──"

stamp_in_pane() {  # stamp_in_pane <payload-json>
  run_in_pane "$SOCK" workproj "printf %s '$1' | TMUX_TMPDIR='$TMPROOT' '$STAMP'; echo done" >/dev/null
}
opt() { tmux -L "$SOCK" show-option -qv -t workproj @harness_session; }

tmux -L "$SOCK" set-option -t workproj -u @harness_session 2>/dev/null
stamp_in_pane '{"session_id":"abc-123","cwd":"/tmp"}'
ok "stamps the session id" "abc-123" "$(opt)"

# Resume: the same conversation restarting re-stamps the same id.
stamp_in_pane '{"session_id":"abc-123","cwd":"/elsewhere"}'
ok "resume re-stamps same id" "abc-123" "$(opt)"

# A different conversation in that pane replaces it — a fresh session must
# not inherit the previous one's identity.
stamp_in_pane '{"session_id":"def-456","cwd":"/tmp"}'
ok "new session replaces id" "def-456" "$(opt)"

# A harness spawned INSIDE another agent's process tree (pi's claude-bridge
# children, subagents) inherits AGENT_SESSION_ID from the outer agent. The
# outer agent owns the pane's identity and stamps it itself — the child's
# hook must not steal the slot.
run_in_pane "$SOCK" workproj "printf %s '{\"session_id\":\"bridge-child\"}' | AGENT_SESSION_ID=outer-agent TMUX_TMPDIR='$TMPROOT' '$STAMP'; echo done" >/dev/null
ok "child of another agent does not stamp" "def-456" "$(opt)"
rc=$(run_in_pane "$SOCK" workproj "printf %s '{\"session_id\":\"bridge-child\"}' | AGENT_SESSION_ID=outer-agent TMUX_TMPDIR='$TMPROOT' '$STAMP'; echo \$?")
ok "child skip still exits 0" "0" "$rc"

# Junk must never reach tmux: the value ends up in file paths downstream.
stamp_in_pane '{"session_id":"../../etc/passwd"}'
ok "rejects traversal, keeps prior" "def-456" "$(opt)"
stamp_in_pane '{"session_id":""}'
ok "ignores empty id"               "def-456" "$(opt)"
stamp_in_pane 'not json at all'
ok "survives malformed payload"     "def-456" "$(opt)"

# A hook must never fail a session start, whatever it is handed.
rc=$(run_in_pane "$SOCK" workproj "printf %s 'garbage' | TMUX_TMPDIR='$TMPROOT' '$STAMP'; echo \$?")
ok "exits 0 on garbage" "0" "$rc"

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
