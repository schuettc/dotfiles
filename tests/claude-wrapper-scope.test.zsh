#!/usr/bin/env zsh
# Bounds what the claude() wrapper in config/zsh/ is allowed to do.
#
# Run directly:  zsh tests/claude-wrapper-scope.test.zsh
#
# The wrapper shapes ARGV and nothing else: it adds `--` when called with no
# arguments, because a bare `claude` opens agent view (the fleet launcher)
# instead of starting a session. Every other invocation must reach the real
# binary byte-identical, so `claude agents`, `--bg`, `--resume` and `-p` keep
# working. That passthrough is the reason this is a wrapper instead of the
# global `disableAgentView` switch, which would take `--bg`, `/background` and
# the on-demand daemon with it.
#
# This file used to be no-claude-wrapper.test.zsh and banned the wrapper
# outright. That was too blunt a reading of its own rationale: the dangerous
# thing was never wrapping, it was IDENTITY. The old handshake guessed a
# muster alias from the tmux session name and upserted it with no liveness
# check, so a tmux session sharing a name with a live claimed alias took over
# that conversation's row and inbox. Assigning bus identity is muster's job —
# it can compare harness UUIDs atomically inside one transaction, which a
# shell round-trip cannot.
#
# So the ban is now scoped to what actually bites: no muster registration, no
# --harness-session, no minted --session-id. Widening the wrapper past argv
# shaping should fail here.

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

