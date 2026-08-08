#!/usr/bin/env zsh
# Tests for statusline.sh's name-sync block (session-identity plan
# 2026-08-08): a user-set name (transcript custom-title == session_name)
# RENAMES the tmux session; auto topics only write the @claude_task
# subtitle; a stale title (== the promoted marker) never reverts an
# operator rename; collisions with live sessions refuse the rename.
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
command -v jq   >/dev/null || { echo "jq required";   exit 1; }

WORK=$(mktemp -d)
export TMUX_TMPDIR="$WORK"          # scoped: the collision scan globs this
SOCKDIR="$WORK/tmux-$(id -u)"
trap 'tmux -S "$SOCKDIR/main" kill-server 2>/dev/null;
      tmux -S "$SOCKDIR/other" kill-server 2>/dev/null; rm -rf "$WORK"' EXIT
mkdir -p "$SOCKDIR"
tmux -S "$SOCKDIR/main" new-session -d -s start-name -x 80 -y 24
PANE=$(tmux -S "$SOCKDIR/main" display-message -p -t start-name '#{pane_id}')
export TMUX="$SOCKDIR/main,999,0" TMUX_PANE="$PANE"

name()   { tmux -S "$SOCKDIR/main" display-message -p '#{session_name}'; }
sub()    { tmux -S "$SOCKDIR/main" show-option -qv -t "$PANE" @claude_task; }
marker() { tmux -S "$SOCKDIR/main" show-option -qv -t "$PANE" @claude_task_promoted; }

TRANSCRIPT="$WORK/t.jsonl"
statusline() {  # $1 = session_name, $2 = transcript path ("" for none)
  jq -n --arg n "$1" --arg tp "$2" \
    '{model:{display_name:"Fable"},context_window:{used_percentage:10},
      workspace:{current_dir:"/w"},session_name:$n,transcript_path:$tp}' \
    | bash "$REPO/config/claude/statusline.sh" >/dev/null 2>&1
}

PATH_SAVE="$PATH"
# Keep tmux and jq reachable while dropping muster (~/.local/bin): a bare
# /usr/bin:/bin would strip the Homebrew binaries the script under test uses.
NOMUSTER_PATH="$(dirname "$(command -v tmux)"):$(dirname "$(command -v jq)"):/usr/bin:/bin"
if PATH="$NOMUSTER_PATH" command -v muster >/dev/null 2>&1; then
  echo "muster still reachable on NOMUSTER_PATH — adjust the test"; exit 1
fi

# ── auto topic: subtitle only, session name untouched ───────────────
print '── auto topic → subtitle only ──'
printf '%s\n' '{"type":"user"}' > "$TRANSCRIPT"
export PATH="$NOMUSTER_PATH"
statusline "Debug tmux titles" "$TRANSCRIPT"
ok "session name untouched"  "start-name"        "$(name)"
ok "topic lands in subtitle" "Debug tmux titles" "$(sub)"

# ── user-set valid name, muster absent: tmux rename ─────────────────
print '── user-set name → rename (no muster) ──'
printf '%s\n' '{"type":"custom-title","customTitle":"dotfiles/nfl-4","sessionId":"u1"}' > "$TRANSCRIPT"
statusline "dotfiles/nfl-4" "$TRANSCRIPT"
ok "session renamed"  "dotfiles/nfl-4" "$(name)"
ok "marker recorded"  "dotfiles/nfl-4" "$(marker)"

# ── stale title never reverts an operator rename ────────────────────
print '── stale title vs prefix T ──'
tmux -S "$SOCKDIR/main" rename-session -t "=dotfiles/nfl-4" "operator-name"
statusline "dotfiles/nfl-4" "$TRANSCRIPT"   # transcript still holds the OLD title
ok "operator rename survives" "operator-name" "$(name)"

# ── invalid charset: subtitle only, even when user-set ──────────────
print '── invalid charset never renames ──'
printf '%s\n' '{"type":"custom-title","customTitle":"has spaces","sessionId":"u1"}' > "$TRANSCRIPT"
statusline "has spaces" "$TRANSCRIPT"
ok "no rename on bad charset" "operator-name" "$(name)"
ok "subtitle still updates"   "has spaces"    "$(sub)"

# ── collision: a live session elsewhere holds the name ──────────────
print '── collision refusal ──'
tmux -S "$SOCKDIR/other" new-session -d -s wanted -x 80 -y 24
printf '%s\n' '{"type":"custom-title","customTitle":"wanted","sessionId":"u1"}' > "$TRANSCRIPT"
statusline "wanted" "$TRANSCRIPT"
ok "held name not stolen" "operator-name" "$(name)"

# ── muster present: become --no-inject after the rename ─────────────
print '── delegation (fake muster with become) ──'
mkdir -p "$WORK/bin"
cat > "$WORK/bin/muster" <<'EOF'
#!/bin/sh
echo "$@" >> "${MUSTER_ARGS_LOG:?}"
[ "$1" = "become" ] || exit 1
exit 0
EOF
chmod +x "$WORK/bin/muster"
export PATH="$WORK/bin:$NOMUSTER_PATH" MUSTER_ARGS_LOG="$WORK/args.log"
printf '%s\n' '{"type":"custom-title","customTitle":"dotfiles/nfl-7","sessionId":"u1"}' > "$TRANSCRIPT"
statusline "dotfiles/nfl-7" "$TRANSCRIPT"
ok "renamed with muster present" "dotfiles/nfl-7" "$(name)"
ok "become --no-inject called"   "become --no-inject dotfiles/nfl-7" "$(tail -1 "$MUSTER_ARGS_LOG")"

# ── aligned fast path: no transcript read ───────────────────────────
print '── aligned fast path ──'
export PATH="$NOMUSTER_PATH"
statusline "dotfiles/nfl-7" "$WORK/does-not-exist.jsonl"   # would fail if read mattered
ok "aligned state stays put" "dotfiles/nfl-7" "$(name)"
ok "marker seeded"           "dotfiles/nfl-7" "$(marker)"

export PATH="$PATH_SAVE"
print
print "PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
