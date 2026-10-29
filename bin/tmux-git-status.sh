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

# The setting is the only opt-in boundary; missing/older proj stays normal.
themed=false
if proj theme --enabled --json 2>/dev/null | jq -e '.enabled == true' >/dev/null 2>&1; then
  themed=true
fi

success='#a6e3a1'; warning='#f9e2af'; count_color='#fab387'
if $themed; then
  IFS='|' read -r success warning < <(tmux display-message -p -t "${2:-}" '#{?@proj_theme_success,#{@proj_theme_success},default}|#{?@proj_theme_warning,#{@proj_theme_warning},default}' 2>/dev/null)
  success="${success:-default}"; warning="${warning:-default}"; count_color="$warning"
fi
if [ "$dirty" = "0" ]; then
  # Clean: green branch glyph + name.
  printf '#[fg=%s] %s#[default]' "$success" "$branch"
else
  # Dirty: yellow branch + peach count dot.
  printf '#[fg=%s] %s #[fg=%s,bold]●%s#[default]' "$warning" "$branch" "$count_color" "$dirty"
fi
