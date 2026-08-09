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
# proj() also fires the update-nudge script; point it at throwaway state and
# a non-repo so it never touches the real ~/.cache/dotfiles-update-state or
# does a real network fetch against the user's actual clone.
export DOTFILES_UPDATE_STATE="$TMP/update-state"
export DOTFILES_UPDATE_REPO="$TMP/notarepo"    # not a git repo → refresh exits 0 instantly
mkdir -p "$DOTFILES_UPDATE_REPO"
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
# Screen 1's while loop must not re-show itself for a real project pick (only
# the add/remove rows loop back) — it hands off to Screen 2 exactly once.
# proj() always shows Screen 2 next (session-identity: no non-git special
# case), so the picker is shown twice total: Screen 1, then Screen 2.
script_picker "$TMP/GitHub/repo-a"
proj >/dev/null 2>&1
ok "picker not re-shown for screen 1" "2" "$(shown)"

echo "── Screen 2: sessions, not branches ──"
print -- "$TMP/GitHub" > "$ROOTS"
# Re-stub launch to RECORD its arguments (still never runs tmux).
__proj_launch() { print -r -- "$1|$2|$3|${4:-}" > "$TMP/launch"; }
rm -f "$TMP/launch"
script_picker "$TMP/GitHub/repo-a" "$ESC"
proj >/dev/null 2>&1
ok "screen 2 shown"          "2" "$(shown)"
ok "home base row offered"   "1" "$(menu 2 | grep -cF -- '🏠 repo-a')"
ok "new-work row offered"    "1" "$(menu 2 | grep -cF -- '+ new work…')"
ok "no worktree rows"        "0" "$(menu 2 | grep -c -- '▸\|worktree\|branch')"
ok "screen 2 is 2 rows"      "2" "$(menu 2 | wc -l | tr -d ' ')"

echo "── + new work creates <project>/<work> in the primary clone ──"
__proj_read_work() { print -r -- "nfl-4"; }
script_picker "$TMP/GitHub/repo-a" "+ new work…"
proj >/dev/null 2>&1
ok "launch called with the work name" \
   "proj-repo-a|repo-a/nfl-4|$TMP/GitHub/repo-a|" "$(cat "$TMP/launch")"

echo "── invalid work names are refused ──"
__proj_read_work() { print -r -- "bad name"; }
rm -f "$TMP/launch"
script_picker "$TMP/GitHub/repo-a" "+ new work…"
proj >/dev/null 2>&1
ok "no launch on invalid name" "" "$(cat "$TMP/launch" 2>/dev/null)"

echo "── home base row opens the bare project session ──"
rm -f "$TMP/launch"
script_picker "$TMP/GitHub/repo-a" "🏠 repo-a — home base (primary clone)"
proj >/dev/null 2>&1
ok "home base launches bare name" \
   "proj-repo-a|repo-a|$TMP/GitHub/repo-a|" "$(cat "$TMP/launch")"

echo "── proj <project> jumps straight to Screen 2 ──"
rm -f "$TMP/launch"
script_picker "$ESC"
proj repo-a >/dev/null 2>&1
ok "screen 1 skipped"          "1" "$(shown)"
ok "screen 2 menu shown first" "1" "$(menu 1 | grep -cF -- '+ new work…')"

echo "── live sessions listed identity-first, legacy names included ──"
__proj_servers() { print -- fake; }
tmux() {
  case "$*" in
    *" ls -F"*) printf 'repo-a/nfl-3\ttopic x\nrepo-a-2\t\nrepo-b/other\t\n';;
    *) return 1;;
  esac
}
script_picker "$TMP/GitHub/repo-a" "$ESC"
proj >/dev/null 2>&1
ok "named session listed with topic" "1" "$(menu 2 | grep -cF -- '● repo-a/nfl-3  — topic x')"
ok "legacy numbered slot listed"     "1" "$(menu 2 | grep -cF -- '● repo-a-2')"
ok "other project's session hidden"  "0" "$(menu 2 | grep -cF -- 'repo-b/other')"
tmux() { return 1; }
__proj_servers() { return 0; }

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
