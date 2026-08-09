#!/usr/bin/env zsh
# pt and the auto-join hook after the session-identity change: pt creates
# <project>/<work> (never a numbered slot); auto-join never mints sessions
# — it hands the project to proj's Screen 2.
REPO="${0:A:h:h}"
source "$REPO/config/zsh/03-proj-roots.zsh"
source "$REPO/config/zsh/04-aliases.zsh"
unalias -m '*'

typeset -g PASS=0 FAIL=0
ok() {
  if [[ "$2" == "$3" ]]; then
    (( PASS++ )); printf '  ok   %s\n' "$1"
  else
    (( FAIL++ )); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
  fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/GitHub/repo-a"
export XDG_CONFIG_HOME="$TMP/xdg"
mkdir -p "$XDG_CONFIG_HOME/proj"
print -- "$TMP/GitHub" > "$XDG_CONFIG_HOME/proj/roots"

# Stub the endgames — record, never exec/attach.
__proj_ensure_session() { print -r -- "ensure:$1|$2|$3|${4:-}" >> "$TMP/log"; }
__proj_attach_exec()    { print -r -- "attach:$1|$2" >> "$TMP/log"; }
__proj_launch()         { print -r -- "launch:$1|$2|$3|${4:-}" >> "$TMP/log"; }
tmux() { return 1; }

echo "── pt <work> inside a project dir ──"
: > "$TMP/log"; unset TMUX
( cd "$TMP/GitHub/repo-a" && pt nfl-4 ) >/dev/null 2>&1
ok "ensure + exec attach, named session" \
   "ensure:proj-repo-a|repo-a/nfl-4|$TMP/GitHub/repo-a|
attach:proj-repo-a|repo-a/nfl-4" "$(cat "$TMP/log")"

echo "── pt <project> <work> from anywhere ──"
: > "$TMP/log"
( cd "$TMP" && pt repo-a nfl-5 ) >/dev/null 2>&1
ok "explicit project resolves" \
   "ensure:proj-repo-a|repo-a/nfl-5|$TMP/GitHub/repo-a|
attach:proj-repo-a|repo-a/nfl-5" "$(cat "$TMP/log")"

echo "── pt --claude passes the agent through ──"
: > "$TMP/log"
( cd "$TMP/GitHub/repo-a" && pt --claude nfl-6 ) >/dev/null 2>&1
ok "agent recorded" \
   "ensure:proj-repo-a|repo-a/nfl-6|$TMP/GitHub/repo-a|claude
attach:proj-repo-a|repo-a/nfl-6" "$(cat "$TMP/log")"

echo "── pt refuses bad or missing names ──"
: > "$TMP/log"
( cd "$TMP/GitHub/repo-a" && pt "bad name" ) >/dev/null 2>&1
ok "invalid name: nothing launched" "" "$(cat "$TMP/log")"
( cd "$TMP" && pt ) >/dev/null 2>&1
ok "no args outside a project: nothing launched" "" "$(cat "$TMP/log")"

echo "── pt inside tmux uses launch (switch, not exec) ──"
: > "$TMP/log"; export TMUX="fake,1,0"
( cd "$TMP/GitHub/repo-a" && pt nfl-7 ) >/dev/null 2>&1
ok "launch path inside tmux" \
   "launch:proj-repo-a|repo-a/nfl-7|$TMP/GitHub/repo-a|" "$(cat "$TMP/log")"
unset TMUX

echo "── auto-join hands the project to proj ──"
# Run in a fresh INTERACTIVE zsh (-i satisfies the $- guard) with stubs.
autojoin() {  # $1 = extra env setup, $2 = cwd
  zsh -fi -c "
    export HOME='$TMP'   # a real ~/.no-auto-tmux must not skew the test
    source '$REPO/config/zsh/03-proj-roots.zsh'
    source '$REPO/config/zsh/04-aliases.zsh'
    unalias -m '*' 2>/dev/null
    proj() { print -r -- \"proj:\$*\" >> '$TMP/log'; }
    $1
    cd '$2'
    source '$REPO/config/zsh/06-tmux-autojoin.zsh'
  " >/dev/null 2>&1
}
: > "$TMP/log"
autojoin 'unset TMUX' "$TMP/GitHub/repo-a"
ok "proj called with the project" "proj:repo-a" "$(cat "$TMP/log")"
: > "$TMP/log"
autojoin 'unset TMUX; export AUTO_CLAUDE=1' "$TMP/GitHub/repo-a"
ok "AUTO_CLAUDE adds --claude" "proj:--claude repo-a" "$(cat "$TMP/log")"
: > "$TMP/log"
autojoin 'export TMUX=fake,1,0' "$TMP/GitHub/repo-a"
ok "inside tmux: untouched" "" "$(cat "$TMP/log")"
: > "$TMP/log"
autojoin 'unset TMUX' "$TMP"
ok "outside a project: untouched" "" "$(cat "$TMP/log")"

print
print "PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
