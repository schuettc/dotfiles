#!/usr/bin/env zsh
# Exercise status renderers with a private tmux server and stubbed proj/git.
set -eu
REPO="${0:A:h:h}"
REAL_TMUX=$(command -v tmux)
WORK=$(mktemp -d)
export HOME="$WORK/home" PROJ_HOME="$WORK/proj" PI_CODING_AGENT_DIR="$WORK/pi"
export XDG_CONFIG_HOME="$WORK/config" XDG_CACHE_HOME="$WORK/cache" TMUX_TMPDIR="$WORK"
export THEME_CALLS="$WORK/calls" THEME_ENABLED=true
mkdir -p "$WORK/bin" "$HOME" "$XDG_CACHE_HOME/claude-status"
export THEME_SOCKET="$WORK/server" REAL_TMUX
trap '"$REAL_TMUX" -S "$THEME_SOCKET" kill-server 2>/dev/null || true; rm -rf "$WORK"' EXIT
cat > "$WORK/bin/tmux" <<'SH'
#!/bin/bash
printf '%s\n' "$1" >> "$THEME_CALLS"
exec "$REAL_TMUX" -S "$THEME_SOCKET" "$@"
SH
cat > "$WORK/bin/proj" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$THEME_CALLS"
[[ "$*" == 'theme --enabled --json' ]] || exit 99
printf '{"enabled":%s}\n' "$THEME_ENABLED"
SH
cat > "$WORK/bin/git" <<'SH'
#!/bin/bash
case "$1" in
rev-parse) exit 0;;
symbolic-ref) echo feature;;
status) [[ "${DIRTY:-0}" == 1 ]] && echo ' M file'; exit 0;;
*) exit 99;;
esac
SH
cat > "$WORK/bin/cksum" <<'SH'
#!/bin/bash
[[ "$THEME_ENABLED" == true ]] && { echo 'unexpected theme name hash' >&2; exit 99; }
exec /usr/bin/cksum "$@"
SH
printf '#!/bin/sh\nexit 99\n' > "$WORK/bin/osascript"
chmod +x "$WORK/bin/"*
export PATH="$WORK/bin:$PATH"
"$REAL_TMUX" -S "$THEME_SOCKET" -f /dev/null new-session -d -s example -x 80 -y 24
pane=$(tmux display-message -p '#{pane_id}')
# Status jobs inherit their own server context, never the test caller's.
export TMUX="$THEME_SOCKET,$("$REAL_TMUX" -S "$THEME_SOCKET" display-message -p '#{pid}'),0" TMUX_PANE="$pane"
for role value in accent '#112233' accent_text '#223344' success '#334455' warning '#445566' error '#556677' muted '#667788'; do
  tmux set-option "@proj_theme_$role" "$value"
