#!/bin/bash
# Print the session name wrapped in a stable, name-hashed color for tmux's
# status-left. Same name → same color across restarts, so each session keeps
# a consistent identity at a glance.
#
# Usage:
#   tmux-session-color.sh <session_name>     # from tmux's '#S'
#
# Output: "#[fg=<color>,bold] <name> #[default]"

set -u

name="${1:-}"
[[ -z "$name" ]] && exit 0

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

sum=$(printf '%s' "$name" | cksum | awk '{print $1}')
idx=$(( sum % ${#palette[@]} ))

printf '#[fg=%s,bold] %s #[default]' "${palette[$idx]}" "$name"
