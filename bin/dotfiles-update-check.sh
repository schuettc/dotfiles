#!/bin/bash
# Update nudge for the dotfiles repo. Detection only — fetches, never pulls,
# never touches the working tree. `proj` prints `status` (instant file read)
# and fires `refresh` in the background; `update.sh` calls `clear` after a
# successful pull so the nudge dies immediately.
#
# Usage:
#   dotfiles-update-check.sh [status]   # dim one-liner if behind, else nothing
#   dotfiles-update-check.sh refresh    # age-gated fetch + rewrite state
#   dotfiles-update-check.sh clear      # record up-to-date
#
# State file (~/.cache/dotfiles-update-state): one line `behind=N`;
# mtime = last check. Env overrides (used by tests):
#   DOTFILES_UPDATE_STATE  DOTFILES_UPDATE_REPO  DOTFILES_UPDATE_MAX_AGE

set -u

STATE="${DOTFILES_UPDATE_STATE:-$HOME/.cache/dotfiles-update-state}"
REPO="${DOTFILES_UPDATE_REPO:-$HOME/dotfiles}"
MAX_AGE="${DOTFILES_UPDATE_MAX_AGE:-14400}"   # 4 hours

write_state() {
  mkdir -p "$(dirname "$STATE")" 2>/dev/null || return 0
  printf 'behind=%s\n' "$1" > "$STATE" 2>/dev/null
}

case "${1:-status}" in
  status)
    [[ -r "$STATE" ]] || exit 0
    behind=$(sed -n 's/^behind=\([0-9][0-9]*\)$/\1/p' "$STATE" | head -1)
    [[ -n "$behind" && "$behind" -gt 0 ]] || exit 0
    printf '\033[2mdotfiles: %s behind · dotup\033[0m\n' "$behind"
    ;;
  refresh)
    git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
    now=$(date +%s)
    mtime=$(stat -f %m "$STATE" 2>/dev/null || echo 0)
    (( now - mtime < MAX_AGE )) && exit 0
    git -C "$REPO" fetch --quiet origin 2>/dev/null || exit 0
    git -C "$REPO" rev-parse --verify --quiet origin/main >/dev/null 2>&1 || exit 0
    behind=$(git -C "$REPO" rev-list --count HEAD..origin/main 2>/dev/null) || exit 0
    write_state "$behind"
    ;;
  clear)
    write_state 0
    ;;
esac
exit 0
