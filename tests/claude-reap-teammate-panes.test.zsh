#!/usr/bin/env zsh
# claude-reap-teammate-panes.sh finds a finished teammate's pane on the lead's
# project server under either socket prefix: cast-<project> (what cast starts
# sessions on) and proj-<project> (a server started before the rename).
#
# Run directly:  zsh tests/claude-reap-teammate-panes.test.zsh
#
# A private tmux server under a temporary TMUX_TMPDIR stands in for the
# project's; HOME and XDG_CACHE_HOME are temporary too. Dry run only: nothing
# is killed and the machine's own tmux servers are never reached.

set -u
REPO="${0:A:h:h}"
SCRIPT="$REPO/bin/claude-reap-teammate-panes.sh"

typeset -g PASS=0 FAIL=0
ok() {
  if [[ "$2" == "$3" ]]; then
    (( PASS++ )); printf '  ok   %s\n' "$1"
  else
    (( FAIL++ )); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
  fi
}

TMP=$(mktemp -d); TMP=${TMP:A}
export TMUX_TMPDIR="$TMP/tmux" HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache"
mkdir -p "$TMUX_TMPDIR" "$HOME/.claude/teams/t" "$XDG_CACHE_HOME"
unset TMUX TMUX_PANE
SOCKS=()
trap 'for s in $SOCKS; do tmux -L "$s" kill-server 2>/dev/null; done; rm -rf "$TMP"' EXIT

# reap <socket>: a teammate pane on <socket>, idle and just joined, with the
# lead in .../demo; prints the dry run's row for it ("<socket> would reap").
reap() {
  local sock=$1
  SOCKS+=("$sock")
  tmux -L "$sock" -f /dev/null new-session -d -s demo -x 80 -y 24 'sleep 600'
  local pane; pane=$(tmux -L "$sock" display-message -p -t demo '#{pane_id}')
  tmux -L "$sock" select-pane -t "$pane" -T '✳ idle'
  cat > "$HOME/.claude/teams/t/config.json" <<EOF
{"members": [
  {"tmuxPaneId": "leader", "cwd": "$TMP/work/demo"},
  {"tmuxPaneId": "$pane", "agentId": "a1", "name": "mate", "joinedAt": $(( $(date +%s) * 1000 ))}
]}
EOF
  bash "$SCRIPT" --idle-minutes 0 --sample-gap 0 2>&1 | awk '$4 ~ /m$/ {print $1, $5, $6}'
  tmux -L "$sock" kill-server 2>/dev/null
}

echo "── teammate panes are found on either socket prefix ──"
ok "a cast- server's teammate pane" "cast-demo would reap" "$(reap cast-demo)"
ok "a proj- server's teammate pane" "proj-demo would reap" "$(reap proj-demo)"

print
print "PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
