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

if [ "$dirty" = "0" ]; then
  # Clean: green branch glyph + name.
  printf '#[fg=#a6e3a1] %s#[default]' "$branch"
else
  # Dirty: yellow branch + peach count dot.
  printf '#[fg=#f9e2af] %s #[fg=#fab387,bold]●%s#[default]' "$branch" "$dirty"
fi
