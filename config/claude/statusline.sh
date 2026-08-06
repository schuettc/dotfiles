#!/bin/bash
# Claude Code Status Line.
#
# Runs once per Claude turn. Three responsibilities:
#   1. Print the status line shown at the bottom of the Claude UI
#      (model · context % · folder). Git status is intentionally omitted
#      — tmux already shows branch + dirty count and the duplication was
#      noisy and prone to drift.
#   2. Write a per-pane state file so tmux's status-right can show the
#      current context % for the focused Claude pane. The file is keyed
#      by tmux socket name + the inherited TMUX_PANE env var (pane ids are
#      only unique per server); bin/tmux-claude-context.sh reads it from
#      the tmux side with the identical key derivation.
#   3. Sync a custom Claude session name (/rename) into the tmux
#      session's @claude_task label so it shows on every surface.

input=$(cat)

# ─── Parse JSON ──────────────────────────────────────────────────────
# Claude pre-computes the cumulative context-window usage percentage in
# `.context_window.used_percentage`. (Don't compute from
# `current_usage.input_tokens` — that's only the *new* tokens this turn,
# typically 1–2 due to prompt caching.)
MODEL=$(echo "$input"        | jq -r '.model.display_name // "Claude"')
CONTEXT_PCT=$(echo "$input"  | jq -r '.context_window.used_percentage // 0')
CURRENT_DIR=$(echo "$input"  | jq -r '.workspace.current_dir // ""')

FOLDER_NAME=""
[[ -n "$CURRENT_DIR" ]] && FOLDER_NAME=$(basename "$CURRENT_DIR")

# Optional feature label (legacy hook from feature-workflow).
FEATURE=""
[[ -f ~/.claude/feature-context ]] && FEATURE=$(cat ~/.claude/feature-context)

# ─── Write state file for tmux status bar ────────────────────────────
# Keyed by SOCKET + pane. Pane ids are only unique within one tmux server,
# and this machine runs a per-project socket for every workspace — so keying
# on the pane alone made every server's %NN collide on one file, and the
# status bar showed some *other* socket's context %. $TMUX looks like
# "<socket-path>,<pid>,<session>", so the socket NAME is the basename of the
# first comma-field. bin/tmux-claude-context.sh derives the identical key
# from '#{socket_path}' on the reading side — change the two together.
if [[ -n "${TMUX_PANE:-}" ]]; then
  state_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-status"
  mkdir -p "$state_dir" 2>/dev/null

  # One-time migration: legacy keys were "_<pane-number>" (socket-agnostic).
  # They can never match the new key, so drop them rather than leave stale
  # files lying around forever.
  rm -f "$state_dir"/_[0-9]* 2>/dev/null

  sock="${TMUX%%,*}"; sock="${sock##*/}"
  [[ -n "$sock" ]] || sock=unknown
  state_key="${sock}_${TMUX_PANE#%}"
  state_key="${state_key//[^a-zA-Z0-9_.-]/_}"
  printf 'context_pct=%d\nmodel=%s\nupdated=%d\npane=%s\nsocket=%s\n' \
    "$CONTEXT_PCT" "$MODEL" "$(date +%s)" "$TMUX_PANE" "$sock" \
    > "$state_dir/$state_key" 2>/dev/null
fi

