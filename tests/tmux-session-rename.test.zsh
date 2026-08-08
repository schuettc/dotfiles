#!/usr/bin/env zsh
# Tests for bin/tmux-session-rename.sh: prefix T renames the SESSION (the
# name is the identity — session-identity plan 2026-08-08). Must validate
# the charset, refuse names live sessions hold on ANY server, work with
# and without muster, and never send-keys.
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

WORK=$(mktemp -d)
# The shim scans ${TMUX_TMPDIR}/tmux-$UID/* for collisions — point that at
# a private dir so the test sees only its own servers.
export TMUX_TMPDIR="$WORK"
SOCKDIR="$WORK/tmux-$(id -u)"
trap 'tmux -S "$SOCKDIR/main" kill-server 2>/dev/null;
      tmux -S "$SOCKDIR/other" kill-server 2>/dev/null; rm -rf "$WORK"' EXIT

mkdir -p "$SOCKDIR"
tmux -S "$SOCKDIR/main" new-session -d -s start-name -x 80 -y 24
PANE=$(tmux -S "$SOCKDIR/main" display-message -p -t start-name '#{pane_id}')
export TMUX="$SOCKDIR/main,999,0"

name() { tmux -S "$SOCKDIR/main" display-message -p '#{session_name}'; }

# ── muster ABSENT: plain-tmux rename ────────────────────────────────
print '── fallback (no muster) ──'
PATH_SAVE="$PATH"
# Keep tmux reachable while dropping muster (~/.local/bin): a bare
# /usr/bin:/bin would strip Homebrew's tmux and break the shim itself.
TMUXDIR="$(dirname "$(command -v tmux)")"
NOMUSTER_PATH="$TMUXDIR:/usr/bin:/bin"
if command -v muster >/dev/null 2>&1 \
   && [[ "$(dirname "$(command -v muster)")" == "$TMUXDIR" ]]; then
  echo "muster shares tmux's dir — NOMUSTER_PATH can't strip it"; exit 1
fi
export PATH="$NOMUSTER_PATH"
"$REPO/bin/tmux-session-rename.sh" "$PANE" "dotfiles/nfl-4"
ok "renames the session"        "dotfiles/nfl-4" "$(name)"
"$REPO/bin/tmux-session-rename.sh" "$PANE" "bad name"
ok "invalid charset refused"    "dotfiles/nfl-4" "$(name)"
"$REPO/bin/tmux-session-rename.sh" "$PANE" "bad:name"
ok "colon refused"              "dotfiles/nfl-4" "$(name)"
"$REPO/bin/tmux-session-rename.sh" "$PANE" ""
ok "empty input is a no-op"     "dotfiles/nfl-4" "$(name)"

# ── collision with a live session on ANOTHER server ─────────────────
print '── cross-server collision ──'
tmux -S "$SOCKDIR/other" new-session -d -s taken-name -x 80 -y 24
"$REPO/bin/tmux-session-rename.sh" "$PANE" "taken-name"
ok "name held elsewhere refused" "dotfiles/nfl-4" "$(name)"
export PATH="$PATH_SAVE"

# ── muster PRESENT: become delegation AFTER the tmux rename ─────────
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
"$REPO/bin/tmux-session-rename.sh" "$PANE" "dotfiles/nfl-5"
ok "tmux renamed first"       "dotfiles/nfl-5" "$(name)"
ok "delegates to become"      "become dotfiles/nfl-5" "$(tail -1 "$MUSTER_ARGS_LOG")"

# ── muster present but PRE-become (probe fails): tmux-only ──────────
print '── degradation (muster without become) ──'
cat > "$WORK/bin/muster" <<'EOF'
#!/bin/sh
echo "$@" >> "${MUSTER_ARGS_LOG:?}"
exit 1
EOF
chmod +x "$WORK/bin/muster"
: > "$MUSTER_ARGS_LOG"
"$REPO/bin/tmux-session-rename.sh" "$PANE" "dotfiles/nfl-6"
ok "still renames tmux"          "dotfiles/nfl-6" "$(name)"
ok "only the probe hit muster"   "become --help" "$(cat "$MUSTER_ARGS_LOG")"

print
print "PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
