#!/bin/bash
# Emit a colored context-% indicator for tmux's status-right when the
# focused pane is running Claude Code. Reads the per-pane state file
# written by ~/.config/claude/statusline.sh.
#
# Usage:
#   tmux-claude-context.sh <pane_id>          # e.g. '%47' (from tmux's #{pane_id})
#
# Output (with embedded tmux color directives):
#   "⌬ 24%"   green  (< 50%)
#   "⌬ 64%"   yellow (50–79%)
#   "⌬ 88%"   red    (≥ 80%)
#   ""        (nothing) — no Claude in this pane, or state is stale

set -u

pane_id="${1:-}"
[[ -z "$pane_id" ]] && exit 0

# Liveness gate: only show the indicator if this pane is actually running a
# coding agent. A Claude pane's current command is the version string (e.g.
# "2.1.156") or "claude"; a pi pane's is "node" — pi is a node script, so tmux
# reports the interpreter regardless of process.title. "node" is generic, but
# the state-file-exists check below is the real pi gate: only the harness writes
# a state file for a pi pane's exact socket+pane key, so a plain node process
# has none and shows nothing. This beats guessing from file age — the writer
# only rewrites the state file at each turn boundary, so during a long turn the
# file looks "stale" while the session is very much alive.
#
# The same query also yields '#{socket_path}' — the server that owns this pane
# — so one tmux call covers both the liveness gate and the state key below.
info=$(tmux display-message -p -t "$pane_id" '#{pane_current_command}
#{socket_path}|#{?@proj_theme_accent,#{@proj_theme_accent},default}|#{?@proj_theme_accent_text,#{@proj_theme_accent_text},default}|#{?@proj_theme_muted,#{@proj_theme_muted},default}|#{?@proj_theme_success,#{@proj_theme_success},default}|#{?@proj_theme_warning,#{@proj_theme_warning},default}|#{?@proj_theme_error,#{@proj_theme_error},default}' 2>/dev/null)
cmd=${info%%$'\n'*}
IFS='|' read -r sock_path accent text muted success warning error <<< "${info#*$'\n'}"
accent="${accent:-default}"; text="${text:-default}"; muted="${muted:-default}"
success="${success:-default}"; warning="${warning:-default}"; error="${error:-default}"
# The setting is the only opt-in boundary; missing/older proj stays normal.
themed=false
if proj theme --enabled --json 2>/dev/null | jq -e '.enabled == true' >/dev/null 2>&1; then
  themed=true
fi
badge_text='#1e1e2e'
$themed && badge_text="$text"
[[ "$cmd" == claude || "$cmd" == pi || "$cmd" == node || "$cmd" =~ ^[0-9]+\.[0-9]+ ]] || exit 0

# Stable path: $HOME/.cache is identical for the Claude process (even when
# its sandbox sets a different $TMPDIR) and for tmux — so both sides agree.
state_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-status"

# Key = socket name + pane number, identical to the derivation in
# ~/.config/claude/statusline.sh. Pane ids repeat across the ~14 per-project
# tmux servers on this machine, so a pane-only key mixed up their state files.
# The writer takes the socket from its inherited $TMUX; here it comes from
# '#{socket_path}' of the server that owns the pane. Both are basenames, so
# the /tmp vs /private/tmp symlink difference can't split them.
sock=${sock_path##*/}
[[ -n "$sock" ]] || { sock="${TMUX:-}"; sock="${sock%%,*}"; sock="${sock##*/}"; }
[[ -n "$sock" ]] || sock=unknown
state_key="${sock}_${pane_id#%}"
state_key="${state_key//[^a-zA-Z0-9_.-]/_}"
state_file="$state_dir/$state_key"

[[ -f "$state_file" ]] || exit 0

# Orphan backstop (paranoia only — liveness already proved Claude is running
# in this pane). Just suppresses a genuinely ancient file (>7 days), e.g. left
# by a long-dead session whose pane id got reused. A multi-hour idle gap is
# normal (work overnight, resume) and must NOT hide the indicator.
updated=$(awk -F= '$1=="updated"{print $2}' "$state_file" 2>/dev/null)
now=$(date +%s)
if [[ -n "$updated" ]] && (( now - updated > 604800 )); then
  exit 0
fi

model=$(awk -F= '$1=="model"{print $2}' "$state_file" 2>/dev/null)
pct=$(awk -F= '$1=="context_pct"{print $2}' "$state_file" 2>/dev/null)
# Thinking level, written by pi-tmux-bridge for a reasoning model; absent for
# Claude Code panes and non-reasoning models.
thinking=$(awk -F= '$1=="thinking"{print $2}' "$state_file" 2>/dev/null)

# Model badge, tinted by provider so a glance tells you what is driving the
# pane: Claude (mauve), local llama/Qwen (green), Codex/GPT (sky), else blue.
# Dark bold text on the tint — the readable badge idiom the muster-inbox
# indicator in status-left uses, instead of the old dim grey text.
model_badge=""
if [[ -n "$model" ]]; then
  case "$model" in
    *[Cc]laude*|*[Ff]able*|*[Oo]pus*|*[Ss]onnet*|*[Hh]aiku*) mbg="#cba6f7" ;;
    *[Qq]wen*|*[Ll]lama*)                                    mbg="#a6e3a1" ;;
    *[Gg]pt*|*[Cc]odex*)                                     mbg="#89dceb" ;;
    *)                                                        mbg="#89b4fa" ;;
  esac
  $themed && mbg="$accent"
  model_badge="#[fg=${badge_text},bg=${mbg},bold] ${model} #[default]"
fi

# Thinking badge, tinted cool to warm as the effort rises, so the level reads
# at a glance: off grey, minimal teal, low sky, medium blue, high peach,
# xhigh maroon, max red. Omitted when the pane's model has no level.
think_badge=""
if [[ -n "$thinking" ]]; then
  case "$thinking" in
    off)     tbg="#6c7086" ;;
    minimal) tbg="#94e2d5" ;;
    low)     tbg="#89dceb" ;;
    medium)  tbg="#89b4fa" ;;
    high)    tbg="#fab387" ;;
    xhigh)   tbg="#eba0ac" ;;
    max)     tbg="#f38ba8" ;;
    *)       tbg="#b4befe" ;;
  esac
  if $themed; then
    case "$thinking" in
      off) tbg="$muted" ;;
      high) tbg="$warning" ;;
      xhigh|max) tbg="$error" ;;
      *) tbg="$accent" ;;
    esac
  fi
  think_badge="#[fg=${badge_text},bg=${tbg},bold] ${thinking} #[default]"
fi

# Context badge, tinted by how full the window is: green < 50, yellow 50-79,
# red >= 80. Dark bold text on the tint. Omitted until there's a real value.
ctx_badge=""
if [[ "$pct" =~ ^[0-9]+$ ]] && (( pct > 0 )); then
  if   (( pct >= 80 )); then cbg="#f38ba8"
  elif (( pct >= 50 )); then cbg="#f9e2af"
  else                       cbg="#a6e3a1"
  fi
  if $themed; then
    if (( pct >= 80 )); then cbg="$error"
    elif (( pct >= 50 )); then cbg="$warning"
    else cbg="$success"
    fi
  fi
  ctx_badge="#[fg=${badge_text},bg=${cbg},bold] ⌬ ${pct}% #[default]"
fi

# Nothing useful to show → stay silent. A thin gap between badges reads
# cleaner than butting them together.
out=""
for badge in "$model_badge" "$think_badge" "$ctx_badge"; do
  [[ -n "$badge" ]] && out="${out:+$out }$badge"
done
[[ -n "$out" ]] && printf '%s' "$out"
exit 0
