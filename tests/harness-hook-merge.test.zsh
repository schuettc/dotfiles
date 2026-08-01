#!/usr/bin/env zsh
# Tests for codex_ensure_hook / cursor_ensure_hook in packages/lib.sh.
#
# Run directly:  zsh tests/harness-hook-merge.test.zsh
#
# These files are shared: the muster package writes bus hooks into them and
# the codex/cursor packages write session-identity hooks. They used to be
# rewritten wholesale, so whichever package ran last erased the others'
# entries — and muster runs last in install.sh, so it always won. The
# assertions below are mostly about that: entries from different writers
# must survive each other, in either order.

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

command -v jq >/dev/null || { echo "jq required"; exit 1; }

# lib.sh is bash; drive it through bash with HOME pointed at a temp dir so
# nothing touches the operator's real ~/.codex or ~/.cursor.
FAKE=$(mktemp -d)
trap 'rm -rf "$FAKE"' EXIT

lib() {  # lib <bash snippet…>  — runs against the fake HOME
  HOME="$FAKE" bash -c "source '$REPO/packages/lib.sh' >/dev/null 2>&1; $*" 2>/dev/null
}

STAMP="\$HOME/dotfiles/bin/harness-session-stamp.sh"
MUSTER="\$HOME/.local/bin/muster hook SessionStart codex"

echo "── codex hooks.json ──"

lib "codex_ensure_hook SessionStart \"$STAMP\""
ok "creates the file" "1" "$([[ -f "$FAKE/.codex/hooks.json" ]] && echo 1 || echo 0)"
ok "valid json"       "0" "$(jq -e . "$FAKE/.codex/hooks.json" >/dev/null 2>&1; echo $?)"
ok "records the hook" "1" \
   "$(jq --arg c "$FAKE/dotfiles/bin/harness-session-stamp.sh" \
        '[.hooks.SessionStart[].hooks[]?.command] | index($c) | if . == null then 0 else 1 end' \
        "$FAKE/.codex/hooks.json")"

# Idempotent: the installer runs repeatedly.
lib "codex_ensure_hook SessionStart \"$STAMP\""
lib "codex_ensure_hook SessionStart \"$STAMP\""
ok "no duplicates on re-run" "1" \
   "$(jq '[.hooks.SessionStart[].hooks[]?.command] | length' "$FAKE/.codex/hooks.json")"

# The regression: a second writer must not erase the first.
lib "codex_ensure_hook SessionStart \"$MUSTER\""
ok "both writers survive" "2" \
   "$(jq '[.hooks.SessionStart[].hooks[]?.command] | length' "$FAKE/.codex/hooks.json")"

# …and in the other install order too.
rm -f "$FAKE/.codex/hooks.json"
lib "codex_ensure_hook SessionStart \"$MUSTER\"; codex_ensure_hook Stop \"$MUSTER\""
lib "codex_ensure_hook SessionStart \"$STAMP\""
ok "reverse order keeps both" "2" \
   "$(jq '[.hooks.SessionStart[].hooks[]?.command] | length' "$FAKE/.codex/hooks.json")"
ok "other events untouched"  "1" \
   "$(jq '[.hooks.Stop[].hooks[]?.command] | length' "$FAKE/.codex/hooks.json")"

# A corrupt file must not be silently overwritten, nor take the install down.
printf 'not json' > "$FAKE/.codex/hooks.json"
lib "codex_ensure_hook SessionStart \"$STAMP\""
ok "leaves corrupt file alone" "not json" "$(command cat "$FAKE/.codex/hooks.json")"

echo "── cursor hooks.json ──"

lib "cursor_ensure_hook sessionStart \"$STAMP\""
ok "cursor: version stamped" "1" "$(jq -r '.version' "$FAKE/.cursor/hooks.json")"
ok "cursor: flat command shape" "1" \
   "$(jq --arg c "$FAKE/dotfiles/bin/harness-session-stamp.sh" \
        '[.hooks.sessionStart[].command?] | index($c) | if . == null then 0 else 1 end' \
        "$FAKE/.cursor/hooks.json")"

lib "cursor_ensure_hook sessionStart \"$STAMP\""
ok "cursor: idempotent" "1" \
   "$(jq '[.hooks.sessionStart[].command?] | length' "$FAKE/.cursor/hooks.json")"

lib "cursor_ensure_hook sessionStart \"\$HOME/.local/bin/muster hook SessionStart cursor\""
ok "cursor: both writers survive" "2" \
   "$(jq '[.hooks.sessionStart[].command?] | length' "$FAKE/.cursor/hooks.json")"

# Cursor carries per-entry extras; they must land on the entry itself.
lib "cursor_ensure_hook stop \"\$HOME/.local/bin/muster hook Stop cursor\" '{\"loop_limit\":3}'"
ok "cursor: extras applied" "3" \
   "$(jq '.hooks.stop[0].loop_limit' "$FAKE/.cursor/hooks.json")"

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
