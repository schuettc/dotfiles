#!/bin/bash
# Claude Code notification hook for cmux
# Sends notifications to cmux sidebar when Claude needs attention

# Only run inside cmux
[[ -z "$CMUX_SOCKET_PATH" ]] && exit 0

# Read hook input
input=$(cat)
hook_name=$(echo "$input" | jq -r '.hook_name // ""')

case "$hook_name" in
  Notification)
    title=$(echo "$input" | jq -r '.notification.title // "Claude Code"')
    body=$(echo "$input" | jq -r '.notification.body // ""')
    cmux notify --title "$title" --body "$body" 2>/dev/null || true
    ;;
esac