# Strip comments before scanning: the block explaining WHY identity seeding is
# banned necessarily names every construct it bans.
code() { grep -hv '^[[:space:]]*#' "$ZSHDIR"/*.zsh; }

echo "── the wrapper exists, exactly once ──"
ok "one claude() function" "1" \
   "$(code | grep -cE '^[[:space:]]*(function[[:space:]]+claude[[:space:]]*\{|claude[[:space:]]*\(\))')"
# An alias is expanded before the function is looked up, so a stray one would
# shadow the wrapper entirely and silently restore the bare-claude bug.
ok "no claude alias" "0" "$(code | grep -cE "^[[:space:]]*alias[[:space:]]+claude=")"
ok "stale alias cleared on reload" "1" "$(grep -c '^unalias claude' "$ZSHDIR/04-aliases.zsh")"

echo "── it seeds no identity ──"
ok "no muster register"   "0" "$(code | grep -c 'muster.*register')"
ok "no --harness-session" "0" "$(code | grep -c 'harness-session')"
ok "no --session-id"      "0" "$(code | grep -c 'session-id')"

echo "── it shapes argv and nothing else ──"
# Run the real wrapper against a fake `claude` on PATH: the only honest way to
# assert passthrough is byte-identical, since a regex can't tell `"$@"` from
# something that quietly rebuilds the argument list.
#
# The fake brackets each argument SEPARATELY rather than echoing "$*". That
# detail is the test: `$*` collapses the boundaries, so a wrapper that split
# `-p 'two words'` into three arguments would print the same line as one that
# passed two, and the defect would go unnoticed.
#
# Confirmed against three mutations of the wrapper, each caught:
#   command claude "$@"   (drops the --)   -> "bare gets --" fails
#   command claude "$*"   (joins argv)     -> "flags pass" + quoting fail
#   command claude $=*    (splits argv)    -> "quoting preserved" fails
# Note that plain unquoted `$*` is NOT one of them: zsh does not word-split
# parameter expansions the way bash does, so it forwards argv intact. Reach
# for $=* if you want to prove the split case by hand.
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
print -r -- '#!/bin/sh'                                    > "$TMP/claude"
print -r -- 'printf ARGV:; for a in "$@"; do printf "[%s]" "$a"; done; echo' >> "$TMP/claude"
chmod +x "$TMP/claude"

# Arguments go to the inner shell POSITIONALLY, not interpolated into its
# script text. Interpolating re-parses them in the outer shell first, which
# splits `-p "two words"` before the wrapper ever sees it — the test would
# then pass no matter what the wrapper did with quoting.
# TMUX is unset explicitly: the bare branch now asks tmux for #S, and this
# suite usually runs from inside a tmux pane, so an inherited $TMUX would
# quietly put every "outside tmux" assertion on the named path.
drive() {  # drive <arg>... -> what the real binary received
  zsh -c "unset TMUX; source '$ZSHDIR/04-aliases.zsh' 2>/dev/null; unalias -m '*' 2>/dev/null
          PATH='$TMP':\$PATH; claude \"\$@\"" zsh "$@" 2>/dev/null | grep '^ARGV:'
}

# Same, but with the shell believing it sits in a tmux session named $1.
# The fake tmux answers the one question the wrapper asks (#S); anything
# else it is asked would be a widening of scope and shows up as a diff here.
drive_in_tmux() {  # drive_in_tmux <session-name> <arg>... -> received argv
  local sname="$1"; shift
  print -r -- '#!/bin/sh'                                  > "$TMP/tmux"
  print -r -- "printf '%s\\n' '$sname'"                   >> "$TMP/tmux"
  chmod +x "$TMP/tmux"
  zsh -c "source '$ZSHDIR/04-aliases.zsh' 2>/dev/null; unalias -m '*' 2>/dev/null
          PATH='$TMP':\$PATH; TMUX=/tmp/fake,1,0; claude \"\$@\"" zsh "$@" 2>/dev/null \
    | grep '^ARGV:'
}

ok "bare gets --"            "ARGV:[--]"             "$(drive)"
ok "subcommand passes"       "ARGV:[agents]"         "$(drive agents)"
ok "flags pass"              "ARGV:[--bg][-p][hi]"   "$(drive --bg -p hi)"
ok "resume passes"           "ARGV:[--resume]"       "$(drive --resume)"
# The wrapper must not re-add `--` to an invocation that already has one.
ok "explicit -- not doubled" "ARGV:[--]"             "$(drive --)"
# A quoted argument containing spaces must survive as ONE argument — this is
# what catches a wrapper that rebuilds argv instead of forwarding "$@".
ok "quoting preserved"       "ARGV:[-p][two words]"  "$(drive -p 'two words')"

echo "── inside tmux, a bare claude adopts the session name ──"
# The session name IS the identity, and proj/pt already picked it. A
# hand-typed `claude` in that pane should not have to be renamed afterwards
# — prefix T exists for CHANGING the name, not for setting it the first
# time. This is display-name shaping, not identity seeding: `--name` names
# the conversation, it does not claim a bus alias or mint a session id, and
# the three bans above still assert zero hits.
ok "adopts #S"              "ARGV:[--name][dotfiles/nfl-4][--]" \
   "$(drive_in_tmux 'dotfiles/nfl-4')"
# Home base sessions are bare <project> — still a name worth carrying.
ok "adopts a bare #S"       "ARGV:[--name][dotfiles][--]" \
   "$(drive_in_tmux 'dotfiles')"
# Passthrough is untouched inside tmux: --resume picks the conversation (and
# its name) interactively, so forcing a name onto it would fight the picker.
ok "resume still passes"    "ARGV:[--resume]"       "$(drive_in_tmux 'dotfiles/nfl-4' --resume)"
# A tmux that answers nothing (server gone, pane detached) must degrade to
# the plain form rather than emitting `--name '' --`.
ok "empty #S falls back"    "ARGV:[--]"             "$(drive_in_tmux '')"

echo "── it cannot recurse into itself ──"
# Without `command`, `claude` inside claude() re-enters the function forever.
# Scan the whole body rather than the definition line: the wrapper stopped
# being a one-liner when it grew the name branch, and an assertion that only
# reads line 1 would have gone quietly vacuous.
body() { awk '/^claude\(\) \{/,/^\}/' "$ZSHDIR/04-aliases.zsh"; }
ok "body found"             "1" "$(body | grep -c '^claude() {')"
ok "dispatches via command" "1" "$(body | grep -c 'command claude "\$@"')"
# Delete every `command claude` and no bare `claude` token may remain.
ok "no recursive call"      "0" \
   "$(body | tail -n +2 | grep -vE '^[[:space:]]*#' | sed 's/command claude//g' | grep -cE '(^|[^[:alnum:]_-])claude([^[:alnum:]_-]|$)')"

echo "── claude is reachable at all ──"
if [[ -x "$HOME/.local/bin/claude" ]]; then
  ok "claude resolves on PATH" "1" \
     "$(env -i PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin" sh -c 'command -v claude >/dev/null && echo 1 || echo 0')"
else
  echo "  skip (claude not installed)"
fi

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
