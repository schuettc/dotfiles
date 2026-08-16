#!/usr/bin/env zsh
# Tests for bin/tmux-session-rename.sh: prefix T renames the SESSION (the
# name is the identity — session-identity plan 2026-08-08). Must validate
# the charset, refuse names live sessions hold on ANY server, work with
# and without muster, and never send-keys.
#
# It also owns BOTH halves of the prefix-T gesture now: `--prompt` computes
# the pre-fill (the work segment alone) and issues the command-prompt, and
# the rename half re-attaches the project prefix to a bare work name. The
# project half of the identity is never typed — see the header comment in
# the script for why.
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

# Target the pane id: with no client and no -t, tmux resolves to the most
# recently created session, so the extra sessions the collision tests spawn
# would be the one reported. Pane ids survive renames; session names don't.
name() { tmux -S "$SOCKDIR/main" display-message -p -t "$PANE" '#{session_name}'; }

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
"$REPO/bin/tmux-session-rename.sh" "$PANE" "bad.name"
ok "invalid charset refused"    "dotfiles/nfl-4" "$(name)"
"$REPO/bin/tmux-session-rename.sh" "$PANE" "bad:name"
ok "colon refused"              "dotfiles/nfl-4" "$(name)"
"$REPO/bin/tmux-session-rename.sh" "$PANE" ""
ok "empty input is a no-op"     "dotfiles/nfl-4" "$(name)"

# ── composition: a bare work name inherits the project prefix ───────
# The operator types the WORK, never the project — the project half is a
# property of where the session lives, and re-typing it was the whole
# reason a cleared prompt used to strip a session out of its project.
print '── project prefix is re-attached ──'
"$REPO/bin/tmux-session-rename.sh" "$PANE" "nfl-5"
ok "bare work gets the prefix"   "dotfiles/nfl-5" "$(name)"
"$REPO/bin/tmux-session-rename.sh" "$PANE" "fix prefix T"
ok "slugified, then prefixed"    "dotfiles/fix-prefix-T" "$(name)"
# Escape hatch: a typed name that already carries a '/' is taken verbatim,
# which is the only way to re-home a session (or leave it deliberately bare
# under a one-segment name).
"$REPO/bin/tmux-session-rename.sh" "$PANE" "otherproj/nfl-4"
ok "slashed name taken verbatim" "otherproj/nfl-4" "$(name)"
# Home base (#S has no '/'): the whole name IS the project, so a bare work
# name promotes it into <project>/<work> rather than replacing it.
tmux -S "$SOCKDIR/main" rename-session -t "$PANE" "homebase"
"$REPO/bin/tmux-session-rename.sh" "$PANE" "nfl-7"
ok "home base promotes to work"   "homebase/nfl-7" "$(name)"
# Re-typing the work you already have is a no-op, not a self-collision:
# composition happens BEFORE the equality check.
"$REPO/bin/tmux-session-rename.sh" "$PANE" "nfl-7"
ok "same work is a no-op"         "homebase/nfl-7" "$(name)"
tmux -S "$SOCKDIR/main" rename-session -t "$PANE" "dotfiles/nfl-4"

# ── prefill: the prompt offers the work segment alone ───────────────
# --prompt needs an attached client for command-prompt, which a headless
# test server has none of. Shim tmux to log the command-prompt argv (and
# pass everything else through to the real server) and assert on -I.
print '── prompt pre-fill ──'
REALTMUX="$(command -v tmux)"
mkdir -p "$WORK/bin3"
cat > "$WORK/bin3/tmux" <<EOF
#!/bin/sh
if [ "\$1" = "command-prompt" ]; then
  printf '%s\n' "\$*" > "\${PROMPT_LOG:?}"
  exit 0
fi
exec "$REALTMUX" "\$@"
EOF
chmod +x "$WORK/bin3/tmux"
export PROMPT_LOG="$WORK/prompt.log"
PATH="$WORK/bin3:$NOMUSTER_PATH" "$REPO/bin/tmux-session-rename.sh" --prompt "$PANE"
ok "pre-fills the work only"  "nfl-4" "$(sed -n 's/^command-prompt -I \(.*\) -p .*/\1/p' "$PROMPT_LOG")"
ok "prompts for work, not session" "1" \
   "$(grep -c 'rename work:' "$PROMPT_LOG")"
ok "hands the pane id back"   "1" \
   "$(grep -c "tmux-session-rename.sh $PANE" "$PROMPT_LOG")"
# The binding passes #{client_tty}: a run-shell child is client-less, so an
# untargeted prompt would land on whichever client tmux used last — wrong on
# a server with one client per session.
PATH="$WORK/bin3:$NOMUSTER_PATH" "$REPO/bin/tmux-session-rename.sh" --prompt "$PANE" /dev/ttys999
ok "targets the pressing client" "1" \
   "$(grep -c -- '-t /dev/ttys999' "$PROMPT_LOG")"
tmux -S "$SOCKDIR/main" rename-session -t "$PANE" "homebase"
PATH="$WORK/bin3:$NOMUSTER_PATH" "$REPO/bin/tmux-session-rename.sh" --prompt "$PANE"
ok "home base pre-fills empty" "" "$(sed -n 's/^command-prompt -I \(.*\) -p .*/\1/p' "$PROMPT_LOG")"
tmux -S "$SOCKDIR/main" rename-session -t "$PANE" "dotfiles/nfl-4"

# ── collision with a live session on ANOTHER server ─────────────────
# The typed work composes to dotfiles/taken-name, so the session that
# holds the name has to be created under that composed name.
print '── cross-server collision ──'
tmux -S "$SOCKDIR/other" new-session -d -s dotfiles/taken-name -x 80 -y 24
"$REPO/bin/tmux-session-rename.sh" "$PANE" "taken-name"
ok "name held elsewhere refused" "dotfiles/nfl-4" "$(name)"

# ── collision with a live session on the SAME server ─────────────────
# The scan globs every socket under TMUX_TMPDIR/tmux-$UID, including the
# shim's own server — confirm a same-server collision is caught the same
# way as cross-server, before rename-session is ever attempted.
print '── same-server collision ──'
tmux -S "$SOCKDIR/main" new-session -d -s dotfiles/local-taken -x 80 -y 24
"$REPO/bin/tmux-session-rename.sh" "$PANE" "local-taken"
ok "name held on same server refused" "dotfiles/nfl-4" "$(name)"
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

# ── rename-session failure must not report success or call become ───
# The collision scan can't reach this path directly: a pre-created
# same-name session is caught by the scan above, before rename-session
# ever runs (see "same-server collision"). Force the underlying failure
# instead — shim tmux so rename-session itself errors (simulating a lost
# race) while every other tmux call still hits the real server — and
# exercise the exit-status guard.
print '── rename-session failure is not swallowed ──'
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
: > "$MUSTER_ARGS_LOG"
BEFORE="$(name)"
export PATH="$WORK/bin2:$WORK/bin:$NOMUSTER_PATH"
"$REPO/bin/tmux-session-rename.sh" "$PANE" "rename-boom"
ok "name unchanged on failed rename" "$BEFORE" "$(name)"
ok "become skipped on failed rename" "" "$(cat "$MUSTER_ARGS_LOG" 2>/dev/null)"
export PATH="$PATH_SAVE"

print
print "PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
