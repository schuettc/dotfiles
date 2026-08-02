#!/usr/bin/env zsh
# Tests for set-titles-string in .tmux.conf.
#
# Run directly:  zsh tests/set-titles-string.test.zsh
#
# The format is extracted from .tmux.conf and rendered by a REAL tmux against
# a throwaway session whose @-options are set per case. Nothing is duplicated
# into the test: a copy of the format string here would pass forever while
# the shipped one rotted.
#
# Worth testing because tmux formats fail SILENTLY. The previous version
# nested the alias as the ELSE branch of the unread test, so any session with
# mail rendered no identity at all — visibly wrong, and it survived in the
# config until someone happened to look.

set -u

REPO="${0:A:h:h}"

typeset -g PASS=0 FAIL=0
ok() {
  if [[ "$2" == "$3" ]]; then
    (( PASS++ )); printf '  ok   %s\n' "$1"
  else
    (( FAIL++ )); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
  fi
}

command -v tmux >/dev/null || { echo "tmux required"; exit 1; }

# Pull the live format out of the config rather than restating it.
FMT=$(sed -n "s/^set -g set-titles-string '\(.*\)'$/\1/p" "$REPO/.tmux.conf")
[[ -n "$FMT" ]] || { echo "could not extract set-titles-string from .tmux.conf"; exit 1; }

TMPROOT=$(mktemp -d)
export TMUX_TMPDIR="$TMPROOT"
SOCK="titletest-$$"
trap 'tmux -L "$SOCK" kill-server 2>/dev/null; rm -rf "$TMPROOT"' EXIT
tmux -L "$SOCK" new-session -d -s workspace-3 -x 80 -y 24

# render <agent> <task> <inbox> <attn> — set the options and render the title.
render() {
  local agent="$1" task="$2" inbox="$3" attn="$4" o
  for o in @muster_agent @claude_task @muster_inbox @claude_attn; do
    tmux -L "$SOCK" set-option -t workspace-3 -u "$o" 2>/dev/null
  done
  [[ -n "$agent" ]] && tmux -L "$SOCK" set-option -t workspace-3 @muster_agent "$agent"
  [[ -n "$task"  ]] && tmux -L "$SOCK" set-option -t workspace-3 @claude_task  "$task"
  [[ -n "$inbox" ]] && tmux -L "$SOCK" set-option -t workspace-3 @muster_inbox "$inbox"
  [[ -n "$attn"  ]] && tmux -L "$SOCK" set-option -t workspace-3 @claude_attn  "$attn"
  tmux -L "$SOCK" display-message -p -t workspace-3 "$FMT"
}

echo "── seed case: alias equals the session name ──"
# The overwhelming majority of sessions. Must render exactly as before the
# alias-first change, i.e. the session name leads and no @alias appears.
ok "name leads, no alias echo" "workspace-3 · writing docs" \
   "$(render workspace-3 'writing docs' '' '')"
ok "no alias at all"           "workspace-3 · writing docs" \
   "$(render '' 'writing docs' '' '')"
ok "bare session"              "workspace-3" "$(render '' '' '' '')"

echo "── claimed alias leads ──"
ok "alias replaces the name" "@durable-alias · writing docs" \
   "$(render durable-alias 'writing docs' '' '')"
ok "alias alone"             "@durable-alias" "$(render durable-alias '' '' '')"

echo "── mail no longer suppresses identity ──"
# The regression this change exists to fix: the alias used to be the ELSE of
# the unread test, so mail hid it entirely.
ok "alias AND badge together" "@durable-alias · writing docs · 📬1" \
   "$(render durable-alias 'writing docs' 1 '')"
ok "badge on a seed session"  "workspace-3 · writing docs · 📬3" \
   "$(render workspace-3 'writing docs' 3 '')"
ok "alias and badge, no task" "@durable-alias · 📬2" \
   "$(render durable-alias '' 2 '')"

echo "── topic/alias dedupe ──"
# Labelling a session, then claiming the same word, used to print it twice.
ok "duplicate topic dropped" "@nfl-a2" "$(render nfl-a2 nfl-a2 '' '')"
ok "distinct topic kept"     "@nfl-a2 · debug alarms" \
   "$(render nfl-a2 'debug alarms' '' '')"

echo "── attention bell prefixes everything ──"
ok "bell leads"          "🔔 @durable-alias · 📬1" "$(render durable-alias '' 1 1)"
ok "bell on seed"        "🔔 workspace-3"          "$(render '' '' '' 1)"

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
