#!/usr/bin/env zsh
# Tests for statusline.sh's name-sync block: a user-set name (transcript
# custom-title == session_name) is PROMOTED to a manual label; an auto topic
# stays display-only and defers to the manual flag; nothing ever demotes.
# (naming-contract plan, 2026-08-05). Real throwaway tmux server; a fake
# `muster` script records delegation.

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
command -v jq   >/dev/null || { echo "jq required"; exit 1; }

WORK=$(mktemp -d)
trap 'tmux -S "$WORK/sock" kill-server 2>/dev/null; rm -rf "$WORK"' EXIT
tmux -S "$WORK/sock" new-session -d -s t -x 80 -y 24
PANE=$(tmux -S "$WORK/sock" display-message -p -t t '#{pane_id}')
export TMUX="$WORK/sock,999,0" TMUX_PANE="$PANE"

opt()    { tmux -S "$WORK/sock" show-option -qv -t t @claude_task; }
manual() { tmux -S "$WORK/sock" show-option -qv -t t @claude_task_manual; }
reset()  { tmux -S "$WORK/sock" set-option -u -t t @claude_task 2>/dev/null
           tmux -S "$WORK/sock" set-option -u -t t @claude_task_manual 2>/dev/null; }

TRANSCRIPT="$WORK/t.jsonl"
statusline() {  # $1 = session_name, $2 = transcript path ("" for none)
  jq -n --arg n "$1" --arg tp "$2" \
    '{model:{display_name:"Fable"},context_window:{used_percentage:10},
      workspace:{current_dir:"/w"},session_name:$n,transcript_path:$tp}' \
    | "$REPO/config/claude/statusline.sh" >/dev/null 2>&1
}

# ── auto topic: display-only (today's behavior, must survive) ───────
reset
printf '%s\n' '{"type":"user"}' > "$TRANSCRIPT"   # no custom-title record
statusline "Debug tmux titles" "$TRANSCRIPT"
ok "auto topic lands in label" "Debug tmux titles" "$(opt)"
ok "auto topic sets NO manual flag" "" "$(manual)"

# ── user-set name, muster absent: plain-tmux promotion ──────────────
reset
printf '%s\n' '{"type":"custom-title","customTitle":"nfl-3","sessionId":"u1"}' > "$TRANSCRIPT"
PATH_SAVE="$PATH"
# Strip muster (and everything else non-core) but keep tmux+jq reachable —
# on Homebrew/Apple Silicon they live in /opt/homebrew/bin, not /usr/bin.
TMUX_DIR="${$(command -v tmux):h}"
export PATH="$TMUX_DIR:/usr/bin:/bin"
statusline "nfl-3" "$TRANSCRIPT"
export PATH="$PATH_SAVE"
ok "custom title promotes label"  "nfl-3" "$(opt)"
ok "custom title promotes manual" "1"     "$(manual)"

# ── user-set name, muster present: --no-inject delegation ───────────
reset
mkdir -p "$WORK/bin"
cat > "$WORK/bin/muster" <<'EOF'
#!/bin/sh
echo "$@" >> "${MUSTER_ARGS_LOG:?}"
# Simulate the real `muster label --no-inject <name>` side effect (that
# flag doesn't exist on this machine yet — pending muster PR, see
# task-2-brief.md). Production `muster label` sets the pane's tmux option
# pair itself (bin/tmux-muster-label.sh's delegation branch relies on the
# same fact); the "never demote" block right after this one needs that
# state to have landed, same as it would against a real muster.
if [ "$1" = "label" ]; then
  shift
  [ "$1" = "--no-inject" ] && shift
  if [ -n "${1:-}" ] && [ -n "${TMUX_PANE:-}" ]; then
    tmux set-option -t "$TMUX_PANE" @claude_task "$1"
    tmux set-option -t "$TMUX_PANE" @claude_task_manual 1
  fi
fi
EOF
chmod +x "$WORK/bin/muster"
export PATH="$WORK/bin:$PATH" MUSTER_ARGS_LOG="$WORK/args.log"
statusline "nfl-3" "$TRANSCRIPT"
ok "delegates with --no-inject" "label --no-inject nfl-3" "$(tail -1 "$WORK/args.log")"

