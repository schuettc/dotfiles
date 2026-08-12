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
#   3. Keep the tmux session name aligned with a user-set Claude name
#      (/rename) and mirror Claude's current name/topic into the
#      @claude_task subtitle.

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

# ─── Sync Claude session name ↔ tmux session name ────────────────────
# The tmux session name IS the identity (session-identity plan 2026-08-08;
# spec docs/superpowers/specs/2026-08-08-proj-session-identity-design.md).
# Claude ships `session_name` in the statusline JSON — an explicit /rename
# AND the auto-generated topic land in the same field; a transcript
# {"type":"custom-title"} record whose customTitle equals session_name
# proves the name is USER-SET. Rules:
#   • user-set + valid charset ([A-Za-z0-9_/-]) + differs from #S and from
#     the promoted marker + no live session anywhere holds it → RENAME the
#     tmux session, then `muster become --no-inject` when available (the
#     name already came from /rename — injecting it back would loop).
#   • everything else → @claude_task subtitle only: whatever Claude calls
#     the conversation, for the title's middle segment (the title template
#     dedupes it against #S). NOTHING here renames from an auto topic.
# @claude_task_promoted records the last title this script acted on: a
# STALE transcript title (prefix-T's /rename keystrokes eaten by a busy
# turn — seen live 2026-08-06) must not revert an operator rename on the
# next tick. Aligned sessions seed the marker on the cheap path (no
# transcript read). Accepted limitation (unchanged from the label era):
# /renaming BACK to the exact marker value after a prefix-T divergence is
# ignored — rename through a different name first.
SESSION_NAME=$(echo "$input" | jq -r '.session_name // ""')
TRANSCRIPT_PATH=$(echo "$input" | jq -r '.transcript_path // ""')
if [[ -n "$SESSION_NAME" && -n "${TMUX_PANE:-}" ]]; then
  tmux_name=$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}' 2>/dev/null)
  promoted=$(tmux show-option -qv -t "$TMUX_PANE" @claude_task_promoted 2>/dev/null)
  if [[ "$SESSION_NAME" == "$tmux_name" ]]; then
    # fast path: aligned — keep the marker seeded, read nothing else.
    if [[ "$promoted" != "$SESSION_NAME" ]]; then
      tmux set-option -t "$TMUX_PANE" @claude_task_promoted "$SESSION_NAME" 2>/dev/null
    fi
    # A subtitle equal to #S is pure duplicate noise in status-left and the
    # picker rows (e.g. left over from a rename that landed after the
    # subtitle write on the same diverged tick — see the successful-rename
    # branch below, which clears it too; change the two together). One
    # show-option + conditional unset keeps this fast path cheap: still no
    # transcript read.
    aligned_sub=$(tmux show-option -qv -t "$TMUX_PANE" @claude_task 2>/dev/null)
    if [[ "$aligned_sub" == "$SESSION_NAME" ]]; then
      tmux set-option -u -t "$TMUX_PANE" @claude_task 2>/dev/null
    fi
  else
    # Subtitle first: display-only and safe for every kind of name.
    current_sub=$(tmux show-option -qv -t "$TMUX_PANE" @claude_task 2>/dev/null)
    if [[ "$current_sub" != "$SESSION_NAME" ]]; then
      tmux set-option -t "$TMUX_PANE" @claude_task "$SESSION_NAME" 2>/dev/null
      tmux refresh-client -S 2>/dev/null
    fi
    # Rename only for a FRESH, machine-shaped, user-set name.
    if [[ "$SESSION_NAME" != "$promoted" && "$SESSION_NAME" =~ ^[A-Za-z0-9_/-]+$ ]]; then
      custom_title=""
      if [[ -n "$TRANSCRIPT_PATH" && -r "$TRANSCRIPT_PATH" ]]; then
        custom_title=$(grep '"custom-title"' "$TRANSCRIPT_PATH" 2>/dev/null \
          | tail -1 | jq -r '.customTitle // ""' 2>/dev/null)
      fi
      if [[ -n "$custom_title" && "$custom_title" == "$SESSION_NAME" ]]; then
        # Refuse names a live session holds — the name doubles as the
        # bus-global alias; identity theft must be explicit. Same scan as
        # bin/tmux-session-rename.sh's prefix-T gesture — change both
        # together.
        taken=0
        sockdir="${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)"
        for s in "$sockdir"/*; do
          [[ -S "$s" ]] || continue
          tmux -S "$s" has-session -t "=$SESSION_NAME" 2>/dev/null && { taken=1; break; }
        done
        if (( ! taken )); then
          # Guard the whole post-rename block on rename-session's own exit
          # status: a lost race or an out-of-glob collision makes the
          # rename fail even past the scan above, and recording the marker
          # anyway would block every future retry of this name forever.
          if tmux rename-session -t "$TMUX_PANE" "$SESSION_NAME" 2>/dev/null; then
            # The subtitle mirrored this same name during the divergence —
            # now that #S matches it, it's pure duplication (see the
            # aligned fast path above, which reconciles the same drift on
            # its own tick — change the two together).
            tmux set-option -u -t "$TMUX_PANE" @claude_task 2>/dev/null
            if command -v muster >/dev/null 2>&1; then
              # A pre-become muster fails the probe; the rename above already
              # landed — tmux-only is the accepted degradation.
              if muster become --help >/dev/null 2>&1; then
                # Capture instead of discarding: a failed claim used to be
                # swallowed entirely (both streams to /dev/null, exit status
                # ignored), leaving #S and the bus alias silently diverged
                # with nothing reported anywhere — that's how a live session
                # ended up tmux-named "bettor-help-workspace/debug-alarms"
                # while its alias stayed "debug-alarms". Same report shape
                # as bin/tmux-session-rename.sh's identical situation.
                # stdout here IS the rendered status line, so the failure
                # goes to display-message (→ tmux), never echo/printf.
                if ! out=$(muster become --no-inject "$SESSION_NAME" 2>&1); then
                  tmux display-message -t "$TMUX_PANE" \
                    "renamed → $SESSION_NAME · muster become FAILED: ${out//$'\n'/ · }" 2>/dev/null
                fi
              fi
            fi
            # Stamped even when become failed above: this block only runs
            # once per rename, gated by @claude_task_promoted below — an
            # unset marker would re-enter on every future tick and repeat
            # the display-message on every status-line render. The marker
            # tracks tmux/Claude-name sync, not the separate muster claim.
            tmux set-option -t "$TMUX_PANE" @claude_task_promoted "$SESSION_NAME" 2>/dev/null
            tmux refresh-client -S 2>/dev/null
          fi
        fi
      fi
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
