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

# ── never demote: manual flag blocks a later auto topic ─────────────
printf '%s\n' '{"type":"user"}' > "$TRANSCRIPT"   # custom-title gone from a NEW transcript
statusline "Some auto topic" "$TRANSCRIPT"
ok "auto topic never clobbers manual label" "nfl-3" "$(opt)"
ok "manual flag survives"                   "1"     "$(manual)"

# ── fast path: aligned state reads no transcript ────────────────────
rm -f "$MUSTER_ARGS_LOG"
statusline "nfl-3" "$WORK/does-not-exist.jsonl"   # would fail if read mattered
ok "aligned state does nothing" "" "$(cat "$MUSTER_ARGS_LOG" 2>/dev/null)"

print
print "PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