# ── user-set name, muster present but rejects --no-inject: a binary
# predating the flag fails the parse and exits non-zero without touching
# pane options at all. The caller must fall back to the plain-tmux pair
# write itself — same two lines as the muster-absent branch — or the
# pane goes unlabeled and every future tick re-greps + re-spawns muster
# for nothing. ─────────────────────────────────────────────────────────
reset
cat > "$WORK/bin/muster" <<'EOF'
#!/bin/sh
echo "$@" >> "${MUSTER_ARGS_LOG:?}"
# Simulate a muster binary predating --no-inject: the flag parse fails,
# it exits non-zero, and — like the real failure mode — never touches
# the pane's tmux options.
exit 1
EOF
chmod +x "$WORK/bin/muster"
export PATH="$WORK/bin:$PATH" MUSTER_ARGS_LOG="$WORK/args-fail.log"
statusline "nfl-3" "$TRANSCRIPT"
ok "failing muster still sets tmux-only label" "nfl-3" "$(opt)"
ok "failing muster still sets manual flag"     "1"     "$(manual)"

# ── never demote: manual flag blocks a later auto topic ─────────────
printf '%s\n' '{"type":"user"}' > "$TRANSCRIPT"   # custom-title gone from a NEW transcript
statusline "Some auto topic" "$TRANSCRIPT"
ok "auto topic never clobbers manual label" "nfl-3" "$(opt)"
ok "manual flag survives"                   "1"     "$(manual)"

# ── fast path: aligned state reads no transcript ────────────────────
rm -f "$MUSTER_ARGS_LOG"
statusline "nfl-3" "$WORK/does-not-exist.jsonl"   # would fail if read mattered
ok "aligned state does nothing" "" "$(cat "$MUSTER_ARGS_LOG" 2>/dev/null)"

# ── fast path, stronger version: still skips muster even when the
# transcript DOES exist and its custom-title DOES match — proving the
# early-return happens before the transcript is ever read, not that it
# happens to re-derive the same no-op result after reading it. A fake
# muster that would log a call sits on PATH the whole time. ─────────
tmux -S "$WORK/sock" set-option -t t @claude_task "nfl-3"
tmux -S "$WORK/sock" set-option -t t @claude_task_manual 1
printf '%s\n' '{"type":"custom-title","customTitle":"nfl-3","sessionId":"u1"}' > "$TRANSCRIPT"
cat > "$WORK/bin/muster" <<'EOF'
#!/bin/sh
echo "$@" >> "${MUSTER_ARGS_LOG:?}"
EOF
chmod +x "$WORK/bin/muster"
export MUSTER_ARGS_LOG="$WORK/args-fastpath.log"
rm -f "$MUSTER_ARGS_LOG"
statusline "nfl-3" "$TRANSCRIPT"
ok "fast path skips muster even with matching transcript present" "" "$(cat "$MUSTER_ARGS_LOG" 2>/dev/null)"

# ── promotion marker: a prefix-T label must survive a STALE title ────
# The live bug (hit twice, 2026-08-06): prefix T sets a new label and types
# /rename into the pane; on a busy pane the keystrokes are eaten, so the
# transcript keeps the OLD custom-title. Every later tick then re-promoted
# that old title over the operator's fresh label — a revert hours after the
# gesture. @claude_task_promoted records the last title this script acted
# on, so an unchanged title can't promote twice.
marker() { tmux -S "$WORK/sock" show-option -qv -t t @claude_task_promoted; }
clear_marker() { tmux -S "$WORK/sock" set-option -u -t t @claude_task_promoted 2>/dev/null; }
set_pair() {  # $1 = label — simulate a prefix-T gesture (bypasses statusline)
  tmux -S "$WORK/sock" set-option -t t @claude_task "$1"
  tmux -S "$WORK/sock" set-option -t t @claude_task_manual 1
}

# Restore the side-effecting fake muster (the fast-path block above left a
# log-only one on PATH, which would make promotions look like no-ops).
cat > "$WORK/bin/muster" <<'EOF'
#!/bin/sh
echo "$@" >> "${MUSTER_ARGS_LOG:?}"
if [ "$1" = "label" ]; then
  shift
  [ "$1" = "--no-inject" ] && shift
  if [ -n "${1:-}" ] && [ -n "${TMUX_PANE:-}" ]; then
    tmux set-option -t "$TMUX_PANE" @claude_task "$1"
    tmux set-option -t "$TMUX_PANE" @claude_task_manual 1
  fi
