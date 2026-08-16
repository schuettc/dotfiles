#!/bin/bash
# prefix T handler: rename this SESSION — one gesture for every surface
# (session-identity plan 2026-08-08; spec in docs/superpowers/specs/).
#
# The tmux session name IS the identity: #S = the work = (with muster) the
# bus alias. The tmux half lives here: validate, refuse collisions, rename.
# With muster present, `muster become <name>` additionally claims the alias
# on the bus (mail follows via lineage) and types /rename into the
# registered Claude pane — muster owns injection; this script never
# send-keys. A muster whose CLI predates `become` fails the probe and the
# rename stays tmux-only (Claude's internal name catches up on the
# operator's next /rename).
#
# THE OPERATOR TYPES THE WORK, NEVER THE PROJECT. A session identity is
# <project>/<work>, but only the work half is the operator's to choose —
# the project half is a property of where the session lives. So this script
# owns both ends of the gesture: `--prompt` pre-fills the command-prompt
# with the work segment alone, and the rename half re-attaches the project
# prefix to whatever comes back. The binding used to pre-fill the whole #S
# instead, which meant clearing the prompt and typing a bare label silently
# renamed the session OUT of its project — it stopped matching proj's
# Screen-2 <project>/* scan and rendered differently in status-left. A
# typed name that already carries a '/' is taken verbatim; that is the
# escape hatch for re-homing a session under a different project.
#
# tmux run-shell children inherit $TMUX but NOT $TMUX_PANE — $1 is
# #{pane_id}, expanded by the binding at press time; $2 is the new name.
# Output goes through display-message: run-shell opens a full-screen view
# for ANY stdout, which reads as an error screen instead of feedback.

# Absolute path to this script, so the command-prompt below can hand the
# rename half back to the same copy that raised it (the worktree copy under
# test, not whatever ~/dotfiles happens to hold).
case "$0" in
  */*) self="$(cd "${0%/*}" && pwd)/${0##*/}" ;;
  *)   self="$0" ;;
esac

# ── prompt half: raise the command-prompt, pre-filled with the work ──
# Bound to prefix T. Computing the pre-fill here rather than in the binding
# keeps one definition of "which part of #S is the work" — a tmux format
# string could strip the prefix too, but it cannot express the home-base
# case (no '/' at all, so the whole name is the project and there is no
# work to offer yet).
if [[ "$1" == "--prompt" ]]; then
  pane="$2"
  client="${3:-}"
  cur=$(tmux display-message -p -t "$pane" '#{session_name}')
  work=""
  [[ "$cur" == */* ]] && work="${cur#*/}"
  # -t <client> because a run-shell child reaches the server as a fresh
  # client-less command: untargeted, the prompt lands on whichever client
  # tmux used most recently, and these servers carry one client per session.
  client_arg=()
  [[ -n "$client" ]] && client_arg=(-t "$client")
  # Same shape the .tmux.conf binding used to carry: the inner \"%%\" keeps
  # a name with spaces as ONE argument once command-prompt substitutes it.
  tmux command-prompt "${client_arg[@]}" -I "$work" -p 'rename work:' \
    "run-shell -b \"$self $pane \\\"%%\\\"\""
  exit 0
fi

export TMUX_PANE="$1"
new="$2"

cur=$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}')

# Names are typed naturally but live as addresses (tmux target, muster
# alias): collapse whitespace runs to hyphens instead of refusing them.
# Same slug rule as __proj_slug_work in 04-aliases.zsh — change both together.
read -ra __words <<<"$new"
new=$(IFS='-'; printf '%s' "${__words[*]}")

if [[ -z "$new" ]]; then
  tmux display-message "rename cancelled (still: $cur)"
  exit 0
fi

if [[ ! "$new" =~ ^[A-Za-z0-9_/-]+$ ]]; then
  tmux display-message "invalid name: $new (allowed: letters digits - _ /)"
  exit 0
fi

# Re-attach the project prefix to a bare work name. The project is the
# FIRST segment of the current name; for a home-base session (no '/') that
# is the whole name, so typing a work name promotes <project> into
# <project>/<work>. Composition happens BEFORE the equality check below, so
# re-typing the work you already have still reads as "no change".
if [[ "$new" != */* ]]; then
  new="${cur%%/*}/$new"
fi

if [[ "$new" == "$cur" ]]; then
  tmux display-message "rename cancelled (still: $cur)"
  exit 0
fi

# Refuse names a LIVE session already holds — on any server, because the
# name doubles as the bus-global muster alias. Silent identity theft is the
# failure mode this exists to prevent. Same scan as statusline.sh's
# name-sync block — change both together.
sockdir="${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)"
for s in "$sockdir"/*; do
  [[ -S "$s" ]] || continue
  if tmux -S "$s" has-session -t "=$new" 2>/dev/null; then
    tmux display-message "name taken by a live session: $new"
    exit 0
  fi
done

# Guard the success report on rename-session's own exit status — a lost
# race (name taken between the scan above and this call) must not display
# "renamed" or hand the stale name to muster become.
if tmux rename-session -t "$TMUX_PANE" "$new"; then
  if command -v muster >/dev/null 2>&1 && muster become --help >/dev/null 2>&1; then
    if out=$(muster become "$new" 2>&1); then
      tmux display-message "renamed → $new · muster: ${out//$'\n'/ · }"
    else
      tmux display-message "renamed → $new · muster become FAILED: ${out//$'\n'/ · }"
    fi
  else
    tmux display-message "renamed → $new (tmux only)"
  fi
else
  tmux display-message "rename failed (name just taken?): $new"
fi
tmux refresh-client -S
