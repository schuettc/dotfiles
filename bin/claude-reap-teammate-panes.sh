#!/bin/bash
# Reap tmux panes belonging to FINISHED Claude Code teammates.
#
# Why this exists: Claude Code teammates (teammateMode) are spawned into their
# own tmux pane and are deliberately PERSISTENT — a finished teammate stays
# resumable, so nothing ever terminates it. Verified on 2026-07-20:
#   * SubagentStop does NOT fire for teammates (only for in-process Task
#     subagents), so a hook-based reaper is impossible.
#   * A `shutdown_request` to an idle teammate is never processed — it does not
#     wake to handle its mailbox, so the pane is not reclaimed.
#   * `remain-on-exit` is already off; the pane lives because the PROCESS lives.
# Each finished teammate therefore holds a pty forever. The binding limit is
# kern.tty.ptmx_max (511 on this machine); marathon multi-agent days ratchet
# toward it until an unrelated session's spawn dies with
# "fork failed: Device not configured" (ENXIO).
#
# Safety model — a pane is only ever killed when ALL of these hold:
#   1. IDENTITY: it is listed in ~/.claude/teams/<team>/config.json as a member
#      with a real `tmuxPaneId` (%N). Leader panes ("leader") and in-process
#      members are structurally excluded, so a main session pane can never be
#      targeted. This also sidesteps the pane-renumbering trap: %N pane IDs are
#      stable and never reused within a server, unlike indexes.
#   2. IDLE: its title carries the idle glyph, sampled TWICE with a gap, so a
#      spinner animation frame can never be mistaken for idleness.
#   3. AGE: the teammate joined more than --idle-minutes ago.
#   4. RECHECK: identity + idleness are re-verified at kill time.
# Default is a DRY RUN. Nothing is killed without --kill.
#
# Usage:
#   claude-reap-teammate-panes.sh                  # dry run (default)
#   claude-reap-teammate-panes.sh --kill           # actually reap
#   claude-reap-teammate-panes.sh --idle-minutes 60
set -u

KILL=0
IDLE_MIN="${CLAUDE_REAP_IDLE_MINUTES:-30}"   # knob: grace period, tunable
SAMPLE_GAP="${CLAUDE_REAP_SAMPLE_GAP:-3}"    # knob: seconds between idle samples
IDLE_GLYPH='✳'                               # idle marker; spinner frames are ⠂/⠐

while [ $# -gt 0 ]; do
  case "$1" in
    --kill) KILL=1 ;;
    --idle-minutes) IDLE_MIN="${2:?}"; shift ;;
    --sample-gap) SAMPLE_GAP="${2:?}"; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

now=$(date +%s)
teams_dir="$HOME/.claude/teams"
[ -d "$teams_dir" ] || { echo "no teams dir; nothing to do"; exit 0; }

# Emit candidate teammates as: socket|pane|agentId|name|age_minutes
# The socket is derived from the team lead's cwd, matching the per-project
# socket convention (proj-<basename cwd>) used by __proj_srv.
candidates=$(python3 - "$teams_dir" "$now" "$IDLE_MIN" <<'PY'
import json, os, sys, glob
teams_dir, now, idle_min = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
for cfg in glob.glob(os.path.join(teams_dir, '*', 'config.json')):
    try:
        d = json.load(open(cfg))
    except Exception:
        continue
    members = d.get('members', [])
    lead_cwd = next((m.get('cwd') for m in members if m.get('tmuxPaneId') == 'leader' and m.get('cwd')), None)
    if not lead_cwd:
        continue
    sock = 'proj-' + os.path.basename(lead_cwd.rstrip('/'))
    for m in members:
        pane = m.get('tmuxPaneId') or ''
        if not pane.startswith('%'):        # excludes 'leader' and 'in-process'
            continue
        joined = int(m.get('joinedAt', 0) / 1000)
        age = int((now - joined) / 60) if joined else 10**6
        if age < idle_min:
            continue
        print('%s|%s|%s|%s|%d|%d' % (sock, pane, m.get('agentId'), m.get('name'), age, joined))
PY
)

# Identity gate. Teams configs accumulate STALE mappings forever (measured:
# 33 stale vs 25 live), and tmux pane IDs restart at %0 when a server restarts —
# so a stale `name -> %38` can later point at an unrelated, live pane. The idle
# glyph does NOT save us: main session panes show it too (e.g. "✳ Build lineups
# for today"). So before trusting a mapping, require the pane's process to have
# started when the teammate joined. Measured across 25 live teammate panes, the
# delta is <=1s; a recycled pane id or a main pane misses by hours.
proc_start_matches() {  # $1=pid  $2=joined_epoch
  python3 - "$1" "$2" "${CLAUDE_REAP_START_TOLERANCE:-120}" <<'PY'
import subprocess, sys, time, datetime
pid, joined, tol = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
out = subprocess.run(['ps','-o','lstart=','-p',pid], capture_output=True, text=True).stdout.strip()
if not out:
    sys.exit(1)
try:
    started = time.mktime(datetime.datetime.strptime(out, "%a %b %d %H:%M:%S %Y").timetuple())
except Exception:
    sys.exit(1)
sys.exit(0 if abs(started - joined) <= tol else 1)
PY
}