fi
EOF
chmod +x "$WORK/bin/muster"
export MUSTER_ARGS_LOG="$WORK/args-marker.log"

reset; clear_marker
printf '%s\n' '{"type":"custom-title","customTitle":"T1","sessionId":"u1"}' > "$TRANSCRIPT"
statusline "T1" "$TRANSCRIPT"
ok "promotion sets label"  "T1" "$(opt)"
ok "promotion sets marker" "T1" "$(marker)"

set_pair "T2"                                     # prefix T; /rename never landed
statusline "T1" "$TRANSCRIPT"                     # transcript still says T1
ok "stale title does NOT revert the prefix-T label" "T2" "$(opt)"
ok "skipped promotion leaves the marker alone"      "T1" "$(marker)"

# ── a REAL /rename still wins from that same diverged state ─────────
printf '%s\n' '{"type":"custom-title","customTitle":"T3","sessionId":"u1"}' > "$TRANSCRIPT"
statusline "T3" "$TRANSCRIPT"
ok "a new title still promotes over a manual label" "T3" "$(opt)"
ok "marker advances to the new title"               "T3" "$(marker)"
ok "manual flag still set"                          "1"  "$(manual)"

# ── seeding: a session aligned BEFORE the marker existed ────────────
# Its marker is unset, and unset != the stale title — so without the fast
# path seeding it, the next prefix-T divergence would revert exactly as
# before. The seed happens with no transcript read and no muster call.
reset; clear_marker
set_pair "T1"
rm -f "$MUSTER_ARGS_LOG"
statusline "T1" "$WORK/does-not-exist.jsonl"      # fast path
ok "fast path seeds the marker"          "T1" "$(marker)"
ok "seeding still skips muster"          ""   "$(cat "$MUSTER_ARGS_LOG" 2>/dev/null)"

set_pair "T2"                                     # prefix T; /rename eaten again
printf '%s\n' '{"type":"custom-title","customTitle":"T1","sessionId":"u1"}' > "$TRANSCRIPT"
statusline "T1" "$TRANSCRIPT"
ok "seeded marker prevents the revert"   "T2" "$(opt)"

# ── clear gesture: prefix T unsets the pair but not the marker ──────
# The still-current title must be re-adoptable — an unlabeled session
# taking its own name back can't be overriding anybody.
reset                                             # marker stays at T1
statusline "T1" "$TRANSCRIPT"
ok "cleared label re-adopts its own title" "T1" "$(opt)"
ok "re-adoption re-sets the manual flag"   "1"  "$(manual)"
ok "re-adoption keeps the marker"          "T1" "$(marker)"

# ── an EMPTY label can't be overriding anybody either ───────────────
# Label unset while the manual flag survives and the marker still holds the
# title — reachable via a partially-failed clear or a raw `set-option -u
# @claude_task`. Without the empty-label clause this state is permanently
# un-promotable: the marker blocks it and the flag blocks the auto branch,
# so the session shows no label forever.
reset; clear_marker
tmux -S "$WORK/sock" set-option -t t @claude_task_promoted "T1"
tmux -S "$WORK/sock" set-option -t t @claude_task_manual 1     # label left unset
statusline "T1" "$TRANSCRIPT"
ok "empty label re-promotes despite the marker" "T1" "$(opt)"

# ── the marker write lives OUTSIDE the muster if/else ───────────────
# All three promotion paths (muster ok, muster failing, muster absent) must
# record the marker. A refactor that moved the write inside the else would
# leave every muster-present session unmarked — the guard would silently die
# while this suite stayed green. Pin the muster-ABSENT path explicitly.
reset; clear_marker
printf '%s\n' '{"type":"custom-title","customTitle":"T1","sessionId":"u1"}' > "$TRANSCRIPT"
PATH_SAVE="$PATH"
export PATH="$TMUX_DIR:/usr/bin:/bin"             # muster off PATH, tmux+jq on it
statusline "T1" "$TRANSCRIPT"
ok "muster-absent promotion sets the label"  "T1" "$(opt)"
ok "muster-absent promotion sets the marker" "T1" "$(marker)"

set_pair "T2"                                     # prefix T; /rename eaten
statusline "T1" "$TRANSCRIPT"                     # stale tick, still no muster
ok "muster-absent marker blocks the revert"  "T2" "$(opt)"
export PATH="$PATH_SAVE"

print
print "PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
