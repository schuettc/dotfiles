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
ok "subtitle reconciled after rename" "" "$(sub)"

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

# ── failed rename must not record the marker (retry stays possible) ─
# The collision scan already refuses a name that's LIVE anywhere, so a
# pre-created same-name session can't reach rename-session itself — it's
# caught above. Exercise the exit-status guard directly instead: shim tmux
# so rename-session fails (simulating a lost race / out-of-glob collision)
# while every other tmux call still hits the real server.
print '── failed rename leaves the marker unset ──'
REALTMUX="$(command -v tmux)"
mkdir -p "$WORK/bin2"
cat > "$WORK/bin2/tmux" <<EOF
#!/bin/sh
if [ "\$1" = "rename-session" ]; then
  exit 1
fi
exec "$REALTMUX" "\$@"
EOF
chmod +x "$WORK/bin2/tmux"
export PATH="$WORK/bin2:$NOMUSTER_PATH"
printf '%s\n' '{"type":"custom-title","customTitle":"rename-boom","sessionId":"u1"}' > "$TRANSCRIPT"
statusline "rename-boom" "$TRANSCRIPT"
ok "name unchanged on failed rename"   "operator-name"   "$(name)"
ok "marker not stamped with failed name" "0" "$([[ "$(marker)" == "rename-boom" ]] && echo 1 || echo 0)"
export PATH="$NOMUSTER_PATH"

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

# ── aligned fast path: no transcript read, no muster call ───────────
# A vacuous version of this block (transcript path that doesn't exist)
# would pass even if the fast path READ the transcript, because a missing
# file just yields an empty custom_title either way. Make it detectable:
# the transcript DOES exist and its custom-title DOES match session_name,
# a logging fake `muster` sits on PATH, and the marker is unset first so
# seeding is demonstrably the fast path's own doing. If the fast path ever
# fell through to the diverged branch (read the transcript, re-entered the
# rename logic), that branch would call muster — the log would be non-empty.
print '── aligned fast path ──'
mkdir -p "$WORK/bin"
cat > "$WORK/bin/muster" <<'EOF'
#!/bin/sh
echo "$@" >> "${MUSTER_ARGS_LOG:?}"
[ "$1" = "become" ] || exit 1
exit 0
EOF
chmod +x "$WORK/bin/muster"
export PATH="$WORK/bin:$NOMUSTER_PATH" MUSTER_ARGS_LOG="$WORK/args-fastpath.log"
rm -f "$MUSTER_ARGS_LOG"
tmux -S "$SOCKDIR/main" set-option -u -t "$PANE" @claude_task_promoted 2>/dev/null
printf '%s\n' '{"type":"custom-title","customTitle":"dotfiles/nfl-7","sessionId":"u1"}' > "$TRANSCRIPT"
statusline "dotfiles/nfl-7" "$TRANSCRIPT"
ok "aligned state stays put"      "dotfiles/nfl-7" "$(name)"
ok "marker seeded by fast path"   "dotfiles/nfl-7" "$(marker)"
ok "fast path never calls muster" "" "$(cat "$MUSTER_ARGS_LOG" 2>/dev/null)"

# ── aligned fast path also reconciles a stale subtitle == #S ────────
# Simulate the freeze case: a subtitle left equal to the (now-aligned)
# session name from an earlier diverged tick. The next aligned tick must
# clear it — the same reconciliation the successful-rename branch does,
# just reached from the other side.
print '── aligned tick clears a stale subtitle equal to #S ──'
tmux -S "$SOCKDIR/main" set-option -t "$PANE" @claude_task "dotfiles/nfl-7" 2>/dev/null
rm -f "$MUSTER_ARGS_LOG"
printf '%s\n' '{"type":"user"}' > "$TRANSCRIPT"
statusline "dotfiles/nfl-7" "$TRANSCRIPT"
ok "aligned tick leaves name"       "dotfiles/nfl-7" "$(name)"
ok "stale subtitle cleared"         ""               "$(sub)"
ok "still never calls muster"       ""               "$(cat "$MUSTER_ARGS_LOG" 2>/dev/null)"

export PATH="$PATH_SAVE"
print
print "PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