done
contains() { [[ "$2" == *"$3"* ]] || { print -u2 "FAIL $1: $2 (missing $3)"; exit 1; }; }
render() { : > "$THEME_CALLS"; "$REPO/bin/$1.sh" "${@:2}"; }
# Losing the theme branch must fail even when the session name stays unchanged.
out=$(render tmux-session-color example)
contains identity "$out" '#[fg=#112233,bold] example '
[[ $(grep -c display-message "$THEME_CALLS") == 1 ]]
export DIRTY=0
contains clean "$(render tmux-git-status "$WORK" example)" '#[fg=#334455] feature'
export DIRTY=1
contains dirty "$(render tmux-git-status "$WORK" example)" '#[fg=#445566] feature #[fg=#445566,bold]●1'
# A bell in another visited session still asks for attention.
tmux new-session -d -s waiting
# list-windows' bell state is external; return a controlled observation only there.
sed -i '' '/exec/i\
[[ "$1" == list-windows ]] \&\& { echo "waiting 1 123"; exit 0; }\
' "$WORK/bin/tmux"
contains attention "$(render tmux-attention example)" '#[fg=#223344,bg=#556677,bold] ⚠ 1: waiting '
# The focused command and socket are observed, not inferred from live agent files.
cat > "$WORK/bin/tmux" <<'SH'
#!/bin/bash
printf '%s\n' "$1" >> "$THEME_CALLS"
if [[ "$1" == display-message && "$*" == *pane_current_command* ]]; then
  fmt="${!#}"
  fmt="${fmt//'#{pane_current_command}'/node}"
  args=("$@")
  args[${#args[@]}-1]="$fmt"
  set -- "${args[@]}"
fi
exec "$REAL_TMUX" -S "$THEME_SOCKET" "$@"
SH
printf 'model=Claude\nthinking=high\ncontext_pct=88\n' > "$XDG_CACHE_HOME/claude-status/server_${pane#%}"
out=$(render tmux-claude-context "$pane")
contains model "$out" 'bg=#112233,bold] Claude '
contains thinking "$out" 'bg=#445566,bold] high '
contains context "$out" 'bg=#556677,bold] ⌬ 88% '
[[ $(grep -c display-message "$THEME_CALLS") == 1 ]]
[[ $(render tmux-session-color --enabled example) == 1 ]]
tmux source-file "$REPO/.tmux.conf"
tmux set-option @claude_task 'writing docs'
contains native-task "$(tmux display-message -p -t example '#{E:status-left}')" 'writing docs'
# Supply the completed setting-job result; status fields must not need a job.
tmux set-option -g @proj_theme_enabled_format 1
left() { tmux display-message -p -t example '#{E:status-left}'; }
right() { tmux display-message -p -t example '#{E:status-right}'; }
tmux set-option @muster_agent other-alias
tmux set-option @muster_inbox 2
tmux set-option @wakeup '14:00 in 2m'
tmux set-option -t waiting @proj_theme_accent '#998877'
out=$(left)
contains task "$out" '#[fg=#112233]writing docs '
contains mail "$out" '#[fg=#223344,bg=#112233,bold] 📬2 '
tmux set-option @claude_task 'changed task'
tmux set-option @muster_inbox 3
contains changed-task "$(left)" '#[fg=#112233]changed task '
contains changed-mail "$(left)" '📬3 '
tmux set-option -u @muster_inbox
contains alias "$(left)" '#[fg=#667788]@other-alias'
contains wakeup "$(right)" '#[fg=#445566]⏰ 14:00 in 2m'
contains clock "$(right)" '#[fg=#667788]'
for pct expected in 24 '#334455' 64 '#445566' 88 '#556677'; do
  printf 'context_pct=%s\n' "$pct" > "$XDG_CACHE_HOME/claude-status/server_${pane#%}"
  contains "context $pct" "$(render tmux-claude-context "$pane")" "bg=${expected},bold] ⌬ ${pct}%"
done
export THEME_ENABLED=false
tmux set-option -g @proj_theme_enabled_format 0
[[ $(render tmux-session-color --enabled example) == 0 ]]
contains normal "$(render tmux-session-color example)" '#[fg=#f9e2af,bold] example '
contains normal-context "$(render tmux-claude-context "$pane")" 'bg=#f38ba8,bold] ⌬ 88% '
contains normal-task "$(left)" '#[fg=#b4befe]changed task '
contains normal-alias "$(left)" '#[fg=#6c7086]@other-alias'
contains normal-wakeup "$(right)" '#[fg=#f9e2af]⏰ 14:00 in 2m'
contains normal-clock "$(right)" '#[fg=#a6adc8]'
contains normal-git "$(render tmux-git-status "$WORK" example)" '#[fg=#f9e2af] feature #[fg=#fab387,bold]●1'
export THEME_ENABLED=true
tmux set-option -g @proj_theme_enabled_format 1
for role in accent accent_text success warning error muted; do tmux set-option -u "@proj_theme_$role"; done
contains unassigned "$(render tmux-session-color example)" '#[fg=default,bold] example '
contains unassigned-git "$(render tmux-git-status "$WORK" example)" '#[fg=default] feature #[fg=default,bold]●1'
contains unassigned-context "$(render tmux-claude-context "$pane")" '#[fg=default,bg=default,bold] ⌬ 88% '
# Load only this worktree config on the private server; no status jobs run without clients.
tmux source-file "$REPO/.tmux.conf"
contains refresh "$(tmux show-option -gv status-right)" '#(proj __theme-sync)'
contains enabled-format "$(tmux show-option -gv @proj_theme_enabled_format)" 'tmux-session-color.sh --enabled'
contains native-clock "$(tmux show-option -gv status-right)" '%a %b %d  %H:%M'
[[ $(tmux show-option -gv status-interval) == 5 ]]
contains focus "$(tmux show-hooks -g client-focus-in)" 'claude-attn clear'
contains title "$(tmux show-option -gv set-titles-string)" '@muster_inbox'
print 'PASS: themed/normal/unassigned roles, context meanings, refresh and preserved hooks/title'
