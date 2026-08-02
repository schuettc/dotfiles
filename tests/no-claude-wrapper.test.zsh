#!/usr/bin/env zsh
# Guards the deliberate ABSENCE of a claude() wrapper in config/zsh/.
#
# Run directly:  zsh tests/no-claude-wrapper.test.zsh
#
# The shell used to wrap `claude` to pre-register a muster alias derived from
# the tmux session name. That seed is obsolete — muster's own SessionStart
# hook resolves its pane and registers itself (verified: with $TMUX,
# $TMUX_PANE and $CLAUDE_CODE_SESSION_ID stripped, the hook still records the
# correct socket/session_name/pane_id plus the harness UUID). It was also
# unsafe: a plain upsert on a guessed alias, so a tmux session sharing a name
# with a live claimed alias got that conversation's row taken over.
#
# The failure mode this guards is a well-meaning re-introduction: someone
# sees a session register "wrong" and reaches for a wrapper again. The fix
# belongs in muster's hook, which can do the check atomically.

set -u

REPO="${0:A:h:h}"
ZSHDIR="$REPO/config/zsh"

typeset -g PASS=0 FAIL=0
ok() {
  if [[ "$2" == "$3" ]]; then
    (( PASS++ )); printf '  ok   %s\n' "$1"
  else
    (( FAIL++ )); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
  fi
}

# Strip comments before scanning: the block explaining WHY the wrapper is
# gone necessarily names the things it must not do.
code() { grep -hv '^[[:space:]]*#' "$ZSHDIR"/*.zsh; }

echo "── no claude wrapper ──"
ok "no claude() function"  "0" "$(code | grep -cE '^[[:space:]]*(function[[:space:]]+claude[[:space:]]*\{|claude[[:space:]]*\(\))')"
ok "no claude alias"       "0" "$(code | grep -cE "^[[:space:]]*alias[[:space:]]+claude=")"

echo "── no identity seeding from the shell ──"
ok "no muster register"    "0" "$(code | grep -c 'muster.*register')"
ok "no --harness-session"  "0" "$(code | grep -c 'harness-session')"
ok "no --session-id pass"  "0" "$(code | grep -c 'session-id')"

echo "── the stale wrapper is cleared on reload ──"
# A shell that loaded the old config keeps the function in memory; sourcing
# the current config must drop it rather than leave it live.
ok "unfunction claude present" "1" \
   "$(grep -c '^unfunction claude' "$ZSHDIR/04-aliases.zsh")"

echo "── claude is reachable without a wrapper ──"
# The wrapper pinned $HOME/.local/bin/claude; removing it is only safe if the
# binary is on PATH. Skip rather than fail where claude isn't installed.
if [[ -x "$HOME/.local/bin/claude" ]]; then
  ok "claude resolves on PATH" "1" \
     "$(env -i PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin" sh -c 'command -v claude >/dev/null && echo 1 || echo 0')"
else
  echo "  skip (claude not installed)"
fi

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