# ─── Sync Claude session name → tmux task label ──────────────────────
# Claude ships `session_name` in the statusline JSON whenever the session
# has a name — an explicit /rename (or --name) AND the auto-generated topic
# both land in the same field. The transcript disambiguates (naming-contract
# plan 2026-08-05): a {"type":"custom-title"} record whose customTitle
# equals the current session_name proves the name is USER-SET. User-set →
# PROMOTE: label + @claude_task_manual, bus-synced via `muster label
# --no-inject` when muster is installed (--no-inject because the name
# already CAME from /rename — re-typing it would loop text into the pane).
# Auto topic → display-only, defers to the manual flag (unchanged). Nothing
# here ever demotes. Newest gesture wins: a fresh /rename overwrites a
# stale manual label because its custom-title matches the new session_name.
#
# …but only a *fresh* one. @claude_task_promoted records the last title this
# script promoted, and a title equal to that marker never promotes again.
# Without it a STALE title reverts the operator: prefix T sets a new label
# and types /rename into the pane; on a busy pane the keystrokes get eaten
# mid-turn (seen twice on 2026-08-06), so the transcript keeps the OLD
# custom-title — and the next tick "promoted" that old name back over the
# fresh label, hours after the gesture. Rules:
#   • title != marker            → promote (a real /rename; newest wins),
#                                  then the marker becomes that title.
#   • aligned fast path          → seed the marker if unset/different. Load
#                                  bearing: a session aligned from BEFORE
#                                  this marker existed has none, and an
#                                  unset marker != a stale title, so the
#                                  very next prefix-T divergence would
#                                  still revert. Written only when it
#                                  differs — the fast path stays cheap
#                                  (still no transcript read).
#   • no manual flag + title == session_name → promote regardless of the
#                                  marker. Prefix T's CLEAR gesture unsets
#                                  the option pair (bin/tmux-muster-label.sh)
#                                  but not the marker; an unlabeled session
#                                  adopting its own title is always safe.
#   • auto-topic branch          → unchanged, never touches the marker.
# Accepted limitations: /renaming BACK to the exact marker value after a
# prefix-T divergence is ignored — indistinguishable from the stale case
# without timestamps; the workaround is prefix T, or renaming through a
# different name first. And this guard makes prefix T durable against
# statusline ticks, NOT against a resume: muster's SessionStart projection
# re-asserts the transcript title, so a prefix-T name only becomes durable
# once a /rename actually lands in the transcript.
SESSION_NAME=$(echo "$input" | jq -r '.session_name // ""')
TRANSCRIPT_PATH=$(echo "$input" | jq -r '.transcript_path // ""')
if [[ -n "$SESSION_NAME" && -n "${TMUX_PANE:-}" ]]; then
  is_manual=$(tmux show-option -qv -t "$TMUX_PANE" @claude_task_manual 2>/dev/null)
  current_label=$(tmux show-option -qv -t "$TMUX_PANE" @claude_task 2>/dev/null)
  promoted=$(tmux show-option -qv -t "$TMUX_PANE" @claude_task_promoted 2>/dev/null)
  if [[ "$current_label" == "$SESSION_NAME" && -n "$is_manual" ]]; then
    # fast path: already promoted and aligned — no transcript read.
    if [[ "$promoted" != "$SESSION_NAME" ]]; then
      tmux set-option -t "$TMUX_PANE" @claude_task_promoted "$SESSION_NAME" 2>/dev/null
    fi
  else
    custom_title=""
    if [[ -n "$TRANSCRIPT_PATH" && -r "$TRANSCRIPT_PATH" ]]; then
      custom_title=$(grep '"custom-title"' "$TRANSCRIPT_PATH" 2>/dev/null \
        | tail -1 | jq -r '.customTitle // ""' 2>/dev/null)
    fi
    user_set=0
    [[ -n "$custom_title" && "$custom_title" == "$SESSION_NAME" ]] && user_set=1
    # A user-set title promotes when it's NEW (differs from the marker), or
    # when the session carries no manual label to protect — no flag, or no
    # label at all. The empty-label half closes an otherwise permanently
    # un-promotable state: label unset while the manual flag survives and
    # the marker still holds the title (a partially-failed clear, or a raw
    # `tmux set-option -u @claude_task`). An empty label, like an unlabeled
    # session, can't be overriding anybody.
    if (( user_set )) && [[ "$custom_title" != "$promoted" || -z "$is_manual" || -z "$current_label" ]]; then
      if command -v muster >/dev/null 2>&1; then
        # A muster binary predating --no-inject fails the flag parse (exit
        # non-zero) without touching the pane options at all — guard the
        # call and fall back to the plain-tmux pair write so the session
        # still gets labeled. Degradation is tmux-only promotion; the
        # muster SessionStart projection re-converges the bus later.
        if ! muster label --no-inject "$SESSION_NAME" >/dev/null 2>&1; then
          tmux set-option -t "$TMUX_PANE" @claude_task "$SESSION_NAME" 2>/dev/null
          tmux set-option -t "$TMUX_PANE" @claude_task_manual 1 2>/dev/null
        fi
      else
        tmux set-option -t "$TMUX_PANE" @claude_task "$SESSION_NAME" 2>/dev/null
        tmux set-option -t "$TMUX_PANE" @claude_task_manual 1 2>/dev/null
      fi
      tmux set-option -t "$TMUX_PANE" @claude_task_promoted "$SESSION_NAME" 2>/dev/null
      tmux refresh-client -S 2>/dev/null
    elif [[ -z "$is_manual" && "$SESSION_NAME" != "$current_label" ]]; then
      tmux set-option -t "$TMUX_PANE" @claude_task "$SESSION_NAME" 2>/dev/null
      tmux refresh-client -S 2>/dev/null
    fi
  fi
fi

# ─── Print the in-Claude status line ─────────────────────────────────
# Inside tmux: print NOTHING. Model + context% are shown in tmux's
# status-right (bin/tmux-claude-context.sh reads the state file written
# above). An empty line here can't overflow the pane width, so it can't
# leave the wrapped-status redraw residue Claude's TUI produces under tmux.
#
# Outside tmux there's no status bar to carry it, so fall back to a lean,
# ASCII-only label (no width-2 emoji) — model (or feature) · folder.
if [[ -z "${TMUX_PANE:-}" ]]; then
  if [[ -n "$FEATURE" ]]; then
    printf '%s' "$FEATURE"
  else
    printf '%s' "$MODEL"
  fi
  [[ -n "$FOLDER_NAME" ]] && printf ' · %s' "$FOLDER_NAME"
  echo
fi
