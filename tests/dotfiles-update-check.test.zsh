#!/usr/bin/env zsh
# Tests for bin/dotfiles-update-check.sh (status / refresh / clear).
#
# Run directly:  zsh tests/dotfiles-update-check.test.zsh
#
# No network: refresh tests use a local directory as the git remote.

set -u

REPO="${0:A:h:h}"
SCRIPT="$REPO/bin/dotfiles-update-check.sh"

typeset -g PASS=0 FAIL=0
ok() {
  if [[ "$2" == "$3" ]]; then
    (( PASS++ )); printf '  ok   %s\n' "$1"
  else
    (( FAIL++ )); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
  fi
}

FAKE=$(mktemp -d)
trap 'rm -rf "$FAKE"' EXIT

export DOTFILES_UPDATE_STATE="$FAKE/state"
export DOTFILES_UPDATE_REPO="$FAKE/clone"

DIM_3=$'\033[2mdotfiles: 3 behind · dotup\033[0m'

# ── status ───────────────────────────────────────────────────────────────
echo "status:"

out=$("$SCRIPT" status)
ok "missing state file → silent" "" "$out"

printf 'behind=3\n' > "$FAKE/state"
out=$("$SCRIPT" status)
ok "behind=3 → dim nudge line" "$DIM_3" "$out"

out=$("$SCRIPT")
ok "status is the default subcommand" "$DIM_3" "$out"

printf 'behind=0\n' > "$FAKE/state"
out=$("$SCRIPT" status)
ok "behind=0 → silent" "" "$out"

printf 'behind=banana\n' > "$FAKE/state"
out=$("$SCRIPT" status)
ok "corrupt state → silent" "" "$out"

printf 'garbage\n' > "$FAKE/state"
out=$("$SCRIPT" status)
ok "unparseable state → silent" "" "$out"

# ── summary ──────────────────────────────────────────────────────────────
echo ""
echo "$PASS passed, $FAIL failed"
(( FAIL == 0 ))