[ -z "$candidates" ] && { echo "no teammate panes older than ${IDLE_MIN}m — nothing to do"; exit 0; }

# --- sample 1: which candidates are live AND idle right now -------------------
declare -a live=()
while IFS='|' read -r sock pane aid name age joined; do
  [ -n "$pane" ] || continue
  ppid=$(tmux -L "$sock" display-message -p -t "$pane" '#{pane_pid}' 2>/dev/null)
  title=$(tmux -L "$sock" display-message -p -t "$pane" '#{pane_title}' 2>/dev/null)
  [ -n "$title" ] && [ -n "$ppid" ] || continue
  # Identity gate first — a mapping we cannot prove is skipped, never killed.
  proc_start_matches "$ppid" "$joined" || continue
  # Snapshot rendered content; compared after the gap below. A working agent
  # redraws (spinner, elapsed timer, token counts), an idle one is byte-stable.
  hash=$(tmux -L "$sock" capture-pane -p -t "$pane" 2>/dev/null | md5)
  case "$title" in
    "$IDLE_GLYPH"*) live+=("$sock|$pane|$aid|$name|$age|$hash|$title") ;;
  esac
done <<<"$candidates"

[ "${#live[@]}" -eq 0 ] && { echo "no idle teammate panes — nothing to do"; exit 0; }

# --- sample 2: re-check after a gap so a spinner frame can't masquerade -------
sleep "$SAMPLE_GAP"
printf '%-34s %-6s %-22s %-6s %s\n' SOCKET PANE TEAMMATE AGE STATE
reaped=0; skipped=0
for row in "${live[@]}"; do
  IFS='|' read -r sock pane aid name age hash title <<<"$row"
  t2=$(tmux -L "$sock" display-message -p -t "$pane" '#{pane_title}' 2>/dev/null)
  case "$t2" in
    "$IDLE_GLYPH"*) ;;
    *) printf '%-34s %-6s %-22s %-6s %s\n' "$sock" "$pane" "$name" "${age}m" "SKIP (became active)"; skipped=$((skipped+1)); continue ;;
  esac
  # Second, glyph-independent idle proof: the rendered pane must not have
  # changed across the gap. Survives any future change to the spinner glyphs.
  h2=$(tmux -L "$sock" capture-pane -p -t "$pane" 2>/dev/null | md5)
  if [ "$h2" != "$hash" ]; then
    printf '%-34s %-6s %-22s %-6s %s\n' "$sock" "$pane" "$name" "${age}m" "SKIP (screen changed — working)"
    skipped=$((skipped+1)); continue
  fi
  if [ "$KILL" = 1 ]; then
    # Final recheck at kill time, then reap.
    t3=$(tmux -L "$sock" display-message -p -t "$pane" '#{pane_title}' 2>/dev/null)
    case "$t3" in
      "$IDLE_GLYPH"*)
        if tmux -L "$sock" kill-pane -t "$pane" 2>/dev/null; then
          printf '%-34s %-6s %-22s %-6s %s\n' "$sock" "$pane" "$name" "${age}m" "REAPED"
          reaped=$((reaped+1))
        else
          printf '%-34s %-6s %-22s %-6s %s\n' "$sock" "$pane" "$name" "${age}m" "kill failed"
          skipped=$((skipped+1))
        fi ;;
      *) printf '%-34s %-6s %-22s %-6s %s\n' "$sock" "$pane" "$name" "${age}m" "SKIP (raced)"; skipped=$((skipped+1)) ;;
    esac
  else
    printf '%-34s %-6s %-22s %-6s %s\n' "$sock" "$pane" "$name" "${age}m" "would reap"
    reaped=$((reaped+1))
  fi
done

echo
if [ "$KILL" = 1 ]; then
  echo "reaped $reaped pane(s), skipped $skipped. ptys now: $(lsof /dev/ttys* 2>/dev/null | awk 'NR>1{print $NF}' | sort -u | wc -l | tr -d ' ') / $(sysctl -n kern.tty.ptmx_max 2>/dev/null)"
else
  echo "DRY RUN — $reaped pane(s) would be reaped, $skipped skipped. Re-run with --kill to apply."
fi
