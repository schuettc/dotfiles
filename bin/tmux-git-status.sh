#!/bin/bash
# Compact git status for tmux's status-right, called via #(...).
#
# Usage:
#   tmux-git-status.sh <path>
#
# Output:
#   " main"            (clean repo on branch "main")
#   " feature/x ●3"    (3 uncommitted changes on branch feature/x)
#   ""                  (not a git repo, or git not installed)
#
# Colors use Catppuccin Mocha hex values, embedded as tmux format
# directives (#[fg=...]).

set -u

path="${1:-$PWD}"
cd "$path" 2>/dev/null || exit 0

command -v git >/dev/null 2>&1 || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Branch name, or short SHA if HEAD is detached.
branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null) || \
  branch=$(git rev-parse --short HEAD 2>/dev/null) || exit 0
[ -z "$branch" ] && exit 0

# Count uncommitted changes (staged + unstaged + untracked).
dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

# Primary-clone warning. If THIS pane is in the primary clone (not a linked
# worktree) AND linked worktrees exist, flag it: editing the shared tree while
# parallel work is live is the collision trap. Nudge toward `proj` (which puts
# a branch in its own worktree). In a linked worktree the git-dir differs from
# the common git-dir; in the primary clone they're the same.
# A linked worktree's git-dir path contains "/worktrees/"; the primary clone's
# does not. (Avoids macOS /var↔/private/var symlink mismatches from comparing
# absolute paths.)
wt_flag=""
case "$(git rev-parse --git-dir 2>/dev/null)" in
  */worktrees/*) : ;;   # linked worktree — never flag
  ?*)                   # primary clone
    wt_count=$(git worktree list --porcelain 2>/dev/null | grep -c '^worktree ')
    [ "${wt_count:-0}" -gt 1 ] && wt_flag=' #[fg=#1e1e2e,bg=#fab387,bold] ⚠ primary #[default]'
    ;;
esac

if [ "$dirty" = "0" ]; then
  # Clean: green branch glyph + name.
  printf '#[fg=#a6e3a1] %s#[default]%s' "$branch" "$wt_flag"
else
  # Dirty: yellow branch + peach count dot.
  printf '#[fg=#f9e2af] %s #[fg=#fab387,bold]●%s#[default]%s' "$branch" "$dirty" "$wt_flag"
fi
