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

# ── refresh ──────────────────────────────────────────────────────────────
echo "refresh:"

# Fixture: local "origin" repo + a clone of it. Committing more in origin
# afterwards puts the clone behind — fetch is file-path local, no network.
G="git -c user.name=t -c user.email=t@t -c commit.gpgsign=false"
git init -q -b main "$FAKE/origin"
eval "$G -C '$FAKE/origin' commit -q --allow-empty -m c1"
git clone -q "$FAKE/origin" "$FAKE/clone"
eval "$G -C '$FAKE/origin' commit -q --allow-empty -m c2"
eval "$G -C '$FAKE/origin' commit -q --allow-empty -m c3"

rm -f "$FAKE/state"
"$SCRIPT" refresh
out=$(cat "$FAKE/state" 2>/dev/null)
ok "no state → fetches, records behind=2" "behind=2" "$out"

eval "$G -C '$FAKE/origin' commit -q --allow-empty -m c4"
"$SCRIPT" refresh
out=$(cat "$FAKE/state" 2>/dev/null)
ok "fresh state → age-gated, no refetch" "behind=2" "$out"

touch -t 202001010000 "$FAKE/state"
"$SCRIPT" refresh
out=$(cat "$FAKE/state" 2>/dev/null)
ok "stale state → refetches, behind=3" "behind=3" "$out"

git -C "$FAKE/clone" remote set-url origin "$FAKE/nonexistent"
touch -t 202001010000 "$FAKE/state"
"$SCRIPT" refresh
out=$(cat "$FAKE/state" 2>/dev/null)
ok "fetch failure → prior state kept" "behind=3" "$out"
git -C "$FAKE/clone" remote set-url origin "$FAKE/origin"

mkdir -p "$FAKE/notarepo"
rm -f "$FAKE/state"
DOTFILES_UPDATE_REPO="$FAKE/notarepo" "$SCRIPT" refresh
ok "not a git repo → silent, no state written" "no-state" "$([[ -e $FAKE/state ]] && echo state || echo no-state)"

# ── summary ──────────────────────────────────────────────────────────────
echo ""
echo "$PASS passed, $FAIL failed"
(( FAIL == 0 ))
