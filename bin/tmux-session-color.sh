#!/bin/bash
# Render session identity and inline status segments. Opt-in uses proj roles;
# normal rendering retains the stable name hash and existing status colors.
#
# Usage:
#   tmux-session-color.sh [--left|--right|--clock] <session_name>
#
# Output: "#[fg=<color>,bold] <name> #[default]"

set -u

mode="${1:-}"
name="${2:-$mode}"
[[ -z "$name" ]] && exit 0

# The setting is the only opt-in boundary; missing/older proj stays normal.
themed=false
if proj theme --enabled --json 2>/dev/null | jq -e '.enabled == true' >/dev/null 2>&1; then
  themed=true
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
case "$mode" in
  --left)
    if $themed; then
      task='#{?@proj_theme_accent,#{@proj_theme_accent},default}'
      text='#{?@proj_theme_accent_text,#{@proj_theme_accent_text},default}'
      mail="$task"
      muted='#{?@proj_theme_muted,#{@proj_theme_muted},default}'
    else
      task='#b4befe'; text='#1e1e2e'; mail='#89dceb'; muted='#6c7086'
    fi
    format+="#{?@claude_task,#[fg=${task}]#{@claude_task} #[default],}#{?@muster_inbox,#[fg=${text}#,bg=${mail}#,bold] 📬#{@muster_inbox} #[default] ,#{?@muster_agent,#[fg=${muted}]#{?#{!=:#{@muster_agent},#S},@#{@muster_agent},@}#[default] ,}}"
    ;;
  --right)
    if $themed; then
      warning='#{?@proj_theme_warning,#{@proj_theme_warning},default}'
    else
      warning='#f9e2af'
    fi
    format="#{?@wakeup,#[fg=${warning}]⏰ #{@wakeup}#[default]  ,}"
    # --right is placed before git/context; the clock is a separate mode.
    ;;
  --clock)
    if $themed; then color='#{?@proj_theme_muted,#{@proj_theme_muted},default}'; else color='#a6adc8'; fi
    format="#[fg=${color}]$(date '+%a %b %d  %H:%M') "
    ;;
esac
if $themed || [[ "$mode" == --* ]]; then
  tmux display-message -p -t "$name" "$format" 2>/dev/null
else
  printf '%s' "$format"
fi
