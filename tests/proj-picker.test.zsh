#!/usr/bin/env zsh
# Tests for proj()'s Screen 1 — specifically the two roots-file editor rows
# ("[+ add …]" / "[- remove …]") and the loop that returns you to a rebuilt
# list afterwards.
#
# Run directly:  zsh tests/proj-picker.test.zsh
#
# proj() calls fzf inside a command substitution, i.e. a SUBSHELL. A stub
# that recorded what it saw in a shell variable would lose every write, and
# a pick-queue held in an array would never advance — proj() would re-pick
# the same row forever. So the queue and the transcript live in files.
#
# No `set -u` here, unlike proj-roots.test.zsh: proj() tests "$1" with no
# argument, which is fine in the interactive shells it runs in but fatal
# under nounset — the shell would exit before the first assertion.

REPO="${0:A:h:h}"
source "$REPO/config/zsh/03-proj-roots.zsh"
# 04-aliases.zsh defines aliases and a claude() wrapper alongside proj();
# sourcing the real file is the point — a copy would let the thing under
# test drift away from what ships.
source "$REPO/config/zsh/04-aliases.zsh"
# …but its aliases rebind grep->rg and cat->bat, which changes the output
# the assertions below parse. Drop them; proj() itself doesn't rely on any.
unalias -m '*'

typeset -g PASS=0 FAIL=0

ok() {  # ok <label> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    (( PASS++ )); printf '  ok   %s\n' "$1"
  else
    (( FAIL++ )); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
  fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/GitHub/repo-a" "$TMP/dotfiles"
export XDG_CONFIG_HOME="$TMP/xdg"
mkdir -p "$XDG_CONFIG_HOME/proj"
ROOTS="$XDG_CONFIG_HOME/proj/roots"

PICKS="$TMP/picks"      # one canned answer per line, consumed in order
COUNT="$TMP/count"      # how many times the picker has been shown
ESC='__ESC__'           # a canned answer meaning "user pressed Esc"

# Queue the picker answers for one proj() run and reset the transcript.
script_picker() { print -rl -- "$@" > "$PICKS"; print -- 0 > "$COUNT"; }
shown() { print -- "$(<"$COUNT")"; }            # times the picker appeared
menu()  { cat "$TMP/menu-$1" 2>/dev/null; }     # the Nth menu, as shown

fzf() {
  local menu n next
  menu=$(cat)
  n=$(( $(<"$COUNT") + 1 ))
  print -- "$n" > "$COUNT"
  print -r -- "$menu" > "$TMP/menu-$n"

  [[ -s "$PICKS" ]] || return 0
  next=$(head -1 "$PICKS")
  tail -n +2 "$PICKS" > "$PICKS.new" && mv "$PICKS.new" "$PICKS"
  [[ "$next" == "$ESC" ]] && return 0
  print -r -- "$next"
}

# No live sessions, and never a real tmux call.
tmux() { return 1; }
# Selecting a real project sends proj() into session creation, which shells
# out to bin/proj-right-column.sh and blocks. Screen 1 is what's under test,
# so stop at its edge.
__proj_launch() { return 0; }
__proj_worktree_list() { return 0; }

ADD_ROW="[+ add new project root…]"
RM_ROW="[- remove a project root…]"

echo "── the editor rows are offered ──"
cat > "$ROOTS" <<EOF
$TMP/GitHub
project:$TMP/dotfiles
EOF
script_picker "$ESC"
proj >/dev/null 2>&1
ok "add row offered"    "1" "$(menu 1 | grep -cF -- "$ADD_ROW")"
ok "remove row offered" "1" "$(menu 1 | grep -cF -- "$RM_ROW")"
ok "projects listed"    "1" "$(menu 1 | grep -cF -- "$TMP/dotfiles")"
# Editors sit below the projects so they're out of the way of the common case.
ok "editors are last" "$ADD_ROW,$RM_ROW" "$(menu 1 | tail -2 | paste -sd, -)"

echo "── picking remove edits the file and loops ──"
cat > "$ROOTS" <<EOF
# keep me
$TMP/GitHub
project:$TMP/dotfiles
EOF
# 1st: the picker — choose the remove row.
# 2nd: __proj_remove_root's own picker, whose menu is "<index>\t<entry>" —
#      echo back the line for the GitHub root (file line 2).
# 3rd: the rebuilt picker — Esc out.
script_picker "$RM_ROW" "2	$TMP/GitHub" "$ESC"
proj >/dev/null 2>&1
ok "picker ran three times"  "3" "$(shown)"
ok "entry removed from file" "# keep me,project:$TMP/dotfiles" \
   "${(pj:,:)${(@f)$(<"$ROOTS")}}"
ok "removed project gone from rebuilt list" \
   "0" "$(menu 3 | grep -cF -- "$TMP/GitHub/repo-a")"
ok "remaining project still listed" \
   "1" "$(menu 3 | grep -cF -- "$TMP/dotfiles")"

echo "── cancelling the remove picker returns to the list ──"
print -- "$TMP/GitHub" > "$ROOTS"
script_picker "$RM_ROW" "$ESC" "$ESC"
proj >/dev/null 2>&1
ok "loops back after cancel"  "3" "$(shown)"
ok "file untouched by cancel" "$TMP/GitHub" "$(<"$ROOTS")"

echo "── picking a project exits the loop ──"
print -- "$TMP/GitHub" > "$ROOTS"
script_picker "$TMP/GitHub/repo-a"
proj >/dev/null 2>&1
ok "picker ran once" "1" "$(shown)"

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
