#!/bin/bash
# Render session identity, or the opt-in indicator used by native status formats.
# Opt-in uses proj roles; normal rendering retains the stable name hash.
#
# Usage: tmux-session-color.sh [--enabled] <session_name>

set -u

mode="${1:-}"
name="${2:-$mode}"
[[ -z "$name" ]] && exit 0

# The setting is the only opt-in boundary; missing/older proj stays normal.
themed=false
if proj theme --enabled --json 2>/dev/null | jq -e '.enabled == true' >/dev/null 2>&1; then
  themed=true
fi
if [[ "$mode" == --enabled ]]; then
  if $themed; then printf '1'; else printf '0'; fi
  exit 0
fi

# Catppuccin Mocha accents. No red — it reads as an error state.
palette=(
  "#89b4fa"  # blue
  "#cba6f7"  # mauve
  "#a6e3a1"  # green
  "#fab387"  # peach
  "#94e2d5"  # teal
  "#f5c2e7"  # pink
  "#f9e2af"  # yellow
  "#74c7ec"  # sapphire
)

if ! $themed; then
  sum=$(printf '%s' "$name" | cksum | awk '{print $1}')
  idx=$(( sum % ${#palette[@]} ))
  color="${palette[$idx]}"
else
  color='#{?@proj_theme_accent,#{@proj_theme_accent},default}'
fi
format="#[fg=${color},bold] ${name} #[default]"
if $themed; then
  tmux display-message -p -t "$name" "$format" 2>/dev/null
else
  printf '%s' "$format"
fi
