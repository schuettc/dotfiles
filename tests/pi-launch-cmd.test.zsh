#!/usr/bin/env zsh
# Guards the `proj --pi` / `pt --pi` auto-launch path — the pi analog of
# claude-launch-cmd.test.zsh.
#
# Run directly:  zsh tests/pi-launch-cmd.test.zsh
#
# pi launches interactive from a bare `pi` (no agent-view trap the way claude
# has), so unlike the claude helper there is no load-bearing `--`. What DOES
# matter, and what this guards, is that the launch carries the tmux session
# name into pi via `--name` so the harness extension's identity stamp and the
# muster registration line up with the pane — exactly the parity the claude
# path already has. The default launcher stays claude; --pi is opt-in for the
# trial before any default flip.

set -u

REPO="${0:A:h:h}"
ZSHDIR="$REPO/config/zsh"

typeset -g PASS=0 FAIL=0
ok() {
  if [[ "$2" == "$3" ]]; then
    (( PASS++ )); printf '  ok   %s\n' "$1"
  else
    (( FAIL++ )); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
  fi
}

# Strip comments before scanning: the WHY blocks quote forms they warn about.
code() { grep -hv '^[[:space:]]*#' "$ZSHDIR"/*.zsh; }

echo "── one canonical launch command ──"
ok "__pi_launch_cmd defined once" "1" \
   "$(code | grep -cE '^[[:space:]]*__pi_launch_cmd[[:space:]]*\(\)')"

# Source for the real value rather than asserting on the source text — a
# helper that returns the wrong string would pass a grep and fail in a pane.
ok "emits bare 'pi'" "pi" \
   "$(zsh -c "source '$ZSHDIR/04-aliases.zsh' 2>/dev/null; __pi_launch_cmd")"

echo "── the session name carries into pi ──"
# proj/pt create the session already named for the work; --name is what tells
# pi that name at launch, with no injection and no waiting for the agent to
# boot, so the harness extension stamps @harness_session and registers with
# muster under the same identity as the pane.
ok "names the session" "pi --name 'dotfiles/nfl-4'" \
   "$(zsh -c "source '$ZSHDIR/04-aliases.zsh' 2>/dev/null; __pi_launch_cmd 'dotfiles/nfl-4'")"
# An empty argument must fall back to the bare form rather than emitting
# `--name ''`, which would name the session the empty string.
ok "empty name falls back" "pi" \
   "$(zsh -c "source '$ZSHDIR/04-aliases.zsh' 2>/dev/null; __pi_launch_cmd ''")"

echo "── the auto-launch site passes the session name ──"
# Not the literal string 'pi' — the session name proj just created.
ok "launch site passes \$name" "1" \
   "$(code | grep -c '__pi_launch_cmd "\$name"')"

echo "── every launch site routes through the helper ──"
# One call site: __proj_ensure_session, shared by proj/pt/auto-join.
ok "one helper call site" "1" "$(code | grep -c '\$(__pi_launch_cmd')"

echo "── --pi is parsed wherever --claude is ──"
# Both entry points (proj and pt) parse the agent flags in a while loop; --pi
# must set auto_agent in each, or `proj --pi` silently falls through to the
# picker with no agent.
ok "--pi parsed in every flag loop" "2" \
   "$(code | grep -c '\[\[ "\$1" == "--pi" \]\] && auto_agent="pi"')"

echo "── send-keys targets a pane, not a session ──"
# Same tmux 3.7b rule as the claude branch: send-keys needs "=name:", not a
# bare "=name", or the keys vanish to stderr and the launch is silent.
ok "pi branch uses =\$name: target" "1" \
   "$(code | grep -c 'send-keys -t "=$name:" "$(__pi_launch_cmd')"

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
