#!/bin/bash
# SwiftBar plugin — Claude attention indicator in the macOS menu bar.
#
# The filename interval (claude-attn.3s.sh) refreshes every 3s; the Claude
# Notification hook (claude-notify.sh → claude-attn) also pokes it for an
# instant update via  open "swiftbar://refreshplugin?name=claude-attn".
#
# Reads the single source of truth — `claude-attn list` (tmux @claude_attn) —
# so it always matches the 🔔 in the Ghostty tab/Dock titles.
#
# <swiftbar.title>Claude Attention</swiftbar.title>
# <swiftbar.author>Court Schuett</swiftbar.author>
# <swiftbar.desc>Shows which Claude Code (tmux) sessions are waiting for input.</swiftbar.desc>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

sessions=$(claude-attn list 2>/dev/null)

if [[ -z "$sessions" ]]; then
  # Idle — a dim bell so you know where the indicator lives, unobtrusive.
  echo ":bell: | sfcolor=#585b70"
  exit 0
fi

count=$(printf '%s\n' "$sessions" | grep -c .)

# Menu-bar title: a red badged bell + the count.
echo ":bell.badge.fill: ${count} | sfcolor=#f38ba8"
echo "---"
echo "Claude is waiting in:"
while IFS= read -r s; do
  [[ -z "$s" ]] && continue
  # Clicking a session brings its Ghostty window to the front (and clears the
  # flag). Focusing it in tmux also clears it via the pane-focus-in hook.
  echo "🔔 ${s} | bash='${HOME}/.local/bin/claude-attn' param1=focus param2='${s}' terminal=false refresh=true"
done <<< "$sessions"
