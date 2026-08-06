#!/usr/bin/env zsh
# Tests for bin/tmux-muster-label.sh: the prefix-T shim must work with AND
# without muster on PATH (naming-contract plan, 2026-08-05). Real throwaway
# tmux server; a fake `muster` script records delegation.

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
trap 'tmux -S "$WORK/sock" kill-server 2>/dev/null; rm -rf "$WORK"' EXIT
tmux -S "$WORK/sock" new-session -d -s t -x 80 -y 24
PANE=$(tmux -S "$WORK/sock" display-message -p -t t '#{pane_id}')
export TMUX="$WORK/sock,999,0"

opt()    { tmux -S "$WORK/sock" show-option -qv -t t @claude_task; }
manual() { tmux -S "$WORK/sock" show-option -qv -t t @claude_task_manual; }

# ── muster ABSENT: plain-tmux fallback ──────────────────────────────
print '── fallback (no muster) ──'
PATH_SAVE="$PATH"
# Strip muster (and everything else non-core) but keep tmux reachable —
# on Homebrew/Apple Silicon it lives in /opt/homebrew/bin, not /usr/bin.
TMUX_DIR="${$(command -v tmux):h}"
export PATH="$TMUX_DIR:/usr/bin:/bin"
"$REPO/bin/tmux-muster-label.sh" "$PANE" "nfl-3"
ok "fallback sets label"        "nfl-3" "$(opt)"
ok "fallback sets manual flag"  "1"     "$(manual)"
"$REPO/bin/tmux-muster-label.sh" "$PANE" ""
ok "fallback clear unsets label"  "" "$(opt)"
ok "fallback clear unsets manual" "" "$(manual)"
export PATH="$PATH_SAVE"

# ── muster PRESENT: delegation, args recorded ───────────────────────
print '── delegation (fake muster) ──'
mkdir -p "$WORK/bin"
cat > "$WORK/bin/muster" <<'EOF'
#!/bin/sh
echo "$@" >> "${MUSTER_ARGS_LOG:?}"
echo "labeled"
EOF
chmod +x "$WORK/bin/muster"
export PATH="$WORK/bin:$PATH" MUSTER_ARGS_LOG="$WORK/args.log"
"$REPO/bin/tmux-muster-label.sh" "$PANE" "nfl-3"
ok "delegates to muster label" "label nfl-3" "$(tail -1 "$WORK/args.log")"

print
print "PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
